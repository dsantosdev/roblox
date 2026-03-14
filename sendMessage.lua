print('[KAH][LOAD] sendMessage.lua')
-- ============================================
-- MODULE: SEND MESSAGE
-- API central para envio de mensagens no chat.
-- Outros módulos chamam via _G.KAHChat.enviar(msg)
-- ============================================

local VERSION     = "1.0.0"
local CATEGORIA   = "Utility"
local MODULE_NAME = "Send Message"
local MODULE_STATE_KEY = "__kah_sendmessage_state"

local Players         = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Chat            = game:GetService("Chat")

local player = Players.LocalPlayer

-- ============================================
-- DEDUPLICAÇÃO
-- Evita enviar a mesma mensagem duas vezes em
-- menos de DEDUPE_SEC segundos.
-- ============================================
local DEDUPE_SEC   = 1.0
local lastSentMsg  = ""
local lastSentAt   = 0

-- ============================================
-- ENVIO
-- Tenta 3 métodos em sequência até um funcionar.
-- Retorna true se conseguiu enviar.
-- ============================================
local function enviar(msg)
    if type(msg) ~= "string" or #msg == 0 then return false end

    -- Deduplicação
    local now = os.clock()
    if msg == lastSentMsg and (now - lastSentAt) < DEDUPE_SEC then
        return false
    end
    lastSentMsg = msg
    lastSentAt  = now

    -- Método 1: TextChatService (sistema novo Roblox)
    local ok = false
    pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local chan  = TextChatService:FindFirstChild("TextChannels")
            local geral = chan and (
                chan:FindFirstChild("RBXGeneral") or
                chan:FindFirstChild("General")
            )
            if geral and geral.SendAsync then
                geral:SendAsync(msg)
                ok = true
            end
        end
    end)
    if ok then return true end

    -- Método 2: Legacy SayMessageRequest
    pcall(function()
        local r   = game:GetService("ReplicatedStorage")
        local d   = r:FindFirstChild("DefaultChatSystemChatEvents")
        local say = d and d:FindFirstChild("SayMessageRequest")
        if say then
            say:FireServer(msg, "All")
            ok = true
        end
    end)
    if ok then return true end

    -- Método 3: Bubble chat local (fallback sempre visível)
    pcall(function()
        local head = player.Character and player.Character:FindFirstChild("Head")
        if head then
            Chat:Chat(head, msg, Enum.ChatColor.White)
            ok = true
        end
    end)

    return ok
end

-- ============================================
-- HELPERS DE MENSAGENS PRONTAS
-- Funções de conveniência para eventos comuns.
-- Outros módulos podem chamar diretamente ou
-- usar enviar() com texto livre.
-- ============================================
local function temploAberto()
    return enviar("Templo da Selva aberto!")
end

local function fortalezaIniciando()
    return enviar("Iniciando a Fortaleza")
end

local function fortalezaAberta()
    return enviar("Fortaleza aberta!")
end

-- ============================================
-- API GLOBAL
-- ============================================
_G.KAHChat = {
    enviar           = enviar,
    temploAberto     = temploAberto,
    fortalezaIniciando = fortalezaIniciando,
    fortalezaAberta  = fortalezaAberta,
}

-- ============================================
-- REGISTRO NO HUB (sem UI, só para aparecer
-- na lista e poder ser desativado se necessário)
-- ============================================
do
    local old = _G[MODULE_STATE_KEY]
    if old and old.cleanup then pcall(old.cleanup) end
    _G[MODULE_STATE_KEY] = nil
end

local function onToggle(ativo)
    -- Quando desativado, substitui enviar por no-op
    if ativo then
        _G.KAHChat.enviar = enviar
    else
        _G.KAHChat.enviar = function() return false end
    end
    -- Restaura os helpers para refletir o estado
    _G.KAHChat.temploAberto       = function() return _G.KAHChat.enviar("Templo da Selva aberto!") end
    _G.KAHChat.fortalezaIniciando = function() return _G.KAHChat.enviar("Iniciando a Fortaleza") end
    _G.KAHChat.fortalezaAberta    = function() return _G.KAHChat.enviar("Fortaleza aberta!") end
end

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, true)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome      = MODULE_NAME,
        toggleFn  = onToggle,
        categoria = CATEGORIA,
        jaAtivo   = true,
    })
end

_G[MODULE_STATE_KEY] = {
    cleanup = function()
        -- Restaura no-op seguro se o módulo for recarregado
        if _G.KAHChat then
            _G.KAHChat.enviar = function() return false end
        end
    end,
}
