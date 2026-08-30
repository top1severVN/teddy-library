-- ============================================
-- Teddy.lua - Roblox Task Manager 🧸
-- Optimized for game development
-- v2.1 - Async / DataStore support
-- ============================================
-- ⚠️ REQUIRES: Roblox/Luau with task library
-- ============================================

local Teddy = {}
Teddy.__index = Teddy

-- State enum
local S = {
	IDLE = 1,
	RUN = 2,
	PAUSE = 3,
	WAIT = 4,
	OK = 5,
	ERR = 6,
	SKIP = 7
}

-- ============================================
-- CORE
-- ============================================

function Teddy.new()
	local self = setmetatable({}, Teddy)
	self.t = {} -- tasks
	self.cb = {} -- callbacks
	self.n = 0 -- counter
	return self
end

function Teddy:mk(cfg) -- make/add
	self.n = self.n + 1
	local id = self.n

	local task = {
		id = id,
		nm = cfg.name or "T" .. id,
		p = cfg.priority or 0,
		d = cfg.dependencies or {}, -- deps
		f = cfg.callback, -- function
		s = S.IDLE, -- state
		r = nil, -- result
		e = nil, -- error
		c = nil, -- coroutine
		ca = os.clock(),
		sa = nil,
		ea = nil, -- end at
		to = cfg.timeout,
		rc = cfg.retryCount or 0, -- retry count
		mr = cfg.maxRetries or 3, -- max retries
		rl = cfg.rateLimit, -- rate limit
		bo = cfg.backoff, -- backoff: nil/false = fixed 1s, true = default backoff, table = custom
		le = 0 -- last exec
	}

	self.t[id] = task
	self:_emit("add", task)
	return id
end

-- ============================================
-- STATE CHECKS
-- ============================================

function Teddy:st(id) -- state
	local t = self.t[id]
	return t and t.s or nil
end

function Teddy:is(id, s) -- is state
	return self:st(id) == s
end

function Teddy:idle(id)
	return self:is(id, S.IDLE)
end

function Teddy:run(id)
	return self:is(id, S.RUN)
end

function Teddy:pause(id)
	return self:is(id, S.PAUSE)
end

function Teddy:wait(id)
	return self:is(id, S.WAIT)
end

function Teddy:ok(id)
	return self:is(id, S.OK)
end

function Teddy:err(id)
	return self:is(id, S.ERR)
end

function Teddy:skip(id)
	return self:is(id, S.SKIP)
end

function Teddy:done(id)
	local s = self:st(id)
	return s and s >= S.OK or false
end

-- ============================================
-- CONTROL
-- ============================================

function Teddy:go(id) -- start/go
	local t = self.t[id]
	if not t then return false end

	if t.s == S.RUN or t.s == S.WAIT then
		return false
	end

	-- Check deps
	if #t.d > 0 then
		t.s = S.WAIT
		self:_emit("wait", t)
		return true
	end

	-- Rate limit
	if t.rl then
		local now = os.clock()
		local iv = 1 / t.rl
		if now - t.le < iv then
			self:_sch(id, iv - (now - t.le))
			return true
		end
		t.le = now
	end

	return self:_run(id)
end

function Teddy:_run(id) -- execute
	local t = self.t[id]
	if not t then return false end

	if not t.c then
		t.c = coroutine.create(function()
			-- pcall preserves yielding in Luau, so callbacks that yield
			-- on native async calls (DataStore GetAsync/SetAsync/UpdateAsync,
			-- HttpService requests, etc.) work correctly here: the engine
			-- resumes this coroutine directly once the async op completes.
			local ok, res = pcall(t.f)
			if ok then
				t.s = S.OK
				t.r = res
				t.ea = os.clock()
				self:_emit("ok", t)
				self:_deps(id)
			else
				t.s = S.ERR
				t.e = res
				self:_emit("err", t)

				if t.rc < t.mr then
					t.rc = t.rc + 1
					t.s = S.IDLE
					t.c = nil
					self:_emit("retry", t)
					self:_sch(id, self:_delay(t))
				end
			end
		end)
	end

	t.s = S.RUN
	t.sa = os.clock()
	self:_emit("go", t)

	local ok, err = coroutine.resume(t.c)

	if not ok and coroutine.status(t.c) ~= "dead" then
		t.s = S.ERR
		t.e = err
		self:_emit("err", t)
		return false
	end

	return true
end

function Teddy:pause(id)
	local t = self.t[id]
	if not t or t.s ~= S.RUN then
		return false
	end

	t.s = S.PAUSE
	self:_emit("pause", t)
	return true
end

function Teddy:cont(id) -- continue
	local t = self.t[id]
	if not t or t.s ~= S.PAUSE then
		return false
	end

	t.s = S.RUN
	self:_emit("cont", t)

	local ok, err = coroutine.resume(t.c)
	if not ok then
		t.s = S.ERR
		t.e = err
		self:_emit("err", t)
		return false
	end

	return true
end

function Teddy:stop(id, force)
	local t = self.t[id]
	if not t then return false end

	if t.s == S.OK or t.s == S.SKIP then
		return false
	end

	if force and t.c then
		t.s = S.SKIP
		t.c = nil
		self:_emit("skip", t)
		return true
	end

	t.s = S.SKIP
	self:_emit("skip", t)
	return true
end

-- ============================================
-- INTERNAL
-- ============================================

function Teddy:_sch(id, delay) -- schedule
	task.delay(delay, function()
		self:go(id)
	end)
end

-- Retry delay: fixed 1s by default, or exponential backoff when
-- cfg.backoff is truthy. bo can be `true` (defaults) or a table:
-- { base = 1, mult = 2, max = 30, jitter = true }
function Teddy:_delay(t)
	if not t.bo then
		return 1
	end

	local cfg = type(t.bo) == "table" and t.bo or {}
	local base = cfg.base or 1
	local mult = cfg.mult or 2
	local max = cfg.max or 30
	local d = math.min(base * (mult ^ (t.rc - 1)), max)

	if cfg.jitter ~= false then
		d = d * (0.7 + math.random() * 0.6) -- +/- 30% jitter
	end

	return d
end

function Teddy:_deps(id) -- trigger deps
	for _, t in pairs(self.t) do
		if t.s == S.WAIT then
			for i, did in ipairs(t.d) do
				if did == id then
					table.remove(t.d, i)
					break
				end
			end

			if #t.d == 0 then
				t.s = S.IDLE
				self:go(t.id)
			end
		end
	end
end

function Teddy:_emit(ev, ...) -- emit event
	local cbs = self.cb[ev] or {}
	for _, fn in ipairs(cbs) do
		task.spawn(fn, ...)
	end
end

-- ============================================
-- INFO & INSPECT
-- ============================================

function Teddy:info(id)
	local t = self.t[id]
	if not t then return nil end

	return {
		id = t.id,
		name = t.nm,
		state = t.s,
		result = t.r,
		error = t.e,
		retries = t.rc,
		done = t.s >= S.OK,
		createdAt = t.ca,
		startedAt = t.sa,
		endedAt = t.ea
	}
end

function Teddy:await(id, to) -- await/wait for
	local t = self.t[id]
	if not t then return false end

	if t.s == S.OK then
		return true, t.r
	end

	local st = os.clock()
	while t.s < S.OK do
		if to and os.clock() - st > to then
			return false, "timeout"
		end
		task.wait()
	end

	if t.s == S.OK then
		return true, t.r
	else
		return false, t.e or "fail"
	end
end

-- ============================================
-- EVENTS
-- ============================================

function Teddy:on(ev, fn) -- on event
	if not self.cb[ev] then
		self.cb[ev] = {}
	end
	table.insert(self.cb[ev], fn)
end

-- ============================================
-- BATCH & UTILITIES
-- ============================================

function Teddy:batch(items, fn, conc)
	conc = conc or 3

	local pend = {}
	local res = {}
	local done = 0

	for _, v in ipairs(items) do
		table.insert(pend, v)
	end

	local eng = Teddy.new()

	for i = 1, math.min(conc, #items) do
		eng:mk({
			name = "w" .. i,
			callback = function()
				while #pend > 0 do
					local v = table.remove(pend, 1)
					table.insert(res, fn(v))
					done = done + 1
					task.wait()
				end
			end
		})
		eng:go(i)
	end

	while done < #items do
		task.wait(0.1)
	end

	return res
end

function Teddy:wrap(nm, fn) -- wrap function
	return self:mk({
		name = nm,
		callback = fn
	})
end

function Teddy:all(ids) -- await all
	local res = {}

	for _, id in ipairs(ids) do
		self:go(id)
	end

	for _, id in ipairs(ids) do
		local ok, r = self:await(id)
		res[id] = { ok = ok, r = r }
	end

	return res
end

-- ============================================
-- ASYNC / DATASTORE HELPERS
-- ============================================
-- These build on the core task engine above. Because Luau's pcall
-- preserves yielding, any callback that calls a native async Roblox
-- API (DataStoreService, HttpService, MemoryStoreService, ...) already
-- runs correctly through tm:mk/tm:go without extra plumbing - the task
-- just sits in RUN until the engine resumes it. The helpers below add
-- the two things you actually want for DataStore specifically:
-- request-budget-aware throttling and exponential backoff on retry.

local DSS = game:GetService("DataStoreService")
local ReqType = Enum.DataStoreRequestType

-- Waits until Roblox's DataStore request budget for this request type
-- has room, so bursts of dsGet/dsSet/dsInc calls don't get throttled.
local function _waitBudget(reqType)
	local budget = DSS:GetRequestBudgetForRequestType(reqType)
	while budget <= 0 do
		task.wait(1)
		budget = DSS:GetRequestBudgetForRequestType(reqType)
	end
end

-- Generic async shortcut: create + auto-start a task in one call.
-- local id = tm:async(function() return doSomethingThatYields() end)
-- local ok, result = tm:await(id)
function Teddy:async(fn, cfg)
	cfg = cfg or {}
	cfg.callback = fn
	local id = self:mk(cfg)
	self:go(id)
	return id
end

-- tm:dsGet(store, key, cfg?) → id
function Teddy:dsget(store, key, cfg)
	cfg = cfg or {}
	local id = self:mk({
		name = cfg.name or ("ds_get_" .. tostring(key)),
		priority = cfg.priority,
		timeout = cfg.timeout,
		maxRetries = cfg.maxRetries or 5,
		backoff = cfg.backoff == nil and true or cfg.backoff,
		callback = function()
			_waitBudget(ReqType.GetAsync)
			return store:GetAsync(key)
		end
	})
	if cfg.autoStart ~= false then self:go(id) end
	return id
end

-- tm:dsSet(store, key, value, cfg?) → id
function Teddy:dsset(store, key, value, cfg)
	cfg = cfg or {}
	local id = self:mk({
		name = cfg.name or ("ds_set_" .. tostring(key)),
		priority = cfg.priority,
		timeout = cfg.timeout,
		maxRetries = cfg.maxRetries or 5,
		backoff = cfg.backoff == nil and true or cfg.backoff,
		callback = function()
			_waitBudget(ReqType.SetIncrementAsync)
			store:SetAsync(key, value)
			return true
		end
	})
	if cfg.autoStart ~= false then self:go(id) end
	return id
end

-- tm:dsUpdate(store, key, transformFn, cfg?) → id
function Teddy:dsupdate(store, key, transformFn, cfg)
	cfg = cfg or {}
	local id = self:mk({
		name = cfg.name or ("ds_update_" .. tostring(key)),
		priority = cfg.priority,
		timeout = cfg.timeout,
		maxRetries = cfg.maxRetries or 5,
		backoff = cfg.backoff == nil and true or cfg.backoff,
		callback = function()
			_waitBudget(ReqType.UpdateAsync)
			return store:UpdateAsync(key, transformFn)
		end
	})
	if cfg.autoStart ~= false then self:go(id) end
	return id
end

-- tm:dsInc(store, key, delta?, cfg?) → id
function Teddy:dsinc(store, key, delta, cfg)
	cfg = cfg or {}
	local id = self:mk({
		name = cfg.name or ("ds_inc_" .. tostring(key)),
		priority = cfg.priority,
		timeout = cfg.timeout,
		maxRetries = cfg.maxRetries or 5,
		backoff = cfg.backoff == nil and true or cfg.backoff,
		callback = function()
			_waitBudget(ReqType.SetIncrementAsync)
			return store:IncrementAsync(key, delta or 1)
		end
	})
	if cfg.autoStart ~= false then self:go(id) end
	return id
end

-- tm:dsRemove(store, key, cfg?) → id
function Teddy:dsremove(store, key, cfg)
	cfg = cfg or {}
	local id = self:mk({
		name = cfg.name or ("ds_remove_" .. tostring(key)),
		priority = cfg.priority,
		timeout = cfg.timeout,
		maxRetries = cfg.maxRetries or 5,
		backoff = cfg.backoff == nil and true or cfg.backoff,
		callback = function()
			_waitBudget(ReqType.SetIncrementAsync)
			return store:RemoveAsync(key)
		end
	})
	if cfg.autoStart ~= false then self:go(id) end
	return id
end

return Teddy