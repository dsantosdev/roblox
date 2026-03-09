-- ============================================
-- MODULO: HIDE HEALTH BAR
-- ============================================

local VERSION   = "1.0"
local NOME      = "Hide Blink Damage"
local CATEGORIA = "World"

if not _G.Hub and not _G.HubFila then
    print('>>> NoDamageBlink: hub nao encontrado, abortando')
    return
end

local StarterGui = game:GetService("StarterGui")

local function onToggle(ativo)
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, not ativo)
    end)
end

if _G.Hub then
    _G.Hub.registrar(NOME, onToggle, CATEGORIA, true)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = NOME, toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = true })
end

print(">>> NO DAMAGE BLINK ATIVO")