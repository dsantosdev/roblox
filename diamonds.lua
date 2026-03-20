print('[KAH][LOAD] diamonds.lua')
-- ============================================
-- MODULE: DIAMOND FARM (burst)
-- Executa coleta curta sob demanda (API/Hub).
-- ============================================

local CATEGORIA = "Farm"
local MODULE_NAME = "Diamond"
local MODULE_STATE_KEY = "__kah_diamond_state"
local MODULE_API_KEY = "__kah_diamond_api"
local BURST_SECONDS = 3
local POST_OPEN_DELAY_DEFAULT = 1
local STEP_WAIT = 0.08

if not _G.Hub and not _G.HubFila then
    return
end

local RS = game:GetService("ReplicatedStorage")

do
    local old = _G[MODULE_STATE_KEY]
    if old and type(old.cleanup) == "function" then
        pcall(old.cleanup)
    end
    _G[MODULE_STATE_KEY] = nil
    _G[MODULE_API_KEY] = nil
end

local burstRunning = false
local burstToken = 0
local pendingToken = 0
local totalCollected = 0
local lastBurstAt = 0

local function getDiamondRemote()
    local remotes = RS:FindFirstChild("RemoteEvents")
    if not remotes then return nil end
    return remotes:FindFirstChild("RequestTakeDiamonds")
end

local function collectOnce()
    local remote = getDiamondRemote()
    if not remote then
        return 0
    end

    local items = workspace:FindFirstChild("Items")
    if not items then
        return 0
    end

    local count = 0
    for _, item in ipairs(items:GetChildren()) do
        if not burstRunning then
            break
        end
        if item:IsA("Model") and item.Name == "Diamond" then
            local ok = pcall(function()
                remote:FireServer(item)
            end)
            if ok then
                count += 1
            end
            task.wait(STEP_WAIT)
        end
    end
    return count
end

local function stopBurst()
    burstToken += 1
    burstRunning = false
end

local function runBurstDirect(durationSec)
    local sec = tonumber(durationSec) or BURST_SECONDS
    sec = math.max(0.5, sec)
    if burstRunning then
        return true
    end

    burstToken += 1
    local token = burstToken
    burstRunning = true
    lastBurstAt = os.clock()

    task.spawn(function()
        local deadline = os.clock() + sec
        while burstRunning and token == burstToken and os.clock() < deadline do
            local got = collectOnce()
            totalCollected += got
            task.wait(0.02)
        end
        if token ~= burstToken then
            return
        end
        burstRunning = false
        if _G.Hub and type(_G.Hub.setEstado) == "function" then
            pcall(function()
                _G.Hub.setEstado(MODULE_NAME, false)
            end)
        end
    end)
    return true
end

local function startBurst(durationSec)
    if burstRunning then
        return true
    end
    if _G.Hub and type(_G.Hub.setEstado) == "function" then
        local isOn = false
        if type(_G.Hub.getEstado) == "function" then
            local okGet, current = pcall(_G.Hub.getEstado, MODULE_NAME)
            isOn = okGet and current == true
        end
        if not isOn then
            pcall(function()
                _G.Hub.setEstado(MODULE_NAME, true)
            end)
            if burstRunning then
                return true
            end
        end
    end
    return runBurstDirect(durationSec)
end

local function runAfterChestOpen(delaySec)
    local delayValue = tonumber(delaySec) or POST_OPEN_DELAY_DEFAULT
    delayValue = math.max(0, delayValue)
    pendingToken += 1
    local token = pendingToken
    task.spawn(function()
        if delayValue > 0 then
            task.wait(delayValue)
        end
        if token ~= pendingToken then
            return
        end
        startBurst(BURST_SECONDS)
    end)
    return true
end

local function onToggle(ativo)
    if ativo == true then
        startBurst(BURST_SECONDS)
    else
        stopBurst()
    end
end

local opts = {
    statusProvider = function()
        return burstRunning and "RUN" or ""
    end,
}

if _G.Hub then
    if _G.Hub.remover then
        pcall(function()
            _G.Hub.remover(MODULE_NAME)
        end)
    end
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, false, opts)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome = MODULE_NAME,
        toggleFn = onToggle,
        categoria = CATEGORIA,
        jaAtivo = false,
        opts = opts,
    })
end

local function cleanup()
    pendingToken += 1
    stopBurst()
    if _G.Hub and type(_G.Hub.setEstado) == "function" then
        pcall(function()
            _G.Hub.setEstado(MODULE_NAME, false)
        end)
    end
end

local api = {
    burst = function(durationSec)
        return startBurst(durationSec or BURST_SECONDS)
    end,
    runAfterChestOpen = runAfterChestOpen,
    isRunning = function()
        return burstRunning
    end,
    getLastBurstAt = function()
        return lastBurstAt
    end,
    getTotal = function()
        return totalCollected
    end,
}

_G.KAHDiamond = api
_G[MODULE_API_KEY] = api
_G[MODULE_STATE_KEY] = {
    cleanup = cleanup,
    stop = stopBurst,
}
