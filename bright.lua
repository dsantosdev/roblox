print('[KAH][LOAD] bright.lua')
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local function applyFullBright()
    -- Conexão para garantir que o brilho não mude (ex: ciclo dia/noite do jogo)
    local brightConn = RunService.RenderStepped:Connect(function()
        Lighting.Brightness = 3
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
    end)
    return brightConn
end

-- Ativa o brilho imediatamente
applyFullBright()