print('[KAH][LOAD] nightSkipMachine.lua')
-- ============================================
-- MODULE: SKIP NIGHT (headless)
-- Controlled only from Hub row:
-- toggle + dynamic "next" countdown in label.
-- ============================================

local VERSION = "2.0.0"
local CATEGORIA = "Utility"
local MODULE_NAME = "Skip Night"
local MODULE_STATE_KEY = "__kah_night_skip_state"

if not _G.Hub and not _G.HubFila then
    return
end

local HS = game:GetService("HttpService")
local RE = game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvents")
local Players = game:GetService("Players")

local CFG_KEY = "night_skip_cfg.json"
local INTERVALO = 10

local cfg = {
    enabled = false,
}

local function loadCfg()
    if not (isfile and readfile and isfile(CFG_KEY)) then return end
    local ok, data = pcall(function()
        return HS:JSONDecode(readfile(CFG_KEY))
    end)
    if ok and type(data) == "table" then
        cfg.enabled = data.enabled == true
    end
end

local function saveCfg()
    if not writefile then return end
    pcall(writefile, CFG_KEY, HS:JSONEncode(cfg))
end

loadCfg()

do
    local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        local old = pg:FindFirstChild("NightSkip_hud")
        if old then
            pcall(function() old:Destroy() end)
        end
    end
end

do
    local old = _G[MODULE_STATE_KEY]
    if old and old.stop then
        pcall(old.stop)
    end
    _G[MODULE_STATE_KEY] = nil
end

local running = false
local loopToken = 0
local nextCheckAt = 0
local totalFires = 0
local lastResult = "--"

local function getMachine()
    local structs = workspace:FindFirstChild("Structures")
    return structs and structs:FindFirstChild("Temporal Accelerometer")
end

local function fireMachine(machine)
    if not machine then return false end
    local ok = pcall(function()
        RE.RequestActivateNightSkipMachine:FireServer(machine)
    end)
    return ok
end

local function stopLoop()
    running = false
    loopToken += 1
    lastResult = "off"
end

local function startLoop()
    if running then return end
    running = true
    loopToken += 1
    local token = loopToken
    nextCheckAt = os.clock()
    lastResult = "on"

    task.spawn(function()
        while running and token == loopToken do
            local now = os.clock()
            if now < nextCheckAt then
                task.wait(math.min(0.25, nextCheckAt - now))
            else
                local machine = getMachine()
                local ok = fireMachine(machine)
                if ok then
                    totalFires += 1
                    lastResult = "ok"
                else
                    lastResult = machine and "fail" or "no-machine"
                end
                nextCheckAt = os.clock() + INTERVALO
            end
        end
    end)
end

local function getRemainingSeconds()
    if not running then return nil end
    return math.max(0, math.ceil(nextCheckAt - os.clock()))
end

local function onToggle(ativo)
    cfg.enabled = ativo == true
    saveCfg()
    if cfg.enabled then
        startLoop()
    else
        stopLoop()
    end
end

local opts = {
    statusProvider = function()
        local rem = getRemainingSeconds()
        if rem == nil then
            return "next --"
        end
        return string.format("next %ds", rem)
    end,
}

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, cfg.enabled, opts)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome = MODULE_NAME,
        toggleFn = onToggle,
        categoria = CATEGORIA,
        jaAtivo = cfg.enabled,
        opts = opts,
    })
end

if cfg.enabled then
    startLoop()
end

_G.KAHNightSkip = {
    isRunning = function() return running end,
    getRemaining = getRemainingSeconds,
    getTotalFires = function() return totalFires end,
    getLastResult = function() return lastResult end,
}

_G[MODULE_STATE_KEY] = {
    stop = stopLoop,
}
