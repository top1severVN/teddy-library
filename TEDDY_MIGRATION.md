# 🔄 Teddy.lua API Migration Guide

> From original to optimized - all examples side-by-side

---

## 🆙 Upgrading from 2.0 → 2.1 (Async/DataStore update)

**Nothing breaks.** 2.1 is purely additive — every 2.0 API keeps working
unchanged. You only need to change anything if you want to *opt in* to the
new features:

| New in 2.1 | Old way (2.0, still works) | New way |
|------------|------------------------------|---------|
| Async shortcut | `local id = tm:mk({...}); tm:go(id)` | `local id = tm:async(function() ... end)` |
| DataStore Get | `tm:mk({callback = function() return store:GetAsync(key) end})` | `tm:dsGet(store, key)` |
| DataStore Set | `tm:mk({callback = function() store:SetAsync(key, v) end})` | `tm:dsSet(store, key, v)` |
| Retry delay | Always fixed 1s | Add `backoff = true` to any `mk()`/`ds*` config for exponential backoff |

No renamed functions, no changed event names, no changed property names —
see the rest of this guide for the 1.0 → 2.0 renames, which are unaffected.

---

## ✅ Most APIs Stay Identical

These work exactly the same in both versions:

```lua
-- IDENTICAL in both versions:
tm:info(id)
tm:await(id)
tm:await(id, timeout)
tm:on(event, callback)
tm:batch(items, processor, concurrency)
tm:wrap(name, fn)
tm:all(ids)
tm:pause(id)
tm:stop(id)
tm:stop(id, force)
```

---

## 🔀 APIs That Changed

### Task Creation

```lua
-- BEFORE
local id = tm:add({
    name = "my_task",
    callback = function()
        return "result"
    end
})

-- AFTER (only function name changed)
local id = tm:mk({
    name = "my_task",
    callback = function()
        return "result"
    end
})

-- Same config object, just different method name
```

---

### Starting Tasks

```lua
-- BEFORE
tm:start(id)

-- AFTER
tm:go(id)

-- Same functionality, just shorter name
```

---

### Resuming Paused Tasks

```lua
-- BEFORE
tm:resume(id)

-- AFTER
tm:cont(id)

-- "cont" = continue (shorter, still clear)
```

---

### State Checking

```lua
-- BEFORE
if tm:idle(id) then ... end
if tm:run(id) then ... end      -- "run" but not the method name!
if tm:paused(id) then ... end
if tm:wait(id) then ... end
if tm:done(id) then ... end
if tm:failed(id) then ... end
if tm:cancel(id) then ... end
if tm:finish(id) then ... end

-- AFTER (better semantics)
if tm:idle(id) then ... end
if tm:run(id) then ... end       -- Same
if tm:pause(id) then ... end     -- Changed name!
if tm:wait(id) then ... end      -- Changed name!
if tm:ok(id) then ... end        -- New: success state
if tm:err(id) then ... end       -- New: error state
if tm:skip(id) then ... end      -- New: cancelled state
if tm:done(id) then ... end      -- Better logic

-- Migration:
tm:failed(id) → tm:err(id)
tm:cancel(id) → tm:skip(id)
tm:finish(id) → tm:done(id)
```

---

### Getting State

```lua
-- BEFORE
local state = task:getState()
local isRunning = task:run(id)

-- AFTER
local state = tm:st(id)         -- Get state number
local isRunning = tm:run(id)    -- Same check method
local isRunning = tm:is(id, 2)  -- Alternative: explicit state
```

---

## 🎯 Real-World Migration Examples

### Example 1: Simple Task

**BEFORE:**
```lua
local Teddy = require(game.ServerScriptService:WaitForChild("Teddy"))
local tm = Teddy.new()

local id = tm:add({
    name = "load_sword",
    callback = function()
        local sword = game:GetService("InsertService"):LoadAsset(12345)
        return sword:GetChildren()[1]
    end
})

tm:start(id)
local ok, sword = tm:await(id)

if ok then
    print("Loaded:", sword.Name)
end
```

**AFTER (only 2 lines change):**
```lua
local Teddy = require(game.ServerScriptService:WaitForChild("Teddy"))
local tm = Teddy.new()

local id = tm:mk({  -- ← Changed
    name = "load_sword",
    callback = function()
        local sword = game:GetService("InsertService"):LoadAsset(12345)
        return sword:GetChildren()[1]
    end
})

tm:go(id)  -- ← Changed
local ok, sword = tm:await(id)

if ok then
    print("Loaded:", sword.Name)
end
```

---

### Example 2: State Checking

**BEFORE:**
```lua
local taskId = tm:add({ ... })
tm:start(taskId)

while not tm:finish(taskId) do
    if tm:failed(taskId) then
        print("Task failed!")
        break
    end
    task.wait(0.1)
end

if tm:done(taskId) then
    print("Task completed!")
end
```

**AFTER:**
```lua
local id = tm:mk({ ... })
tm:go(id)

while not tm:done(id) do  -- ← Better name
    if tm:err(id) then     -- ← Better: err instead of failed
        print("Task failed!")
        break
    end
    task.wait(0.1)
end

if tm:ok(id) then          -- ← Better: ok instead of done for success
    print("Task completed!")
end
```

---

### Example 3: Sequential Tasks

**BEFORE:**
```lua
local step1 = tm:add({
    name = "download",
    callback = function() return download() end
})

local step2 = tm:add({
    name = "process",
    dependencies = {step1},
    callback = function()
        return process(tm:info(step1).result)
    end
})

tm:start(step2)
tm:await(step2)

if tm:done(step2) then
    print("All steps complete!")
end
```

**AFTER:**
```lua
local step1 = tm:mk({
    name = "download",
    callback = function() return download() end
})

local step2 = tm:mk({
    name = "process",
    dependencies = {step1},
    callback = function()
        return process(tm:info(step1).result)
    end
})

tm:go(step2)
tm:await(step2)

if tm:done(step2) then
    print("All steps complete!")
end
```

**Changes:** `add` → `mk`, `start` → `go`

---

### Example 4: Event Handling

**BEFORE:**
```lua
local taskId = tm:add({ ... })

tm:on("start", function(task)
    print("Started:", task.name)
end)

tm:on("done", function(task)
    print("✓ Done:", task.name)
end)

tm:on("fail", function(task)
    print("✗ Failed:", task.name, "→", task.error)
end)

tm:on("retry", function(task)
    print("Retry", task.name, "attempt", task.retryCount)
end)

tm:start(taskId)
```

**AFTER:**
```lua
local id = tm:mk({ ... })

tm:on("go", function(t)  -- ← "start" renamed to "go"
    print("Started:", t.nm)  -- ← "name" property can be accessed as "nm"
end)

tm:on("ok", function(t)  -- ← "done" renamed to "ok"
    print("✓ Done:", t.nm)
end)

tm:on("err", function(t)  -- ← "fail" renamed to "err"
    print("✗ Failed:", t.nm, "→", t.e)  -- ← "error" is "e"
end)

tm:on("retry", function(t)
    print("Retry", t.nm, "attempt", t.rc)  -- ← "retryCount" is "rc"
end)

tm:go(id)
```

**Event name changes:**
- `start` → `go`
- `done` → `ok`
- `fail` → `err`

**Task property names:**
- `task.name` → `task.nm`
- `task.error` → `task.e`
- `task.retryCount` → `task.rc`
- `task.result` → `task.r`

---

### Example 5: Monitoring with Shorthand

**BEFORE:**
```lua
local tm = Teddy.new()

tm:on("start", function(task)
    print("⏱️ Started:", task.name)
end)

tm:on("done", function(task)
    print("✅ Done:", task.name, "Result:", task.result)
end)

tm:on("fail", function(task)
    print("❌ Failed:", task.name, "Error:", task.error)
end)

tm:on("retry", function(task)
    print("🔄 Retry:", task.name, "Attempt", task.retryCount)
end)

local id = tm:add({
    name = "api_call",
    callback = function()
        return httpService:GetAsync("https://api.example.com")
    end,
    maxRetries = 3
})

tm:start(id)
```

**AFTER:**
```lua
local tm = Teddy.new()

tm:on("go", function(t)
    print("⏱️ Started:", t.nm)
end)

tm:on("ok", function(t)
    print("✅ Done:", t.nm, "Result:", t.r)
end)

tm:on("err", function(t)
    print("❌ Failed:", t.nm, "Error:", t.e)
end)

tm:on("retry", function(t)
    print("🔄 Retry:", t.nm, "Attempt", t.rc)
end)

local id = tm:mk({
    name = "api_call",
    callback = function()
        return httpService:GetAsync("https://api.example.com")
    end,
    maxRetries = 3
})

tm:go(id)
```

---

## 📋 Migration Checklist

- [ ] Replace `tm:add(` with `tm:mk(`
- [ ] Replace `tm:start(` with `tm:go(`
- [ ] Replace `tm:resume(` with `tm:cont(`
- [ ] Replace `tm:failed(id)` with `tm:err(id)`
- [ ] Replace `tm:cancel(id)` with `tm:skip(id)`
- [ ] Replace `tm:finish(id)` with `tm:done(id)`
- [ ] Update event names:
  - [ ] `"start"` → `"go"`
  - [ ] `"done"` → `"ok"`
  - [ ] `"fail"` → `"err"`
- [ ] Update task property references in event handlers:
  - [ ] `task.name` → `task.nm`
  - [ ] `task.error` → `task.e`
  - [ ] `task.result` → `task.r`
  - [ ] `task.retryCount` → `task.rc`
  - [ ] `task.createdAt` → `task.ca`
  - [ ] `task.startedAt` → `task.sa`
  - [ ] `task.completedAt` → `task.ea`

---

## 🔍 Migration Script Template

Use this template to migrate existing code:

```lua
-- Copy your old code and use these replacements:

local originalCode = [[
    local id = tm:add({ ... })
    tm:start(id)
    tm:resume(id)
    if tm:failed(id) then
    if tm:cancel(id) then
    if tm:finish(id) then
    tm:on("start", ...)
    tm:on("done", ...)
    tm:on("fail", ...)
]]

-- Replace with:
-- add → mk
-- start → go
-- resume → cont
-- failed → err
-- cancel → skip
-- finish → done
-- "start" → "go"
-- "done" → "ok"
-- "fail" → "err"
```

---

## ⚠️ Breaking Changes Summary

| Old | New | Type | Fix |
|-----|-----|------|-----|
| `tm:add()` | `tm:mk()` | Function rename | Global replace |
| `tm:start()` | `tm:go()` | Function rename | Global replace |
| `tm:resume()` | `tm:cont()` | Function rename | Global replace |
| `tm:failed()` | `tm:err()` | Function rename | Global replace |
| `tm:cancel()` | `tm:skip()` | Function rename | Global replace |
| `tm:finish()` | `tm:done()` | Function rename | Verify logic |
| `"start"` event | `"go"` event | Event rename | Update handlers |
| `"done"` event | `"ok"` event | Event rename | Update handlers |
| `"fail"` event | `"err"` event | Event rename | Update handlers |
| `task.name` | `task.nm` | Property rename | Update refs |
| `task.error` | `task.e` | Property rename | Update refs |
| `task.result` | `task.r` | Property rename | Update refs |
| `task.retryCount` | `task.rc` | Property rename | Update refs |

---

## ✅ Backward Compat Notes

### What DOESN'T Change
```lua
-- All of these stay the same:
tm:info(id)
tm:await(id)
tm:await(id, timeout)
tm:on(event, cb)
tm:batch(items, processor, concurrency)
tm:wrap(name, fn)
tm:all(ids)
tm:pause(id)
tm:stop(id)
tm:stop(id, force)

-- State check methods (names stay same):
tm:idle(id)
tm:run(id)
tm:pause(id)
tm:wait(id)
tm:ok(id)      -- New in optimized
tm:err(id)     -- New in optimized
tm:skip(id)    -- New in optimized
tm:done(id)    -- Improved behavior
```

### What DOES Change
```lua
-- Function names:
tm:add → tm:mk
tm:start → tm:go
tm:resume → tm:cont
tm:failed → tm:err
tm:cancel → tm:skip
tm:finish → tm:done

-- Event names:
"start" → "go"
"done" → "ok"
"fail" → "err"

-- Task property names:
task.name → task.nm
task.error → task.e
task.result → task.r
task.retryCount → task.rc
task.createdAt → task.ca
task.startedAt → task.sa
task.completedAt → task.ea
```

---

## 🚀 Migration Time Estimate

- **Small project (< 10 tasks):** 5 minutes (manual)
- **Medium project (< 100 tasks):** 10 minutes (find & replace)
- **Large project (1000+ tasks):** 30 minutes (careful review)

**Pro tip:** Use your IDE's find & replace with regex to automate most changes.

---

**Ready to upgrade? 🎉**