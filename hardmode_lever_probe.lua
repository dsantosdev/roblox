-- ============================================
-- HARDMODE LEVER PROBE (isolated)
-- Clipboard logs only. No print/warn.
-- ============================================

local STATE_KEY = "__kah_hardmode_lever_probe_state"

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

do
    local old = _G[STATE_KEY]
    if old then
        if old.cleanup then pcall(old.cleanup) end
        if old.gui and old.gui.Parent then
            pcall(function() old.gui:Destroy() end)
        end
    end
    _G[STATE_KEY] = nil
end

local C = {
    bg = Color3.fromRGB(10, 11, 15),
    panel = Color3.fromRGB(15, 17, 23),
    header = Color3.fromRGB(12, 14, 20),
    border = Color3.fromRGB(28, 32, 48),
    accent = Color3.fromRGB(0, 220, 255),
    text = Color3.fromRGB(180, 190, 210),
    muted = Color3.fromRGB(95, 108, 132),
    green = Color3.fromRGB(50, 220, 100),
    greenDim = Color3.fromRGB(15, 55, 25),
    red = Color3.fromRGB(220, 50, 70),
    redDim = Color3.fromRGB(55, 12, 18),
    row = Color3.fromRGB(18, 20, 28),
}

local ICONS = {
    min = "rbxassetid://6031090990",
    close = "rbxassetid://6031091004",
}

local dead = false
local logsEnabled = true
local logs = {}
local conns = {}
local terminals = {}

local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Hardmode Probe",
            Text = tostring(msg),
            Duration = 2.5,
        })
    end)
end

local function tsNow()
    local ok, dt = pcall(function() return DateTime.now() end)
    if ok and dt then
        return dt:FormatLocalTime("HH:mm:ss", "pt-br")
    end
    return os.date("%H:%M:%S")
end

local function pushLog(msg)
    if dead or not logsEnabled then return end
    local line = string.format("%s | %s", tsNow(), tostring(msg))
    table.insert(logs, line)
    if #logs > 220 then
        table.remove(logs, 1)
    end
    local dump = table.concat(logs, "\n")
    _G.__kah_hardmode_probe_log = dump
    if setclipboard then
        pcall(setclipboard, dump)
    end
end

local function getHRP()
    local ch = player.Character
    if not ch then return nil end
    return ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
end

local function lower(v)
    return string.lower(tostring(v or ""))
end

local function getMainPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") and obj.PrimaryPart then return obj.PrimaryPart end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("BasePart") then
            return d
        end
    end
    return nil
end

local function parseNumber(name)
    local n = string.match(tostring(name), "(%d+)")
    return tonumber(n) or 999
end

local function findOutpost()
    local map = workspace:FindFirstChild("Map")
    local landmarks = map and map:FindFirstChild("Landmarks")
    local outpost = landmarks and landmarks:FindFirstChild("Research Outpost")
    return outpost
end

local function scanTerminals()
    local outpost = findOutpost()
    if not outpost then
        return {}
    end

    local list = {}
    for _, d in ipairs(outpost:GetDescendants()) do
        if d:IsA("Model") and string.find(lower(d.Name), "voteterminal", 1, true) then
            local prompt = d:FindFirstChildWhichIsA("ProximityPrompt", true)
            local lever = d:FindFirstChild("Lever", true)
            local part = getMainPart(lever) or getMainPart(d)
            local uid = d:GetAttribute("UserId")
            list[#list + 1] = {
                model = d,
                name = d.Name,
                number = parseNumber(d.Name),
                userId = tonumber(uid),
                prompt = prompt,
                part = part,
            }
        end
    end

    table.sort(list, function(a, b)
        if a.number ~= b.number then
            return a.number < b.number
        end
        return tostring(a.name) < tostring(b.name)
    end)

    return list
end

local function findByNumber(num)
    local n = tonumber(num)
    if not n then return nil end
    for _, t in ipairs(terminals) do
        if t.number == n then
            return t
        end
    end
    return nil
end

local function findMyTerminal()
    local myId = player.UserId
    for _, t in ipairs(terminals) do
        if t.userId == myId then
            return t
        end
    end
    return nil
end

local function terminalDist(t)
    local hrp = getHRP()
    if not hrp or not t or not t.part then return nil end
    return (hrp.Position - t.part.Position).Magnitude
end

local function logScan()
    terminals = scanTerminals()
    pushLog(string.format("scan terminals=%d", #terminals))
    if #terminals == 0 then
        return
    end
    for _, t in ipairs(terminals) do
        local dist = terminalDist(t)
        local dtxt = dist and string.format("%.1f", dist) or "na"
        pushLog(string.format("terminal=%s num=%d user=%s prompt=%s dist=%s",
            tostring(t.name),
            tonumber(t.number) or -1,
            t.userId and tostring(t.userId) or "nil",
            t.prompt and "yes" or "no",
            dtxt
        ))
    end
end

local function tpFront(t)
    if not t or not t.part then
        pushLog("tp failed: terminal/part not found")
        return false
    end
    local hrp = getHRP()
    if not hrp then
        pushLog("tp failed: no hrp")
        return false
    end
    local base = t.part.Position
    local lv = t.part.CFrame.LookVector
    local flat = Vector3.new(lv.X, 0, lv.Z)
    if flat.Magnitude < 0.001 then
        flat = Vector3.new(0, 0, -1)
    end
    local dst = base + flat.Unit * 2.2 + Vector3.new(0, 1.0, 0)
    hrp.CFrame = CFrame.lookAt(dst, base + Vector3.new(0, 1.0, 0))
    pushLog(string.format("tp ok %s", tostring(t.name)))
    return true
end

local function firePrompt(prompt)
    if not prompt then return false, "no prompt" end
    if type(fireproximityprompt) ~= "function" then
        return false, "fireproximityprompt missing"
    end

    local ok = pcall(function() fireproximityprompt(prompt) end)
    if ok then return true, "ok(default)" end

    ok = pcall(function() fireproximityprompt(prompt, 0) end)
    if ok then return true, "ok(hold0)" end

    ok = pcall(function() fireproximityprompt(prompt, 0, true) end)
    if ok then return true, "ok(hold0,skip)" end

    return false, "all calls failed"
end

local function tryPromptOn(t, tag)
    if not t then
        pushLog(string.format("%s failed: terminal nil", tostring(tag)))
        return false
    end
    local ok, info = firePrompt(t.prompt)
    pushLog(string.format("%s %s -> %s", tostring(tag), tostring(t.name), tostring(info)))
    return ok
end

local function tryRemoteOn(t)
    local remote = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents")
    remote = remote and remote:FindFirstChild("RequestActivateHardModeLever")
    if not remote then
        pushLog("remote missing: RequestActivateHardModeLever")
        return
    end
    if not t then
        pushLog("remote failed: terminal nil")
        return
    end

    local variants = {
        { "none", function() remote:FireServer() end },
        { "model", function() remote:FireServer(t.model) end },
        { "name", function() remote:FireServer(t.name) end },
        { "num", function() remote:FireServer(t.number) end },
    }

    for _, v in ipairs(variants) do
        local ok, err = pcall(v[2])
        pushLog(string.format("remote[%s] ok=%s err=%s", v[1], tostring(ok), tostring(err)))
    end
end

local pg = player:WaitForChild("PlayerGui")
local oldGui = pg:FindFirstChild("HardmodeLeverProbe_hud")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "HardmodeLeverProbe_hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = pg

local W = 320
local H = 312
local H_HDR = 34
local PAD = 6
local minimizado = false
local fullH = H

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, W, 0, H)
frame.Position = UDim2.new(0, 20, 0, 120)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color = C.border

local topLine = Instance.new("Frame")
topLine.Size = UDim2.new(1, 0, 0, 2)
topLine.BackgroundColor3 = C.accent
topLine.BorderSizePixel = 0
topLine.Parent = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, H_HDR)
header.BackgroundColor3 = C.header
header.BorderSizePixel = 0
header.Active = true
header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -90, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.Text = "HARDMODE LEVER PROBE"
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.TextColor3 = C.accent
title.TextXAlignment = Enum.TextXAlignment.Left
title.BackgroundTransparency = 1
title.Parent = header

local function mkIconBtn(xOffset, bg, color, img)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 20, 0, 20)
    b.Position = UDim2.new(1, xOffset, 0.5, -10)
    b.BackgroundColor3 = bg
    b.Text = ""
    b.BorderSizePixel = 0
    b.Parent = header
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 3)
    local st = Instance.new("UIStroke", b)
    st.Color = C.border
    local ic = Instance.new("ImageLabel")
    ic.AnchorPoint = Vector2.new(0.5, 0.5)
    ic.Position = UDim2.new(0.5, 0, 0.5, 0)
    ic.Size = UDim2.new(0, 12, 0, 12)
    ic.BackgroundTransparency = 1
    ic.Image = img
    ic.ImageColor3 = color
    ic.Parent = b
    return b
end

local minBtn = mkIconBtn(-44, Color3.fromRGB(25, 28, 38), C.muted, ICONS.min)
local closeBtn = mkIconBtn(-20, C.redDim, C.red, ICONS.close)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -12, 0, 20)
status.Position = UDim2.new(0, 6, 0, H_HDR + PAD - 1)
status.BackgroundTransparency = 1
status.Text = "Pronto."
status.TextColor3 = C.text
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = frame

local targetLabel = Instance.new("TextLabel")
targetLabel.Size = UDim2.new(0, 54, 0, 20)
targetLabel.Position = UDim2.new(0, 6, 0, H_HDR + PAD + 18)
targetLabel.Text = "TARGET #"
targetLabel.BackgroundTransparency = 1
targetLabel.TextColor3 = C.muted
targetLabel.Font = Enum.Font.GothamBold
targetLabel.TextSize = 10
targetLabel.TextXAlignment = Enum.TextXAlignment.Left
targetLabel.Parent = frame

local targetBox = Instance.new("TextBox")
targetBox.Size = UDim2.new(0, 46, 0, 20)
targetBox.Position = UDim2.new(0, 62, 0, H_HDR + PAD + 18)
targetBox.Text = "1"
targetBox.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
targetBox.TextColor3 = C.accent
targetBox.Font = Enum.Font.GothamBold
targetBox.TextSize = 10
targetBox.BorderSizePixel = 0
targetBox.ClearTextOnFocus = false
targetBox.Parent = frame
Instance.new("UICorner", targetBox).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", targetBox).Color = C.border

local btnHolder = Instance.new("Frame")
btnHolder.Size = UDim2.new(1, -12, 0, 78)
btnHolder.Position = UDim2.new(0, 6, 0, H_HDR + PAD + 42)
btnHolder.BackgroundTransparency = 1
btnHolder.Parent = frame

local function mkActionButton(text, x, y, w, colorA, colorB)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, 22)
    b.Position = UDim2.new(0, x, 0, y)
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = colorA
    b.BackgroundColor3 = colorB
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Parent = btnHolder
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    local st = Instance.new("UIStroke", b)
    st.Color = C.border
    return b
end

local scanBtn = mkActionButton("SCAN", 0, 0, 72, C.accent, Color3.fromRGB(12, 36, 50))
local tpBtn = mkActionButton("TP TARGET", 76, 0, 86, C.text, C.row)
local pullBtn = mkActionButton("PULL TARGET", 166, 0, 100, C.text, C.row)
local myBtn = mkActionButton("PULL MINE", 0, 26, 86, C.text, C.row)
local allBtn = mkActionButton("PULL ALL", 90, 26, 76, C.text, C.row)
local remoteBtn = mkActionButton("REMOTE TEST", 170, 26, 96, C.text, C.row)
local logToggleBtn = mkActionButton("LOGS: ON", 0, 52, 86, C.green, C.greenDim)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -12, 1, -(H_HDR + PAD + 126))
scroll.Position = UDim2.new(0, 6, 0, H_HDR + PAD + 124)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.ScrollBarThickness = 4
scroll.BackgroundColor3 = C.panel
scroll.BorderSizePixel = 0
scroll.Parent = frame
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", scroll).Color = C.border

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 3)
listLayout.Parent = scroll

local function refreshList()
    for _, ch in ipairs(scroll:GetChildren()) do
        if ch:IsA("TextLabel") then
            ch:Destroy()
        end
    end

    for _, t in ipairs(terminals) do
        local dist = terminalDist(t)
        local text = string.format("[%d] %s | user:%s | dist:%s | prompt:%s",
            t.number,
            t.name,
            t.userId and tostring(t.userId) or "nil",
            dist and string.format("%.1f", dist) or "na",
            t.prompt and "yes" or "no"
        )
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -6, 0, 18)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = C.text
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = scroll
    end

    task.defer(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 6)
    end)
end

local function setStatus(msg, color)
    status.Text = tostring(msg)
    if color then
        status.TextColor3 = color
    else
        status.TextColor3 = C.text
    end
end

local function runScan()
    logScan()
    refreshList()
    setStatus(string.format("Terminais detectados: %d", #terminals), C.accent)
end

local function resolveTarget()
    local idx = tonumber(targetBox.Text)
    if not idx then
        setStatus("Target invalido.", C.red)
        return nil
    end
    local t = findByNumber(idx)
    if not t then
        setStatus("Target nao encontrado.", C.red)
        pushLog(string.format("target %s not found", tostring(targetBox.Text)))
        return nil
    end
    return t
end

local function tapFeedback(btn)
    local old = btn.BackgroundColor3
    TS:Create(btn, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(30, 55, 40) }):Play()
    task.delay(0.16, function()
        if btn and btn.Parent then
            TS:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = old }):Play()
        end
    end)
end

table.insert(conns, scanBtn.MouseButton1Click:Connect(function()
    tapFeedback(scanBtn)
    runScan()
end))

table.insert(conns, tpBtn.MouseButton1Click:Connect(function()
    tapFeedback(tpBtn)
    if #terminals == 0 then runScan() end
    local t = resolveTarget()
    if not t then return end
    local ok = tpFront(t)
    setStatus(ok and "Teleport aplicado." or "Teleport falhou.", ok and C.green or C.red)
end))

table.insert(conns, pullBtn.MouseButton1Click:Connect(function()
    tapFeedback(pullBtn)
    if #terminals == 0 then runScan() end
    local t = resolveTarget()
    if not t then return end
    local ok = tryPromptOn(t, "pull_target")
    setStatus(ok and "Tentativa enviada." or "Falha ao enviar.", ok and C.green or C.red)
end))

table.insert(conns, myBtn.MouseButton1Click:Connect(function()
    tapFeedback(myBtn)
    if #terminals == 0 then runScan() end
    local t = findMyTerminal()
    if not t then
        pushLog("pull_mine failed: my lever not found")
        setStatus("Nao achou alavanca vinculada ao seu UserId.", C.red)
        return
    end
    local ok = tryPromptOn(t, "pull_mine")
    setStatus(ok and "Tentativa enviada." or "Falha ao enviar.", ok and C.green or C.red)
end))

table.insert(conns, allBtn.MouseButton1Click:Connect(function()
    tapFeedback(allBtn)
    if #terminals == 0 then runScan() end
    local sent = 0
    for _, t in ipairs(terminals) do
        if tryPromptOn(t, "pull_all") then
            sent = sent + 1
        end
    end
    setStatus(string.format("Tentativas enviadas: %d", sent), C.accent)
end))

table.insert(conns, remoteBtn.MouseButton1Click:Connect(function()
    tapFeedback(remoteBtn)
    if #terminals == 0 then runScan() end
    local t = resolveTarget()
    if not t then return end
    tryRemoteOn(t)
    setStatus("Remote test registrado no log.", C.accent)
end))

table.insert(conns, logToggleBtn.MouseButton1Click:Connect(function()
    logsEnabled = not logsEnabled
    if logsEnabled then
        logToggleBtn.Text = "LOGS: ON"
        logToggleBtn.TextColor3 = C.green
        logToggleBtn.BackgroundColor3 = C.greenDim
        pushLog("logging resumed")
        setStatus("Logs no clipboard: ON", C.green)
    else
        logToggleBtn.Text = "LOGS: OFF"
        logToggleBtn.TextColor3 = C.red
        logToggleBtn.BackgroundColor3 = C.redDim
        setStatus("Logs no clipboard: OFF", C.red)
    end
end))

table.insert(conns, minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    if minimizado then
        fullH = frame.Size.Y.Offset
        frame.Size = UDim2.new(0, W, 0, H_HDR)
        status.Visible = false
        targetLabel.Visible = false
        targetBox.Visible = false
        btnHolder.Visible = false
        scroll.Visible = false
    else
        frame.Size = UDim2.new(0, W, 0, fullH)
        status.Visible = true
        targetLabel.Visible = true
        targetBox.Visible = true
        btnHolder.Visible = true
        scroll.Visible = true
    end
end))

local function cleanup()
    if dead then return end
    dead = true
    logsEnabled = false
    for _, c in ipairs(conns) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(conns)
    table.clear(logs)
    _G.__kah_hardmode_probe_log = nil
    if gui and gui.Parent then
        pcall(function() gui:Destroy() end)
    end
    _G[STATE_KEY] = nil
end

table.insert(conns, closeBtn.MouseButton1Click:Connect(function()
    cleanup()
end))

local dragging = false
local dragStart
local startPos

table.insert(conns, header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = i.Position
        startPos = frame.Position
    end
end))

table.insert(conns, UIS.InputChanged:Connect(function(i)
    if not dragging then return end
    if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local d = i.Position - dragStart
    frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
end))

table.insert(conns, UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end))

_G[STATE_KEY] = {
    gui = gui,
    cleanup = cleanup,
}

runScan()
setStatus("Pronto. Logs ativos no clipboard.", C.green)
notify("Probe iniciado.")
