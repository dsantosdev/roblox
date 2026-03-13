print('[KAH][LOAD] jungleTemple.lua')
-- ============================================
-- MODULE: JUNGLE TEMPLE (NO UI)
-- ============================================

local CATEGORIA = "Farm"
local MODULE_NAME = "JG Temple"
local STRONG_RUNNING_KEY = "__kah_stronghold_running"
local MODULE_STATE_KEY = "__jungle_temple_module_state"

if not _G.Hub and not _G.HubFila then
    return
end

do
    local old = _G[MODULE_STATE_KEY]
    if old and old.cleanup then
        pcall(old.cleanup)
    end
    _G[MODULE_STATE_KEY] = nil
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local CYCLE_COOLDOWN_SEC  = 5 * 60
local RETRY_DELAY_SEC     = 3
local CHECK_INTERVAL_SEC  = 0.8
local STRONG_PRIORITY_SEC = 60
local CHEST_PREWAIT_SEC   = 5
local CHEST_BURST_SEC     = 5
local TIMER_DURATION_SEC  = 310

local enabled   = false
local running   = false
local loopThread = nil
local unlockConns = {}
local templeUnlockSignalAt = 0
local nextRunAt = 0
local lastStrongEnableTryAt = 0
local timerStartedAt = nil
local toggleGeneration = 0
local postTempleBusy = false
local lastTempleCenter = nil
local strongPriorityPending = false
local lastStatusText = ""

-- ============================================
-- HELPERS DE TEMPO
-- ============================================
local function nowClock()
    return os.clock()
end

local function parseClockSeconds(text)
    if type(text) ~= "string" then return nil end
    local m, s = string.match(text, "(%d+)%s*[mM]%s*(%d+)%s*[sS]")
    if m and s then return (tonumber(m) or 0) * 60 + (tonumber(s) or 0) end
    local mm, ss = string.match(text, "(%d+)%s*:%s*(%d+)")
    if mm and ss then return (tonumber(mm) or 0) * 60 + (tonumber(ss) or 0) end
    return nil
end

local function formatTimer(secs)
    secs = math.max(0, math.floor(secs))
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- ============================================
-- STRONGHOLD
-- ============================================
local function getByPath(root, ...)
    local cur = root
    for _, name in ipairs({...}) do
        if not cur then return nil end
        cur = cur:FindFirstChild(name)
    end
    return cur
end

local function readStrongholdSignSeconds()
    local body = getByPath(workspace, "Map", "Landmarks", "Stronghold", "Functional", "Sign", "SurfaceGui", "Frame", "Body")
    if body and body:IsA("TextLabel") then
        local secs = parseClockSeconds(body.Text)
        if secs ~= nil then return secs end
    end
    local sign = getByPath(workspace, "Map", "Landmarks", "Stronghold", "Functional", "Sign")
    if sign then
        for _, d in ipairs(sign:GetDescendants()) do
            if d:IsA("TextLabel") then
                local secs = parseClockSeconds(d.Text)
                if secs ~= nil then return secs end
            end
        end
    end
    return nil
end

local function isStrongExecuting()
    return _G[STRONG_RUNNING_KEY] == true
end

local function shouldPrioritizeStronghold()
    local secs = readStrongholdSignSeconds()
    if not secs then return false end
    if secs > STRONG_PRIORITY_SEC then return false end
    local now = nowClock()
    if (now - lastStrongEnableTryAt) >= 5 then
        lastStrongEnableTryAt = now
        if _G.Hub and _G.Hub.setEstado then
            pcall(function() _G.Hub.setEstado("Stronghold", true) end)
        end
    end
    return true
end

-- ============================================
-- TP VIA KAHtp (com fallback local)
-- ============================================
local function getHRP()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function tpLocal(cf)
    local hrp = getHRP()
    if not hrp then return false end
    local lock = true
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not lock then conn:Disconnect() return end
        local h = getHRP()
        if h then h.CFrame = cf end
    end)
    task.delay(0.9, function() lock = false end)
    return true
end

local function usarTp(fn)
    if _G.KAHtp then
        fn(_G.KAHtp)
    else
        _G.KAHtpFila = _G.KAHtpFila or {}
        table.insert(_G.KAHtpFila, function() fn(_G.KAHtp) end)
    end
end

local function tpCF(cf)
    usarTp(function(api)
        if api and api.teleportar then api.teleportar(cf)
        else tpLocal(cf) end
    end)
end

-- ============================================
-- OBJETO HELPERS
-- ============================================
local function getMainPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        local main = obj:FindFirstChild("Main", true)
        if main and main:IsA("BasePart") then return main end
        if obj.PrimaryPart then return obj.PrimaryPart end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end
    local main = obj:FindFirstChild("Main", true)
    if main and main:IsA("BasePart") then return main end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end

local function getCF(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.CFrame end
    if obj:IsA("Model") then
        local ok, cf = pcall(function() return obj:GetPivot() end)
        if ok and cf then return cf end
    end
    local main = getMainPart(obj)
    return main and main.CFrame or nil
end

local function moveObj(obj, cf)
    if not obj or not cf then return false end
    if obj:IsA("BasePart") then obj.CFrame = cf return true end
    if obj:IsA("Model") then
        local ok = pcall(function() obj:PivotTo(cf) end)
        if ok then return true end
    end
    local main = getMainPart(obj)
    if main then main.CFrame = cf return true end
    return false
end

local function getObjectPos(obj)
    local cf = getCF(obj)
    return cf and cf.Position or nil
end

local function getTempleCFFromTeleporter()
    local tp = _G.KAHtp
    if type(tp) == "table" and type(tp.getTemploCf) == "function" then
        local ok, cf = pcall(tp.getTemploCf)
        if ok and typeof(cf) == "CFrame" then
            return cf
        end
    end
    return nil
end

-- ============================================
-- PODIUMS / KEYS
-- ============================================
local function scanPodiums()
    local out = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name == "JungleGemPodium" then
            out[#out + 1] = d
        end
    end
    return out
end

local function allPodiumsFilled(podiums)
    for _, p in ipairs(podiums) do
        if p:GetAttribute("GemAdded") ~= true then return false end
    end
    return true
end

local function getCentro(podiums)
    local sum = Vector3.new(0, 0, 0)
    local count = 0
    for _, p in ipairs(podiums) do
        local pos = getObjectPos(p)
        if pos then sum += pos count += 1 end
    end
    if count <= 0 then return nil end
    return sum / count
end

local function normalizeKeyRoot(inst)
    if not inst then return nil end
    local model = inst:IsA("Model") and inst or inst:FindFirstAncestorWhichIsA("Model")
    if model then return model end
    if inst:IsA("BasePart") then return inst end
    return nil
end

local function getKeys()
    local keys = {}
    local seen = {}
    local items = workspace:FindFirstChild("Items")
    if not items then return keys end
    for _, d in ipairs(items:GetDescendants()) do
        local nm = string.lower(tostring(d.Name or ""))
        if string.find(nm, "crystal skull key", 1, true) then
            local root = normalizeKeyRoot(d)
            if root and not seen[root] and getMainPart(root) then
                seen[root] = true
                keys[#keys + 1] = root
            end
        end
    end
    return keys
end

local function getKeyMaisProxima(targetPos, keys, used)
    local best, bestDist
    for _, key in ipairs(keys) do
        if not used[key] then
            local p = getObjectPos(key)
            if p then
                local d = (p - targetPos).Magnitude
                if not bestDist or d < bestDist then
                    best = key
                    bestDist = d
                end
            end
        end
    end
    return best
end

-- ============================================
-- INTERAÇÃO COM PODIUMS
-- ============================================
local function tryRequestAddGem(remoteFn, podium, key)
    if not remoteFn then return end
    pcall(function() remoteFn:InvokeServer() end)
    pcall(function() remoteFn:InvokeServer(podium) end)
    pcall(function() remoteFn:InvokeServer(key) end)
    pcall(function() remoteFn:InvokeServer(podium, key) end)
    pcall(function() remoteFn:InvokeServer(key, podium) end)
end

local function tryPrompts(obj)
    if type(fireproximityprompt) ~= "function" then return end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            pcall(function() fireproximityprompt(d) end)
            task.wait(0.03)
        end
    end
end

local function tryMouseClick(key)
    local main = getMainPart(key)
    if not main then return end
    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(main.Position + Vector3.new(0, 3, 0))
        task.wait(0.2)
    end
    pcall(function()
        local mouse = player:GetMouse()
        moveObj(key, mouse.Hit)
        task.wait(0.1)
        mouse1press(main)
        task.wait(0.1)
        mouse1release(main)
    end)
end

-- ============================================
-- UNLOCK EVENTS
-- ============================================
local function disconnectUnlockEvents()
    for i = #unlockConns, 1, -1 do
        local c = unlockConns[i]
        if c then pcall(function() c:Disconnect() end) end
        unlockConns[i] = nil
    end
end

local function bindUnlockEvents()
    if #unlockConns > 0 then return end
    local function bindEvent(name)
        local ev = RS:FindFirstChild(name, true)
        if ev and ev:IsA("RemoteEvent") then
            local c = ev.OnClientEvent:Connect(function()
                templeUnlockSignalAt = nowClock()
            end)
            table.insert(unlockConns, c)
        end
    end
    bindEvent("UnlockJungleTempleAnimation")
    bindEvent("AnimateJungleTempleStairs")
end

-- ============================================
-- PÓS-ABERTURA: CHEST FARM BURST + GEM COLLECTOR
-- ============================================
local function ativarCollector(gen)
    if not enabled or gen ~= toggleGeneration then return end
    if _G.GemCollector and _G.GemCollector.ativar then
        pcall(_G.GemCollector.ativar)
    elseif _G.Hub then
        pcall(function() _G.Hub.setEstado("Gem Collector", true) end)
    end
end

local function runChestFarmBurst(gen, seconds)
    if not enabled or gen ~= toggleGeneration then return end
    local burstSec = math.max(0, tonumber(seconds) or CHEST_BURST_SEC)
    local usedApi = false
    local api = _G.__kah_chest_farm_api
    if type(api) == "table" and type(api.runFor) == "function" then
        usedApi = true
        pcall(api.runFor, burstSec)
        return
    end
    if _G.Hub and _G.Hub.setEstado then
        usedApi = true
        pcall(function() _G.Hub.setEstado("Chest Farm", true) end)
        local untilAt = os.clock() + burstSec
        while os.clock() < untilAt do
            if not enabled or gen ~= toggleGeneration then break end
            task.wait(0.1)
        end
        pcall(function() _G.Hub.setEstado("Chest Farm", false) end)
    end
    if not usedApi then
        local untilAt = os.clock() + burstSec
        while os.clock() < untilAt do
            if not enabled or gen ~= toggleGeneration then break end
            task.wait(0.1)
        end
    end
end

local function waitWithGuard(gen, seconds)
    local sec = math.max(0, tonumber(seconds) or 0)
    local untilAt = os.clock() + sec
    while os.clock() < untilAt do
        if not enabled or gen ~= toggleGeneration then
            return false
        end
        task.wait(0.1)
    end
    return true
end

-- ============================================
-- ON TEMPLE OPENED
-- ============================================
local function onTempleOpened()
    if not enabled then return end
    timerStartedAt = nowClock()
    if postTempleBusy then return end
    postTempleBusy = true
    local gen = toggleGeneration
    task.spawn(function()
        pcall(function()
            if not waitWithGuard(gen, CHEST_PREWAIT_SEC) then
                return
            end
            runChestFarmBurst(gen, CHEST_BURST_SEC)
            ativarCollector(gen)
        end)
        postTempleBusy = false
    end)
end

-- ============================================
-- CYCLE PRINCIPAL
-- ============================================
local function openTempleCycle()
    if not enabled then return false end
    local podiums = scanPodiums()
    if #podiums == 0 then
        local cfFromTp = getTempleCFFromTeleporter()
        if cfFromTp then
            tpCF(cfFromTp)
            task.wait(1.0)
            podiums = scanPodiums()
        end
    end
    if #podiums == 0 and lastTempleCenter then
        tpCF(CFrame.new(lastTempleCenter))
        task.wait(1.0)
        podiums = scanPodiums()
    end
    if #podiums == 0 then return false end

    local keys = getKeys()
    if #keys < #podiums then return false end

    local centro = getCentro(podiums)
    if not centro then return false end
    lastTempleCenter = centro

    tpCF(CFrame.new(centro))
    task.wait(0.8)
    if not enabled then return false end

    local requestFn = nil
    local rf = RS:FindFirstChild("RequestAddJungleTempleGem", true)
    if rf and rf:IsA("RemoteFunction") then requestFn = rf end

    local used = {}
    local positioned = {}

    for i, podium in ipairs(podiums) do
        if not enabled then return false end
        if podium:GetAttribute("GemAdded") == true then continue end
        local podiumCF = getCF(podium)
        if not podiumCF then return false end
        local key = getKeyMaisProxima(podiumCF.Position, keys, used)
        if not key then return false end
        moveObj(key, podiumCF * CFrame.new(0, 3, 0))
        used[key] = true
        positioned[i] = key
        task.wait(0.25)
    end

    task.wait(0.4)

    local cycleStartedAt = nowClock()

    for i, key in ipairs(positioned) do
        if not enabled then return false end
        if not key then continue end
        local podium = podiums[i]
        if not podium or podium:GetAttribute("GemAdded") == true then continue end
        local podiumCF = getCF(podium)
        if not podiumCF then continue end
        moveObj(key, podiumCF * CFrame.new(0, 3, 0))
        task.wait(0.12)
        tryRequestAddGem(requestFn, podium, key)
        tryPrompts(podium)
        tryPrompts(key)
        tryMouseClick(key)
        task.wait(0.3)
    end

    local timeoutAt = nowClock() + 14
    while nowClock() < timeoutAt do
        if not enabled then return false end
        if templeUnlockSignalAt >= cycleStartedAt then
            onTempleOpened()
            return true
        end
        task.wait(0.25)
    end

    return false
end

-- ============================================
-- RUNNER
-- ============================================
local function stopRunner()
    running = false
    postTempleBusy = false
    strongPriorityPending = false
    if loopThread then
        task.cancel(loopThread)
        loopThread = nil
    end
    disconnectUnlockEvents()
end

local function startRunner()
    if loopThread then return end
    local runGen = toggleGeneration
    bindUnlockEvents()
    nextRunAt = 0
    strongPriorityPending = false
    loopThread = task.spawn(function()
        while enabled and runGen == toggleGeneration do
            if #unlockConns == 0 then bindUnlockEvents() end
            if (not running) and nowClock() >= nextRunAt then
                if isStrongExecuting() then
                    strongPriorityPending = true
                    nextRunAt = nowClock() + 1
                elseif (not strongPriorityPending) and shouldPrioritizeStronghold() then
                    strongPriorityPending = true
                    nextRunAt = nowClock() + 2
                else
                    running = true
                    local okRun, opened = pcall(openTempleCycle)
                    running = false
                    strongPriorityPending = false
                    if okRun and opened then
                        nextRunAt = nowClock() + CYCLE_COOLDOWN_SEC
                    else
                        nextRunAt = nowClock() + RETRY_DELAY_SEC
                    end
                end
            end
            task.wait(CHECK_INTERVAL_SEC)
        end
        running = false
    end)
end

local function onToggle(ativo)
    local want = (ativo == true)
    if want == enabled then
        if want then
            if not loopThread then startRunner() end
        else
            if loopThread then stopRunner() end
        end
        return
    end
    enabled = want
    toggleGeneration += 1
    if enabled then
        startRunner()
    else
        stopRunner()
    end
end

-- ============================================
-- STATUS PROVIDER — timer regressivo no hub
-- ============================================
local function statusProvider()
    if not enabled then
        lastStatusText = ""
        return ""
    end
    if running then
        lastStatusText = "RUN"
        return lastStatusText
    end
    if timerStartedAt then
        local elapsed = nowClock() - timerStartedAt
        local remaining = TIMER_DURATION_SEC - elapsed
        if remaining > 0 then
            lastStatusText = "CD " .. formatTimer(remaining)
            return lastStatusText
        end
        timerStartedAt = nil
    end
    local waitLeft = math.max(0, math.floor((nextRunAt or 0) - nowClock()))
    if waitLeft > 0 then
        lastStatusText = "WAIT " .. formatTimer(waitLeft)
    else
        lastStatusText = "SCAN"
    end
    return lastStatusText
end

-- ============================================
-- REGISTRO NO HUB
-- ============================================
local opts = { statusProvider = statusProvider }

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, false, opts)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = MODULE_NAME, toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = false, opts = opts })
end

_G[MODULE_STATE_KEY] = {
    cleanup = function()
        enabled = false
        toggleGeneration += 1
        stopRunner()
    end,
}
