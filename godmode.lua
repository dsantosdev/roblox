local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local player = Players.LocalPlayer or Players:GetPropertyChangedSignal('LocalPlayer'):Wait()

local godAtivado = true
local godConexao = nil

-- Função para limpar tanto o Highlight quanto o ForceField
local function limparEfeito()
    local char = player.Character
    if not char then return end
    for _, v in ipairs(char:GetChildren()) do
        -- Agora ele limpa os dois tipos de efeitos
        if v:IsA('Highlight') or v:IsA('ForceField') then 
            v:Destroy() 
        end
    end
end

local function aplicarEfeito(ativo)
    limparEfeito()
    local char = player.Character
    if not char or not ativo then return end

    -- Criando o ForceField em vez do Highlight
    local ff = Instance.new('ForceField')
    ff.Visible = true
    ff.Parent = char
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
    print("God Mode: " .. (godAtivado and "ATIVADO" or "DESATIVADO"))
end

-- Reaplicar quando o personagem renascer
player.CharacterAdded:Connect(function()
    task.wait(0.3)
    if godAtivado then aplicarGod() end
end)

-- Tecla PageUp para ligar/desligar
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.PageUp then
        alternarGod()
    end
end)

-- Início imediato
task.spawn(function()
    local char = player.Character or player.CharacterAdded:Wait()
    task.wait(0.3)
    aplicarGod()
end)
