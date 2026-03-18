local M = {}

local function connect(conns, signal, fn)
    local c = signal:Connect(fn)
    if type(conns) == "table" then
        table.insert(conns, c)
    end
    return c
end

local function styleButton(btn)
    btn.BorderSizePixel = 0
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.AutoButtonColor = true
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
end

local function pulseBtn(ts, btn, baseColor)
    if not ts or not btn or not btn.Parent then return end
    local pulse = Color3.new(
        math.clamp(baseColor.R + 0.08, 0, 1),
        math.clamp(baseColor.G + 0.08, 0, 1),
        math.clamp(baseColor.B + 0.08, 0, 1)
    )
    pcall(function()
        ts:Create(btn, TweenInfo.new(0.08), { BackgroundColor3 = pulse }):Play()
    end)
    task.delay(0.16, function()
        if btn and btn.Parent then
            pcall(function()
                ts:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = baseColor }):Play()
            end)
        end
    end)
end

local function makeSection(parent, colors, title)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = colors.panel
    card.BorderSizePixel = 0
    card.Parent = parent
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 4)
    Instance.new("UIStroke", card).Color = colors.border

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.PaddingTop = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.Parent = card

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = card

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.BackgroundTransparency = 1
    lbl.Text = tostring(title or "")
    lbl.TextColor3 = colors.accent
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 10
    lbl.Parent = card

    return card
end

function M.mount(ctx)
    ctx = type(ctx) == "table" and ctx or {}
    local page = ctx.page
    local C = type(ctx.colors) == "table" and ctx.colors or {}
    local conns = ctx.conns
    local actions = ctx.actions
    local TS = ctx.tweenService

    if not page or type(actions) ~= "table" then
        return false, "invalid_ctx"
    end

    local root = Instance.new("Frame")
    root.Size = UDim2.new(1, 0, 1, 0)
    root.BackgroundTransparency = 1
    root.Parent = page

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = C.accent
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.Parent = root

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 6)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = scroll

    local topPad = Instance.new("UIPadding")
    topPad.PaddingTop = UDim.new(0, 2)
    topPad.PaddingBottom = UDim.new(0, 2)
    topPad.Parent = scroll

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -4, 0, 28)
    info.BackgroundTransparency = 1
    info.TextWrapped = true
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextColor3 = C.text
    info.Font = Enum.Font.Gotham
    info.TextSize = 10
    info.Text = "Botoes de debug para passos e teleports do Stronghold."
    info.Parent = scroll

    local stepCard = makeSection(scroll, C, "PASSOS DO FLUXO")

    local labels = actions.getStepLabels and actions.getStepLabels() or nil
    local stepCount = 5
    if type(labels) == "table" then
        local lastIdx = 0
        for i = 1, #labels do
            if labels[i] ~= nil then
                lastIdx = i
            end
        end
        if lastIdx > 0 then
            stepCount = lastIdx
        end
    end

    for i = 1, stepCount do
        local text = (type(labels) == "table" and labels[i]) or ("PASSO " .. tostring(i))
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 26)
        b.Text = tostring(text)
        b.BackgroundColor3 = Color3.fromRGB(12, 36, 50)
        b.TextColor3 = C.accent
        b.Parent = stepCard
        styleButton(b)
        connect(conns, b.MouseButton1Click, function()
            pulseBtn(TS, b, Color3.fromRGB(12, 36, 50))
            if actions.step then
                actions.step(i)
            end
        end)
    end

    local runAllBtn = Instance.new("TextButton")
    runAllBtn.Size = UDim2.new(1, 0, 0, 28)
    runAllBtn.Text = "RUN ALL"
    runAllBtn.BackgroundColor3 = C.greenDim
    runAllBtn.TextColor3 = C.green
    runAllBtn.Parent = stepCard
    styleButton(runAllBtn)
    connect(conns, runAllBtn.MouseButton1Click, function()
        pulseBtn(TS, runAllBtn, C.greenDim)
        if actions.runAll then
            actions.runAll()
        end
    end)

    local stopBtn = Instance.new("TextButton")
    stopBtn.Size = UDim2.new(1, 0, 0, 26)
    stopBtn.Text = "STOP"
    stopBtn.BackgroundColor3 = C.redDim
    stopBtn.TextColor3 = C.red
    stopBtn.Parent = stepCard
    styleButton(stopBtn)
    connect(conns, stopBtn.MouseButton1Click, function()
        pulseBtn(TS, stopBtn, C.redDim)
        if actions.stop then
            actions.stop()
        end
    end)

    local tpCard = makeSection(scroll, C, "TELEPORTES")

    local tpDefs = {
        { key = "entry", label = "TP ENTRADA" },
        { key = "bridge", label = "TP BRIDGE" },
        { key = "door1", label = "TP PORTA 1" },
        { key = "door2", label = "TP PORTA 2" },
        { key = "diamond", label = "TP DIAMOND" },
    }

    for _, it in ipairs(tpDefs) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 26)
        b.Text = it.label
        b.BackgroundColor3 = C.row
        b.TextColor3 = C.text
        b.Parent = tpCard
        styleButton(b)
        connect(conns, b.MouseButton1Click, function()
            pulseBtn(TS, b, C.row)
            if actions.teleport then
                actions.teleport(it.key, it.label)
            end
        end)
    end

    local pingBtn = Instance.new("TextButton")
    pingBtn.Size = UDim2.new(1, 0, 0, 26)
    pingBtn.Text = "PING DIAMOND"
    pingBtn.BackgroundColor3 = Color3.fromRGB(26, 38, 52)
    pingBtn.TextColor3 = C.accent
    pingBtn.Parent = tpCard
    styleButton(pingBtn)
    connect(conns, pingBtn.MouseButton1Click, function()
        pulseBtn(TS, pingBtn, Color3.fromRGB(26, 38, 52))
        if actions.pingDiamond then
            actions.pingDiamond()
        end
    end)

    local burstBtn = Instance.new("TextButton")
    burstBtn.Size = UDim2.new(1, 0, 0, 26)
    burstBtn.Text = "CHEST FARM BURST"
    burstBtn.BackgroundColor3 = C.greenDim
    burstBtn.TextColor3 = C.green
    burstBtn.Parent = tpCard
    styleButton(burstBtn)
    connect(conns, burstBtn.MouseButton1Click, function()
        pulseBtn(TS, burstBtn, C.greenDim)
        if actions.chestFarmBurst then
            actions.chestFarmBurst()
        end
    end)

    local scanCard = makeSection(scroll, C, "MOB SCANNER")

    local scanInfo = Instance.new("TextLabel")
    scanInfo.Size = UDim2.new(1, 0, 0, 28)
    scanInfo.BackgroundTransparency = 1
    scanInfo.TextWrapped = true
    scanInfo.TextYAlignment = Enum.TextYAlignment.Top
    scanInfo.TextXAlignment = Enum.TextXAlignment.Left
    scanInfo.TextColor3 = C.muted or C.text
    scanInfo.Font = Enum.Font.Gotham
    scanInfo.TextSize = 10
    scanInfo.Text = "Captura spawn de mobs e salva no clipboard com passo atual/entre passos ao parar."
    scanInfo.Parent = scanCard

    local scanStartBtn = Instance.new("TextButton")
    scanStartBtn.Size = UDim2.new(1, 0, 0, 26)
    scanStartBtn.Text = "START MOB SCANNER"
    scanStartBtn.BackgroundColor3 = C.greenDim
    scanStartBtn.TextColor3 = C.green
    scanStartBtn.Parent = scanCard
    styleButton(scanStartBtn)
    connect(conns, scanStartBtn.MouseButton1Click, function()
        pulseBtn(TS, scanStartBtn, C.greenDim)
        if actions.startMobScanner then
            actions.startMobScanner()
        end
    end)

    local scanStopBtn = Instance.new("TextButton")
    scanStopBtn.Size = UDim2.new(1, 0, 0, 26)
    scanStopBtn.Text = "STOP + COPY REPORT"
    scanStopBtn.BackgroundColor3 = Color3.fromRGB(52, 46, 22)
    scanStopBtn.TextColor3 = C.yellow
    scanStopBtn.Parent = scanCard
    styleButton(scanStopBtn)
    connect(conns, scanStopBtn.MouseButton1Click, function()
        pulseBtn(TS, scanStopBtn, Color3.fromRGB(52, 46, 22))
        if actions.stopMobScanner then
            actions.stopMobScanner()
        end
    end)

    local spacer = Instance.new("Frame")
    spacer.Size = UDim2.new(1, 0, 0, 2)
    spacer.BackgroundTransparency = 1
    spacer.Parent = scroll

    return true
end

return M
