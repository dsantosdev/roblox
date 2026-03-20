print("[KAH][LOAD] dev_stronghold_spawn_probe.lua")

-- ============================================================================
-- DEV STRONGHOLD SPAWN PROBE (isolado / nao altera o principal)
-- Objetivo:
-- - Detectar spawn de mobs com contexto de passo do Stronghold.
-- - Gerar relatorio (texto + JSON) e copiar para clipboard.
-- - Expor funcoes de teste para executar fluxo/passo sem editar o modulo principal.
-- ============================================================================

local STATE_KEY = "__kah_dev_strong_spawn_probe"

do
    local old = _G[STATE_KEY]
    if type(old) == "table" and type(old.cleanup) == "function" then
        pcall(old.cleanup)
    end
    _G[STATE_KEY] = nil
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local lp = Players.LocalPlayer
if not lp then
    return
end

local PROBE_INTERVAL = tonumber(_G.KAH_DEV_SPAWN_PROBE_INTERVAL) or 0.4
local MAX_SCAN_MODELS = tonumber(_G.KAH_DEV_SPAWN_MAX_SCAN_MODELS) or 1200
local ONLY_CULTIST = (_G.KAH_DEV_SPAWN_ONLY_CULTIST == true)

local scanner = {
    running = false,
    startedAtClock = 0,
    sessionId = 0,
    conns = {},
    events = {},
    byName = {},
    byBetween = {},
    seenModels = setmetatable({}, { __mode = "k" }),
    lastProbeAt = 0,
}

local function trimInline(v)
    return tostring(v or ""):gsub("[%c]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function vec3ToLine(v)
    if typeof(v) ~= "Vector3" then
        return "nil"
    end
    return string.format("(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
end

local function copyToClipboard(text)
    local payload = tostring(text or "")
    if setclipboard then
        local ok = pcall(setclipboard, payload)
        if ok then
            return true
        end
    end
    if toclipboard then
        local ok = pcall(toclipboard, payload)
        if ok then
            return true
        end
    end
    return false
end

local function getStrongState()
    local st = _G.__stronghold_module_state
    if type(st) == "table" then
        return st
    end
    return nil
end

local function callStateFn(st, fnName, ...)
    local fn = st and st[fnName]
    if type(fn) ~= "function" then
        return false, "missing"
    end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        return false, a
    end
    return true, a, b, c
end

local function getFlowInfo()
    local st = getStrongState()
    if not st then
        return {
            running = false,
            currentIdx = 0,
            currentLabel = "",
            lastCompletedIdx = 0,
            lastCompletedLabel = "",
            debugTrying = "",
            debugDone = "",
            debugNext = "",
        }
    end
    local ok, info = callStateFn(st, "getFlowStepInfo")
    if not ok or type(info) ~= "table" then
        return {
            running = false,
            currentIdx = 0,
            currentLabel = "",
            lastCompletedIdx = 0,
            lastCompletedLabel = "",
            debugTrying = "",
            debugDone = "",
            debugNext = "",
        }
    end
    return info
end

local function buildBetweenLabel(flowInfo)
    local cur = math.max(0, math.floor(tonumber(flowInfo.currentIdx) or 0))
    local last = math.max(0, math.floor(tonumber(flowInfo.lastCompletedIdx) or 0))
    if cur > 0 and last > 0 and cur ~= last then
        return string.format("entre passo %d->%d", last, cur)
    end
    if cur > 0 then
        return string.format("durante passo %d", cur)
    end
    if last > 0 then
        return string.format("apos passo %d", last)
    end
    return "fora do fluxo"
end

local function getLocalRoot()
    local ch = lp.Character
    if not ch then
        return nil
    end
    return ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
end

local function getModelRoot(model)
    if not model or not model:IsA("Model") then
        return nil
    end
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function getPosFromModel(model)
    local root = getModelRoot(model)
    if root then
        return root.Position
    end
    local ok, cf = pcall(function()
        return model:GetPivot()
    end)
    if ok and typeof(cf) == "CFrame" then
        return cf.Position
    end
    return nil
end

local function isMobCandidate(model)
    if not model or not model:IsA("Model") then
        return false, nil
    end
    if Players:GetPlayerFromCharacter(model) then
        return false, nil
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then
        return false, nil
    end
    if ONLY_CULTIST then
        local n = string.lower(tostring(model.Name or ""))
        if not string.find(n, "cultist", 1, true) then
            return false, nil
        end
    end
    return true, hum
end

local function pushEvent(name, reason, model, hum)
    local flowInfo = getFlowInfo()
    local between = buildBetweenLabel(flowInfo)
    local pos = model and getPosFromModel(model) or nil
    local localRoot = getLocalRoot()
    local dist = nil
    if typeof(pos) == "Vector3" and localRoot then
        dist = (pos - localRoot.Position).Magnitude
    end
    local fullPath = "?"
    local parentPath = "?"
    if model then
        pcall(function()
            fullPath = model:GetFullName()
        end)
        pcall(function()
            parentPath = model.Parent and model.Parent:GetFullName() or "?"
        end)
    end

    local ev = {
        idx = #scanner.events + 1,
        t = os.clock(),
        reason = tostring(reason or "spawn"),
        name = tostring(name or "?"),
        fullPath = tostring(fullPath or "?"),
        parentPath = tostring(parentPath or "?"),
        pos = pos,
        dist = dist,
        health = hum and tonumber(hum.Health) or nil,
        maxHealth = hum and tonumber(hum.MaxHealth) or nil,
        between = between,
        stepCurrent = math.max(0, math.floor(tonumber(flowInfo.currentIdx) or 0)),
        stepCurrentLabel = trimInline(flowInfo.currentLabel),
        stepLast = math.max(0, math.floor(tonumber(flowInfo.lastCompletedIdx) or 0)),
        stepLastLabel = trimInline(flowInfo.lastCompletedLabel),
        debugTrying = trimInline(flowInfo.debugTrying),
        debugDone = trimInline(flowInfo.debugDone),
        debugNext = trimInline(flowInfo.debugNext),
        strongRunning = flowInfo.running == true,
    }

    table.insert(scanner.events, ev)
    scanner.byName[ev.name] = (scanner.byName[ev.name] or 0) + 1
    scanner.byBetween[ev.between] = (scanner.byBetween[ev.between] or 0) + 1
end

local function addMobEvent(model, reason)
    if not scanner.running then
        return false
    end
    if not model or not model.Parent or not model:IsA("Model") then
        return false
    end
    if scanner.seenModels[model] then
        return false
    end
    local okMob, hum = isMobCandidate(model)
    if not okMob then
        return false
    end
    scanner.seenModels[model] = true
    pushEvent(model.Name, reason, model, hum)
    return true
end

local function bindScannerContainer(label, container)
    if not container then
        return
    end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Model") then
            addMobEvent(child, label .. ":existing")
        end
    end
    table.insert(scanner.conns, container.ChildAdded:Connect(function(child)
        if child and child:IsA("Model") then
            addMobEvent(child, label .. ":child_added")
        end
    end))
end

local function disconnectScanner()
    for _, c in ipairs(scanner.conns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    scanner.conns = {}
end

local function resetScannerData()
    scanner.events = {}
    scanner.byName = {}
    scanner.byBetween = {}
    scanner.seenModels = setmetatable({}, { __mode = "k" })
end

local function periodicProbe()
    if not scanner.running then
        return
    end
    local now = os.clock()
    if (now - scanner.lastProbeAt) < PROBE_INTERVAL then
        return
    end
    scanner.lastProbeAt = now

    local scanned = 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        if not scanner.running then
            return
        end
        if scanned >= MAX_SCAN_MODELS then
            break
        end
        if obj:IsA("Model") then
            scanned += 1
            addMobEvent(obj, "periodic_probe")
        end
    end
end

local function buildScannerReport()
    local flowNow = getFlowInfo()
    local duration = 0
    if tonumber(scanner.startedAtClock) and scanner.startedAtClock > 0 then
        duration = os.clock() - scanner.startedAtClock
    end

    local lines = {}
    lines[#lines + 1] = "DEV_STRONG_MOB_SCANNER_PROBE"
    lines[#lines + 1] = string.format(
        "session=%d | place=%s | job=%s | user=%s(%d)",
        tonumber(scanner.sessionId) or 0,
        tostring(game.PlaceId),
        tostring(game.JobId),
        tostring(lp.Name or "?"),
        tonumber(lp.UserId or 0)
    )
    lines[#lines + 1] = string.format(
        "started_clock=%.3f | duration_sec=%.3f | total_events=%d | only_cultist=%s",
        tonumber(scanner.startedAtClock) or 0,
        tonumber(duration) or 0,
        #scanner.events,
        tostring(ONLY_CULTIST == true)
    )
    lines[#lines + 1] = string.format(
        "flow_now cur=%d:%s | last=%d:%s | running=%s",
        math.max(0, math.floor(tonumber(flowNow.currentIdx) or 0)),
        trimInline(flowNow.currentLabel),
        math.max(0, math.floor(tonumber(flowNow.lastCompletedIdx) or 0)),
        trimInline(flowNow.lastCompletedLabel),
        tostring(flowNow.running == true)
    )
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[BY_NAME]"
    do
        local names = {}
        for name, _ in pairs(scanner.byName) do
            names[#names + 1] = name
        end
        table.sort(names, function(a, b)
            return tostring(a):lower() < tostring(b):lower()
        end)
        if #names == 0 then
            lines[#lines + 1] = "none=0"
        else
            for _, name in ipairs(names) do
                lines[#lines + 1] = string.format("%s=%d", trimInline(name), tonumber(scanner.byName[name]) or 0)
            end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[BY_BETWEEN_STEP]"
    do
        local keys = {}
        for key, _ in pairs(scanner.byBetween) do
            keys[#keys + 1] = key
        end
        table.sort(keys, function(a, b)
            return tostring(a):lower() < tostring(b):lower()
        end)
        if #keys == 0 then
            lines[#lines + 1] = "none=0"
        else
            for _, key in ipairs(keys) do
                lines[#lines + 1] = string.format("%s=%d", trimInline(key), tonumber(scanner.byBetween[key]) or 0)
            end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[EVENTS]"
    if #scanner.events == 0 then
        lines[#lines + 1] = "(no events)"
    else
        for _, ev in ipairs(scanner.events) do
            lines[#lines + 1] = string.format(
                "#%d t=%.3f name=%s reason=%s between=%s cur=%d:%s last=%d:%s pos=%s dist=%.1f hp=%.1f/%.1f parent=%s full=%s dbg_try=%s dbg_next=%s",
                tonumber(ev.idx) or 0,
                tonumber(ev.t) or 0,
                trimInline(ev.name),
                trimInline(ev.reason),
                trimInline(ev.between),
                tonumber(ev.stepCurrent) or 0,
                trimInline(ev.stepCurrentLabel),
                tonumber(ev.stepLast) or 0,
                trimInline(ev.stepLastLabel),
                vec3ToLine(ev.pos),
                tonumber(ev.dist) or -1,
                tonumber(ev.health) or -1,
                tonumber(ev.maxHealth) or -1,
                trimInline(ev.parentPath),
                trimInline(ev.fullPath),
                trimInline(ev.debugTrying),
                trimInline(ev.debugNext)
            )
        end
    end

    local jsonRows = {}
    for _, ev in ipairs(scanner.events) do
        local pos = nil
        if typeof(ev.pos) == "Vector3" then
            pos = { x = ev.pos.X, y = ev.pos.Y, z = ev.pos.Z }
        end
        jsonRows[#jsonRows + 1] = {
            idx = ev.idx,
            t = ev.t,
            name = ev.name,
            reason = ev.reason,
            between = ev.between,
            stepCurrent = ev.stepCurrent,
            stepCurrentLabel = ev.stepCurrentLabel,
            stepLast = ev.stepLast,
            stepLastLabel = ev.stepLastLabel,
            pos = pos,
            dist = ev.dist,
            health = ev.health,
            maxHealth = ev.maxHealth,
            parentPath = ev.parentPath,
            fullPath = ev.fullPath,
            strongRunning = ev.strongRunning,
        }
    end

    local encoded = nil
    pcall(function()
        encoded = HttpService:JSONEncode({
            sessionId = scanner.sessionId,
            placeId = game.PlaceId,
            jobId = game.JobId,
            userId = lp.UserId,
            byName = scanner.byName,
            byBetween = scanner.byBetween,
            events = jsonRows,
        })
    end)
    if type(encoded) == "string" and #encoded > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[JSON]"
        lines[#lines + 1] = encoded
    end

    return table.concat(lines, "\n")
end

local api = {}

function api.start()
    if scanner.running then
        return true, "already_running"
    end
    disconnectScanner()
    resetScannerData()
    scanner.running = true
    scanner.sessionId = (tonumber(scanner.sessionId) or 0) + 1
    scanner.startedAtClock = os.clock()
    scanner.lastProbeAt = 0

    bindScannerContainer("workspace.Characters", workspace:FindFirstChild("Characters"))
    bindScannerContainer("workspace.Enemies", workspace:FindFirstChild("Enemies"))
    bindScannerContainer("workspace.NPCs", workspace:FindFirstChild("NPCs"))

    table.insert(scanner.conns, workspace.DescendantAdded:Connect(function(obj)
        if not scanner.running then
            return
        end
        if obj:IsA("Model") then
            addMobEvent(obj, "workspace:desc_model")
            return
        end
        if obj:IsA("Humanoid") then
            local model = obj.Parent
            if model and model:IsA("Model") then
                addMobEvent(model, "workspace:desc_humanoid")
            end
        end
    end))

    table.insert(scanner.conns, RunService.Heartbeat:Connect(function()
        periodicProbe()
    end))

    return true
end

function api.stop(copyReport)
    if not scanner.running then
        return false, nil, false
    end
    scanner.running = false
    disconnectScanner()
    local report = buildScannerReport()
    local doCopy = (copyReport ~= false)
    local copied = false
    if doCopy then
        copied = copyToClipboard(report)
    end
    return true, report, copied
end

function api.mark(note)
    local label = tostring(note or "manual_mark")
    pushEvent("[MARK] " .. label, "manual_mark", nil, nil)
    return true
end

function api.status()
    return {
        running = scanner.running == true,
        total = #scanner.events,
        sessionId = scanner.sessionId,
        startedAtClock = scanner.startedAtClock,
        interval = PROBE_INTERVAL,
        onlyCultist = ONLY_CULTIST == true,
    }
end

function api.runStep(idx)
    local st = getStrongState()
    if not st then
        return false, "stronghold_state_missing"
    end
    return callStateFn(st, "runStep", math.floor(tonumber(idx) or 0))
end

function api.runAll()
    local st = getStrongState()
    if not st then
        return false, "stronghold_state_missing"
    end
    return callStateFn(st, "runAll")
end

function api.stopStrong()
    local st = getStrongState()
    if not st then
        return false, "stronghold_state_missing"
    end
    return callStateFn(st, "stop")
end

function api.getFlowInfo()
    return getFlowInfo()
end

function api.cleanup()
    scanner.running = false
    disconnectScanner()
    _G[STATE_KEY] = nil
end

_G[STATE_KEY] = api
_G.__kah_dev_strong_spawn_probe = api

print("[KAH][READY] Spawn probe pronto. Use _G.__kah_dev_strong_spawn_probe.start()/stop().")
