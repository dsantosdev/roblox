print('[KAH][LOAD] chestOpen.lua')
-- ============================================
-- MODULE: CHEST REMOTE OPENER
-- Timed burst mode with auto-off.
-- ============================================

local VERSION = "1.2"
local CATEGORIA = "Farm"
local MODULE_NAME = "Chest Farm"
local MODULE_STATE_KEY = "__chest_farm_module_state"
local CHEST_API_KEY = "__kah_chest_farm_api"

if not _G.Hub and not _G.HubFila then
    return
end

local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local RE = RS.RemoteEvents
local userId = tostring(player.UserId)

local CFG_KEY = "chest_farm_cfg.json"
local MIN_DURATION = 1
local MAX_DURATION = 120
local LOOP_INTERVAL = 0.8

local cfg = {
    duration = 5,
}

local rodando = false
local loopThread = nil
local burstToken = 0
local runUntilAt = 0
local syncingHubState = false

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
    if tonumber(data.duration) then
        cfg.duration = math.clamp(math.floor(tonumber(data.duration) + 0.5), MIN_DURATION, MAX_DURATION)
    end
end

local function saveCfg()
    if not writefile then return end
    pcall(writefile, CFG_KEY, HS:JSONEncode(cfg))
end

loadCfg()

local function nextToken()
    burstToken += 1
    return burstToken
end

local function stopLoop()
    rodando = false
    runUntilAt = 0
    local current = coroutine.running()
    local thread = loopThread
    loopThread = nil
    if thread and thread ~= current then
        task.cancel(thread)
    end
end

local function getRemainingSeconds()
    if not rodando or runUntilAt <= 0 then
        return nil
    end
    return math.max(0, math.ceil(runUntilAt - os.clock()))
end

local function syncHubState(ativo)
    local hub = _G.Hub
    if not hub or not hub.setEstado or not hub.getEstado then
        return false
    end
    local desired = (ativo == true)
    local current = hub.getEstado(MODULE_NAME) == true
    if current == desired then
        return true
    end
    syncingHubState = true
    local ok = pcall(function()
        hub.setEstado(MODULE_NAME, desired)
    end)
    syncingHubState = false
    return ok
end

-- Dedup on reload: stop previous runner before this instance is created.
do
    local old = _G[MODULE_STATE_KEY]
    if old and old.stop then
        pcall(old.stop)
    end
    _G[MODULE_STATE_KEY] = nil
    _G[CHEST_API_KEY] = nil
end

local function farmar()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if not rodando then break end
        if obj:IsA("ProximityPrompt") then
            local model = obj.Parent and obj.Parent.Parent and obj.Parent.Parent.Parent
            if model and model.Name then
                local nome = model.Name:lower()
                if nome:find("chest") or nome:find("bau") then
                    local jaAberto = model:GetAttribute("LocalOpened")
                        or model:GetAttribute(userId .. "Opened")
                    if not jaAberto then
                        pcall(function()
                            RE.RequestOpenItemChest:FireServer(model)
                        end)
                        task.wait(0.2)
                    end
                end
            end
        end
    end
end

local function startLoop(seconds)
    local duration = math.clamp(math.floor(tonumber(seconds) or cfg.duration), MIN_DURATION, MAX_DURATION)
    local myToken = nextToken()
    stopLoop()
    rodando = true
    runUntilAt = os.clock() + duration
    syncHubState(true)
    loopThread = task.spawn(function()
        while rodando and myToken == burstToken do
            farmar()
            local remaining = runUntilAt - os.clock()
            if remaining <= 0 then
                break
            end
            task.wait(math.min(LOOP_INTERVAL, math.max(0.1, remaining)))
        end
        if myToken ~= burstToken then
            return
        end
        stopLoop()
        task.defer(function()
            syncHubState(false)
        end)
    end)
    return myToken, duration
end

local function runFor(seconds)
    local myToken = startLoop(seconds)
    if not myToken then
        return false
    end
    while burstToken == myToken and rodando do
        task.wait(0.1)
    end
    return burstToken == myToken and rodando == false
end

local function onToggle(ativo)
    if syncingHubState then
        return
    end
    if ativo then
        startLoop(cfg.duration)
    else
        nextToken()
        stopLoop()
    end
end

local opts = {
    inlineNumber = {
        min = MIN_DURATION,
        max = MAX_DURATION,
        get = function()
            return cfg.duration
        end,
        set = function(v)
            cfg.duration = math.clamp(math.floor(tonumber(v) or cfg.duration), MIN_DURATION, MAX_DURATION)
            saveCfg()
        end,
    },
    statusProvider = function()
        local remaining = getRemainingSeconds()
        if remaining then
            return string.format("%ds", remaining)
        end
        return string.format("%ds", cfg.duration)
    end,
}

if _G.Hub then
    if _G.Hub.remover then
        pcall(function() _G.Hub.remover(MODULE_NAME) end)
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

_G[MODULE_STATE_KEY] = {
    stop = function()
        nextToken()
        stopLoop()
        _G[CHEST_API_KEY] = nil
    end,
    toggle = onToggle,
}

_G[CHEST_API_KEY] = {
    start = function()
        return startLoop(cfg.duration) ~= nil
    end,
    startFor = function(seconds)
        return startLoop(seconds) ~= nil
    end,
    stop = function()
        nextToken()
        stopLoop()
        syncHubState(false)
        return true
    end,
    runFor = runFor,
    isRunning = function()
        return rodando == true
    end,
    getDuration = function()
        return cfg.duration
    end,
    setDuration = function(seconds)
        cfg.duration = math.clamp(math.floor(tonumber(seconds) or cfg.duration), MIN_DURATION, MAX_DURATION)
        saveCfg()
        return cfg.duration
    end,
    getRemaining = getRemainingSeconds,
}
