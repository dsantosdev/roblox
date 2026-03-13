-- ============================================
-- MÓDULO: PLAYER ACTIONS
-- Follow, Câmera, ações sobre jogadores
-- ============================================
local VERSION = "1.0.3"
local CATEGORIA = "Player"
local MODULE_NAME = "Player Actions"

-- Não executa sem o hub
if not _G.Hub and not _G.HubFila then
    print('>>> follow_player: hub não encontrado, abortando')
    return
end

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local TS      = game:GetService("TweenService")
local RS      = game:GetService("RunService")
local player  = Players.LocalPlayer
local FOLLOW_STATE_KEY = "__player_actions_follow_state"

-- ============================================
-- CÂMERA
-- ============================================
local camOrigSub = nil
local camTarget  = nil

local function resetCam()
    local cam = workspace.CurrentCamera
    if camOrigSub then cam.CameraSubject = camOrigSub; camOrigSub = nil
    else
        local c = player.Character
        if c then local h = c:FindFirstChildOfClass("Humanoid"); if h then cam.CameraSubject = h end end
    end
    camTarget = nil
end

local function iniciarCam(target)
    resetCam()
    local cam = workspace.CurrentCamera; camOrigSub = cam.CameraSubject; camTarget = target
    local c = target.Character; if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid"); if hum then cam.CameraSubject = hum end
end

-- ============================================
-- LÓGICA FOLLOW
-- ============================================
local followConn = nil
local targetPlayer = nil
local followMode = "follow"
local orbitAngle = 0
local ORBIT_RAIO = 10
local ORBIT_VEL = 0
local OFFSET_FOLLOW = Vector3.new(0, 0, 1)
local OFFSET_HEAD = Vector3.new(0, 3.5, 0)

local function getHRP(p)
    local c = p and p.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function getHead(p)
    local c = p and p.Character
    return c and c:FindFirstChild("Head")
end

do
    local antigo = _G[FOLLOW_STATE_KEY]
    if antigo and antigo.cleanup then pcall(antigo.cleanup) end
    _G[FOLLOW_STATE_KEY] = { active = false, target = nil, mode = nil }
end

local function pararFollow()
    if followConn then followConn:Disconnect(); followConn = nil end
    targetPlayer = nil
    orbitAngle = 0
    _G[FOLLOW_STATE_KEY] = { active = false, target = nil, mode = nil, cleanup = pararFollow }
end

local function iniciarFollow(target, mode)
    pararFollow()
    targetPlayer = target
    followMode = mode or "follow"
    _G[FOLLOW_STATE_KEY] = { active = true, target = target, mode = followMode, cleanup = pararFollow }

    followConn = RS.Heartbeat:Connect(function(dt)
        if not targetPlayer or not targetPlayer.Parent then pararFollow(); return end
        local myHRP = getHRP(player)
        local targetHRP = getHRP(targetPlayer)
        if not myHRP or not targetHRP then return end

        if followMode == "head" then
            local head = getHead(targetPlayer)
            local base = head and head.CFrame or targetHRP.CFrame
            myHRP.CFrame = CFrame.new(base.Position + OFFSET_HEAD)
        elseif followMode == "inside" then
            myHRP.CFrame = targetHRP.CFrame
        elseif followMode == "orbit" then
            orbitAngle = orbitAngle + ORBIT_VEL * dt
            local cx = targetHRP.Position.X + math.cos(orbitAngle) * ORBIT_RAIO
            local cz = targetHRP.Position.Z + math.sin(orbitAngle) * ORBIT_RAIO
            myHRP.CFrame = CFrame.new(Vector3.new(cx, targetHRP.Position.Y, cz), targetHRP.Position)
        else
            myHRP.CFrame = targetHRP.CFrame * CFrame.new(OFFSET_FOLLOW)
        end
    end)
end

-- ============================================
-- JUMP PLAYERS
-- ============================================
local JUMP_AUTHORIZED = { Kahrrasco = true, Dieisson = true }
local jumpAtivo      = false
local jumpIntervalMs = 1500
local jumpThread     = nil
local jumpOrigemCF   = nil

local function isAuthorized()
    return JUMP_AUTHORIZED[player.Name] == true
end

local function pararJump(voltarOrigem)
    jumpAtivo = false
    if jumpThread then task.cancel(jumpThread); jumpThread = nil end
    if voltarOrigem and jumpOrigemCF then
        local lock = true
        local conn
        conn = RS.Heartbeat:Connect(function()
            if not lock then conn:Disconnect(); return end
            local c = player.Character
            local h = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
            if h then h.CFrame = jumpOrigemCF end
        end)
        task.delay(1.2, function() lock = false end)
        jumpOrigemCF = nil
    end
end

local function iniciarJump()
    if not isAuthorized() then return end
    local c = player.Character
    local hrp = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
    jumpOrigemCF = hrp and hrp.CFrame or nil
    jumpAtivo = true
    jumpThread = task.spawn(function()
        while jumpAtivo do
            local lista = Players:GetPlayers()
            if #lista > 0 then
                local alvo = lista[math.random(1, #lista)]
                local ac = alvo and alvo.Character
                local aHRP = ac and (ac:FindFirstChild("HumanoidRootPart") or ac:FindFirstChild("Torso"))
                local aHead = ac and ac:FindFirstChild("Head")
                if aHRP then
                    -- usa posição "em cima da cabeça" (modo head)
                    local base = aHead and aHead.CFrame or aHRP.CFrame
                    local destino = CFrame.new(base.Position + OFFSET_HEAD)
                    local lock = true
                    local conn
                    conn = RS.Heartbeat:Connect(function()
                        if not lock then conn:Disconnect(); return end
                        local ch = player.Character
                        local h = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
                        if h then h.CFrame = destino end
                    end)
                    task.delay(0.9, function() lock = false end)
                end
            end
            task.wait(jumpIntervalMs / 1000)
        end
    end)
end

-- referência ao visual do toggle jump para atualizar de fora
local setJumpVisualRef = nil

-- ============================================
-- CORES
-- ============================================
local C = {
    bg        = Color3.fromRGB(10, 11, 15),
    header    = Color3.fromRGB(12, 14, 20),
    border    = Color3.fromRGB(28, 32, 48),
    accent    = Color3.fromRGB(0, 220, 255),
    green     = Color3.fromRGB(50, 220, 100),
    greenDim  = Color3.fromRGB(15, 55, 25),
    red       = Color3.fromRGB(220, 50, 70),
    redDim    = Color3.fromRGB(55, 12, 18),
    purple    = Color3.fromRGB(180, 80, 255),
    purpleDim = Color3.fromRGB(40, 15, 70),
    text      = Color3.fromRGB(180, 190, 210),
    muted     = Color3.fromRGB(120, 130, 155),
    rowBg     = Color3.fromRGB(18, 20, 28),
    rowActive = Color3.fromRGB(15, 35, 25),
    panel     = Color3.fromRGB(15, 17, 23)
}

-- ============================================
-- LAYOUT
-- ============================================
local W = 240
local H_HDR        = 34
local H_ROW        = 36
local H_JUMP_ROW   = 44   -- jump slot (tem campo ms)
local H_STATUS     = 22
local PAD          = 6
local H_MAX_SCROLL = 240

local function getMinimizedWidth()
    if _G.KAHUiDefaults and _G.KAHUiDefaults.getMinWidth then
        local ok, v = pcall(_G.KAHUiDefaults.getMinWidth)
        if ok and tonumber(v) then return math.clamp(math.floor(tonumber(v)), 220, 420) end
    end
    return 240
end

-- ============================================
-- GUI
-- ============================================
local pg = player:WaitForChild("PlayerGui")
local ant = pg:FindFirstChild("FollowModule_hud")
if ant then ant:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name           = "FollowModule_hud"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Parent         = pg

local frame = Instance.new("Frame")
frame.Name             = "FollowFrame"
frame.Size             = UDim2.new(0, W, 0, H_HDR)
frame.Position         = UDim2.new(0, 20, 0, 260)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel  = 0
frame.Parent           = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color        = C.border

local topLine = Instance.new("Frame")
topLine.Size             = UDim2.new(1, 0, 0, 2)
topLine.BackgroundColor3 = C.accent
topLine.BorderSizePixel  = 0
topLine.ZIndex           = 5
topLine.Parent           = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

-- Header
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, H_HDR)
header.BackgroundColor3 = C.header
header.BorderSizePixel  = 0
header.Active           = true
header.ZIndex           = 3
header.Parent           = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size               = UDim2.new(1, -80, 1, 0)
titleLbl.Position           = UDim2.new(0, 10, 0, 0)
titleLbl.Text               = "PLAYER ACTIONS"
titleLbl.TextColor3         = C.accent
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 11
titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.ZIndex             = 4
titleLbl.Parent             = header

local minBtn = Instance.new("TextButton")
minBtn.Size             = UDim2.new(0, 20, 0, 20)
minBtn.Position         = UDim2.new(1, -44, 0.5, -10)
minBtn.Text             = "—"
minBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
minBtn.TextColor3       = C.muted
minBtn.Font             = Enum.Font.GothamBold
minBtn.TextSize         = 10
minBtn.BorderSizePixel  = 0
minBtn.ZIndex           = 4
minBtn.Parent           = header
Instance.new("UIStroke", minBtn).Color        = C.border
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 3)

local closeBtn = Instance.new("TextButton")
closeBtn.Size             = UDim2.new(0, 20, 0, 20)
closeBtn.Position         = UDim2.new(1, -20, 0.5, -10)
closeBtn.Text             = "x"
closeBtn.BackgroundColor3 = C.redDim
closeBtn.TextColor3       = C.red
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.TextSize         = 10
closeBtn.BorderSizePixel  = 0
closeBtn.ZIndex           = 4
closeBtn.Parent           = header
Instance.new("UIStroke", closeBtn).Color        = Color3.fromRGB(100, 20, 35)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 3)

-- Status bar
local statusBar = Instance.new("Frame")
statusBar.Size             = UDim2.new(1, 0, 0, H_STATUS)
statusBar.Position         = UDim2.new(0, 0, 0, H_HDR)
statusBar.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
statusBar.BorderSizePixel  = 0
statusBar.ZIndex           = 2
statusBar.Parent           = frame

local statusLine = Instance.new("Frame")
statusLine.Size             = UDim2.new(1, 0, 0, 1)
statusLine.Position         = UDim2.new(0, 0, 1, -1)
statusLine.BackgroundColor3 = C.border
statusLine.BorderSizePixel  = 0
statusLine.ZIndex           = 3
statusLine.Parent           = statusBar

local statusLbl = Instance.new("TextLabel")
statusLbl.Size               = UDim2.new(1, -16, 1, 0)
statusLbl.Position           = UDim2.new(0, 8, 0, 0)
statusLbl.Text               = "// AGUARDANDO SELECAO"
statusLbl.TextColor3         = C.muted
statusLbl.Font               = Enum.Font.Code
statusLbl.TextSize           = 9
statusLbl.BackgroundTransparency = 1
statusLbl.TextXAlignment     = Enum.TextXAlignment.Left
statusLbl.ZIndex             = 3
statusLbl.Parent             = statusBar

-- Botão parar
local stopBtn = Instance.new("TextButton")
stopBtn.Size             = UDim2.new(1, -PAD * 2, 0, 26)
stopBtn.Position         = UDim2.new(0, PAD, 0, H_HDR + H_STATUS + PAD)
stopBtn.Text             = "PARAR DE SEGUIR"
stopBtn.BackgroundColor3 = C.redDim
stopBtn.TextColor3       = C.red
stopBtn.Font             = Enum.Font.GothamBold
stopBtn.TextSize         = 10
stopBtn.BorderSizePixel  = 0
stopBtn.ZIndex           = 3
stopBtn.Visible          = false
stopBtn.Parent           = frame
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", stopBtn).Color        = Color3.fromRGB(100, 20, 35)

-- ============================================
-- JUMP ROW (somente autorizados)
-- Fica logo abaixo do statusBar, antes do scroll
-- ============================================
local jumpRowH = isAuthorized() and (H_JUMP_ROW + PAD) or 0

local jumpSection = Instance.new("Frame")
jumpSection.Name             = "JumpSection"
jumpSection.Size             = UDim2.new(1, -PAD * 2, 0, jumpRowH > 0 and H_JUMP_ROW or 0)
jumpSection.Position         = UDim2.new(0, PAD, 0, H_HDR + H_STATUS + PAD)
jumpSection.BackgroundColor3 = jumpAtivo and Color3.fromRGB(30, 10, 55) or C.rowBg
jumpSection.BorderSizePixel  = 0
jumpSection.Visible          = isAuthorized()
jumpSection.ZIndex           = 3
jumpSection.Parent           = frame
Instance.new("UICorner", jumpSection).CornerRadius = UDim.new(0, 4)
local jumpSectionStroke = Instance.new("UIStroke", jumpSection)
jumpSectionStroke.Color = jumpAtivo and C.purple or C.border

-- barra lateral
local jumpBar = Instance.new("Frame")
jumpBar.Size             = UDim2.new(0, 2, 1, -6)
jumpBar.Position         = UDim2.new(0, 0, 0, 3)
jumpBar.BackgroundColor3 = jumpAtivo and C.purple or C.border
jumpBar.BorderSizePixel  = 0
jumpBar.ZIndex           = 4
jumpBar.Parent           = jumpSection
Instance.new("UICorner", jumpBar).CornerRadius = UDim.new(0, 2)

-- label nome
local jumpNameLbl = Instance.new("TextLabel")
jumpNameLbl.Size               = UDim2.new(1, -90, 0, 16)
jumpNameLbl.Position           = UDim2.new(0, 12, 0, 4)
jumpNameLbl.Text               = "Jump Players"
jumpNameLbl.TextColor3         = jumpAtivo and C.purple or C.text
jumpNameLbl.Font               = Enum.Font.GothamBold
jumpNameLbl.TextSize           = 10
jumpNameLbl.BackgroundTransparency = 1
jumpNameLbl.TextXAlignment     = Enum.TextXAlignment.Left
jumpNameLbl.ZIndex             = 4
jumpNameLbl.Parent             = jumpSection

-- campo ms
local msBox = Instance.new("TextBox")
msBox.Size               = UDim2.new(0, 52, 0, 16)
msBox.Position           = UDim2.new(0, 12, 0, 23)
msBox.Text               = tostring(jumpIntervalMs)
msBox.BackgroundColor3   = Color3.fromRGB(22, 16, 38)
msBox.TextColor3         = C.purple
msBox.PlaceholderColor3  = C.muted
msBox.PlaceholderText    = "ms"
msBox.Font               = Enum.Font.GothamBold
msBox.TextSize           = 9
msBox.BorderSizePixel    = 0
msBox.ClearTextOnFocus   = false
msBox.ZIndex             = 5
msBox.Parent             = jumpSection
Instance.new("UICorner", msBox).CornerRadius = UDim.new(0, 3)
Instance.new("UIStroke", msBox).Color        = C.purpleDim

local msLbl = Instance.new("TextLabel")
msLbl.Size               = UDim2.new(0, 14, 0, 16)
msLbl.Position           = UDim2.new(0, 66, 0, 23)
msLbl.Text               = "ms"
msLbl.TextColor3         = C.muted
msLbl.Font               = Enum.Font.GothamBold
msLbl.TextSize           = 9
msLbl.BackgroundTransparency = 1
msLbl.ZIndex             = 5
msLbl.Parent             = jumpSection

msBox.FocusLost:Connect(function()
    local v = tonumber(msBox.Text)
    jumpIntervalMs = (v and v >= 100) and math.floor(v) or jumpIntervalMs
    msBox.Text = tostring(jumpIntervalMs)
end)

-- toggle track/knob
local jumpTrack = Instance.new("Frame")
jumpTrack.Size             = UDim2.new(0, 34, 0, 16)
jumpTrack.Position         = UDim2.new(1, -44, 0.5, -8)
jumpTrack.BackgroundColor3 = jumpAtivo and C.purpleDim or Color3.fromRGB(25, 28, 40)
jumpTrack.BorderSizePixel  = 0
jumpTrack.ZIndex           = 4
jumpTrack.Parent           = jumpSection
Instance.new("UICorner", jumpTrack).CornerRadius = UDim.new(1, 0)
local jumpTrackStroke = Instance.new("UIStroke", jumpTrack)
jumpTrackStroke.Color = jumpAtivo and C.purple or C.border

local jumpKnob = Instance.new("Frame")
jumpKnob.Size             = UDim2.new(0, 12, 0, 12)
jumpKnob.Position         = jumpAtivo and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
jumpKnob.BackgroundColor3 = jumpAtivo and C.purple or C.muted
jumpKnob.BorderSizePixel  = 0
jumpKnob.ZIndex           = 5
jumpKnob.Parent           = jumpTrack
Instance.new("UICorner", jumpKnob).CornerRadius = UDim.new(1, 0)

local function setJumpVisual(ativo)
    local bg   = ativo and Color3.fromRGB(30, 10, 55) or C.rowBg
    local barC = ativo and C.purple or C.border
    local txtC = ativo and C.purple or C.text
    local trkC = ativo and C.purpleDim or Color3.fromRGB(25, 28, 40)
    local knbP = ativo and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
    TS:Create(jumpSection, TweenInfo.new(0.15), { BackgroundColor3 = bg   }):Play()
    TS:Create(jumpBar,     TweenInfo.new(0.15), { BackgroundColor3 = barC }):Play()
    TS:Create(jumpNameLbl, TweenInfo.new(0.15), { TextColor3 = txtC       }):Play()
    TS:Create(jumpTrack,   TweenInfo.new(0.15), { BackgroundColor3 = trkC }):Play()
    TS:Create(jumpKnob,    TweenInfo.new(0.15), { Position = knbP, BackgroundColor3 = barC }):Play()
    jumpTrackStroke.Color   = barC
    jumpSectionStroke.Color = barC
end
setJumpVisualRef = setJumpVisual

-- botão transparente só sobre o track/knob (evita conflito com msBox)
local jumpBtn = Instance.new("TextButton")
jumpBtn.Size               = UDim2.new(0, 44, 0, 30)
jumpBtn.Position           = UDim2.new(1, -50, 0.5, -15)
jumpBtn.BackgroundTransparency = 1
jumpBtn.Text               = ""
jumpBtn.ZIndex             = 6
jumpBtn.Parent             = jumpSection
jumpBtn.MouseButton1Click:Connect(function()
    jumpAtivo = not jumpAtivo
    setJumpVisual(jumpAtivo)
    if jumpAtivo then iniciarJump() else pararJump(true) end
end)

-- ============================================
-- SCROLL da lista de players
-- ============================================
local SCROLL_Y = H_HDR + H_STATUS + PAD + jumpRowH

local scroll = Instance.new("ScrollingFrame")
scroll.Size                 = UDim2.new(1, -PAD * 2, 0, 0)
scroll.Position             = UDim2.new(0, PAD, 0, SCROLL_Y)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel      = 0
scroll.ScrollBarThickness   = 3
scroll.ScrollBarImageColor3 = C.accent
scroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize  = Enum.AutomaticSize.Y
scroll.ZIndex               = 3
scroll.Parent               = frame

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.Padding   = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- ============================================
-- DRAG + PERSISTÊNCIA DE POSIÇÃO
-- ============================================
local HS = game:GetService("HttpService")
local POS_KEY_FOLLOW = "follow_pos.json"
local minimizado = false
local hFullCache = nil
local _followData = nil
local estadoJanela = "maximizado"

local function setEstadoJanela(v)
    estadoJanela = v
    if _G.KAHWindowState and _G.KAHWindowState.set then _G.KAHWindowState.set(MODULE_NAME, v) end
end

local function salvarPos()
    if writefile then
        pcall(writefile, POS_KEY_FOLLOW, HS:JSONEncode({
            x = frame.Position.X.Offset, y = frame.Position.Y.Offset,
            minimizado = minimizado, hCache = hFullCache, windowState = estadoJanela
        }))
    end
end

local function carregarPos()
    if isfile and readfile and isfile(POS_KEY_FOLLOW) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(POS_KEY_FOLLOW)) end)
        if ok and d then frame.Position = UDim2.new(0, d.x, 0, d.y); _followData = d end
    end
end
carregarPos()

do
    local saved = (_G.KAHWindowState and _G.KAHWindowState.get) and _G.KAHWindowState.get(MODULE_NAME, nil) or nil
    if saved then estadoJanela = saved
    elseif _followData and (_followData.windowState == "maximizado" or _followData.windowState == "minimizado" or _followData.windowState == "fechado") then
        estadoJanela = _followData.windowState
    elseif _followData and _followData.minimizado then estadoJanela = "minimizado" end
end

if _G.Snap then
    _G.Snap.registrar(frame, salvarPos, function(targetW, mode)
        if mode == "minimize" then
            minimizado = true
            hFullCache = hFullCache or frame.Size.Y.Offset
            frame.Size = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
            statusBar.Visible    = false
            scroll.Visible       = false
            stopBtn.Visible      = false
            jumpSection.Visible  = false
            setEstadoJanela("minimizado"); salvarPos()
            return
        end
        minimizado = false
        if tonumber(targetW) then W = math.clamp(math.floor(tonumber(targetW)), 220, 420) end
        statusBar.Visible   = true
        scroll.Visible      = true
        jumpSection.Visible = isAuthorized()
        if targetPlayer then stopBtn.Visible = true end
        frame.Size = UDim2.new(0, W, 0, hFullCache or (SCROLL_Y + 100))
        setEstadoJanela("maximizado"); salvarPos()
    end)
end

local dragging, dragStart, startPos, dragWithTouch
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragWithTouch = (i.UserInputType == Enum.UserInputType.Touch)
        dragStart = i.Position
        startPos  = frame.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if not dragging then return end
    if dragWithTouch and i.UserInputType ~= Enum.UserInputType.Touch then return end
    if (not dragWithTouch) and i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local d  = i.Position - dragStart
    local nx = startPos.X.Offset + d.X
    local ny = startPos.Y.Offset + d.Y
    if _G.Snap then _G.Snap.mover(frame, nx, ny)
    else
        local sw = workspace.CurrentCamera.ViewportSize.X
        local sh = workspace.CurrentCamera.ViewportSize.Y
        frame.Position = UDim2.new(0, math.clamp(nx, 4, sw - frame.Size.X.Offset - 4), 0, math.clamp(ny, 4, sh - frame.Size.Y.Offset - 4))
    end
end)
UIS.InputEnded:Connect(function(i)
    if not dragging then return end
    if dragWithTouch and i.UserInputType ~= Enum.UserInputType.Touch then return end
    if (not dragWithTouch) and i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if _G.Snap then _G.Snap.soltar(frame) else salvarPos() end
    dragging = false; dragWithTouch = false
end)
header.InputEnded:Connect(function(i)
    if not dragging then return end
    if dragWithTouch and i.UserInputType ~= Enum.UserInputType.Touch then return end
    if (not dragWithTouch) and i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if _G.Snap then _G.Snap.soltar(frame) else salvarPos() end
    dragging = false; dragWithTouch = false
end)
header.InputChanged:Connect(function(i)
    if not dragging then return end
    if dragWithTouch and i.UserInputType ~= Enum.UserInputType.Touch then return end
    if (not dragWithTouch) and i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local d  = i.Position - dragStart
    local nx = startPos.X.Offset + d.X
    local ny = startPos.Y.Offset + d.Y
    if _G.Snap then _G.Snap.mover(frame, nx, ny)
    else
        local sw = workspace.CurrentCamera.ViewportSize.X
        local sh = workspace.CurrentCamera.ViewportSize.Y
        frame.Position = UDim2.new(0, math.clamp(nx, 4, sw - frame.Size.X.Offset - 4), 0, math.clamp(ny, 4, sh - frame.Size.Y.Offset - 4))
    end
end)

-- ============================================
-- RENDERIZAR LISTA DE PLAYERS
-- ============================================
local selectedRow = nil

local function atualizarAltura(n)
    local contentH = n * (H_ROW + 4)
    local scrollH  = (n == 0) and 0 or math.min(contentH, H_MAX_SCROLL)
    scroll.Size = UDim2.new(1, -PAD * 2, 0, scrollH)

    local stopExtra = stopBtn.Visible and (26 + PAD) or 0
    local fullH = SCROLL_Y + scrollH + stopExtra + PAD
    hFullCache = fullH
    if minimizado then
        frame.Size = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
        return
    end
    frame.Size = UDim2.new(0, W, 0, fullH)
end

local function setStatus(text, cor)
    statusLbl.Text       = "// " .. text
    statusLbl.TextColor3 = cor or C.muted
end

local function renderPlayers()
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    selectedRow = nil

    local lista = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then table.insert(lista, p) end
    end

    if #lista == 0 then
        setStatus("SEM OUTROS JOGADORES", C.red)
        atualizarAltura(0)
        return
    end

    for i, p in ipairs(lista) do
        local row = Instance.new("Frame")
        row.Name             = "Player_" .. p.Name
        row.Size             = UDim2.new(1, 0, 0, H_ROW)
        row.BackgroundColor3 = C.rowBg
        row.BorderSizePixel  = 0
        row.LayoutOrder      = i
        row.ZIndex           = 4
        row.Parent           = scroll
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
        local rowStroke = Instance.new("UIStroke", row)
        rowStroke.Color = C.border; rowStroke.Thickness = 1

        local leftBar = Instance.new("Frame")
        leftBar.Name             = "LeftBar"
        leftBar.Size             = UDim2.new(0, 2, 1, -8)
        leftBar.Position         = UDim2.new(0, 0, 0, 4)
        leftBar.BackgroundColor3 = C.border
        leftBar.BorderSizePixel  = 0
        leftBar.ZIndex           = 5
        leftBar.Parent           = row
        Instance.new("UICorner", leftBar).CornerRadius = UDim.new(0, 2)

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size               = UDim2.new(1, -100, 0.55, 0)
        nameLbl.Position           = UDim2.new(0, 12, 0, 4)
        nameLbl.Text               = p.DisplayName
        nameLbl.TextColor3         = C.text
        nameLbl.Font               = Enum.Font.GothamBold
        nameLbl.TextSize           = 11
        nameLbl.BackgroundTransparency = 1
        nameLbl.TextXAlignment     = Enum.TextXAlignment.Left
        nameLbl.TextTruncate       = Enum.TextTruncate.AtEnd
        nameLbl.ZIndex             = 5
        nameLbl.Parent             = row

        local userLbl = Instance.new("TextLabel")
        userLbl.Size               = UDim2.new(1, -100, 0.38, 0)
        userLbl.Position           = UDim2.new(0, 12, 0.58, 0)
        userLbl.Text               = "@" .. p.Name
        userLbl.TextColor3         = C.muted
        userLbl.Font               = Enum.Font.Code
        userLbl.TextSize           = 8
        userLbl.BackgroundTransparency = 1
        userLbl.TextXAlignment     = Enum.TextXAlignment.Left
        userLbl.ZIndex             = 5
        userLbl.Parent             = row

        local camBtn = Instance.new("TextButton")
        camBtn.Size             = UDim2.new(0, 20, 0, 20)
        camBtn.Position         = UDim2.new(1, -24, 0.5, -10)
        camBtn.Text             = "C"
        camBtn.BackgroundColor3 = Color3.fromRGB(15, 40, 20)
        camBtn.TextColor3       = C.green
        camBtn.Font             = Enum.Font.GothamBold
        camBtn.TextSize         = 11
        camBtn.BorderSizePixel  = 0
        camBtn.ZIndex           = 7
        camBtn.Parent           = row
        Instance.new("UICorner", camBtn).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", camBtn).Color        = Color3.fromRGB(30, 100, 50)

        camBtn.MouseButton1Click:Connect(function()
            if camTarget == p then
                resetCam()
                camBtn.BackgroundColor3 = Color3.fromRGB(15, 40, 20)
                TS:Create(leftBar, TweenInfo.new(0.15), { BackgroundColor3 = C.border }):Play()
            else
                iniciarCam(p)
                camBtn.BackgroundColor3 = Color3.fromRGB(20, 80, 35)
                TS:Create(leftBar, TweenInfo.new(0.15), { BackgroundColor3 = C.green }):Play()
            end
        end)

        local btnDefs = {
            { icon = "F",  mode = "follow", bg = Color3.fromRGB(15,35,55),   stroke = Color3.fromRGB(20,70,130) },
            { icon = "H",  mode = "head",   bg = Color3.fromRGB(40,25,55),   stroke = Color3.fromRGB(80,40,120) },
            { icon = "I",  mode = "inside", bg = Color3.fromRGB(15,40,40),   stroke = Color3.fromRGB(20,100,100) },
            { icon = "O",  mode = "orbit",  bg = Color3.fromRGB(35,25,10),   stroke = Color3.fromRGB(120,80,20) },
        }

        local modeBtns = {}
        for bi, def in ipairs(btnDefs) do
            local mb = Instance.new("TextButton")
            mb.Size             = UDim2.new(0, 20, 0, 20)
            mb.Position         = UDim2.new(1, -122 + (bi - 1) * 24, 0.5, -10)
            mb.Text             = def.icon
            mb.BackgroundColor3 = def.bg
            mb.TextColor3       = Color3.fromRGB(220, 220, 220)
            mb.Font             = Enum.Font.GothamBold
            mb.TextSize         = 11
            mb.BorderSizePixel  = 0
            mb.ZIndex           = 7
            mb.Parent           = row
            Instance.new("UICorner", mb).CornerRadius = UDim.new(0, 4)
            Instance.new("UIStroke", mb).Color        = def.stroke
            modeBtns[def.mode] = mb
        end

        row.MouseEnter:Connect(function()
            if targetPlayer ~= p then TS:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(22,26,38) }):Play() end
        end)
        row.MouseLeave:Connect(function()
            if targetPlayer ~= p then TS:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = C.rowBg }):Play() end
        end)

        task.spawn(function()
            while row.Parent do
                task.wait(1)
                if camTarget == p and (not p.Character) then
                    resetCam()
                    camBtn.BackgroundColor3 = Color3.fromRGB(15, 40, 20)
                end
            end
        end)

        local modeColors = {
            follow = { row = C.rowActive,                     bar = C.green,                     text = C.green,                     status = "SEGUINDO " },
            head   = { row = Color3.fromRGB(25,15,35),        bar = Color3.fromRGB(180,100,255),  text = Color3.fromRGB(200,150,255),  status = "NA CABECA DE " },
            inside = { row = Color3.fromRGB(10,30,30),        bar = Color3.fromRGB(0,200,180),    text = Color3.fromRGB(0,220,200),    status = "DENTRO DE " },
            orbit  = { row = Color3.fromRGB(30,25,10),        bar = Color3.fromRGB(255,180,30),   text = Color3.fromRGB(255,200,60),   status = "ORBITANDO " },
        }

        local function ativarRow(mode)
            if selectedRow and selectedRow ~= row then
                TS:Create(selectedRow, TweenInfo.new(0.15), { BackgroundColor3 = C.rowBg }):Play()
                local lb = selectedRow:FindFirstChild("LeftBar")
                if lb then TS:Create(lb, TweenInfo.new(0.15), { BackgroundColor3 = C.border }):Play() end
            end
            selectedRow = row
            local mc = modeColors[mode]
            TS:Create(row,     TweenInfo.new(0.15), { BackgroundColor3 = mc.row  }):Play()
            TS:Create(leftBar, TweenInfo.new(0.15), { BackgroundColor3 = mc.bar  }):Play()
            TS:Create(nameLbl, TweenInfo.new(0.15), { TextColor3 = mc.text       }):Play()
            iniciarFollow(p, mode)
            setStatus(mc.status .. p.DisplayName, mc.text)
            stopBtn.Visible  = true
            stopBtn.Position = UDim2.new(0, PAD, 0, H_HDR + H_STATUS + PAD)
            scroll.Position  = UDim2.new(0, PAD, 0, H_HDR + H_STATUS + PAD + 26 + PAD)
            atualizarAltura(#lista)
        end

        for _, def in ipairs(btnDefs) do
            modeBtns[def.mode].MouseButton1Click:Connect(function() ativarRow(def.mode) end)
        end
    end

    atualizarAltura(#lista)
    if not targetPlayer then
        scroll.Position = UDim2.new(0, PAD, 0, SCROLL_Y)
    end
end

-- ============================================
-- PARAR DE SEGUIR
-- ============================================
local function pararUI()
    pararFollow()
    resetCam()
    setStatus("AGUARDANDO SELECAO", C.muted)
    stopBtn.Visible = false
    scroll.Position = UDim2.new(0, PAD, 0, SCROLL_Y)
    if selectedRow then
        TS:Create(selectedRow, TweenInfo.new(0.15), { BackgroundColor3 = C.rowBg }):Play()
        local lb = selectedRow:FindFirstChild("LeftBar")
        if lb then TS:Create(lb, TweenInfo.new(0.15), { BackgroundColor3 = C.border }):Play() end
        selectedRow = nil
    end
    renderPlayers()
end

stopBtn.MouseButton1Click:Connect(pararUI)

-- ============================================
-- ATUALIZA LISTA
-- ============================================
Players.PlayerAdded:Connect(function()
    task.wait(0.5)
    renderPlayers()
end)
Players.PlayerRemoving:Connect(function(p)
    if targetPlayer == p then pararUI() end
    if camTarget == p then resetCam() end
    task.wait(0.2)
    renderPlayers()
end)

-- ============================================
-- MINIMIZAR
-- ============================================
minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    if minimizado then
        hFullCache = frame.Size.Y.Offset
        frame.Size = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
        statusBar.Visible   = false
        stopBtn.Visible     = false
        scroll.Visible      = false
        jumpSection.Visible = false
        minBtn.Text = "A"
    else
        statusBar.Visible   = true
        scroll.Visible      = true
        jumpSection.Visible = isAuthorized()
        if targetPlayer then stopBtn.Visible = true end
        TS:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, W, 0, hFullCache or (SCROLL_Y + 100))
        }):Play()
        minBtn.Text = "-"
    end
    setEstadoJanela(minimizado and "minimizado" or "maximizado")
    salvarPos()
end)

closeBtn.MouseButton1Click:Connect(function()
    if jumpAtivo then pararJump(false) end
    setEstadoJanela("fechado")
    salvarPos()
    pararFollow(); resetCam()
    gui.Enabled = false
    if _G.Hub then pcall(function() _G.Hub.desligar(MODULE_NAME) end) end
end)

-- ============================================
-- REGISTRA NO HUB
-- ============================================
local booting = true
local function onToggle(ativo)
    if not ativo then
        pararFollow(); resetCam()
        if jumpAtivo then pararJump(false) end
    end
    if gui and gui.Parent then gui.Enabled = ativo end
    if not booting then
        if ativo then setEstadoJanela(minimizado and "minimizado" or "maximizado")
        else setEstadoJanela("fechado") end
        salvarPos()
    end
end

local iniciarAtivo = estadoJanela ~= "fechado"
gui.Enabled = iniciarAtivo

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, iniciarAtivo)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = MODULE_NAME, toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = iniciarAtivo })
end

if estadoJanela == "minimizado" or (_followData and _followData.minimizado and estadoJanela ~= "maximizado") then
    hFullCache = _followData and _followData.hCache or frame.Size.Y.Offset
    minimizado = true
    frame.Size          = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
    statusBar.Visible   = false
    stopBtn.Visible     = false
    scroll.Visible      = false
    jumpSection.Visible = false
    minBtn.Text = "A"
end

booting = false
renderPlayers()
print(">>> PLAYER ACTIONS ATIVO")