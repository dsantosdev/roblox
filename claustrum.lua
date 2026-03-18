print('[KAH][LOAD] claustrum.lua')

local CLAUSTRUM_STATE_KEY = "__kah_claustrum_state"

do
    local old = _G[CLAUSTRUM_STATE_KEY]
    if old and type(old.cleanup) == "function" then
        pcall(old.cleanup)
    end
    _G[CLAUSTRUM_STATE_KEY] = nil
end

local Players = game:GetService("Players")
local RS      = game:GetService("RunService")
local player  = Players.LocalPlayer

local ZONE_VERTICES = {
    Vector3.new(-37.4992, 0,  32.0572),
    Vector3.new( 59.4295, 0,  31.8768),
    Vector3.new( 57.6074, 0, -34.6957),
    Vector3.new(-37.5256, 0, -34.4791),
}

local PUSH_MARGIN = 1.5

local function getRepulsionVector(vertices, px, pz)
    local n = #vertices
    local bestPen = 0
    local bestNX, bestNZ = 0, 0

    for i = 1, n do
        local a = vertices[i]
        local b = vertices[(i % n) + 1]
        local ex = b.X - a.X
        local ez = b.Z - a.Z
        local len2 = ex * ex + ez * ez
        if len2 < 1e-8 then continue end
        local len = math.sqrt(len2)

        local t = math.clamp(((px - a.X) * ex + (pz - a.Z) * ez) / len2, 0, 1)
        local cx = a.X + t * ex
        local cz = a.Z + t * ez

        local dx = px - cx
        local dz = pz - cz

        local nx =  ez / len
        local nz = -ex / len

        local side = dx * nx + dz * nz

        if side < PUSH_MARGIN then
            local pen = PUSH_MARGIN - side
            if pen > bestPen then
                bestPen = pen
                bestNX = nx
                bestNZ = nz
            end
        end
    end

    if bestPen == 0 then return nil end
    return Vector3.new(bestNX * bestPen, 0, bestNZ * bestPen)
end

local function getHRP()
    local c = player.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function claustrumDeveAtuar()
    local s = _G.KAHCommandUiState
    if type(s) ~= "table" then return false end
    return s.leviosa == true and s.transitus ~= true
end

local zoneConn = nil

local function tick()
    if not claustrumDeveAtuar() then return end
    local hrp = getHRP()
    if not hrp then return end

    local pos = hrp.Position
    local rep = getRepulsionVector(ZONE_VERTICES, pos.X, pos.Z)
    if rep == nil then return end

    hrp.CFrame = CFrame.new(pos + rep) * (hrp.CFrame - hrp.CFrame.Position)

    local vel = hrp.AssemblyLinearVelocity
    local rn = Vector3.new(rep.X, 0, rep.Z)
    if rn.Magnitude > 1e-4 then
        local u = rn.Unit
        local dot = vel:Dot(u)
        if dot < 0 then
            hrp.AssemblyLinearVelocity = vel - u * dot
        end
    end
end

zoneConn = RS.Heartbeat:Connect(tick)

_G[CLAUSTRUM_STATE_KEY] = {
    cleanup = function()
        if zoneConn then zoneConn:Disconnect(); zoneConn = nil end
    end,
}

print('[KAH][LOAD] CLAUSTRUM ativo')