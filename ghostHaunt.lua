print('[KAH][LOAD] ghostHaunt.lua')
-- ============================================
-- MÓDULO: GHOST HAUNT ENGINE
-- Orbita caótica sem BodyVelocity (sem arremessar)
-- Expõe API via _G.KAHGhostHaunt
-- ============================================
local VERSION   = "1.0.0"
local STATE_KEY = "__kah_ghosthaunt_state"

do
    local old = _G[STATE_KEY]
    if old and old.stop then pcall(old.stop) end
end
_G[STATE_KEY] = nil

local Players = game:GetService("Players")
local RS      = game:GetService("RunService")
local player  = Players.LocalPlayer

local HAUNT_RAIO          = 2.8
local HAUNT_VEL           = 5.5
local HAUNT_VERTICAL_AMP  = 0.7
local HAUNT_VERTICAL_FREQ = 2.2

local hauntAtivo       = false
local hauntConn        = nil
local hauntTarget_     = nil
local hauntAngle       = 0
local hauntSavedCol    = {}
local hauntHighlight   = nil
local hauntChaosTask   = nil
local hauntOrigemCF    = nil

local function pararHaunt()
    hauntAtivo = false
    if hauntChaosTask then task.cancel(hauntChaosTask); hauntChaosTask = nil end
    if hauntConn      then hauntConn:Disconnect(); hauntConn = nil end
    if hauntHighlight then pcall(function() hauntHighlight:Destroy() end); hauntHighlight = nil end

    for _, entry in ipairs(hauntSavedCol) do
        if entry.obj and entry.obj.Parent then
            entry.obj.CanCollide = entry.canCollide
        end
    end
    hauntSavedCol = {}
    hauntTarget_  = nil
    hauntAngle    = 0

    local destCF = hauntOrigemCF
    hauntOrigemCF = nil
    task.spawn(function()
        local c   = player.Character
        local hrp = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
        if hrp then
            hrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
            hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            if destCF then hrp.CFrame = destCF end
            local lockFrames = 12
            local lockConn
            lockConn = RS.Heartbeat:Connect(function()
                lockFrames -= 1
                if lockFrames <= 0 then lockConn:Disconnect(); return end
                local hc = player.Character
                local hh = hc and (hc:FindFirstChild("HumanoidRootPart") or hc:FindFirstChild("Torso"))
                if hh then
                    hh.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
                    hh.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                    if destCF then hh.CFrame = destCF end
                end
            end)
            task.wait(0.22)
        end
        local hc2  = player.Character
        local hum2 = hc2 and hc2:FindFirstChildOfClass("Humanoid")
        if hum2 then
            hum2.PlatformStand = false
            hum2.AutoRotate    = true
        end
    end)
end

local function iniciarHaunt(target)
    if not target or target == player then return end
    pararHaunt()
    task.wait()
    hauntTarget_ = target
    hauntAtivo   = true
    hauntAngle   = 0

    local myChar = player.Character
    local hum    = myChar and myChar:FindFirstChildOfClass("Humanoid")
    local myHRP  = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Torso"))
    if not myHRP then return end

    hauntOrigemCF = myHRP.CFrame
    if hum then hum.PlatformStand = true; hum.AutoRotate = false end
    myHRP.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
    myHRP.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

    hauntSavedCol = {}
    for _, part in ipairs(myChar:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(hauntSavedCol, { obj = part, canCollide = part.CanCollide })
            part.CanCollide = false
        end
    end

    hauntHighlight = Instance.new("Highlight")
    hauntHighlight.Name                = "KAH_HauntFx"
    hauntHighlight.Adornee             = myChar
    hauntHighlight.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    hauntHighlight.FillColor           = Color3.fromRGB(120, 40, 220)
    hauntHighlight.FillTransparency    = 0.55
    hauntHighlight.OutlineColor        = Color3.fromRGB(200, 130, 255)
    hauntHighlight.OutlineTransparency = 0.1
    hauntHighlight.Parent              = myChar

    local chaos = {
        vel = HAUNT_VEL, dir = 1, raio = HAUNT_RAIO,
        yOffset = 0, shakeX = 0, shakeZ = 0, shakeY = 0,
    }

    local function rnd(a, b) return a + math.random() * (b - a) end

    hauntChaosTask = task.spawn(function()
        while hauntAtivo do
            local ev = math.random(1, 4)
            if ev == 1 then
                chaos.dir = -chaos.dir
                task.wait(rnd(0.6, 1.8))
            elseif ev == 2 then
                chaos.vel = rnd(2.0, 10.0)
                task.wait(rnd(0.8, 2.5))
            elseif ev == 3 then
                chaos.raio    = rnd(1.2, 6.0)
                chaos.yOffset = rnd(-3.0, 4.0)
                task.wait(rnd(1.0, 3.0))
            elseif ev == 4 then
                local dur = rnd(0.3, 0.8)
                local t0s = os.clock()
                while hauntAtivo and os.clock() - t0s < dur do
                    chaos.shakeX = rnd(-2.5, 2.5)
                    chaos.shakeZ = rnd(-2.5, 2.5)
                    chaos.shakeY = rnd(-1.5, 1.5)
                    task.wait(0.03)
                end
                chaos.shakeX = 0; chaos.shakeZ = 0; chaos.shakeY = 0
                task.wait(rnd(0.4, 1.5))
            end
        end
    end)

    local t0 = os.clock()
    hauntConn = RS.Heartbeat:Connect(function(dt)
        if not hauntAtivo then return end
        local targetHRP = target.Character and
            (target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("Torso"))
        local myHRPNow = player.Character and
            (player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso"))
        if not targetHRP or not myHRPNow then return end

        hauntAngle = hauntAngle + chaos.vel * chaos.dir * dt
        local elapsed = os.clock() - t0
        local cy = targetHRP.Position.Y
            + HAUNT_VERTICAL_AMP * math.sin(elapsed * HAUNT_VERTICAL_FREQ)
            + chaos.yOffset + chaos.shakeY
        local cx = targetHRP.Position.X + math.cos(hauntAngle) * chaos.raio + chaos.shakeX
        local cz = targetHRP.Position.Z + math.sin(hauntAngle) * chaos.raio + chaos.shakeZ

        myHRPNow.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
        myHRPNow.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        for _, part in ipairs(player.Character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
        myHRPNow.CFrame = CFrame.new(Vector3.new(cx, cy, cz), targetHRP.Position)
    end)
end

-- ============================================
-- API GLOBAL
-- ============================================
_G.KAHGhostHaunt = {
    start    = iniciarHaunt,
    stop     = pararHaunt,
    isActive = function() return hauntAtivo end,
    target   = function() return hauntTarget_ end,
}

_G[STATE_KEY] = { stop = pararHaunt, cleanup = pararHaunt }

print('[KAH][READY] GHOST HAUNT ENGINE v' .. VERSION)
