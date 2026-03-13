print('[KAH][LOAD] chestOpen.lua')
-- ============================================
-- MODULE: CHEST REMOTE OPENER
-- ============================================

local VERSION = "1.1"
local CATEGORIA = "Farm"
local MODULE_NAME = "Chest Farm"
local MODULE_STATE_KEY = "__chest_farm_module_state"
local CHEST_API_KEY = "__kah_chest_farm_api"

if not _G.Hub and not _G.HubFila then
    return
end

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local RE = RS.RemoteEvents
local userId = tostring(player.UserId)

local INTERVALO = 8
local rodando = false
local loopThread = nil
local burstToken = 0

local function stopLoop()
    rodando = false
    if loopThread then
        task.cancel(loopThread)
        loopThread = nil
    end
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

local function startLoop()
    if rodando then return end
    stopLoop()
    rodando = true
    loopThread = task.spawn(function()
        while rodando do
            farmar()
            task.wait(INTERVALO)
        end
    end)
end

local function setChestState(ativo)
    local hub = _G.Hub
    if hub and hub.setEstado then
        local ok = pcall(function()
            hub.setEstado(MODULE_NAME, ativo == true)
        end)
        if ok then
            return true
        end
    end
    if ativo then
        startLoop()
    else
        stopLoop()
    end
    return true
end

local function runFor(seconds)
    burstToken += 1
    local myToken = burstToken
    local dur = math.max(0, tonumber(seconds) or 5)
    setChestState(true)
    local untilAt = os.clock() + dur
    while os.clock() < untilAt do
        if myToken ~= burstToken then
            return false
        end
        task.wait(0.1)
    end
    if myToken ~= burstToken then
        return false
    end
    setChestState(false)
    return true
end

local function onToggle(ativo)
    if ativo then
        startLoop()
    else
        stopLoop()
    end
end

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, false)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome = MODULE_NAME,
        toggleFn = onToggle,
        categoria = CATEGORIA,
        jaAtivo = false,
    })
end

_G[MODULE_STATE_KEY] = {
    stop = function()
        burstToken += 1
        stopLoop()
        _G[CHEST_API_KEY] = nil
    end,
    toggle = onToggle,
}

_G[CHEST_API_KEY] = {
    start = function()
        burstToken += 1
        return setChestState(true)
    end,
    stop = function()
        burstToken += 1
        return setChestState(false)
    end,
    runFor = runFor,
    isRunning = function()
        return rodando == true
    end,
}
