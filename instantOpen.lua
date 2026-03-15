print('[KAH][LOAD] instantOpen.lua')
-- ============================================
-- MODULO: INSTANT PROMPT
-- Zera HoldDuration em todos os ProximityPrompts
-- existentes e em qualquer novo que aparecer.
-- Scan inicial em lotes para evitar travada no load.
-- ============================================

local VERSION = "1.1"
local CATEGORIA = "World"
local MODULE_NAME = "Instant Prompt"
local MODULE_STATE_KEY = "__kah_instant_prompt_state"
local BATCH_SIZE = 180

if not _G.Hub and not _G.HubFila then
    print('[KAH][WARN][InstantPrompt] hub nao encontrado, abortando')
    return
end

do
    local old = _G[MODULE_STATE_KEY]
    if old and old.cleanup then
        pcall(old.cleanup)
    end
    _G[MODULE_STATE_KEY] = nil
end

local conn = nil
local enabled = false
local scanToken = 0

local function zerarPrompt(obj)
    if obj:IsA("ProximityPrompt") and obj.HoldDuration > 0 then
        obj.HoldDuration = 0
    end
end

local function scanPromptsChunked(token)
    local descendants = workspace:GetDescendants()
    for i, obj in ipairs(descendants) do
        if not enabled or token ~= scanToken then
            return
        end
        zerarPrompt(obj)
        if (i % BATCH_SIZE) == 0 then
            task.wait()
        end
    end
end

local function ativar()
    if enabled then return end
    enabled = true
    scanToken += 1
    local token = scanToken
    task.spawn(function()
        scanPromptsChunked(token)
    end)
    conn = workspace.DescendantAdded:Connect(function(obj)
        zerarPrompt(obj)
    end)
end

local function desativar()
    enabled = false
    scanToken += 1
    if conn then
        conn:Disconnect()
        conn = nil
    end
end

local function onToggle(ativo)
    if ativo then
        ativar()
    else
        desativar()
    end
end

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, true)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome = MODULE_NAME,
        toggleFn = onToggle,
        categoria = CATEGORIA,
        jaAtivo = true,
    })
end

ativar()

_G[MODULE_STATE_KEY] = {
    cleanup = function()
        desativar()
    end,
}

print("[KAH][READY] INSTANT PROMPT")
