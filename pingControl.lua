print('[KAH][LOAD] pingControl.lua')
-- ============================================
-- MODULE: PING CONTROL
-- API global para ping (Q + click) com toggle no Hub.
-- Uso: _G.KAHPing.sendWorld(pos) / _G.KAHPing.sendScreen(x,y)
-- ============================================

local VERSION = "1.0.0"
local MODULE_NAME = "Ping"
local CATEGORIA = "Utility"
local STATE_KEY = "__kah_ping_state"
local STATE_FILE = "ping_state.json"

local HS = game:GetService("HttpService")

local enabled = true

local function loadPersisted()
    if isfile and readfile and isfile(STATE_FILE) then
        local ok, data = pcall(function()
            return HS:JSONDecode(readfile(STATE_FILE))
        end)
        if ok and type(data) == "table" and type(data.enabled) == "boolean" then
            return data.enabled
        end
    end
    return nil
end

local function savePersisted(v)
    if not writefile then return end
    pcall(writefile, STATE_FILE, HS:JSONEncode({
        enabled = (v == true),
    }))
end

do
    local old = _G[STATE_KEY]
    if type(old) == "table" and type(old.enabled) == "boolean" then
        enabled = (old.enabled == true)
    end
    local persisted = loadPersisted()
    if type(persisted) == "boolean" then
        enabled = persisted
    end
    if old and old.cleanup then
        pcall(old.cleanup)
    end
    _G[STATE_KEY] = nil
end

local function getVIM()
    local ok, vim = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if ok then return vim end
    return nil
end

local function resolveScreenFromWorld(worldPos, opts)
    local cam = workspace.CurrentCamera
    if not cam then
        return nil, nil, "no_camera"
    end

    opts = opts or {}
    if typeof(worldPos) == "Vector3" then
        local screenPos, onScreen = cam:WorldToViewportPoint(worldPos)
        if onScreen and tonumber(screenPos.Z) and screenPos.Z > 0 then
            local x = math.floor((tonumber(screenPos.X) or 0) + 0.5)
            local y = math.floor((tonumber(screenPos.Y) or 0) + 0.5)
            return x, y, "world"
        end
    end

    if opts.requireOnScreen == true then
        return nil, nil, "offscreen"
    end
    if opts.fallbackToCenter == false then
        return nil, nil, "offscreen"
    end

    local vp = cam.ViewportSize
    local cx = math.floor((tonumber(vp.X) or 0) * 0.5 + 0.5)
    local cy = math.floor((tonumber(vp.Y) or 0) * 0.5 + 0.5)
    return cx, cy, "center"
end

local function performScreenPing(x, y, opts)
    if enabled ~= true then
        return false, "disabled"
    end

    local vim = getVIM()
    if not vim then
        return false, "vim_unavailable"
    end

    local xi = math.floor((tonumber(x) or 0) + 0.5)
    local yi = math.floor((tonumber(y) or 0) + 0.5)
    opts = opts or {}

    local moveMouse = (opts.moveMouse ~= false)
    local holdQ = (opts.holdQ ~= false)

    task.wait(0.03)
    if moveMouse then
        pcall(function()
            vim:SendMouseMoveEvent(xi, yi, game)
        end)
        task.wait(0.02)
    end

    if holdQ then
        pcall(function()
            vim:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
        end)
        task.wait(0.02)
    end

    if moveMouse then
        pcall(function()
            vim:SendMouseMoveEvent(xi, yi, game)
        end)
        task.wait(0.02)
    end

    pcall(function()
        vim:SendMouseButtonEvent(xi, yi, 0, true, game, 0)
    end)
    task.wait(0.02)
    pcall(function()
        vim:SendMouseButtonEvent(xi, yi, 0, false, game, 0)
    end)
    task.wait(0.02)

    if holdQ then
        pcall(function()
            vim:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
        end)
    end

    return true
end

local applyEnabled

local function setEnabledFromApi(v)
    local want = (v == true)
    if _G.Hub and type(_G.Hub.setEstado) == "function" then
        local ok, applied = pcall(function()
            return _G.Hub.setEstado(MODULE_NAME, want)
        end)
        if ok and applied then
            return enabled == true
        end
    end
    applyEnabled(want, false)
    return enabled == true
end

local function isEnabledFromApi()
    return enabled == true
end

local function sendScreenFromApi(x, y, opts)
    return performScreenPing(x, y, opts)
end

local function sendWorldFromApi(worldPos, opts)
    local x, y, mode = resolveScreenFromWorld(worldPos, opts)
    if not x or not y then
        return false, mode or "offscreen"
    end
    local ok, reason = performScreenPing(x, y, opts)
    if not ok then
        return false, reason
    end
    return true, mode, x, y
end

local function refreshApi()
    _G.KAHPing = _G.KAHPing or {}
    _G.KAHPing.enabled = (enabled == true)
    _G.KAHPing.isEnabled = isEnabledFromApi
    _G.KAHPing.setEnabled = setEnabledFromApi
    _G.KAHPing.resolveScreen = resolveScreenFromWorld
    _G.KAHPing.sendScreen = sendScreenFromApi
    _G.KAHPing.sendWorld = sendWorldFromApi
    _G.KAHPing.send = sendWorldFromApi
end

applyEnabled = function(v, fromHub)
    enabled = (v == true)
    savePersisted(enabled)
    refreshApi()
    if type(_G[STATE_KEY]) == "table" then
        _G[STATE_KEY].enabled = enabled
    end
    if not fromHub and _G.Hub and type(_G.Hub.setEstado) == "function" then
        pcall(function()
            _G.Hub.setEstado(MODULE_NAME, enabled)
        end)
    end
    return enabled
end

local function onToggle(ativo)
    applyEnabled(ativo, true)
end

if _G.Hub then
    if _G.Hub.remover then
        pcall(function()
            _G.Hub.remover(MODULE_NAME)
        end)
    end
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, enabled)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome = MODULE_NAME,
        toggleFn = onToggle,
        categoria = CATEGORIA,
        jaAtivo = enabled,
    })
end

_G[STATE_KEY] = {
    enabled = enabled,
    setEnabled = setEnabledFromApi,
    isEnabled = isEnabledFromApi,
    sendScreen = sendScreenFromApi,
    sendWorld = sendWorldFromApi,
    cleanup = function()
        if _G.Hub and _G.Hub.remover then
            pcall(function()
                _G.Hub.remover(MODULE_NAME)
            end)
        end
    end,
}

refreshApi()
print("[KAH][READY] PING CONTROL v" .. VERSION)
