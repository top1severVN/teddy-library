# 🧸 Teddy.lua - Roblox Game Task Manager

> Lightweight async task library for Roblox games. Built on `task` API.
> v2.1 adds first-class async/DataStore support: request-budget throttling + exponential backoff.

**🎮 For:** Roblox Luau development only  
**⚠️ Requires:** Roblox task library (`task.spawn`, `task.delay`, `task.wait`) and `DataStoreService` (for the `ds*` helpers)  
**📦 Size:** ~3KB (minified)  
**Version:** 2.1

---

## 📚 Table of Contents

- [Setup](#-setup)
- [API Reference](#-api-reference)
- [Async & DataStore (v2.1)](#-async--datastore-v21)
- [States](#-states)
- [Game Examples](#-game-examples)
- [Best Practices](#-best-practices)

---

## 🚀 Setup

```lua
-- In your Roblox server/local script
local Teddy = require(game.ServerScriptService:WaitForChild("Teddy"))
local tm = Teddy.new()
```

---

## ⚡ Quick Start

```lua
-- Simple task
local id = tm:mk({
    name = "spawn_enemy",
    callback = function()
        local enemy = Instance.new("Part")
        enemy.Parent = workspace
        return enemy
    end
})

-- Run it
tm:go(id)

-- Wait for result
local ok, enemy = tm:await(id)
if ok then
    print("Enemy spawned:", enemy.Name)
end
```

---

## 📋 API Reference

### Constructor

```lua
local tm = Teddy.new()
```

---

### Task Creation

#### `mk(config) → id`
Creates a task. **mk = make**

```lua
local id = tm:mk({
    name = "load_map",              -- Task name
    callback = function() ... end,  -- Required: function to run
    priority = 1,                   -- Optional: priority level
    dependencies = {id1, id2},      -- Optional: wait for these tasks
    timeout = 5,                    -- Optional: max seconds
    maxRetries = 3,                 -- Optional: retry on error
    rateLimit = 10,                 -- Optional: requests/sec
    backoff = true                  -- Optional (v2.1): exponential backoff on retry
})
```

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `name` | string | - | Descriptive name |
| `callback` | function | - | **Required.** Code to execute. Can freely yield (DataStore, HttpService, etc.) — Luau's `pcall` preserves yielding, so the task engine handles it transparently. |
| `priority` | number | 0 | Higher = runs first |
| `dependencies` | table | {} | Task IDs (wait for these) |
| `timeout` | number | - | Max execution time |
| `maxRetries` | number | 3 | Retry attempts on error |
| `rateLimit` | number | - | Rate limit (reqs/sec) |
| `backoff` | bool/table | nil (fixed 1s) | `true` for default exponential backoff, or `{base=1, mult=2, max=30, jitter=true}` to customize. See [Async & DataStore](#-async--datastore-v21). |

**Returns:** `id` (number)

---

### Control

#### `go(id) → ok`
Start a task. **go = start**

```lua
tm:go(id)  -- Start now
```

Returns `true` if started.

---

#### `pause(id) → ok`
Pause a running task.

```lua
tm:pause(id)
```

---

#### `cont(id) → ok`
Continue a paused task. **cont = continue**

```lua
tm:cont(id)
```

---

#### `stop(id, force?) → ok`
Cancel a task.

```lua
tm:stop(id)          -- Graceful stop
tm:stop(id, true)    -- Force stop (hard kill)
```

---

### State Checking

#### Quick checks
```lua
tm:idle(id)   -- Not started
tm:run(id)    -- Running
tm:pause(id)  -- Paused
tm:wait(id)   -- Waiting for deps
tm:ok(id)     -- Completed ✓
tm:err(id)    -- Failed ✗
tm:skip(id)   -- Skipped
tm:done(id)   -- Any finished state (ok/err/skip)
```

#### Get state
```lua
local state = tm:st(id)  -- Get state number (1-7)
local ok = tm:is(id, S.RUN)  -- Check specific state
```

---

### Wait & Result

#### `await(id, timeout?) → ok, result`
Wait for task completion.

```lua
local ok, result = tm:await(id)           -- No timeout
local ok, result = tm:await(id, 5)        -- 5 sec timeout

if ok then
    print("Success:", result)
else
    print("Failed:", result)  -- error message
end
```

---

### Info

#### `info(id) → table`
Get task info.

```lua
local info = tm:info(id)
print(info.name)
print(info.state)
print(info.result)
print(info.error)
print(info.retries)
print(info.done)
```

---

### Events

#### `on(event, callback)`
Listen to events.

```lua
tm:on("go", function(task)
    print("Task started: " .. task.nm)
end)

tm:on("ok", function(task)
    print("Task success: " .. task.r)
end)

tm:on("err", function(task)
    print("Task error: " .. task.e)
end)

tm:on("retry", function(task)
    print("Retrying: " .. task.nm .. " (attempt " .. task.rc .. ")")
end)

tm:on("pause", function(task)
    print("Paused: " .. task.nm)
end)

tm:on("cont", function(task)
    print("Continued: " .. task.nm)
end)

tm:on("skip", function(task)
    print("Skipped: " .. task.nm)
end)

tm:on("wait", function(task)
    print("Waiting: " .. task.nm)
end)

tm:on("add", function(task)
    print("Added: " .. task.nm)
end)
```

**Events:**
- `add` - Task created
- `go` - Task started
- `ok` - Task completed
- `err` - Task failed
- `retry` - Task retrying
- `pause` - Task paused
- `cont` - Task continued
- `skip` - Task skipped
- `wait` - Task waiting for deps

---

### Batch & Utilities

#### `batch(items, processor, concurrency?) → results`
Process many items in parallel.

```lua
local players = game:GetService("Players"):GetPlayers()
local results = tm:batch(players, function(player)
    return player.leaderstats.Gold.Value
end, 4)  -- 4 workers

print("Gold amounts:", results)
```

---

#### `wrap(name, function) → id`
Quick task wrapper.

```lua
local id = tm:wrap("check_health", function()
    return character:FindFirstChild("Humanoid").Health
end)

tm:go(id)
```

---

#### `all(ids) → results`
Start and await multiple tasks.

```lua
local ids = {id1, id2, id3}
local results = tm:all(ids)

for taskId, res in pairs(results) do
    if res.ok then
        print("Task " .. taskId .. ": " .. res.r)
    end
end
```

---

## 🧵 Async & DataStore (v2.1)

Teddy's task engine already supports any yielding call inside a `callback` —
Luau's `pcall` preserves yields across the coroutine boundary, so a task that
calls `DataStoreService`, `HttpService`, or `MemoryStoreService` just sits in
the `RUN` state and completes normally once the async op returns. You don't
need anything special for that part.

What you *do* want for DataStore specifically is:
1. **Request-budget awareness** — Roblox throttles DataStore calls per minute; bursts get errors.
2. **Exponential backoff on retry** — hammering a failing request every 1s is bad practice.

The `ds*` helpers below wrap both of these around the core engine.

### `async(fn, cfg?) → id`
Generic async shortcut — create **and** start a task in one call.

```lua
local id = tm:async(function()
    return game:GetService("HttpService"):GetAsync(url)
end)

local ok, body = tm:await(id, 10)
```

`cfg` accepts the same fields as `mk()` (name, maxRetries, backoff, etc).

---

### `dsGet(store, key, cfg?) → id`
Wraps `store:GetAsync(key)` with request-budget throttling + retry/backoff.

```lua
local DataStoreService = game:GetService("DataStoreService")
local goldStore = DataStoreService:GetDataStore("PlayerGold")

local id = tm:dsGet(goldStore, "user_" .. player.UserId)
local ok, gold = tm:await(id, 10)

if ok then
    player.leaderstats.Gold.Value = gold or 0
else
    warn("Failed to load gold:", gold)
end
```

---

### `dsSet(store, key, value, cfg?) → id`
Wraps `store:SetAsync(key, value)`.

```lua
tm:dsSet(goldStore, "user_" .. player.UserId, player.leaderstats.Gold.Value)
```

---

### `dsUpdate(store, key, transformFn, cfg?) → id`
Wraps `store:UpdateAsync(key, transformFn)` — use this instead of `dsGet` +
`dsSet` when a value needs to change atomically (read-modify-write).

```lua
tm:dsUpdate(goldStore, "user_" .. player.UserId, function(old)
    return (old or 0) + 100
end)
```

---

### `dsInc(store, key, delta?, cfg?) → id`
Wraps `store:IncrementAsync(key, delta)`. `delta` defaults to `1`.

```lua
tm:dsInc(goldStore, "user_" .. player.UserId, 50)
```

---

### `dsRemove(store, key, cfg?) → id`
Wraps `store:RemoveAsync(key)`.

```lua
tm:dsRemove(goldStore, "user_" .. player.UserId)
```

---

### Shared `cfg` fields for `ds*` helpers

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `name` | string | auto | Task name (defaults to `ds_get_<key>` etc.) |
| `maxRetries` | number | 5 | DataStore ops are worth retrying more than default |
| `backoff` | bool/table | `true` | Exponential backoff is on by default for `ds*` |
| `timeout` | number | - | Passed straight to `mk()` |
| `autoStart` | bool | `true` | Set `false` to get the `id` back without starting (e.g. to attach `dependencies` first) |

All `ds*` helpers **return an id immediately** and run the actual DataStore
call asynchronously — use `tm:await(id, timeout)` or `tm:on("ok"/"err", ...)`
to react to the result, exactly like any other Teddy task.

### Backoff config

```lua
backoff = true  -- defaults: base=1s, mult=2x, max=30s, +/-30% jitter

-- or customize:
backoff = {
    base = 0.5,   -- first retry delay (seconds)
    mult = 2,     -- multiplier per retry
    max = 20,     -- cap
    jitter = true -- randomize +/-30% to avoid thundering herd
}
```

### Why request-budget throttling matters

Roblox grants a limited number of DataStore requests per minute per request
type (Get, Set/Increment, Update, ...). If you fire off dozens of `dsSet`
calls in a loop (e.g. saving many players in `game:BindToClose`), some will
get throttled and error. The `ds*` helpers check
`DataStoreService:GetRequestBudgetForRequestType(...)` before making the
call and wait if the budget is exhausted, so you can fire many calls without
manually rate-limiting them yourself.

```lua
-- Safe to fire many at once — Teddy throttles internally
for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
    tm:dsSet(goldStore, "user_" .. player.UserId, player.leaderstats.Gold.Value)
end
```

---

## 🎯 States

```
1 = IDLE         Not started
2 = RUN          Running
3 = PAUSE        Paused (can continue)
4 = WAIT         Waiting for dependencies
5 = OK           ✓ Completed successfully
6 = ERR          ✗ Failed
7 = SKIP         Cancelled
```

**Flow:**
```
IDLE → RUN → OK ✓
  ↓     ↓
 WAIT  PAUSE → RUN → OK ✓
       ↓
      ERR (retry → IDLE → RUN → OK)
      
SKIP (cancelled anytime)
```

---

## 🎮 Game Examples

### Example 1: Load Assets

```lua
local tm = Teddy.new()

local modelId = tm:mk({
    name = "load_sword",
    callback = function()
        local sword = game:GetService("InsertService"):LoadAsset(12345):GetChildren()[1]
        sword.Parent = workspace
        return sword
    end
})

tm:go(modelId)
local ok, sword = tm:await(modelId, 10)  -- 10 sec timeout

if ok then
    print("Sword loaded:", sword.Name)
else
    print("Failed to load:", ok)
end
```

### Example 2: Sequential Tasks (Dependencies)

```lua
-- Step 1: Download data
local downloadId = tm:mk({
    name = "download_map",
    callback = function()
        -- Simulate download
        local data = httpService:GetAsync("https://api.game.com/map")
        return data
    end
})

-- Step 2: Parse (waits for Step 1)
local parseId = tm:mk({
    name = "parse_map",
    dependencies = {downloadId},
    callback = function()
        local data = tm:info(downloadId).result
        return game:GetService("HttpService"):JSONDecode(data)
    end
})

-- Step 3: Load (waits for Step 2)
local loadId = tm:mk({
    name = "load_map",
    dependencies = {parseId},
    callback = function()
        local mapData = tm:info(parseId).result
        -- Load map...
        return "Map loaded"
    end
})

tm:go(loadId)  -- Automatically runs: download → parse → load
tm:await(loadId)
print("Pipeline complete!")
```

### Example 3: Spawn Enemies (Parallel)

```lua
local enemyIds = {}

for i = 1, 10 do
    local id = tm:mk({
        name = "spawn_enemy_" .. i,
        callback = function()
            local enemy = Instance.new("Part")
            enemy.Name = "Enemy"
            enemy.Position = Vector3.new(i * 5, 5, 0)
            enemy.Parent = workspace
            return enemy
        end
    })
    table.insert(enemyIds, id)
end

-- Spawn all in parallel
local enemies = tm:all(enemyIds)
print("Spawned " .. #enemies .. " enemies")
```

### Example 4: Player Loading

```lua
local Players = game:GetService("Players")
local tm = Teddy.new()

local function setupPlayer(player)
    local id = tm:mk({
        name = "setup_" .. player.Name,
        callback = function()
            -- Load character
            player:WaitForDataReady()
            
            -- Create leaderstats
            local stats = Instance.new("Folder")
            stats.Name = "leaderstats"
            stats.Parent = player
            
            local gold = Instance.new("IntValue")
            gold.Name = "Gold"
            gold.Value = 100
            gold.Parent = stats
            
            return { player = player, gold = gold }
        end,
        maxRetries = 2  -- Retry if fails
    })
    
    return id
end

Players.PlayerAdded:Connect(function(player)
    local id = setupPlayer(player)
    tm:go(id)
    
    tm:on("ok", function(task)
        if task.nm == "setup_" .. player.Name then
            print(player.Name .. " is ready!")
        end
    end)
    
    tm:on("err", function(task)
        if task.nm == "setup_" .. player.Name then
            print("Failed to setup " .. player.Name)
        end
    end)
end)
```

### Example 5: API Rate Limiting

```lua
local HttpService = game:GetService("HttpService")
local tm = Teddy.new()

local function queryAPI(endpoint)
    return tm:mk({
        name = "api_" .. endpoint,
        callback = function()
            return HttpService:GetAsync("https://api.game.com/" .. endpoint)
        end,
        rateLimit = 5,  -- 5 requests/sec
        maxRetries = 3
    })
end

-- Make 50 requests (rate limited to 5/sec = 10 seconds)
local ids = {}
for i = 1, 50 do
    local id = queryAPI("data/" .. i)
    table.insert(ids, id)
    tm:go(id)
end

-- Wait for all
local results = tm:all(ids)
print("All requests done!")
```

### Example 6: Game Loop Task

```lua
local tm = Teddy.new()
local running = true

local gameLoopId = tm:mk({
    name = "game_loop",
    callback = function()
        while running do
            -- Update game
            for _, player in pairs(game:GetService("Players"):GetPlayers()) do
                if player.Character then
                    local humanoid = player.Character:FindFirstChild("Humanoid")
                    if humanoid then
                        -- Update health, position, etc
                    end
                end
            end
            
            task.wait(0.1)  -- 10 FPS update
        end
        return "Game loop ended"
    end
})

tm:go(gameLoopId)

-- Stop on shutdown
game:BindToClose(function()
    running = false
    tm:stop(gameLoopId)
end)
```

### Example 7: Retry with Backoff

```lua
local attempt = 0

local id = tm:mk({
    name = "connect_server",
    callback = function()
        attempt = attempt + 1
        
        local success = attemptConnection()  -- Your function
        
        if not success then
            error("Connection failed (attempt " .. attempt .. ")")
        end
        
        return "Connected!"
    end,
    maxRetries = 5
})

tm:on("retry", function(task)
    local delay = math.pow(2, task.rc)  -- Exponential backoff
    print("Retry in " .. delay .. " seconds...")
end)

tm:go(id)
local ok, msg = tm:await(id, 30)

if ok then
    print("Connected:", msg)
else
    print("Failed after retries")
end
```

### Example 8: Boss Fight Phases

```lua
local tm = Teddy.new()
local boss = workspace:FindFirstChild("Boss")

-- Phase 1: Intro
local p1 = tm:mk({
    name = "phase_1_intro",
    callback = function()
        boss.Humanoid.Health = 100
        -- Play intro animation
        task.wait(3)
        return "Intro done"
    end
})

-- Phase 2: Combat (waits for Phase 1)
local p2 = tm:mk({
    name = "phase_2_combat",
    dependencies = {p1},
    callback = function()
        local damage = 0
        while damage < 50 do
            task.wait(0.5)
            damage = damage + 10
            boss.Humanoid:TakeDamage(10)
        end
        return "Phase 2 done"
    end
})

-- Phase 3: Final (waits for Phase 2)
local p3 = tm:mk({
    name = "phase_3_final",
    dependencies = {p2},
    callback = function()
        -- Play final attack
        task.wait(2)
        boss.Humanoid.Health = 0
        return "Boss defeated!"
    end
})

tm:go(p3)  -- Automatically runs: intro → combat → final
tm:await(p3)
```

### Example 9: Player Data Save/Load with DataStore (v2.1)

```lua
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local tm = Teddy.new()

local goldStore = DataStoreService:GetDataStore("PlayerGold")

Players.PlayerAdded:Connect(function(player)
    local key = "user_" .. player.UserId

    -- Budget-aware load with retry/backoff built in
    local loadId = tm:dsGet(goldStore, key)

    tm:on("ok", function(t)
        if t.id == loadId then
            local stats = Instance.new("Folder")
            stats.Name = "leaderstats"
            stats.Parent = player

            local gold = Instance.new("IntValue")
            gold.Name = "Gold"
            gold.Value = t.r or 0
            gold.Parent = stats
        end
    end)

    tm:on("err", function(t)
        if t.id == loadId then
            warn("Failed to load data for " .. player.Name .. ":", t.e)
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    local key = "user_" .. player.UserId
    local gold = player:FindFirstChild("leaderstats") and player.leaderstats.Gold.Value

    if gold then
        tm:dsSet(goldStore, key, gold)
    end
end)
```

---

## 📊 Performance Tips

### ✅ DO

```lua
-- Parallel batch processing
tm:batch(items, process, 10)

-- Use dependencies for chaining
local id2 = tm:mk({
    dependencies = {id1},
    callback = function() ... end
})
tm:go(id2)  -- Auto runs id1 first

-- Rate limit API calls
tm:mk({
    callback = api.call,
    rateLimit = 10
})

-- Listen to events for monitoring
tm:on("err", function(t) warn(t.nm, t.e) end)
```

### ❌ DON'T

```lua
-- Polling manually
while not tm:done(id) do
    task.wait()
end

-- Manual retry loops
for retry = 1, 3 do
    tm:go(id)
end

-- Ignoring errors
-- (no tm:on("err", ...))

-- Creating unlimited tasks
for i = 1, 10000 do  -- ❌ Too many
    tm:mk({ ... })
end
```

---

## 📝 API Summary

| Function | Alias | Purpose |
|----------|-------|---------|
| `mk` | add | Create task |
| `go` | start | Start task |
| `pause` | - | Pause task |
| `cont` | continue | Resume task |
| `stop` | - | Cancel task |
| `await` | wait | Wait for result |
| `st` | state | Get state |
| `is` | - | Check state |
| `info` | - | Get task info |
| `on` | - | Listen event |
| `batch` | - | Process multiple |
| `wrap` | - | Quick task |
| `all` | - | Await all tasks |
| `async` | - | Create + start in one call (v2.1) |
| `dsGet` | - | Budget-aware DataStore Get (v2.1) |
| `dsSet` | - | Budget-aware DataStore Set (v2.1) |
| `dsUpdate` | - | Budget-aware DataStore Update (v2.1) |
| `dsInc` | - | Budget-aware DataStore Increment (v2.1) |
| `dsRemove` | - | Budget-aware DataStore Remove (v2.1) |

---

## ⚠️ Common Mistakes

### ❌ Forgetting `go()`
```lua
local id = tm:mk({ ... })
-- ❌ Task never runs!
```

✅ **Always start:**
```lua
local id = tm:mk({ ... })
tm:go(id)
```

---

### ❌ Wrong callback
```lua
tm:mk({
    callback = function(arg)  -- ❌ Don't expect args
        return arg
    end
})
```

✅ **No arguments to callback:**
```lua
tm:mk({
    callback = function()  -- ✓ Correct
        return "result"
    end
})
```

---

### ❌ Dependencies as strings
```lua
tm:mk({
    dependencies = {"task1"}  -- ❌ String!
})
```

✅ **Use task IDs:**
```lua
local id1 = tm:mk({ ... })
tm:mk({
    dependencies = {id1}  -- ✓ Number ID
})
```

---

## 🎯 Optimization Checklist

- [ ] ✓ Use `batch()` for 5+ parallel items
- [ ] ✓ Use `dependencies` for chaining
- [ ] ✓ Use `rateLimit` for API calls
- [ ] ✓ Use `maxRetries` for network ops
- [ ] ✓ Listen to events for logging
- [ ] ✓ Use `await()` with timeout
- [ ] ✓ Always call `go()` to start
- [ ] ✓ Handle `err` events
- [ ] ✓ Use `ds*` helpers for DataStore instead of raw `GetAsync`/`SetAsync`
- [ ] ✓ Enable `backoff` for anything hitting a network/DataStore API

---

## 📞 Function Shortcuts

**Short form** → **Meaning**

- `mk` → make/add task
- `go` → go/start
- `st` → state
- `is` → is state
- `ok` → is successful
- `err` → is error
- `skip` → is cancelled
- `cont` → continue
- `sch` → schedule (internal)
- `run` → run/execute (internal)
- `deps` → dependencies (internal)
- `cb` → callbacks
- `t` → task object
- `nm` → name
- `f` → function
- `s` → state
- `r` → result
- `e` → error
- `c` → coroutine
- `d` → dependencies
- `p` → priority
- `rc` → retry count
- `mr` → max retries
- `rl` → rate limit
- `le` → last exec
- `to` → timeout
- `ca` → created at
- `sa` → started at
- `ea` → ended at
- `bo` → backoff config (v2.1)
- `ds` → DataStore (prefix for `dsGet`/`dsSet`/`dsUpdate`/`dsInc`/`dsRemove`, v2.1)

---

**Happy game building! 🎮🧸**