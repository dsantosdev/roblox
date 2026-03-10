local SoundService = game:GetService("SoundService")

-- 1. Forçar configurações globais de áudio para zero
-- Isso afeta categorias inteiras do jogo (Ambiente, Música, etc)
SoundService.AmbientReverb = Enum.ReverbType.NoReverb
SoundService.DistanceFactor = 0
SoundService.DopplerScale = 0

-- 2. Função de Mute Agressivo
local function forceMute(obj)
    if obj:IsA("Sound") then
        obj.Volume = 0
        obj.Playing = false -- Força a parada física do som
        -- Impede o jogo de aumentar o volume de volta
        obj:GetPropertyChangedSignal("Volume"):Connect(function()
            obj.Volume = 0
        end)
        obj:GetPropertyChangedSignal("Playing"):Connect(function()
            obj.Playing = false
        end)
    end
end

-- 3. Aplicar em tudo que já existe
for _, v in ipairs(game:GetDescendants()) do
    -- Não mutar VoiceChat (AudioDeviceInput/Output)
    if not v:IsA("AudioDeviceInput") and not v:IsA("AudioDeviceOutput") then
        forceMute(v)
    end
end

-- 4. Monitorar tudo que for criado (novos sons ambientes)
game.DescendantAdded:Connect(function(v)
    if not v:IsA("AudioDeviceInput") and not v:IsA("AudioDeviceOutput") then
        forceMute(v)
    end
end)

print(">>> SILÊNCIO TOTAL ATIVADO (Voz mantida)")