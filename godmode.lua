local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local player = Players.LocalPlayer or Players:GetPropertyChangedSignal('LocalPlayer'):Wait()

local godAtivado = true
local godConexao = nil

local function limparEfeito()
    local char = player.Character
    if not char then return end
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA('Highlight') then v:Destroy() end
    end
end

local function aplicarEfeito(ativo)
    limparEfeito()
    local char = player.Character
    if not char or not ativo then return end

    local hl = Instance.new('Highlight')
    hl.FillColor = Color3.fromRGB(0, 255, 120)
    hl.OutlineColor = Color3.fromRGB(0, 255, 120)
    hl.FillTransparency = 0.6
    hl.OutlineTransparency = 0
    hl.Parent = char
end

local function aplicarGod()
    if godConexao then godConexao:Disconnect(); godConexao = nil end
    aplicarEfeito(godAtivado)
    if not godAtivado then return end
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

local function alternarGod()
    godAtivado = not godAtivado
    aplicarGod()
end

player.CharacterAdded:Connect(function()
    task.wait(0.3)
    if godAtivado then aplicarGod() end
end)

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.PageUp then
        alternarGod()
    end
end)

task.spawn(function()
    local char = player.Character or player.CharacterAdded:Wait()
    task.wait(0.3)
    aplicarGod()
end)