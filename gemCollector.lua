print('[KAH][LOAD] gemCollector.lua')
-- ============================================
-- MODULE: GEM COLLECTOR (NO UI)
-- ============================================

local CATEGORIA   = "Farm"
local MODULE_NAME = "Gem Collector"

if not _G.Hub and not _G.HubFila then
    return
end

local Players = game:GetService("Players")
local player  = Players.LocalPlayer

local POS_ENTREGA = Vector3.new(20, 3, -5)
local ENTREGA_SLOT_NAMES = {
    "Entrega Gem",
    "Entrega",
    "Gem Collector",
    "Gem",
}
local TURBO_CLICK = true

local NOMES_ALVO = {
    "Gem of the Forest Fragment",
    "Gem of the Forest",
    "Cultist Gem",
}

-- ============================================
-- TP VIA KAHtp (com fallback local)
-- ============================================
local RunService = game:GetService("RunService")

local function getHRP()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function tpLocal(cf)
    local hrp = getHRP()
    if not hrp then return false end
    local lock = true
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not lock then conn:Disconnect() return end
        local h = getHRP()
        if h then h.CFrame = cf end
    end)
    task.delay(0.9, function() lock = false end)
    return true
end

local function usarTp(fn)
    if _G.KAHtp then
        fn(_G.KAHtp)
    else
        _G.KAHtpFila = _G.KAHtpFila or {}
        table.insert(_G.KAHtpFila, function() fn(_G.KAHtp) end)
    end
end

local function toCFrame(value)
    if typeof(value) == "CFrame" then
        return value
    end
    if typeof(value) == "Vector3" then
        return CFrame.new(value)
    end
    if type(value) == "table" then
        local x = tonumber(value.X or value.x)
        local y = tonumber(value.Y or value.y)
        local z = tonumber(value.Z or value.z)
        if x and y and z then
            return CFrame.new(x, y, z)
        end
    end
    return nil
end

local function getEntregaBaseCFrame()
    local tp = _G.KAHtp
    if type(tp) == "table" then
        if type(tp.getGemDeliveryCf) == "function" then
            local ok, cf = pcall(tp.getGemDeliveryCf)
            if ok and typeof(cf) == "CFrame" then
                return cf
            end
        end
        if type(tp.getSlotCf) == "function" then
            for _, name in ipairs(ENTREGA_SLOT_NAMES) do
                local ok, cf = pcall(tp.getSlotCf, name)
                if ok and typeof(cf) == "CFrame" then
                    return cf
                end
            end
        end
    end

    local direct = toCFrame(_G.__kah_gem_delivery_cf)
    if direct then
        return direct
    end

    return CFrame.new(POS_ENTREGA)
end

local function getEntregaTeleportCFrame()
    local base = getEntregaBaseCFrame()
    return CFrame.new(base.Position + Vector3.new(0, 3, 0))
end

local function getEntregaDropCFrame()
    local base = getEntregaBaseCFrame()
    return CFrame.new(base.Position + Vector3.new(0, 2, 0))
end

local function irParaEntrega()
    usarTp(function(api)
        local destino = getEntregaTeleportCFrame()
        if api and api.bancada then
            api.bancada()
        elseif api and api.teleportar then
            api.teleportar(destino)
        else
            tpLocal(destino)
        end
    end)
end

-- ============================================
-- OBJETO HELPERS
-- ============================================
local function getMainPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        local main = obj:FindFirstChild("Main", true)
        if main and main:IsA("BasePart") then return main end
        if obj.PrimaryPart then return obj.PrimaryPart end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end
    local main = obj:FindFirstChild("Main", true)
    if main and main:IsA("BasePart") then return main end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end

local function moveObj(obj, cf)
    if not obj or not cf then return false end
    if obj:IsA("BasePart") then obj.CFrame = cf return true end
    if obj:IsA("Model") then
        local ok = pcall(function() obj:PivotTo(cf) end)
        if ok then return true end
    end
    local main = getMainPart(obj)
    if main then main.CFrame = cf return true end
    return false
end

local function normalizeRoot(inst)
    if not inst then return nil end
    local model = inst:IsA("Model") and inst or inst:FindFirstAncestorWhichIsA("Model")
    if model then return model end
    if inst:IsA("BasePart") then return inst end
    return nil
end

local function tinyYield()
    if TURBO_CLICK then
        RunService.Heartbeat:Wait()
    else
        task.wait(0.08)
    end
end

-- ============================================
-- COLETA
-- ============================================
local function coletarTudo()
    local items = workspace:FindFirstChild("Items")
    if not items then
        if _G.Hub then pcall(function() _G.Hub.setEstado(MODULE_NAME, false) end) end
        return
    end

    local encontrados = {}
    local seen = {}

    for _, alvo in ipairs(NOMES_ALVO) do
        local alvoBaixo = string.lower(alvo)
        for _, d in ipairs(items:GetDescendants()) do
            local nm = string.lower(tostring(d.Name or ""))
            if nm == alvoBaixo then
                local root = normalizeRoot(d)
                if root and not seen[root] and getMainPart(root) then
                    seen[root] = true
                    table.insert(encontrados, root)
                end
            end
        end
    end

    -- Log de contagem no hub via statusProvider (não usa warn)
    -- Registra contagem em _G para debug se necessário
    local contagem = {}
    for _, item in ipairs(encontrados) do
        local nm = tostring(item.Name or "?")
        contagem[nm] = (contagem[nm] or 0) + 1
    end
    _G.GemCollector._ultimaContagem = contagem
    _G.GemCollector._totalUltimaColeta = #encontrados

    if #encontrados == 0 then
        if _G.Hub then pcall(function() _G.Hub.setEstado(MODULE_NAME, false) end) end
        return
    end

    irParaEntrega()
    tinyYield()

    local entregaCf = getEntregaDropCFrame()

    -- Fluxo simplificado:
    -- teleporta para o ponto de entrega e move os itens direto para la
    for _, item in ipairs(encontrados) do
        moveObj(item, entregaCf)
        tinyYield()
    end

    -- Auto-desliga após executar
    if _G.Hub then pcall(function() _G.Hub.setEstado(MODULE_NAME, false) end) end
end

-- ============================================
-- STATUS PROVIDER — mostra contagem no hub
-- ============================================
local function statusProvider()
    if not _G.GemCollector then return "" end
    local total = _G.GemCollector._totalUltimaColeta
    if not total then return "" end
    return total .. " itens"
end

-- ============================================
-- TOGGLE
-- ============================================
local function onToggle(ativo)
    if not ativo then return end
    task.spawn(coletarTudo)
end

-- ============================================
-- API GLOBAL
-- ============================================
_G.GemCollector = {
    ativar = function()
        if _G.Hub then
            pcall(function() _G.Hub.setEstado(MODULE_NAME, true) end)
        else
            task.spawn(coletarTudo)
        end
    end,
    coletarAgora = function()
        coletarTudo()
        return true
    end,
    definirEntrega = function(cfOrPos)
        local cf = toCFrame(cfOrPos)
        if not cf then
            return false
        end
        _G.__kah_gem_delivery_cf = cf
        return true
    end,
    getEntrega = function()
        return getEntregaBaseCFrame()
    end,
    _ultimaContagem = nil,
    _totalUltimaColeta = nil,
}

-- Processa fila pendente (caso alguém tenha chamado ativar() antes deste módulo carregar)
if _G.GemCollectorFila then
    for _, fn in ipairs(_G.GemCollectorFila) do pcall(fn) end
    _G.GemCollectorFila = nil
end

-- ============================================
-- REGISTRO NO HUB
-- ============================================
local opts = { statusProvider = statusProvider }

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, false, opts)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = MODULE_NAME, toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = false, opts = opts })
end
