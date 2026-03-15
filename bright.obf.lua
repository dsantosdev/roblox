print('[KAH][LOAD] bright.obf.lua')

local Lighting = game:GetService("Lighting")
local MODULE_STATE_KEY = "__kah_bright_state"

do
    local old = _G[MODULE_STATE_KEY]
    if old and old.cleanup then
        pcall(old.cleanup)
    end
    _G[MODULE_STATE_KEY] = nil
end

local TARGET = {
    Brightness = 3,
    ClockTime = 14,
    FogEnd = 100000,
    GlobalShadows = false,
    Ambient = Color3.fromRGB(255, 255, 255),
    OutdoorAmbient = Color3.fromRGB(255, 255, 255),
}

local WATCHED = {
    Brightness = true,
    ClockTime = true,
    FogEnd = true,
    GlobalShadows = true,
    Ambient = true,
    OutdoorAmbient = true,
}

local applying = false
local changedConn = nil

local function applyFullBright()
    applying = true
    Lighting.Brightness = TARGET.Brightness
    Lighting.ClockTime = TARGET.ClockTime
    Lighting.FogEnd = TARGET.FogEnd
    Lighting.GlobalShadows = TARGET.GlobalShadows
    Lighting.Ambient = TARGET.Ambient
    Lighting.OutdoorAmbient = TARGET.OutdoorAmbient
    applying = false
end

changedConn = Lighting.Changed:Connect(function(prop)
    if applying or not WATCHED[prop] then
        return
    end
    applyFullBright()
end)

applyFullBright()

_G[MODULE_STATE_KEY] = {
    cleanup = function()
        if changedConn then
            changedConn:Disconnect()
            changedConn = nil
        end
    end,
}
