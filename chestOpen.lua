-- ============================================
-- MÓDULO: CHEST REMOTE OPENER
-- ============================================

local VERSION   = "1.0"
local CATEGORIA = "Farm" -- << mude aqui para trocar de aba

-- Não executa sem o hub
if not _G.Hub and not _G.HubFila then
    print('>>> chest_farm: hub não encontrado, abortando')
    return
end

local RS      = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local player  = Players.LocalPlayer
local RE      = RS.RemoteEvents
local userId  = tostring(player.UserId)

local INTERVALO  = 8
local rodando    = false
local loopThread = nil

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
                        pcall(function() RE.RequestOpenItemChest:FireServer(model) end)
                        task.wait(0.2)
                    end
                end
            end
        end
    end
end

local function onToggle(ativo)
    rodando = ativo
    if ativo then
        loopThread = task.spawn(function()
            while rodando do farmar(); task.wait(INTERVALO) end
        end)
    else
        if loopThread then task.cancel(loopThread); loopThread = nil end
    end
end

if _G.Hub then
    _G.Hub.registrar("Chest Farm", onToggle, CATEGORIA)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = "Chest Farm", toggleFn = onToggle, categoria = CATEGORIA })
end
