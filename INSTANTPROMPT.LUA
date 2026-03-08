-- ============================================
-- MÓDULO: INSTANT PROMPT
-- Zera HoldDuration em todos os ProximityPrompts
-- existentes e em qualquer novo que aparecer
-- ============================================

local CATEGORIA = "World"

-- Não executa sem o hub
if not _G.Hub and not _G.HubFila then
    print('>>> instant_prompt: hub não encontrado, abortando')
    return
end

local conn = nil

local function zerarPrompt(obj)
    if obj:IsA("ProximityPrompt") and obj.HoldDuration > 0 then
        obj.HoldDuration = 0
    end
end

local function ativar()
    for _, obj in ipairs(workspace:GetDescendants()) do
        zerarPrompt(obj)
    end
    conn = workspace.DescendantAdded:Connect(zerarPrompt)
end

local function desativar()
    if conn then conn:Disconnect(); conn = nil end
end

local function onToggle(ativo)
    if ativo then ativar() else desativar() end
end

if _G.Hub then
    _G.Hub.registrar("Instant Prompt", onToggle, CATEGORIA, true)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome="Instant Prompt", toggleFn=onToggle, categoria=CATEGORIA, jaAtivo=true })
end

ativar()
print(">>> INSTANT PROMPT ATIVO")
