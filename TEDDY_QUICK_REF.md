# ⚡ Teddy.lua - Roblox Quick Reference

## 🎮 Setup
```lua
local Teddy = require(game.ServerScriptService:WaitForChild("teddy"))
local tm = Teddy.new()
```

## 🧵 Async / DataStore (v2.1)
```lua
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("PlayerGold")

tm:dsGet(store, key, cfg)         -- budget-aware Get
tm:dsSet(store, key, value, cfg)  -- budget-aware Set
tm:dsUpdate(store, key, fn, cfg)  -- budget-aware Update
tm:dsInc(store, key, delta, cfg)  -- budget-aware Increment
tm:dsRemove(store, key, cfg)      -- budget-aware Remove

-- All ds* helpers auto-start (autoStart=false to opt out),
-- default maxRetries=5, backoff=true.
local ok, value = tm:await(tm:dsGet(store, key), 10)

-- Generic async shortcut (create + start in one call)
local id = tm:async(function() return anyYieldingCall() end)
```

---

## ➕ Create Task
```lua
local id = tm:mk({
    name = "my_task",
    callback = function()
        return "result"
    end,
    maxRetries = 3,
    rateLimit = 5,
    backoff = true   -- NEW: exponential backoff on retry (default: fixed 1s)
})
```

---

## ▶️ Control
```lua
tm:go(id)           -- Start
tm:pause(id)        -- Pause
tm:cont(id)         -- Continue
tm:stop(id)         -- Cancel
tm:stop(id, true)   -- Force kill
```

---

## ✔️ State Checks
```lua
tm:idle(id)   -- 1: Not started
tm:run(id)    -- 2: Running
tm:pause(id)  -- 3: Paused
tm:wait(id)   -- 4: Waiting for deps
tm:ok(id)     -- 5: ✓ Done
tm:err(id)    -- 6: ✗ Error
tm:skip(id)   -- 7: Cancelled
tm:done(id)   -- Any end state?
```

---

## 📊 Get Info
```lua
local info = tm:info(id)
info.name           -- "my_task"
info.state          -- 1-7
info.result         -- Success value
info.error          -- Error message
info.retries        -- Retry count
info.done           -- true/false
info.createdAt
info.startedAt
info.endedAt
```

---

## ⏳ Wait & Get Result
```lua
local ok, result = tm:await(id)
local ok, result = tm:await(id, 5)  -- 5 sec timeout

if ok then
    print("Success:", result)
else
    print("Failed:", result)
end
```

---

## 🎧 Events
```lua
tm:on("go", function(t) end)     -- Started
tm:on("ok", function(t) end)     -- Completed ✓
tm:on("err", function(t) end)    -- Failed ✗
tm:on("retry", function(t) end)  -- Retrying
tm:on("pause", function(t) end)  -- Paused
tm:on("cont", function(t) end)   -- Continued
tm:on("skip", function(t) end)   -- Cancelled
tm:on("wait", function(t) end)   -- Waiting
tm:on("add", function(t) end)    -- Created
```

---

## 🔗 Dependencies (Sequential)
```lua
-- Task 1
local id1 = tm:mk({
    name = "download",
    callback = function()
        return "data"
    end
})

-- Task 2 (waits for task 1)
local id2 = tm:mk({
    name = "process",
    dependencies = {id1},
    callback = function()
        local data = tm:info(id1).result
        return process(data)
    end
})

tm:go(id2)  -- Starts: id1 → id2 automatically
```

---

## 🚀 Batch (Parallel)
```lua
local items = {1, 2, 3, 4, 5}

local results = tm:batch(items, function(item)
    return item * 2
end, 3)  -- 3 workers

print(results)  -- {2, 4, 6, 8, 10}
```

---

## 🎁 Utilities

### Wrap function
```lua
local id = tm:wrap("quick", function()
    return 42
end)
tm:go(id)
```

### Wait all tasks
```lua
local ids = {id1, id2, id3}
local results = tm:all(ids)

for id, res in pairs(results) do
    print(id, res.ok, res.r)
end
```

---

## 📋 Common Patterns

### Load Asset
```lua
local id = tm:mk({
    name = "load_sword",
    callback = function()
        local m = game:GetService("InsertService"):LoadAsset(12345)
        m:MoveTo(workspace)
        return m
    end
})

tm:go(id)
local ok, model = tm:await(id, 10)
```

### Spawn Enemy
```lua
local enemies = {}

for i = 1, 5 do
    local id = tm:mk({
        name = "spawn_enemy_" .. i,
        callback = function()
            local enemy = Instance.new("Part")
            enemy.Position = Vector3.new(i * 5, 5, 0)
            enemy.Parent = workspace
            return enemy
        end
    })
    table.insert(enemies, id)
end

tm:all(enemies)  -- Spawn all at once
```

### API with Rate Limit
```lua
local HTTP = game:GetService("HttpService")

for i = 1, 100 do
    local id = tm:mk({
        name = "api_call_" .. i,
        callback = function()
            return HTTP:GetAsync("https://api.example.com/data/" .. i)
        end,
        rateLimit = 10  -- 10 req/sec
    })
    tm:go(id)
end
```

### With Retry
```lua
local id = tm:mk({
    name = "connect",
    callback = function()
        local ok = attemptConnection()
        if not ok then
            error("Failed to connect")
        end
        return "Connected!"
    end,
    maxRetries = 3
})

tm:on("retry", function(t)
    print("Retry", t.rc)
end)

tm:on("err", function(t)
    print("Final error:", t.e)
end)

tm:go(id)
```

### Save/Load Player Data (DataStore)
```lua
local DataStoreService = game:GetService("DataStoreService")
local goldStore = DataStoreService:GetDataStore("PlayerGold")

-- Load (budget-aware, retries with backoff automatically)
local ok, gold = tm:await(tm:dsGet(goldStore, "user_" .. player.UserId), 10)
if ok then
    player.leaderstats.Gold.Value = gold or 0
end

-- Save
tm:dsSet(goldStore, "user_" .. player.UserId, player.leaderstats.Gold.Value)

-- Atomic increment (e.g. daily reward)
tm:dsInc(goldStore, "user_" .. player.UserId, 50)
```

### Sequential Tasks
```lua
-- Step 1
local s1 = tm:mk({
    name = "step1",
    callback = function() return "A" end
})

-- Step 2 (after 1)
local s2 = tm:mk({
    name = "step2",
    dependencies = {s1},
    callback = function()
        return tm:info(s1).result .. "B"
    end
})

-- Step 3 (after 2)
local s3 = tm:mk({
    name = "step3",
    dependencies = {s2},
    callback = function()
        return tm:info(s2).result .. "C"
    end
})

tm:go(s3)  -- Auto: s1 → s2 → s3
tm:await(s3)
print(tm:info(s3).result)  -- "ABC"
```

### Monitoring
```lua
tm:on("add", function(t)
    print("➕ Added:", t.nm)
end)

tm:on("go", function(t)
    print("⏱️  Started:", t.nm)
end)

tm:on("ok", function(t)
    print("✅ Done:", t.nm, "→", t.r)
end)

tm:on("err", function(t)
    print("❌ Failed:", t.nm, "→", t.e)
end)

tm:on("retry", function(t)
    print("🔄 Retry:", t.nm, "(" .. t.rc .. ")")
end)
```

---

## 🎯 States
```
1 = IDLE      Not started
2 = RUN       Running now
3 = PAUSE     Paused (can cont)
4 = WAIT      Waiting for deps
5 = OK        ✓ Success
6 = ERR       ✗ Failed
7 = SKIP      Cancelled
```

---

## 💡 Tips

✅ **Use `dependencies` instead of await loops**
```lua
-- ❌ Bad
tm:go(id1)
tm:await(id1)
tm:go(id2)

-- ✅ Good
tm:mk({
    dependencies = {id1},
    callback = fn
})
```

✅ **Use `batch` for 5+ parallel tasks**
```lua
-- ❌ Bad
for i = 1, 20 do tm:go(ids[i]) end

-- ✅ Good
tm:batch(items, process, 5)
```

✅ **Always use timeout**
```lua
local ok, r = tm:await(id, 10)  -- 10 sec max
```

✅ **Handle errors**
```lua
tm:on("err", function(t)
    warn("Error in " .. t.nm .. ":", t.e)
end)
```

---

## 🔥 One-Liners

```lua
-- Create and run
tm:go(tm:mk({callback = function() return 42 end}))

-- Get result immediately
local _, r = tm:await(tm:mk({callback = function() return "hi" end}))

-- Batch with print
tm:batch({1,2,3}, function(x) print(x*2) end)

-- Run async
tm:on("ok", function(t) print(t.r) end)
tm:go(tm:mk({callback = function() return "done" end}))

-- Async shortcut (create + start in one call)
local ok, r = tm:await(tm:async(function() return httpService:GetAsync(url) end))
```

---

## 🚫 Common Mistakes

```lua
-- ❌ Forgot go()
local id = tm:mk({...})
tm:await(id)  -- Hangs forever!

-- ✅ Fix
local id = tm:mk({...})
tm:go(id)
tm:await(id)

---

-- ❌ Dependencies as string
dependencies = {"id1"}

-- ✅ Fix
dependencies = {id1}  -- Use variable

---

-- ❌ Callback with args
callback = function(arg) return arg end

-- ✅ Fix
callback = function() return result end

---

-- ❌ No error handling
tm:go(id)
tm:await(id)

-- ✅ Fix
tm:on("err", function(t) print(t.e) end)
tm:go(id)
```

---

## 📊 Performance

```lua
-- Parallel: 10 tasks at once
tm:batch(items, process, 10)  -- Takes 1 second

-- Sequential: 1 task after another
for _, item in ipairs(items) do
    tm:go(process(item))
end  -- Takes 10 seconds

-- Chaining with dependencies
task1 → task2 → task3  -- Takes time1 + time2 + time3
```

---

## 🎮 Game Dev Patterns

**Player join setup:**
```lua
Players.PlayerAdded:Connect(function(p)
    local id = tm:mk({
        name = "setup_" .. p.Name,
        callback = function()
            p:WaitForDataReady()
            -- Setup...
            return p
        end
    })
    tm:go(id)
end)
```

**Game loop:**
```lua
local id = tm:mk({
    name = "gameloop",
    callback = function()
        while true do
            -- Update game
            task.wait(0.1)
        end
    end
})
tm:go(id)
```

**Boss fight phases:**
```lua
local p1 = tm:mk({name = "phase1", callback = function() ... end})
local p2 = tm:mk({name = "phase2", dependencies = {p1}, callback = ...})
local p3 = tm:mk({name = "phase3", dependencies = {p2}, callback = ...})

tm:go(p3)  -- Auto: p1 → p2 → p3
```

---

**Keep it fast, keep it clean! 🚀**