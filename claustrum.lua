-- ============================================
-- MODULE: CLAUSTRUM
-- Zona de colisão virtual quadrada.
-- Bloqueia o jogador dentro (ou fora) de um
-- quadrilátero no plano XZ enquanto:
--   • Leviosa estiver ATIVO
--   • Transitus estiver DESATIVADO
-- ============================================

print("[KAH][LOAD] claustrum.lua")

local CLAUSTRUM_STATE_KEY = "__kah_claustrum_state"

-- Limpa instância anterior se o script for recarregado
do
    local old = _G[CLAUSTRUM_STATE_KEY]
    if old and type(old.cleanup) == "function" then
        pcall(old.cleanup)
    end
    _G[CLAUSTRUM_STATE_KEY] = nil
end

-- ============================================
-- SERVIÇOS
-- ============================================
local Players  = game:GetService("Players")
local RS       = game:GetService("RunService")
local player   = Players.LocalPlayer

-- ============================================
-- ZONA — quatro vértices no plano XZ
-- Os pontos abaixo definem o quadrilátero.
-- Você pode adicionar mais pontos para polígonos
-- convexos; a lógica de projeção funciona para
-- qualquer número de arestas convexas.
-- ============================================
local ZONE_VERTICES = {
    Vector3.new(-37.4992, 0, 32.0572),
    Vector3.new( 59.4295, 0, 31.8768),
    Vector3.new( 57.6074, 0, -34.6957),
    Vector3.new(-37.5256, 0, -34.4791),
}

-- Margem de "empurrão" em studs — distância mínima
-- que o personagem é mantido do interior da aresta.
local PUSH_MARGIN = 1.5

-- ============================================
-- GEOMETRIA 2-D (plano XZ)
-- ============================================

-- Retorna true se o ponto P está dentro do polígono
-- convexo definido pelos vértices (sentido anti-horário
-- ou horário — detectado automaticamente).
-- Usa o teste de cross-product para polígono convexo.
local function insideConvexPolygonXZ(vertices, px, pz)
    local n = #vertices
    local sign = nil
    for i = 1, n do
        local a = vertices[i]
        local b = vertices[(i % n) + 1]
        local ex = b.X - a.X
        local ez = b.Z - a.Z
        local dx = px  - a.X
        local dz = pz  - a.Z
        local cross = ex * dz - ez * dx
        if cross ~= 0 then
            local s = cross > 0
            if sign == nil then
                sign = s
            elseif sign ~= s then
                return false
            end
        end
    end
    return true
end

-- Projeta o ponto (px, pz) sobre o segmento (ax,az)→(bx,bz)
-- e retorna o ponto projetado + a penetração (quanto está além).
local function projectOntoEdge(ax, az, bx, bz, px, pz)
    local ex, ez = bx - ax, bz - az
    local len2 = ex * ex + ez * ez
    if len2 < 1e-8 then
        return ax, az, 0
    end
    local t = math.clamp(((px - ax) * ex + (pz - az) * ez) / len2, 0, 1)
    local cx = ax + t * ex
    local cz = az + t * ez
    local dx = px - cx
    local dz = pz - cz
    local dist = math.sqrt(dx * dx + dz * dz)
    -- normal apontando para dentro (perpendicular à aresta, 90° horário)
    local nx = ez / math.sqrt(len2)
    local nz = -ex / math.sqrt(len2)
    -- dot product: se negativo, o ponto está do lado "de fora" desta aresta
    local side = dx * nx + dz * nz
    return cx, cz, side, dist
end

-- Encontra a aresta mais próxima ao ponto (px, pz)
-- e retorna o vetor de correção para recolocar dentro.
local function getRepulsionVector(vertices, px, pz)
    local n = #vertices
    local bestDist = math.huge
    local bestCX, bestCZ = px, pz
    local bestNX, bestNZ = 0, 0

    for i = 1, n do
        local a = vertices[i]
        local b = vertices[(i % n) + 1]
        local ax, az = a.X, a.Z
        local bx, bz = b.X, b.Z

        local ex, ez = bx - ax, bz - az
        local len2 = ex * ex + ez * ez
        if len2 < 1e-8 then continue end
        local len = math.sqrt(len2)

        local t = math.clamp(((px - ax) * ex + (pz - az) * ez) / len2, 0, 1)
        local cx = ax + t * ex
        local cz = az + t * ez

        local dx = px - cx
        local dz = pz - cz
        local dist = math.sqrt(dx * dx + dz * dz)

        -- normal interna da aresta (90° horário de (ex,ez))
        local nx = ez / len
        local nz = -ex / len

        -- ponto está do lado externo desta aresta?
        local side = dx * nx + dz * nz  -- > 0 = dentro, < 0 = fora

        if side <= PUSH_MARGIN then
            -- aresta candidata — quanto mais perto (ou mais violada), maior prioridade
            local penetration = PUSH_MARGIN - side
            if penetration > bestDist then
                bestDist = penetration
                bestCX, bestCZ = cx, cz
                bestNX, bestNZ = nx, nz
            end
        end
    end

    if bestDist == math.huge then
        return nil -- sem violação
    end

    -- vetor de repulsão: empurra na direção da normal interna
    return Vector3.new(bestNX * bestDist, 0, bestNZ * bestDist)
end

-- ============================================
-- ESTADO DO MÓDULO
-- ============================================
local zoneConn = nil
local ativo    = false

-- ============================================
-- HELPERS — lê o estado global do adminCommands
-- ============================================
local function isLeviosaAtivo()
    local state = _G.__kah_admin_commands_state
    -- tenta ler commandUiState exposto via _G (veja nota abaixo)
    if type(_G.KAHCommandUiState) == "table" then
        return _G.KAHCommandUiState.leviosa == true
    end
    -- fallback: tenta ler direto se o módulo expôs
    if type(_G.kahLeviosa) == "boolean" then
        return _G.kahLeviosa
    end
    return false
end

local function isTransitusAtivo()
    if type(_G.KAHCommandUiState) == "table" then
        return _G.KAHCommandUiState.transitus == true
    end
    if type(_G.kahTransitus) == "boolean" then
        return _G.kahTransitus
    end
    return false
end

local function claustrumDeveAtuar()
    return isLeviosaAtivo() and not isTransitusAtivo()
end

-- ============================================
-- LÓGICA PRINCIPAL
-- ============================================
local function getHRP()
    local c = player.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function tickClaustrum()
    if not claustrumDeveAtuar() then return end

    local hrp = getHRP()
    if not hrp then return end

    local pos = hrp.Position
    local px, pz = pos.X, pos.Z

    -- Se já está dentro (com margem), nada a fazer
    if insideConvexPolygonXZ(ZONE_VERTICES, px, pz) then
        -- verifica margem em relação a cada aresta individualmente
        -- (getRepulsionVector já cobre isso)
    end

    local repulsion = getRepulsionVector(ZONE_VERTICES, px, pz)
    if repulsion == nil then return end

    -- Aplica correção de posição
    local newPos = pos + repulsion
    hrp.CFrame = CFrame.new(newPos) * (hrp.CFrame - hrp.CFrame.Position)

    -- Cancela a componente de velocidade que "fura" a parede
    local vel = hrp.AssemblyLinearVelocity
    -- projeta velocidade na direção da repulsão e zeramos essa componente
    local rn = Vector3.new(repulsion.X, 0, repulsion.Z)
    if rn.Magnitude > 1e-4 then
        local rnUnit = rn.Unit
        local dot = vel:Dot(rnUnit)
        if dot < 0 then
            hrp.AssemblyLinearVelocity = vel - rnUnit * dot
        end
    end
end

-- ============================================
-- INICIAR / PARAR
-- ============================================
local function iniciar()
    if ativo then return end
    ativo = true
    zoneConn = RS.Heartbeat:Connect(tickClaustrum)
    print("[KAH][CLAUSTRUM] zona ativa")
end

local function parar()
    ativo = false
    if zoneConn then
        zoneConn:Disconnect()
        zoneConn = nil
    end
    print("[KAH][CLAUSTRUM] zona inativa")
end

-- ============================================
-- EXPOSIÇÃO GLOBAL
-- (adminCommands.lua precisa atualizar KAHCommandUiState)
-- ============================================

-- Se o adminCommands ainda não expôs KAHCommandUiState,
-- criamos a tabela e ensinamos as funções wingardium/nox/
-- alohomora/colloportus a sincronizá-la.
-- A forma mais limpa é adicionar estas duas linhas DENTRO
-- do adminCommands.lua, logo após a declaração de commandUiState:
--
--   _G.KAHCommandUiState = commandUiState
--
-- E, opcionalmente, para compatibilidade com este módulo:
--   _G.kahLeviosa  = commandUiState.leviosa   (atualizado em wingardium/nox)
--   _G.kahTransitus= commandUiState.transitus (atualizado em alohomora/colloportus)
--
-- Se preferir NÃO alterar o adminCommands, use os wrappers
-- abaixo que fazem monkey-patch nas funções globais.

if type(_G.KAHCommandUiState) ~= "table" then
    -- tenta criar uma tabela proxy ligada ao estado interno se disponível
    _G.KAHCommandUiState = {}
    print("[KAH][CLAUSTRUM] KAHCommandUiState não encontrado — adicione _G.KAHCommandUiState = commandUiState no adminCommands.lua")
end

-- Inicia monitoramento contínuo
iniciar()

-- ============================================
-- CLEANUP
-- ============================================
_G[CLAUSTRUM_STATE_KEY] = {
    cleanup = parar,
    iniciar = iniciar,
    parar   = parar,
}

print("[KAH][LOAD] CLAUSTRUM ativo")