print('[KAH][LOAD] sendMessage.lua')
-- ============================================
-- MODULE: SEND MESSAGE
-- API central para envio de mensagens no chat.
-- Outros modulos chamam via _G.KAHChat.enviar(msg)
-- ============================================

local VERSION     = "1.0.1"
local CATEGORIA   = "Utility"
local MODULE_NAME = "Send Message"
local MODULE_STATE_KEY = "__kah_sendmessage_state"
local STATE_FILE_PATH = "send_message_state.json"

local Players         = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Chat            = game:GetService("Chat")
local HS              = game:GetService("HttpService")

local player = Players.LocalPlayer

-- ============================================
-- DEDUPLICACAO
-- Evita enviar a mesma mensagem duas vezes em
-- menos de DEDUPE_SEC segundos.
-- ============================================
local DEDUPE_SEC   = 1.0
local lastSentMsg  = ""
local lastSentAt   = 0

-- ============================================
-- ENVIO
-- Tenta 3 metodos em sequencia ate um funcionar.
-- Retorna true se conseguiu enviar.
-- ============================================
local function enviar(msg)
    if type(msg) ~= "string" or #msg == 0 then return false end

    local now = os.clock()
    if msg == lastSentMsg and (now - lastSentAt) < DEDUPE_SEC then
        return false
    end
    lastSentMsg = msg
    lastSentAt = now

    local ok = false
    pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local chan = TextChatService:FindFirstChild("TextChannels")
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

    pcall(function()
        local r = game:GetService("ReplicatedStorage")
        local d = r:FindFirstChild("DefaultChatSystemChatEvents")
        local say = d and d:FindFirstChild("SayMessageRequest")
        if say then
            say:FireServer(msg, "All")
            ok = true
        end
    end)
    if ok then return true end

    pcall(function()
        local head = player.Character and player.Character:FindFirstChild("Head")
        if head then
            Chat:Chat(head, msg, Enum.ChatColor.White)
            ok = true
        end
    end)

    return ok
end

local function carregarEstadoPersistido()
    if isfile and readfile and isfile(STATE_FILE_PATH) then
        local ok, data = pcall(function()
            return HS:JSONDecode(readfile(STATE_FILE_PATH))
        end)
        if ok and type(data) == "table" and type(data.enabled) == "boolean" then
            return data.enabled
        end
    end
    return nil
end

local function salvarEstadoPersistido(enabled)
    if not writefile then return end
    pcall(writefile, STATE_FILE_PATH, HS:JSONEncode({
        enabled = enabled == true,
    }))
end

local rememberedEnabled = true
do
    local old = _G[MODULE_STATE_KEY]
    if type(old) == "table" and type(old.enabled) == "boolean" then
        rememberedEnabled = old.enabled == true
    end
    local persisted = carregarEstadoPersistido()
    if type(persisted) == "boolean" then
        rememberedEnabled = persisted
    end
    if old and old.cleanup then
        pcall(old.cleanup)
    end
    _G[MODULE_STATE_KEY] = nil
end

-- ============================================
-- HELPERS DE MENSAGENS PRONTAS
-- ============================================
local function temploAberto()
    return _G.KAHChat and _G.KAHChat.enviar and _G.KAHChat.enviar("Templo da Selva aberto!") or false
end

local function fortalezaIniciando()
    return _G.KAHChat and _G.KAHChat.enviar and _G.KAHChat.enviar("Vou fazer a fortaleza") or false
end

local function fortalezaAberta()
    return _G.KAHChat and _G.KAHChat.enviar and _G.KAHChat.enviar("Fortaleza aberta!") or false
end

local function fortalezaFinalizada()
    return _G.KAHChat and _G.KAHChat.enviar and _G.KAHChat.enviar("Fortaleza finalizada!") or false
end

local function aplicarEstadoChat(enabled)
    _G.KAHChat = _G.KAHChat or {}
    if enabled then
        _G.KAHChat.enviar = enviar
    else
        _G.KAHChat.enviar = function() return false end
    end
    _G.KAHChat.temploAberto = temploAberto
    _G.KAHChat.fortalezaIniciando = fortalezaIniciando
    _G.KAHChat.fortalezaAberta = fortalezaAberta
    _G.KAHChat.fortalezaFinalizada = fortalezaFinalizada
end

aplicarEstadoChat(rememberedEnabled)

local function onToggle(ativo)
    rememberedEnabled = (ativo == true)
    salvarEstadoPersistido(rememberedEnabled)
    aplicarEstadoChat(rememberedEnabled)
    if type(_G[MODULE_STATE_KEY]) == "table" then
        _G[MODULE_STATE_KEY].enabled = rememberedEnabled
    end
end

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, rememberedEnabled)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome = MODULE_NAME,
        toggleFn = onToggle,
        categoria = CATEGORIA,
        jaAtivo = rememberedEnabled,
    })
end

_G[MODULE_STATE_KEY] = {
    enabled = rememberedEnabled,
    cleanup = function()
        if _G.KAHChat then
            _G.KAHChat.enviar = function() return false end
        end
    end,
}
