print('[KAH][LOAD] diamonds.lua')
-- ============================================
-- MODULE: DIAMOND FARM (headless)
-- Controlled only from Hub row:
-- toggle + interval on same line.
-- ============================================

local VERSION = "2.0.0"
local CATEGORIA = "Farm"
local MODULE_NAME = "Diamond"
local MODULE_STATE_KEY = "__kah_diamond_state"

if not _G.Hub and not _G.HubFila then
    return
end

local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local Players = game:GetService("Players")

local CFG_KEY = "diamond_cfg.json"
local MIN_INT = 5
local MAX_INT = 120

local cfg = {
    intervalo = 10,
    enabled = true,
}

local function loadCfg()
    if not (isfile and readfile and isfile(CFG_KEY)) then
        return
    end
    local ok, data = pcall(function()
        return HS:JSONDecode(readfile(CFG_KEY))
    end)
    if not ok or type(data) ~= "table" then
        return
    end
    if tonumber(data.intervalo) then
        cfg.intervalo = math.clamp(math.floor(tonumber(data.intervalo) + 0.5), MIN_INT, MAX_INT)
    end
    cfg.enabled = data.enabled == true
end

local function saveCfg()
    if not writefile then return end
    pcall(writefile, CFG_KEY, HS:JSONEncode(cfg))
end

loadCfg()
cfg.intervalo = 10
cfg.enabled = true
saveCfg()

do
    local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        local old = pg:FindFirstChild("Diamond_hud")
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
local nextCollectAt = 0
local totalCollected = 0

local function getDiamondRemote()
    local remotes = RS:FindFirstChild("RemoteEvents")
    if not remotes then return nil end
    return remotes:FindFirstChild("RequestTakeDiamonds")
end

local function collectOnce()
    local remote = getDiamondRemote()
    if not remote then return 0 end

    local items = workspace:FindFirstChild("Items")
    if not items then return 0 end

    local count = 0
    for _, item in ipairs(items:GetChildren()) do
        if not running then break end
        if item:IsA("Model") and item.Name == "Diamond" then
            local ok = pcall(function()
                remote:FireServer(item)
            end)
            if ok then
                count += 1
            end
            task.wait(0.06)
        end
    end
    return count
end

local function stopLoop()
    running = false
    loopToken += 1
end

local function startLoop()
    if running then return end
    running = true
    loopToken += 1
    local token = loopToken
    nextCollectAt = os.clock() + cfg.intervalo

    task.spawn(function()
        while running and token == loopToken do
            local now = os.clock()
            if now < nextCollectAt then
                task.wait(math.min(0.25, nextCollectAt - now))
            else
                nextCollectAt = os.clock() + cfg.intervalo
                local collected = collectOnce()
                totalCollected += collected
            end
        end
    end)
end

local function setInterval(v)
    cfg.intervalo = math.clamp(math.floor(tonumber(v) or cfg.intervalo), MIN_INT, MAX_INT)
    if running then
        local remain = math.max(0, nextCollectAt - os.clock())
        nextCollectAt = os.clock() + math.min(remain, cfg.intervalo)
    end
    saveCfg()
end

local function getRemainingSeconds()
    if not running then return nil end
    return math.max(0, math.ceil(nextCollectAt - os.clock()))
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
    inlineNumber = {
        min = MIN_INT,
        max = MAX_INT,
        get = function()
            return cfg.intervalo
        end,
        set = function(v)
            setInterval(v)
        end,
    },
    statusProvider = function()
        local rem = getRemainingSeconds()
        if rem == nil then
            return "--"
        end
        return string.format("%ds", rem)
    end,
}

if _G.Hub then
    if _G.Hub.remover then
        pcall(function() _G.Hub.remover(MODULE_NAME) end)
    end
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

_G.KAHDiamond = {
    isRunning = function() return running end,
    getInterval = function() return cfg.intervalo end,
    setInterval = setInterval,
    getRemaining = getRemainingSeconds,
    getTotal = function() return totalCollected end,
}

_G[MODULE_STATE_KEY] = {
    stop = stopLoop,
}
