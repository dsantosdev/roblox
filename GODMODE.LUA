-- ============================================
-- MÓDULO: GOD MODE
-- ============================================

local CATEGORIA = "Player"

local Players = game:GetService('Players')
local player  = Players.LocalPlayer
local godConexao = nil

local function aplicarGod(ativo)
    if godConexao then godConexao:Disconnect(); godConexao = nil end
    if not ativo then return end
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild('Humanoid')
    if not hum then return end
    godConexao = hum.Changed:Connect(function(prop)
        if prop == 'Health' and hum.Health < hum.MaxHealth then
            hum.Health = hum.MaxHealth
            pcall(function()
                game.ReplicatedStorage.RemoteEvents.DamagePlayer:FireServer(-hum.MaxHealth)
            end)
        end
    end)
end

local function onToggle(ativo)
    aplicarGod(ativo)
end

player.CharacterAdded:Connect(function()
    task.wait(0.3)
    if _G.Hub then aplicarGod(_G.Hub.getEstado("God Mode")) end
end)

if _G.Hub then
    _G.Hub.registrar("God Mode", onToggle, CATEGORIA)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = "God Mode", toggleFn = onToggle, categoria = CATEGORIA })
end
