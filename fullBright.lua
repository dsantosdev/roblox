-- ============================================
-- MODULO: FULLBRIGHT
-- ============================================

local VERSION   = "1.0"
local NOME      = "Fullbright"
local CATEGORIA = "World"

if not _G.Hub and not _G.HubFila then
    print('>>> fullbright: hub nao encontrado, abortando')
    return
end

local Lighting   = game:GetService("Lighting")
local RunService = game:GetService("RunService")

-- Salva valores originais para restaurar ao desligar
local original = {
    Brightness     = Lighting.Brightness,
    ClockTime      = Lighting.ClockTime,
    FogEnd         = Lighting.FogEnd,
    GlobalShadows  = Lighting.GlobalShadows,
    Ambient        = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
}

local brightConn = nil

local function ligar()
    if brightConn then return end
    brightConn = RunService.RenderStepped:Connect(function()
        Lighting.Brightness     = 3
        Lighting.ClockTime      = 14
        Lighting.FogEnd         = 100000
        Lighting.GlobalShadows  = false
        Lighting.Ambient        = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
    end)
end

local function desligar()
    if brightConn then brightConn:Disconnect(); brightConn = nil end
    Lighting.Brightness     = original.Brightness
    Lighting.ClockTime      = original.ClockTime
    Lighting.FogEnd         = original.FogEnd
    Lighting.GlobalShadows  = original.GlobalShadows
    Lighting.Ambient        = original.Ambient
    Lighting.OutdoorAmbient = original.OutdoorAmbient
end

local function onToggle(ativo)
    if ativo then ligar() else desligar() end
end

if _G.Hub then
    _G.Hub.registrar(NOME, onToggle, CATEGORIA, true)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = NOME, toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = true })
end

print(">>> FULLBRIGHT ATIVO")