-- T&F BALL MASTER V8 - ENGLISH UI & W-ONLY TURBO (XENO)
local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ball = nil
local speedActive = false
local speedMultiplier = 30 
local bPos = nil
local targetHeight = 0

-- Function to identify the ball
local function getBall()
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.SeatPart then
        local model = humanoid.SeatPart.Parent
        return model:FindFirstChild("CollisionBall", true)
    end
    return nil
end

-- VISUAL INTERFACE (ENGLISH)
local sg = Instance.new("ScreenGui", player.PlayerGui)
sg.Name = "Xeno_BallMaster_EN"

local f = Instance.new("Frame", sg)
f.Size = UDim2.new(0, 260, 0, 240)
f.Position = UDim2.new(0.05, 0, 0.4, 0)
f.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
f.Draggable = true
f.Active = true
Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)

-- Speedometer
local speedDisplay = Instance.new("TextLabel", f)
speedDisplay.Size = UDim2.new(1, 0, 0, 50)
speedDisplay.Position = UDim2.new(0, 0, 0, 35)
speedDisplay.Text = "0 KM/H"
speedDisplay.TextColor3 = Color3.fromRGB(255, 255, 255)
speedDisplay.Font = Enum.Font.Code
speedDisplay.TextSize = 30
speedDisplay.BackgroundTransparency = 1

local speedBarBack = Instance.new("Frame", f)
speedBarBack.Size = UDim2.new(0.9, 0, 0, 10)
speedBarBack.Position = UDim2.new(0.05, 0, 0, 85)
speedBarBack.BackgroundColor3 = Color3.fromRGB(50, 50, 50)

local speedBar = Instance.new("Frame", speedBarBack)
speedBar.Size = UDim2.new(0, 0, 1, 0)
speedBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)

-- Keybind Labels
local label = Instance.new("TextLabel", f)
label.Size = UDim2.new(1, 0, 0, 120)
label.Position = UDim2.new(0, 0, 0, 100)
label.Text = "8/2: Height | 5: Stop/Lock | 0: Fall\n1: Turbo Toggle (HOLD W)\n7/4: +/- Power | 9: Swap 200/5\nX: Close All"
label.TextColor3 = Color3.new(0.8, 0.8, 0.8)
label.BackgroundTransparency = 1
label.TextSize = 13

local status = Instance.new("TextLabel", f)
status.Size = UDim2.new(1, 0, 0, 30)
status.Position = UDim2.new(0, 0, 1, -30)
status.Text = "TURBO POWER: 30"
status.TextColor3 = Color3.fromRGB(255, 255, 0)
status.BackgroundColor3 = Color3.fromRGB(30, 30, 30)

local close = Instance.new("TextButton", f)
close.Size = UDim2.new(0, 25, 0, 25)
close.Position = UDim2.new(1, -30, 0, 5)
close.Text = "X"
close.BackgroundColor3 = Color3.new(0.6, 0, 0)
close.TextColor3 = Color3.new(1,1,1)

-- UPDATE LOOP (PHYSICS + VISUAL)
RunService.RenderStepped:Connect(function()
    ball = getBall()
    local currentVel = 0
    
    if ball and ball.Parent then
        currentVel = math.floor(ball.AssemblyLinearVelocity.Magnitude)
        
        -- CHECKS IF TURBO IS ON AND 'W' IS PRESSED
        local isWPushed = UIS:IsKeyDown(Enum.KeyCode.W)
        
        if speedActive and isWPushed then
            local lookVec = camera.CFrame.LookVector
            local direction = Vector3.new(lookVec.X, 0, lookVec.Z).Unit
            ball.AssemblyLinearVelocity = (direction * (speedMultiplier * 6)) + Vector3.new(0, -15, 0)
        end
    else
        currentVel = math.floor(root.AssemblyLinearVelocity.Magnitude)
    end
    
    speedDisplay.Text = currentVel .. " KM/H"
    local barWidth = math.min(currentVel / 400, 1)
    speedBar.Size = UDim2.new(barWidth, 0, 1, 0)
    speedBar.BackgroundColor3 = Color3.fromHSV(math.max(0, (1 - barWidth) * 0.35), 1, 1)
end)

-- KEYBOARD CONTROLS
local connection
connection = UIS.InputBegan:Connect(function(input, proc)
    if proc then return end
    
    if input.KeyCode == Enum.KeyCode.KeypadEight then -- Up 5
        ball = getBall()
        if ball and not bPos then
            bPos = Instance.new("BodyPosition", ball)
            bPos.MaxForce = Vector3.new(0, math.huge, 0)
            bPos.P = 20000
            targetHeight = ball.Position.Y
        end
        targetHeight = targetHeight + 5
        if bPos then bPos.Position = Vector3.new(0, targetHeight, 0) end
        
    elseif input.KeyCode == Enum.KeyCode.KeypadTwo then -- Down 5
        if bPos then
            targetHeight = targetHeight - 5
            bPos.Position = Vector3.new(0, targetHeight, 0)
        end
        
    elseif input.KeyCode == Enum.KeyCode.KeypadFive then -- Lock/Stop
        speedActive = false
        if ball then
            ball.AssemblyLinearVelocity = Vector3.new(0,0,0)
            if bPos then targetHeight = ball.Position.Y; bPos.Position = Vector3.new(0, targetHeight, 0) end
        end
        
    elseif input.KeyCode == Enum.KeyCode.KeypadZero then -- Fall
        if bPos then bPos:Destroy(); bPos = nil end
        
    elseif input.KeyCode == Enum.KeyCode.KeypadOne then -- Turbo Toggle
        speedActive = not speedActive
        
    elseif input.KeyCode == Enum.KeyCode.KeypadSeven then -- Power +5
        speedMultiplier = speedMultiplier + 5
        
    elseif input.KeyCode == Enum.KeyCode.KeypadFour then -- Power -5
        speedMultiplier = math.max(0, speedMultiplier - 5)
        
    elseif input.KeyCode == Enum.KeyCode.KeypadNine then -- SWAP 200/5
        speedMultiplier = (speedMultiplier == 200) and 5 or 200
    end
    status.Text = "TURBO POWER: " .. speedMultiplier
end)

close.MouseButton1Click:Connect(function()
    if bPos then bPos:Destroy() end
    connection:Disconnect()
    sg:Destroy()
end)
