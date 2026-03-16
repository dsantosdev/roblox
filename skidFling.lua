print('[KAH][LOAD] skidFling.lua')
-- ============================================
-- MÓDULO: SKIDFLING ENGINE
-- Lógica pura de fling — sem GUI
-- Expõe API via _G.KAHSkidFling
-- ============================================
local VERSION         = "1.0.0"
local STATE_KEY       = "__kah_skidfling_state"
local origFPDH        = workspace.FallenPartsDestroyHeight

-- cleanup de instância anterior
do
    local old = _G[STATE_KEY]
    if old and old.stop then pcall(old.stop) end
end
_G[STATE_KEY] = nil

local Players = game:GetService("Players")
local player  = Players.LocalPlayer

-- ============================================
-- TOKEN DE SESSÃO
-- Incrementado a cada stop() para cancelar
-- qualquer fling em andamento imediatamente
-- ============================================
local sessionToken = 0
local oldPos       = nil

-- ============================================
-- RESTORE
-- ============================================
local function restoreCharacter()
    local c   = player.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    local hrp = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
    if hum then
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
    if hrp then
        hrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
    if c then
        for _, v in ipairs(c:GetDescendants()) do
            if v:IsA("BodyVelocity") or v:IsA("BodyAngularVelocity") then
                pcall(function() v:Destroy() end)
            end
        end
    end
    local cam = workspace.CurrentCamera
    local hum2 = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if cam and hum2 then pcall(function() cam.CameraSubject = hum2 end) end
    workspace.FallenPartsDestroyHeight = origFPDH
end

-- ============================================
-- CONTEXTO COMPARTILHADO (evita locais demais)
-- ============================================
local ctx = { token = 0, rootPart = nil, targetHum = nil }

local function alive()
    return sessionToken == ctx.token
end

local function fPos(BasePart, Pos, Ang)
    if not alive() then return end
    local cf = CFrame.new(BasePart.Position) * Pos * Ang
    ctx.rootPart.CFrame = cf
    ctx.rootPart.AssemblyLinearVelocity  = Vector3.new(9e7, 9e7 * 10, 9e7)
    ctx.rootPart.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
end

local function sfBasePart(BasePart)
    local Time  = tick()
    local Angle = 0
    local hum   = ctx.targetHum
    repeat
        if not alive() then break end
        local rp = ctx.rootPart
        if rp and hum then
            local tVel = BasePart.AssemblyLinearVelocity.Magnitude
            if tVel < 50 then
                Angle = Angle + 100
                fPos(BasePart, CFrame.new(0,  1.5, 0) + hum.MoveDirection * tVel / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                task.wait() if not alive() then break end
                fPos(BasePart, CFrame.new(0, -1.5, 0) + hum.MoveDirection * tVel / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                task.wait() if not alive() then break end
                fPos(BasePart, CFrame.new(0,  1.5, 0) + hum.MoveDirection * tVel / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                task.wait() if not alive() then break end
                fPos(BasePart, CFrame.new(0, -1.5, 0) + hum.MoveDirection * tVel / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                task.wait() if not alive() then break end
                fPos(BasePart, CFrame.new(0,  1.5, 0) + hum.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0))
                task.wait() if not alive() then break end
                fPos(BasePart, CFrame.new(0, -1.5, 0) + hum.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0))
                task.wait() if not alive() then break end
            else
                fPos(BasePart, CFrame.new(0,  1.5,  hum.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                task.wait() if not alive() then break end
                fPos(BasePart, CFrame.new(0, -1.5, -hum.WalkSpeed), CFrame.Angles(0, 0, 0))
                task.wait() if not alive() then break end
                fPos(BasePart, CFrame.new(0,  1.5,  hum.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                task.wait() if not alive() then break end
                fPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
                task.wait() if not alive() then break end
                fPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
                task.wait() if not alive() then break end
                fPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
                task.wait() if not alive() then break end
                fPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
                task.wait() if not alive() then break end
            end
        end
    until tick() - Time >= 2.0 or not alive()
end

-- ============================================
-- FLING ÚNICO
-- ============================================
local function skidFling(target)
    local myToken  = sessionToken
    local Char     = player.Character
    local Hum      = Char and Char:FindFirstChildOfClass("Humanoid")
    local Root     = Hum and Hum.RootPart
    local TChar    = target and target.Character
    if not Char or not Hum or not Root or not TChar then return end
    if sessionToken ~= myToken then return end

    local THum  = TChar:FindFirstChildOfClass("Humanoid")
    local TRoot = THum and THum.RootPart
    local THead = TChar:FindFirstChild("Head")
    local Acc   = TChar:FindFirstChildOfClass("Accessory")
    local Hand  = Acc and Acc:FindFirstChild("Handle")

    if not TChar:FindFirstChildWhichIsA("BasePart") then return end
    if THum and THum.Sit then return end

    if Root.AssemblyLinearVelocity.Magnitude < 50 then
        oldPos = Root.CFrame
    end

    if THead then      workspace.CurrentCamera.CameraSubject = THead
    elseif Hand then   workspace.CurrentCamera.CameraSubject = Hand
    elseif THum then   workspace.CurrentCamera.CameraSubject = THum end

    ctx.token     = myToken
    ctx.rootPart  = Root
    ctx.targetHum = THum

    local BV = nil
    pcall(function()
        workspace.FallenPartsDestroyHeight = 0/0
        BV = Instance.new("BodyVelocity")
        BV.Parent   = Root
        BV.Velocity = Vector3.new(0, 0, 0)
        BV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        Hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        sfBasePart(TRoot or THead or Hand)
    end)

    if BV then pcall(function() BV:Destroy() end) end
    pcall(function() Hum:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end)
    restoreCharacter()

    if sessionToken == myToken and oldPos then
        local n = 0
        repeat
            Root.CFrame = oldPos * CFrame.new(0, 0.5, 0)
            Hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            for _, p in ipairs(Char:GetChildren()) do
                if p:IsA("BasePart") then
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                end
            end
            task.wait()
            n += 1
        until (Root.Position - oldPos.p).Magnitude < 25 or n > 60
    end
end

-- ============================================
-- LOOP DE FLING
-- ============================================
local flingAtivo  = false
local flingThread = nil

local function stop()
    sessionToken += 1
    flingAtivo = false
    if flingThread then task.cancel(flingThread); flingThread = nil end
    task.spawn(restoreCharacter)
end

local function start(getTargets)
    if flingAtivo then return end
    flingAtivo = true
    flingThread = task.spawn(function()
        while flingAtivo do
            local targets = getTargets()
            if #targets == 0 then
                stop()
                break
            end
            for _, t in ipairs(targets) do
                if not flingAtivo then break end
                if t and t.Parent then
                    skidFling(t)
                    task.wait(0.1)
                end
            end
            task.wait(0.5)
        end
    end)
end

local function isActive()
    return flingAtivo
end

-- ============================================
-- API GLOBAL
-- ============================================
_G.KAHSkidFling = {
    start    = start,
    stop     = stop,
    isActive = isActive,
    flingOne = skidFling,
}

_G[STATE_KEY] = {
    stop    = stop,
    cleanup = stop,
}

print('[KAH][READY] SKIDFLING ENGINE v' .. VERSION)
