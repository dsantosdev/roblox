-- ============================================
-- MÃ“DULO: PETS & CHAT
-- Renomear pets de qualquer jogador, histÃ³rico, chat do jogo
-- ============================================

local VERSION   = "1.0.9"
local CATEGORIA = "Player"
local MODULE_NAME = "Pet Chats"

if not _G.Hub and not _G.HubFila then
    return
end

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local TS      = game:GetService("TweenService")
local RS      = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player  = Players.LocalPlayer
local Chat    = game:GetService("Chat")
local TextChatService = game:GetService("TextChatService")
local MODULE_STATE_KEY = "__pets_chat_module_state"
local chatEnvioAtivo = true
local CHAT_DEDUPE_KEY = "__pets_chat_last_sent"

-- ============================================
-- CHAT DO JOGO
-- ============================================
local function falarNoChat(msg)
    if not chatEnvioAtivo then return end
    if not msg or #msg == 0 then return end
    do
        local now = os.clock()
        local last = _G[CHAT_DEDUPE_KEY]
        if last and last.msg == msg and (now - (last.t or 0)) < 0.7 then
            return
        end
        _G[CHAT_DEDUPE_KEY] = { msg = msg, t = now }
    end
    local ok = false
    pcall(function()
        local tcs = TextChatService
        if tcs and tcs.ChatVersion == Enum.ChatVersion.TextChatService then
            local chan = tcs:FindFirstChild("TextChannels")
            local geral = chan and (chan:FindFirstChild("RBXGeneral") or chan:FindFirstChild("General"))
            if geral and geral.SendAsync then
                geral:SendAsync(msg)
                ok = true
            end
        end
    end)
    if not ok then
        pcall(function()
            local r = game:GetService("ReplicatedStorage")
            local d = r:FindFirstChild("DefaultChatSystemChatEvents")
            local say = d and d:FindFirstChild("SayMessageRequest")
            if say then
                say:FireServer(msg, "All")
                ok = true
            end
        end)
    end
    if ok then return end
    pcall(function()
        local head = player.Character and player.Character:FindFirstChild("Head")
        if head then Chat:Chat(head, msg, Enum.ChatColor.White) end
    end)
end
local function falarNomePetNoChat(ownerName, novoNome, isMine)
    if not novoNome or #novoNome == 0 then return end
    if isMine then
        falarNoChat(novoNome)
    else
        falarNoChat("[ "..tostring(ownerName or "?").." ]: "..novoNome)
    end
end

-- ============================================
-- HISTÃ“RICO DE NOMES
-- ============================================
local histNomes   = {}
local petNomeSnap = {}

local function registrarNome(petModel, nome, ownerName)
    if not histNomes[petModel] then histNomes[petModel] = {} end
    local h = histNomes[petModel]
    if h[#h] and h[#h].nome == nome then return end
    table.insert(h, { nome = nome, hora = os.date("%H:%M:%S"), ownerName = ownerName or "?" })
end

-- ============================================
-- NOTIFICAÃ‡Ã•ES POPUP
-- ============================================
local notifQueue = {}
local notifAtiva = false

local function mostrarNotif(texto, cor)
    cor = cor or Color3.fromRGB(180, 100, 255)
    table.insert(notifQueue, { texto = texto, cor = cor })
    if notifAtiva then return end
    notifAtiva = true
    task.spawn(function()
        local pg2 = player:WaitForChild("PlayerGui")
        while #notifQueue > 0 do
            local item = table.remove(notifQueue, 1)
            local ng = Instance.new("ScreenGui")
            ng.Name = "PetNotif_tmp"; ng.IgnoreGuiInset = true
            ng.ResetOnSpawn = false; ng.Parent = pg2

            local box = Instance.new("Frame")
            box.Size = UDim2.new(0, 300, 0, 38)
            box.Position = UDim2.new(0.5, -150, 0, -42)
            box.BackgroundColor3 = Color3.fromRGB(10, 9, 18)
            box.BorderSizePixel = 0; box.ZIndex = 20; box.Parent = ng
            Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
            local stroke = Instance.new("UIStroke", box)
            stroke.Color = item.cor; stroke.Thickness = 1.2

            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, -16, 1, 0); lbl.Position = UDim2.new(0, 8, 0, 0)
            lbl.Text = item.texto; lbl.TextColor3 = item.cor
            lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12
            lbl.BackgroundTransparency = 1
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextTruncate = Enum.TextTruncate.AtEnd
            lbl.ZIndex = 21; lbl.Parent = box

            TS:Create(box, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Position = UDim2.new(0.5, -150, 0, 12) }):Play()
            task.wait(3)
            TS:Create(box, TweenInfo.new(0.18), { Position = UDim2.new(0.5, -150, 0, -42) }):Play()
            task.wait(0.2); ng:Destroy()
        end
        notifAtiva = false
    end)
end

-- ============================================
-- RENAME PET
-- ============================================
local function renomearPet(petModel, novoNome)
    pcall(function() petModel:SetAttribute("PetName", novoNome) end)
    local re = ReplicatedStorage:FindFirstChild("RemoteEvents")
    local writeOnCollar = re and re:FindFirstChild("WriteOnCollar")
    if not writeOnCollar then
        return
    end
    local ok = pcall(function() writeOnCollar:FireServer(petModel, novoNome) end)
    if not ok then
        pcall(function() writeOnCollar:FireServer(novoNome, petModel) end)
    end
end

local function encontrarTodosPets()
    local pets = {}
    local chars = workspace:FindFirstChild("Characters"); if not chars then return pets end
    for _, m in ipairs(chars:GetChildren()) do
        if m:GetAttribute("PetCommand") ~= nil then table.insert(pets, m) end
    end
    return pets
end

-- ============================================
-- CORES E FONTES
-- ============================================
local C = {
    bg        = Color3.fromRGB(10, 11, 15),
    header    = Color3.fromRGB(12, 14, 20),
    border    = Color3.fromRGB(28, 32, 48),
    accent    = Color3.fromRGB(0, 220, 255),
    green     = Color3.fromRGB(50, 220, 100),
    red       = Color3.fromRGB(220, 50, 70),
    redDim    = Color3.fromRGB(55, 12, 18),
    yellow    = Color3.fromRGB(255, 200, 50),
    orange    = Color3.fromRGB(255, 140, 30),
    purple    = Color3.fromRGB(180, 100, 255),
    purpleDim = Color3.fromRGB(35, 15, 55),
    text      = Color3.fromRGB(215, 222, 238),
    muted     = Color3.fromRGB(120, 130, 155),
    rowBg     = Color3.fromRGB(15, 17, 25),
    tabBg     = Color3.fromRGB(10, 12, 18),
    tabActive = Color3.fromRGB(18, 22, 32),
}
local FB = Enum.Font.GothamBold
local FM = Enum.Font.GothamMedium

-- ============================================
-- CONSTANTES DE LAYOUT
-- ============================================
local BASE_W   = 360
local MIN_W    = 220
local MAX_W    = 520
local W        = BASE_W
local MIN_EXTRA_H = 0
local MAX_EXTRA_H = 420
local H_EXTRA  = 0
local H_HDR    = 34
local H_TAB    = 26
local H_ROW    = 40
local H_EDIT   = 68
local H_SCROLL = 260
local PAD      = 6

local function getMinimizedWidth()
    if _G.KAHUiDefaults and _G.KAHUiDefaults.getMinWidth then
        local ok, v = pcall(_G.KAHUiDefaults.getMinWidth)
        if ok and tonumber(v) then
            return math.clamp(math.floor(tonumber(v)), 220, 420)
        end
    end
    return 240
end

-- ============================================
-- GUI BASE
-- ============================================
do
    local oldState = _G[MODULE_STATE_KEY]
    if oldState then
        if oldState.cleanup then pcall(oldState.cleanup) end
        if oldState.gui and oldState.gui.Parent then
            pcall(function() oldState.gui:Destroy() end)
        end
    end
end

local pg = player:WaitForChild("PlayerGui")
do local a = pg:FindFirstChild("Interactions_hud"); if a then a:Destroy() end end

local gui = Instance.new("ScreenGui")
gui.Name = "Interactions_hud"; gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true; gui.Parent = pg

gui.DescendantAdded:Connect(function(d)
    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
        d.TextStrokeTransparency = 1
    end
end)

local HS = game:GetService("HttpService")
local POS_KEY_INT = "interact_pos.json"

local frame = Instance.new("Frame")
frame.Name = "IntFrame"; frame.Size = UDim2.new(0, W, 0, H_HDR)
frame.Position = UDim2.new(0, 20, 0, 20)
frame.BackgroundColor3 = C.bg; frame.BorderSizePixel = 0; frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", frame).Color = C.border

local uiScale = Instance.new("UIScale")
uiScale.Name = "__ChatResizeScale"
uiScale.Scale = math.clamp((W / BASE_W) ^ 0.55, 0.88, 1.4)
uiScale.Parent = frame

local minimizado = false
local hCache     = nil
local estadoJanela = "maximizado"
local function setEstadoJanela(v)
    estadoJanela = v
    if _G.KAHWindowState and _G.KAHWindowState.set then
        _G.KAHWindowState.set(MODULE_NAME, v)
    end
end

local function salvarPosInt()
    if writefile then
        pcall(writefile, POS_KEY_INT, HS:JSONEncode({
            x = frame.Position.X.Offset, y = frame.Position.Y.Offset,
            minimizado = minimizado, hCache = hCache,
            chatEnvioAtivo = chatEnvioAtivo, windowState = estadoJanela,
            w = W, hExtra = H_EXTRA
        }))
    end
end
local _posIntData = nil
local function carregarPosInt()
    if isfile and readfile and isfile(POS_KEY_INT) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(POS_KEY_INT)) end)
        if ok and d then
            frame.Position = UDim2.new(0, d.x, 0, d.y)
            _posIntData = d
        end
    end
end
carregarPosInt()
if _posIntData and type(_posIntData.chatEnvioAtivo) == "boolean" then
    chatEnvioAtivo = _posIntData.chatEnvioAtivo
end
if _posIntData then
    W = math.clamp(tonumber(_posIntData.w) or BASE_W, MIN_W, MAX_W)
    H_EXTRA = math.clamp(tonumber(_posIntData.hExtra) or 0, MIN_EXTRA_H, MAX_EXTRA_H)
    frame.Size = UDim2.new(0, W, 0, H_HDR)
    uiScale.Scale = math.clamp((W / BASE_W) ^ 0.55, 0.88, 1.4)
end

do
    local saved = (_G.KAHWindowState and _G.KAHWindowState.get) and _G.KAHWindowState.get(MODULE_NAME, nil) or nil
    if saved then
        estadoJanela = saved
    elseif _posIntData and (_posIntData.windowState == "maximizado" or _posIntData.windowState == "minimizado" or _posIntData.windowState == "fechado") then
        estadoJanela = _posIntData.windowState
    elseif _posIntData and _posIntData.minimizado then
        estadoJanela = "minimizado"
    end
end

local topLine = Instance.new("Frame")
topLine.Size = UDim2.new(1, 0, 0, 2); topLine.BackgroundColor3 = C.orange
topLine.BorderSizePixel = 0; topLine.ZIndex = 6; topLine.Parent = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, H_HDR); header.BackgroundColor3 = C.header
header.BorderSizePixel = 0; header.ZIndex = 4; header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 6)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -114, 1, 0); titleLbl.Position = UDim2.new(0, 10, 0, 0)
titleLbl.Text = "PET CHATS"; titleLbl.TextColor3 = C.orange
titleLbl.Font = FB; titleLbl.TextSize = 12; titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.ZIndex = 5; titleLbl.Parent = header

-- Badge histÃ³rico
local histBadge = Instance.new("Frame")
histBadge.Size = UDim2.new(0, 8, 0, 8); histBadge.Position = UDim2.new(0, 120, 0.5, -4)
histBadge.BackgroundColor3 = C.purple; histBadge.BorderSizePixel = 0
histBadge.ZIndex = 7; histBadge.Visible = false; histBadge.Parent = header
Instance.new("UICorner", histBadge).CornerRadius = UDim.new(1, 0)

local function mkBtn(parent, x, text, bgcol, tcol)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 22, 0, 22); b.Position = UDim2.new(1, x, 0.5, -11)
    b.Text = text; b.BackgroundColor3 = bgcol; b.TextColor3 = tcol
    b.Font = FB; b.TextSize = 11; b.BorderSizePixel = 0; b.ZIndex = 5; b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    Instance.new("UIStroke", b).Color = C.border
    return b
end
local chatBtn  = mkBtn(header, -74, "C ON", Color3.fromRGB(15,55,25), C.green)
local minBtn   = mkBtn(header, -48, "â€”", Color3.fromRGB(22,25,35), C.muted)
local closeBtn = mkBtn(header, -22, "âœ•", C.redDim, C.red)
closeBtn:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(100,20,35)
chatBtn.TextSize = 9

local resizeHandle = Instance.new("TextButton")
resizeHandle.Name = "ResizeHandle"
resizeHandle.Size = UDim2.new(0, 14, 0, 14)
resizeHandle.Position = UDim2.new(1, -14, 1, -14)
resizeHandle.Text = ""
resizeHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeHandle.BorderSizePixel = 0
resizeHandle.AutoButtonColor = true
resizeHandle.ZIndex = 8
resizeHandle.Parent = frame
Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 2)
local rsStroke = Instance.new("UIStroke", resizeHandle)
rsStroke.Color = C.border
rsStroke.Thickness = 1

local resizeDot = Instance.new("Frame")
resizeDot.Size = UDim2.new(0, 3, 0, 3)
resizeDot.Position = UDim2.new(1, -5, 1, -5)
resizeDot.BackgroundColor3 = C.muted
resizeDot.BorderSizePixel = 0
resizeDot.Parent = resizeHandle
Instance.new("UICorner", resizeDot).CornerRadius = UDim.new(1, 0)

local resizeHHandle = Instance.new("TextButton")
resizeHHandle.Name = "ResizeHeightHandle"
resizeHHandle.Size = UDim2.new(0, 24, 0, 8)
resizeHHandle.Position = UDim2.new(0.5, -12, 1, -8)
resizeHHandle.Text = ""
resizeHHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeHHandle.BorderSizePixel = 0
resizeHHandle.AutoButtonColor = true
resizeHHandle.ZIndex = 8
resizeHHandle.Parent = frame
Instance.new("UICorner", resizeHHandle).CornerRadius = UDim.new(1, 0)
local rsHStroke = Instance.new("UIStroke", resizeHHandle)
rsHStroke.Color = C.border
rsHStroke.Thickness = 1

local resizeLHandle = Instance.new("TextButton")
resizeLHandle.Name = "ResizeLeftHandle"
resizeLHandle.Size = UDim2.new(0, 8, 0, 36)
resizeLHandle.Position = UDim2.new(0, 0, 0.5, -18)
resizeLHandle.Text = ""
resizeLHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeLHandle.BorderSizePixel = 0
resizeLHandle.AutoButtonColor = true
resizeLHandle.ZIndex = 8
resizeLHandle.Parent = frame
Instance.new("UICorner", resizeLHandle).CornerRadius = UDim.new(1, 0)
local rsLStroke = Instance.new("UIStroke", resizeLHandle)
rsLStroke.Color = C.border
rsLStroke.Thickness = 1

local resizeRHandle = Instance.new("TextButton")
resizeRHandle.Name = "ResizeRightHandle"
resizeRHandle.Size = UDim2.new(0, 8, 0, 36)
resizeRHandle.Position = UDim2.new(1, -8, 0.5, -18)
resizeRHandle.Text = ""
resizeRHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeRHandle.BorderSizePixel = 0
resizeRHandle.AutoButtonColor = true
resizeRHandle.ZIndex = 8
resizeRHandle.Parent = frame
Instance.new("UICorner", resizeRHandle).CornerRadius = UDim.new(1, 0)
local rsRStroke = Instance.new("UIStroke", resizeRHandle)
rsRStroke.Color = C.border
rsRStroke.Thickness = 1

local function atualizarChatBtn()
    if chatEnvioAtivo then
        chatBtn.Text = "C ON"
        chatBtn.BackgroundColor3 = Color3.fromRGB(15,55,25)
        chatBtn.TextColor3 = C.green
    else
        chatBtn.Text = "C OFF"
        chatBtn.BackgroundColor3 = Color3.fromRGB(55,18,18)
        chatBtn.TextColor3 = C.red
    end
end
atualizarChatBtn()

-- ============================================
-- ABAS: PETS | HISTÃ“RICO
-- ============================================
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, H_TAB); tabBar.Position = UDim2.new(0, 0, 0, H_HDR)
tabBar.BackgroundColor3 = C.tabBg; tabBar.BorderSizePixel = 0; tabBar.ZIndex = 3; tabBar.Parent = frame

local tabSep = Instance.new("Frame")
tabSep.Size = UDim2.new(1, 0, 0, 1); tabSep.Position = UDim2.new(0, 0, 1, -1)
tabSep.BackgroundColor3 = C.border; tabSep.BorderSizePixel = 0; tabSep.ZIndex = 4; tabSep.Parent = tabBar

local TAB_NAMES = { "PETS", "HISTÃ“RICO" }
local tabBtns   = {}
local abaAtiva  = 1
local conteudos = {}

for idx, nome in ipairs(TAB_NAMES) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, W / #TAB_NAMES, 1, 0)
    btn.Position = UDim2.new(0, (idx-1) * (W / #TAB_NAMES), 0, 0)
    btn.Text = nome; btn.BackgroundColor3 = C.tabBg; btn.TextColor3 = C.muted
    btn.Font = FB; btn.TextSize = 10; btn.BorderSizePixel = 0; btn.ZIndex = 4; btn.Parent = tabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)
    tabBtns[idx] = btn

    local f = Instance.new("Frame")
    f.BackgroundTransparency = 1; f.BorderSizePixel = 0
    f.ZIndex = 3; f.Visible = false; f.Parent = frame
    conteudos[idx] = f
end

local function atualizarTabsLargura()
    local n = #TAB_NAMES
    local bw = math.floor(W / math.max(1, n))
    for i, btn in ipairs(tabBtns) do
        local x = (i - 1) * bw
        local w = (i == n) and (W - x) or bw
        btn.Size = UDim2.new(0, w, 1, 0)
        btn.Position = UDim2.new(0, x, 0, 0)
    end
end
atualizarTabsLargura()

local function setConteudoSize(idx, h)
    conteudos[idx].Size     = UDim2.new(1, 0, 0, h + PAD)
    conteudos[idx].Position = UDim2.new(0, 0, 0, H_HDR + H_TAB)
    if abaAtiva == idx and not minimizado then
        hCache = H_HDR + H_TAB + h + PAD
        frame.Size = UDim2.new(0, W, 0, hCache)
    end
end

local function marcarHistNovo()
    histBadge.Visible = true
    TS:Create(histBadge, TweenInfo.new(0.2), {BackgroundColor3 = C.accent}):Play()
    task.delay(0.4, function() TS:Create(histBadge, TweenInfo.new(0.3), {BackgroundColor3 = C.purple}):Play() end)
    if tabBtns[2] and abaAtiva ~= 2 then tabBtns[2].TextColor3 = C.purple end
end
local function limparHistBadge()
    histBadge.Visible = false
    if tabBtns[2] then tabBtns[2].TextColor3 = (abaAtiva == 2) and C.accent or C.muted end
end

local function ativarAba(idx)
    abaAtiva = idx
    for i, btn in ipairs(tabBtns) do
        btn.BackgroundColor3 = (i==idx) and C.tabActive or C.tabBg
        btn.TextColor3       = (i==idx) and C.accent    or C.muted
        local ind = btn:FindFirstChild("Ind")
        if not ind and i==idx then
            ind = Instance.new("Frame", btn); ind.Name = "Ind"
            ind.Size = UDim2.new(1,0,0,2); ind.Position = UDim2.new(0,0,1,-2)
            ind.BackgroundColor3 = C.accent; ind.BorderSizePixel = 0; ind.ZIndex = 6
        end
        if ind then ind.Visible = (i==idx) end
        conteudos[i].Visible = (i==idx)
    end
    local h = conteudos[idx].Size.Y.Offset
    if not minimizado then frame.Size = UDim2.new(0, W, 0, H_HDR + H_TAB + h) end
    if idx == 2 then limparHistBadge() end
    if idx == 1 and gui and gui.Enabled and not minimizado then task.spawn(renderPets) end
end

for i, btn in ipairs(tabBtns) do
    btn.MouseButton1Click:Connect(function() ativarAba(i) end)
end

-- ============================================
-- ABA 1: PETS
-- ============================================
local scrollPets = Instance.new("ScrollingFrame")
scrollPets.Size = UDim2.new(1,-PAD*2,1,-PAD); scrollPets.Position = UDim2.new(0,PAD,0,PAD)
scrollPets.BackgroundTransparency=1; scrollPets.BorderSizePixel=0
scrollPets.ScrollBarThickness=3; scrollPets.ScrollBarImageColor3=C.purple
scrollPets.AutomaticCanvasSize=Enum.AutomaticSize.Y; scrollPets.CanvasSize=UDim2.new(0,0,0,0)
scrollPets.ZIndex=4; scrollPets.Parent=conteudos[1]
Instance.new("UIListLayout", scrollPets).Padding=UDim.new(0,4)

local function refreshPetsHeight()
    task.wait()
    local h = math.clamp(scrollPets.AbsoluteCanvasSize.Y + H_EXTRA, 36, H_SCROLL + H_EXTRA)
    scrollPets.Size = UDim2.new(1,-PAD*2,0,h)
    setConteudoSize(1, h+PAD)
end

local alguemEditando = false

local function renderPets()
    if alguemEditando then return end
    for _, c in ipairs(scrollPets:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end

    local pets = encontrarTodosPets()
    local myId = tostring(player.UserId)

    if #pets == 0 then
        local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,0,34)
        lbl.BackgroundTransparency=1; lbl.Text="Nenhum pet no servidor"
        lbl.TextColor3=C.muted; lbl.Font=FM; lbl.TextSize=11; lbl.LayoutOrder=1
        lbl.ZIndex=4; lbl.Parent=scrollPets; refreshPetsHeight(); return
    end

    for i, pet in ipairs(pets) do
        local petName  = pet:GetAttribute("PetName") or pet.Name
        local petType  = pet.Name
        local ownerId  = tostring(pet:GetAttribute("OwnerId") or "?")
        local isMine   = (ownerId == myId)
        local ownerName = ownerId
        for _, p in ipairs(Players:GetPlayers()) do
            if tostring(p.UserId)==ownerId then ownerName=p.DisplayName; break end
        end

        registrarNome(pet, petName, ownerName)
        petNomeSnap[pet] = petName

        local row=Instance.new("Frame"); row.Name="Pet_"..i
        row.Size=UDim2.new(1,0,0,H_ROW)
        row.BackgroundColor3=isMine and Color3.fromRGB(18,14,28) or C.rowBg
        row.BorderSizePixel=0; row.LayoutOrder=i; row.ZIndex=4; row.Parent=scrollPets
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,5)
        local rs=Instance.new("UIStroke",row); rs.Color=isMine and Color3.fromRGB(60,30,100) or C.border

        local lb=Instance.new("Frame"); lb.Size=UDim2.new(0,2,1,-8); lb.Position=UDim2.new(0,0,0,4)
        lb.BackgroundColor3=isMine and C.purple or C.border; lb.BorderSizePixel=0; lb.ZIndex=5; lb.Parent=row
        Instance.new("UICorner",lb).CornerRadius=UDim.new(0,2)

        local ta=Instance.new("Frame"); ta.Name="TextArea"
        ta.Size=UDim2.new(1,-42,1,0); ta.Position=UDim2.new(0,10,0,0)
        ta.BackgroundTransparency=1; ta.ZIndex=5; ta.Parent=row

        local nl=Instance.new("TextLabel"); nl.Name="NomeLbl"
        nl.Size=UDim2.new(1,0,0.54,0); nl.Position=UDim2.new(0,0,0,4)
        nl.Text=petName..(isMine and " â­" or "")
        nl.TextColor3=isMine and C.purple or C.text
        nl.Font=FB; nl.TextSize=13; nl.BackgroundTransparency=1
        nl.TextXAlignment=Enum.TextXAlignment.Left; nl.TextTruncate=Enum.TextTruncate.AtEnd
        nl.ZIndex=5; nl.Parent=ta

        local il=Instance.new("TextLabel"); il.Size=UDim2.new(1,0,0.36,0); il.Position=UDim2.new(0,0,0.62,0)
        il.Text=petType.." Â· "..ownerName; il.TextColor3=C.muted; il.Font=FM; il.TextSize=10
        il.BackgroundTransparency=1; il.TextXAlignment=Enum.TextXAlignment.Left; il.ZIndex=5; il.Parent=ta

        local ib=Instance.new("TextBox"); ib.Name="Input"
        ib.Size=UDim2.new(1,-44,0,28); ib.Position=UDim2.new(0,10,0.5,-14)
        ib.Text=""; ib.PlaceholderText="Novo nome..."
        ib.BackgroundColor3=Color3.fromRGB(35,28,52)
        ib.TextColor3=Color3.fromRGB(240,230,255)
        ib.PlaceholderColor3=C.muted; ib.Font=FB; ib.TextSize=13
        ib.BorderSizePixel=0; ib.ZIndex=7; ib.Visible=false
        ib.ClearTextOnFocus=false; ib.TextStrokeTransparency=1; ib.Parent=row
        Instance.new("UICorner",ib).CornerRadius=UDim.new(0,4)
        local ibStroke=Instance.new("UIStroke",ib); ibStroke.Color=C.purple; ibStroke.Thickness=1.5

        local rb=Instance.new("TextButton"); rb.Size=UDim2.new(0,26,0,26)
        rb.Position=UDim2.new(1,-30,0.5,-13); rb.Text="âœŽ"
        rb.BackgroundColor3=isMine and Color3.fromRGB(38,22,58) or Color3.fromRGB(32,28,14)
        rb.TextColor3=isMine and C.purple or C.yellow
        rb.Font=FB; rb.TextSize=14; rb.BorderSizePixel=0; rb.ZIndex=6; rb.Parent=row
        Instance.new("UICorner",rb).CornerRadius=UDim.new(0,4)
        Instance.new("UIStroke",rb).Color=isMine and Color3.fromRGB(80,40,130) or Color3.fromRGB(80,70,18)

        local editando=false
        local function abrirEdit()
            editando=true; alguemEditando=true
            ib.Text=""; ib.Visible=true; ta.Visible=false
            row.Size=UDim2.new(1,0,0,H_EDIT)
            task.wait(0.05); ib:CaptureFocus()
        end
        local function fecharEdit()
            editando=false; alguemEditando=false
            ib.Visible=false; ta.Visible=true
            row.Size=UDim2.new(1,0,0,H_ROW); refreshPetsHeight()
        end

        rb.MouseButton1Click:Connect(function() if editando then fecharEdit() else abrirEdit() end end)
        ib.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                local novo = ib.Text:match("^%s*(.-)%s*$")
                if novo and #novo > 0 then
                    renomearPet(pet, novo)
                    nl.Text = novo..(isMine and " â­" or "")
                    registrarNome(pet, novo, ownerName)
                    if abaAtiva == 2 then task.spawn(renderHist) end
                end
            end
            fecharEdit()
        end)
    end
    refreshPetsHeight()
end

-- ============================================
-- ABA 2: HISTÃ“RICO
-- ============================================
local H_RENBAR    = 36
local H_RENFB     = 20
local H_REN_TOTAL = H_RENBAR + H_RENFB + 4

-- Barra renomear TODOS os pets do servidor
local renBar = Instance.new("Frame")
renBar.Size = UDim2.new(1,-PAD*2,0,H_RENBAR); renBar.Position = UDim2.new(0,PAD,0,PAD)
renBar.BackgroundColor3 = Color3.fromRGB(18,14,28); renBar.BorderSizePixel = 0
renBar.ZIndex = 5; renBar.Parent = conteudos[2]
Instance.new("UICorner", renBar).CornerRadius = UDim.new(0,5)
Instance.new("UIStroke", renBar).Color = Color3.fromRGB(60,30,100)

local renAllBox = Instance.new("TextBox")
renAllBox.Size = UDim2.new(1,-PAD*2,0,24); renAllBox.Position = UDim2.new(0,PAD,0.5,-12)
renAllBox.Text = ""; renAllBox.PlaceholderText = "ðŸ¾ Renomear TODOS os pets do servidor... (Enter)"
renAllBox.BackgroundColor3 = Color3.fromRGB(12,9,20)
renAllBox.TextColor3 = Color3.fromRGB(220,200,255); renAllBox.PlaceholderColor3 = C.muted
renAllBox.Font = FB; renAllBox.TextSize = 11; renAllBox.BorderSizePixel = 0
renAllBox.ZIndex = 6; renAllBox.ClearTextOnFocus = false; renAllBox.TextStrokeTransparency = 1
renAllBox.Parent = renBar
Instance.new("UICorner", renAllBox).CornerRadius = UDim.new(0,4)
local renAllStroke=Instance.new("UIStroke", renAllBox)
renAllStroke.Color=Color3.fromRGB(70,35,110); renAllStroke.Thickness=1.2

local renAllFb = Instance.new("TextLabel")
renAllFb.Size = UDim2.new(1,-PAD*2,0,H_RENFB); renAllFb.Position = UDim2.new(0,PAD,0,H_RENBAR+PAD)
renAllFb.Text = ""; renAllFb.Font = FM; renAllFb.TextSize = 10
renAllFb.BackgroundTransparency = 1; renAllFb.TextXAlignment = Enum.TextXAlignment.Left
renAllFb.TextStrokeTransparency = 1; renAllFb.ZIndex = 5; renAllFb.Visible = false
renAllFb.Parent = conteudos[2]

renAllBox.FocusLost:Connect(function(enterPressed)
    if not enterPressed then return end
    local novo = renAllBox.Text:match("^%s*(.-)%s*$")
    if not novo or #novo == 0 then return end
    renAllBox.Text = ""

    -- TODOS os pets do servidor
    local todosPets = encontrarTodosPets()

    if #todosPets == 0 then
        renAllFb.Text = "âš  Nenhum pet no servidor"; renAllFb.TextColor3 = C.yellow
        renAllFb.Visible = true; task.delay(3, function() renAllFb.Visible = false end); return
    end

    renAllFb.Text = "â³ Enviando para "..#todosPets.." pets..."; renAllFb.TextColor3 = C.accent
    renAllFb.Visible = true

    task.spawn(function()
        local aceitos = 0
        for _, pet in ipairs(todosPets) do
            renomearPet(pet, novo)
            task.wait(0.15)
        end
        task.wait(1.5)
        for _, pet in ipairs(todosPets) do
            local depois = pet:GetAttribute("PetName") or pet.Name
            if depois == novo then aceitos = aceitos + 1 end
        end
        if aceitos == #todosPets then
            renAllFb.Text = "âœ“ Todos aceitos! ("..aceitos.."/"..#todosPets..")"; renAllFb.TextColor3 = C.green
            mostrarNotif("âœ… "..aceitos.." pets renomeados para \""..novo.."\"", C.green)
        elseif aceitos > 0 then
            renAllFb.Text = "âš  Parcial: "..aceitos.."/"..#todosPets; renAllFb.TextColor3 = C.yellow
            mostrarNotif("âš  "..aceitos.."/"..#todosPets.." aceitos", C.yellow)
        else
            renAllFb.Text = "âœ— Filtrado/recusado pelo servidor"; renAllFb.TextColor3 = C.red
            mostrarNotif("âŒ Nome bloqueado pelo filtro", C.red)
        end
        task.delay(4, function() renAllFb.Visible = false end)
    end)
end)

local scrollHist = Instance.new("ScrollingFrame")
scrollHist.Size = UDim2.new(1,-PAD*2,1,-PAD); scrollHist.Position = UDim2.new(0,PAD,0,PAD + H_REN_TOTAL)
scrollHist.BackgroundColor3 = Color3.fromRGB(8,9,14); scrollHist.BorderSizePixel = 0
scrollHist.ScrollBarThickness = 3; scrollHist.ScrollBarImageColor3 = C.muted
scrollHist.AutomaticCanvasSize = Enum.AutomaticSize.Y; scrollHist.CanvasSize = UDim2.new(0,0,0,0)
scrollHist.ZIndex = 4; scrollHist.Parent = conteudos[2]
Instance.new("UICorner", scrollHist).CornerRadius = UDim.new(0,4)
Instance.new("UIStroke", scrollHist).Color = C.border
local histLayout = Instance.new("UIListLayout", scrollHist)
histLayout.Padding = UDim.new(0,1); histLayout.SortOrder = Enum.SortOrder.LayoutOrder
Instance.new("UIPadding", scrollHist).PaddingLeft = UDim.new(0,6)

local histCount = 0

local function refreshHistHeight()
    task.wait()
    local maxH = math.max(36, (H_SCROLL - H_REN_TOTAL) + H_EXTRA)
    local h = math.clamp(scrollHist.AbsoluteCanvasSize.Y + H_EXTRA, 36, maxH)
    scrollHist.Size = UDim2.new(1,-PAD*2,0,h)
    setConteudoSize(2, h + H_REN_TOTAL + PAD)
    scrollHist.CanvasPosition = Vector2.new(0, math.max(0, scrollHist.AbsoluteCanvasSize.Y - h))
end

local function adicionarLinhaHist(hora, petType, nome, ownerName, isMine)
    histCount += 1
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,-8,0,42)
    row.BackgroundTransparency = histCount % 2 == 0 and 0.92 or 1
    row.BackgroundColor3 = Color3.fromRGB(22,18,32)
    row.BorderSizePixel = 0; row.LayoutOrder = histCount; row.ZIndex = 4
    row.ClipsDescendants = false; row.Parent = scrollHist
    Instance.new("UICorner", row).CornerRadius = UDim.new(0,3)

    local horaLbl = Instance.new("TextLabel")
    horaLbl.Size = UDim2.new(0,60,0,18); horaLbl.Position = UDim2.new(0,4,0,3)
    horaLbl.Text = hora; horaLbl.TextColor3 = C.muted
    horaLbl.Font = FM; horaLbl.TextSize = 10; horaLbl.BackgroundTransparency = 1
    horaLbl.TextXAlignment = Enum.TextXAlignment.Left
    horaLbl.TextStrokeTransparency = 1; horaLbl.ZIndex = 5; horaLbl.Parent = row

    local metaLbl = Instance.new("TextLabel")
    metaLbl.Size = UDim2.new(1,-68,0,18); metaLbl.Position = UDim2.new(0,66,0,3)
    metaLbl.Text = petType.." Â· "..ownerName
    metaLbl.TextColor3 = isMine and Color3.fromRGB(180,140,255) or C.muted
    metaLbl.Font = FM; metaLbl.TextSize = 10; metaLbl.BackgroundTransparency = 1
    metaLbl.TextXAlignment = Enum.TextXAlignment.Left
    metaLbl.TextTruncate = Enum.TextTruncate.AtEnd
    metaLbl.TextStrokeTransparency = 1; metaLbl.ZIndex = 5; metaLbl.Parent = row

    local nomeLbl = Instance.new("TextLabel")
    nomeLbl.Size = UDim2.new(1,-10,0,20); nomeLbl.Position = UDim2.new(0,6,0,20)
    nomeLbl.Text = "â†’ "..nome
    nomeLbl.TextColor3 = isMine and C.purple or C.text
    nomeLbl.Font = FB; nomeLbl.TextSize = 12; nomeLbl.BackgroundTransparency = 1
    nomeLbl.TextXAlignment = Enum.TextXAlignment.Left
    nomeLbl.TextWrapped = true; nomeLbl.AutomaticSize = Enum.AutomaticSize.Y
    nomeLbl.TextStrokeTransparency = 1; nomeLbl.ZIndex = 5; nomeLbl.Parent = row

    task.wait()
    local nH = nomeLbl.AbsoluteSize.Y
    row.Size = UDim2.new(1,-8,0,24+nH+4)

    if abaAtiva ~= 2 then marcarHistNovo() end
    refreshHistHeight()
end

function renderHist()
    for _, c in ipairs(scrollHist:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    histCount = 0

    local entradas = {}
    for petModel, lista in pairs(histNomes) do
        local petType = (petModel and petModel.Parent) and petModel.Name or "Pet"
        local ownerId = petModel and petModel:GetAttribute("OwnerId")
        local ownerName = tostring(ownerId or "?")
        for _, p in ipairs(Players:GetPlayers()) do
            if tostring(p.UserId) == ownerName then ownerName = p.DisplayName; break end
        end
        local isMine = tostring(ownerId) == tostring(player.UserId)
        for _, e in ipairs(lista) do
            table.insert(entradas, {
                hora=e.hora, petType=petType, nome=e.nome,
                ownerName=e.ownerName, isMine=isMine
            })
        end
    end

    if #entradas == 0 then
        local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(1,0,0,34)
        lbl.BackgroundTransparency=1; lbl.Text="Nenhuma mudanÃ§a ainda"
        lbl.TextColor3=C.muted; lbl.Font=FM; lbl.TextSize=11; lbl.LayoutOrder=1
        lbl.TextStrokeTransparency=1; lbl.ZIndex=4; lbl.Parent=scrollHist
        refreshHistHeight(); return
    end

    for _, e in ipairs(entradas) do
        adicionarLinhaHist(e.hora, e.petType, e.nome, e.ownerName, e.isMine)
    end
end

-- ============================================
-- MONITOR AUTOMÃTICO DE PetName
-- ============================================
local monitorConns = {}
local monitorAtivo = true
local monitoredPets = {}

local function deveAtualizarUiPets()
    return monitorAtivo and gui and gui.Enabled and (not minimizado) and abaAtiva == 1
end

local function atualizarUiPetsSeVisivel()
    if deveAtualizarUiPets() then
        task.spawn(renderPets)
    end
end
local function limparMonitors()
    for _, c in ipairs(monitorConns) do c:Disconnect() end
    monitorConns = {}
    monitoredPets = {}
end

local function anexarMonitorPet(pet, myId)
    if not pet or monitoredPets[pet] or pet:GetAttribute("PetCommand") == nil then return end
    monitoredPets[pet] = true
    local conn = pet.AttributeChanged:Connect(function(attr)
        if attr == "PetCommand" and pet:GetAttribute("PetCommand") == nil then
            monitoredPets[pet] = nil
            atualizarUiPetsSeVisivel()
            return
        end
        if attr ~= "PetName" then return end
        local novoNome = pet:GetAttribute("PetName") or pet.Name
        if petNomeSnap[pet] == novoNome then return end
        local ownerId   = tostring(pet:GetAttribute("OwnerId") or "?")
        local ownerName = ownerId
        for _, p in ipairs(Players:GetPlayers()) do
            if tostring(p.UserId)==ownerId then ownerName=p.DisplayName; break end
        end
        petNomeSnap[pet] = novoNome
        registrarNome(pet, novoNome, ownerName)
        local isMine = (ownerId == myId)
        mostrarNotif(
            (isMine and "Ã¢Â­Â Seu " or "Ã°Å¸ÂÂ¾ "..ownerName.."'s ")
            ..pet.Name..' Ã¢â€ â€™ "'..novoNome..'"',
            isMine and C.purple or C.yellow
        )
        adicionarLinhaHist(os.date("%H:%M:%S"), pet.Name, novoNome, ownerName, isMine)
        falarNomePetNoChat(ownerName, novoNome, isMine)
        atualizarUiPetsSeVisivel()
    end)
    table.insert(monitorConns, conn)
end
local function iniciarMonitor()
    if not monitorAtivo then return end
    limparMonitors()
    local chars = workspace:FindFirstChild("Characters"); if not chars then return end
    local myId  = tostring(player.UserId)
    for _, pet in ipairs(chars:GetChildren()) do
        anexarMonitorPet(pet, myId)
        if false and pet:GetAttribute("PetCommand") ~= nil then
            local conn = pet.AttributeChanged:Connect(function(attr)
                if attr ~= "PetName" then return end
                local novoNome = pet:GetAttribute("PetName") or pet.Name
                if petNomeSnap[pet] == novoNome then return end
                local ownerId   = tostring(pet:GetAttribute("OwnerId") or "?")
                local ownerName = ownerId
                for _, p in ipairs(Players:GetPlayers()) do
                    if tostring(p.UserId)==ownerId then ownerName=p.DisplayName; break end
                end
                petNomeSnap[pet] = novoNome
                registrarNome(pet, novoNome, ownerName)
                local isMine = (ownerId == myId)
                mostrarNotif(
                    (isMine and "â­ Seu " or "ðŸ¾ "..ownerName.."'s ")
                    ..pet.Name..' â†’ "'..novoNome..'"',
                    isMine and C.purple or C.yellow
                )
                adicionarLinhaHist(os.date("%H:%M:%S"), pet.Name, novoNome, ownerName, isMine)
                falarNomePetNoChat(ownerName, novoNome, isMine)
                if abaAtiva == 1 then task.spawn(renderPets) end
            end)
            table.insert(monitorConns, conn)
        end
    end
    table.insert(monitorConns, chars.ChildAdded:Connect(function(pet)
        anexarMonitorPet(pet, myId)
        task.defer(function()
            anexarMonitorPet(pet, myId)
            atualizarUiPetsSeVisivel()
        end)
    end))
    table.insert(monitorConns, chars.ChildRemoved:Connect(function(pet)
        monitoredPets[pet] = nil
        petNomeSnap[pet] = nil
        atualizarUiPetsSeVisivel()
    end))
end

task.spawn(function()
    while gui.Parent do
        task.wait(10)
        if deveAtualizarUiPets() then
            renderPets()
        end
    end
end)

local function cleanupModulo()
    monitorAtivo = false
    limparMonitors()
    if gui and gui.Parent then gui:Destroy() end
end
_G[MODULE_STATE_KEY] = { gui = gui, cleanup = cleanupModulo }

-- ============================================
-- DRAG
-- ============================================
local function setResizeHandlesVisible(v)
    resizeHandle.Visible = v
    resizeHHandle.Visible = v
    resizeLHandle.Visible = v
    resizeRHandle.Visible = v
end

local function clampFramePos()
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
    local nx = math.clamp(frame.Position.X.Offset, 4, vp.X - frame.Size.X.Offset - 4)
    local ny = math.clamp(frame.Position.Y.Offset, 4, vp.Y - frame.Size.Y.Offset - 4)
    frame.Position = UDim2.new(0, nx, 0, ny)
end

local function applyResize(newW, newExtraH, save)
    W = math.clamp(math.floor((tonumber(newW) or W) + 0.5), MIN_W, MAX_W)
    if tonumber(newExtraH) ~= nil then
        H_EXTRA = math.floor((tonumber(newExtraH) or H_EXTRA) + 0.5)
    end
    H_EXTRA = math.clamp(H_EXTRA, MIN_EXTRA_H, MAX_EXTRA_H)
    uiScale.Scale = math.clamp((W / BASE_W) ^ 0.55, 0.88, 1.4)

    atualizarTabsLargura()

    if minimizado then
        frame.Size = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
    else
        refreshPetsHeight()
        refreshHistHeight()
        local h = conteudos[abaAtiva].Size.Y.Offset
        frame.Size = UDim2.new(0, W, 0, H_HDR + H_TAB + h)
    end

    setResizeHandlesVisible(not minimizado)
    clampFramePos()
    if _G.Snap and _G.Snap.atualizarTamanho then
        pcall(function() _G.Snap.atualizarTamanho(frame) end)
    end
    if save then
        salvarPosInt()
    end
end

local dragInput, startPos, startMouse
local resizing, resizeMode, resizeStartMouse, resizeStartW, resizeStartExtraH, resizeStartRightX, resizeStartFrameH
header.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then return end
    if resizing then return end
    dragInput = i; startPos = frame.Position; startMouse = i.Position
end)
UIS.InputChanged:Connect(function(i)
    if resizing and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local dx = i.Position.X - resizeStartMouse.X
        local dy = i.Position.Y - resizeStartMouse.Y
        if resizeMode == "height" then
            applyResize(W, resizeStartExtraH + dy, false)
        elseif resizeMode == "left" then
            applyResize(resizeStartW - dx, resizeStartExtraH, false)
            if resizeStartFrameH and frame.Size.Y.Offset ~= resizeStartFrameH then
                local delta = resizeStartFrameH - frame.Size.Y.Offset
                applyResize(W, H_EXTRA + delta, false)
            end
            local sw = workspace.CurrentCamera.ViewportSize.X
            local nx = math.clamp(resizeStartRightX - frame.Size.X.Offset, 4, sw - frame.Size.X.Offset - 4)
            frame.Position = UDim2.new(0, nx, 0, frame.Position.Y.Offset)
        elseif resizeMode == "right" then
            applyResize(resizeStartW + dx, resizeStartExtraH, false)
            if resizeStartFrameH and frame.Size.Y.Offset ~= resizeStartFrameH then
                local delta = resizeStartFrameH - frame.Size.Y.Offset
                applyResize(W, H_EXTRA + delta, false)
            end
        else
            applyResize(resizeStartW + dx, resizeStartExtraH + dy, false)
        end
        return
    end
    if dragInput and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - startMouse
        local nx = startPos.X.Offset + d.X
        local ny = startPos.Y.Offset + d.Y
        if _G.Snap then _G.Snap.mover(frame, nx, ny)
        else frame.Position = UDim2.new(0, nx, 0, ny) end
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if resizing then
        resizing = false
        resizeMode = nil
        applyResize(W, H_EXTRA, true)
        return
    end
    if dragInput then
        if dragInput.UserInputType == Enum.UserInputType.Touch
        and i.UserInputType == Enum.UserInputType.Touch
        and i ~= dragInput then
            return
        end
        if _G.Snap then _G.Snap.soltar(frame)
        else salvarPosInt() end
        dragInput = nil
    end
end)

resizeHandle.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then return end
    if minimizado then return end
    resizing = true
    resizeMode = "both"
    dragInput = nil
    resizeStartMouse = i.Position
    resizeStartW = W
    resizeStartExtraH = H_EXTRA
    resizeStartFrameH = frame.Size.Y.Offset
end)

resizeHHandle.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then return end
    if minimizado then return end
    resizing = true
    resizeMode = "height"
    dragInput = nil
    resizeStartMouse = i.Position
    resizeStartW = W
    resizeStartExtraH = H_EXTRA
    resizeStartFrameH = frame.Size.Y.Offset
end)

resizeLHandle.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then return end
    if minimizado then return end
    resizing = true
    resizeMode = "left"
    dragInput = nil
    resizeStartMouse = i.Position
    resizeStartW = W
    resizeStartExtraH = H_EXTRA
    resizeStartRightX = frame.Position.X.Offset + frame.Size.X.Offset
    resizeStartFrameH = frame.Size.Y.Offset
end)

resizeRHandle.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then return end
    if minimizado then return end
    resizing = true
    resizeMode = "right"
    dragInput = nil
    resizeStartMouse = i.Position
    resizeStartW = W
    resizeStartExtraH = H_EXTRA
    resizeStartFrameH = frame.Size.Y.Offset
end)

-- ============================================
-- MINIMIZAR
-- ============================================
chatBtn.MouseButton1Click:Connect(function()
    chatEnvioAtivo = not chatEnvioAtivo
    atualizarChatBtn()
    salvarPosInt()
    mostrarNotif(chatEnvioAtivo and "Chat do jogo: ON" or "Chat do jogo: OFF", chatEnvioAtivo and C.green or C.red)
end)

minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    if minimizado then
        hCache = frame.Size.Y.Offset
        frame.Size = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
        tabBar.Visible = false
        for _, c in ipairs(conteudos) do c.Visible = false end
        minBtn.Text = "â–²"
    else
        tabBar.Visible = true
        conteudos[abaAtiva].Visible = true
        frame.Size = UDim2.new(0, W, 0, hCache or H_HDR + H_TAB + 200)
        refreshPetsHeight()
        refreshHistHeight()
        if abaAtiva == 1 then task.spawn(renderPets) end
        minBtn.Text = "â€”"
    end
    setResizeHandlesVisible(not minimizado)
    setEstadoJanela(minimizado and "minimizado" or "maximizado")
    salvarPosInt()
end)

closeBtn.MouseButton1Click:Connect(function()
    monitorAtivo = false
    setEstadoJanela("fechado")
    salvarPosInt(); limparMonitors()
    gui.Enabled = false
    if _G.Hub then pcall(function() _G.Hub.desligar(MODULE_NAME) end) end
end)

-- ============================================
-- HUB
-- ============================================
local booting = true
local function onToggle(ativo)
    monitorAtivo = ativo
    if ativo then iniciarMonitor() else limparMonitors() end
    if gui and gui.Parent then gui.Enabled = ativo end
    if ativo and gui and gui.Enabled and not minimizado and abaAtiva == 1 then
        task.spawn(renderPets)
    end
    if not booting then
        if ativo then
            setEstadoJanela(minimizado and "minimizado" or "maximizado")
        else
            setEstadoJanela("fechado")
        end
        salvarPosInt()
    end
end

if _G.Snap then
    _G.Snap.registrar(frame, salvarPosInt, function(targetW, mode)
        if mode == "minimize" then
            minimizado = true
            hCache = hCache or frame.Size.Y.Offset
            frame.Size = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
            tabBar.Visible = false
            for _, c in ipairs(conteudos) do c.Visible = false end
            setResizeHandlesVisible(false)
            setEstadoJanela("minimizado")
            salvarPosInt()
            return
        end
        minimizado = false
        if tonumber(targetW) then
            W = math.clamp(math.floor(tonumber(targetW)), MIN_W, MAX_W)
        end
        tabBar.Visible = true
        conteudos[abaAtiva].Visible = true
        applyResize(W, H_EXTRA, true)
        setEstadoJanela("maximizado")
    end)
end
local iniciarAtivo = estadoJanela ~= "fechado"
gui.Enabled = iniciarAtivo
monitorAtivo = iniciarAtivo

if _G.Hub then _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, iniciarAtivo)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {nome=MODULE_NAME, toggleFn=onToggle, categoria=CATEGORIA, jaAtivo=iniciarAtivo})
end

-- ============================================
-- INIT
-- ============================================
ativarAba(1); renderPets(); renderHist()
if iniciarAtivo then iniciarMonitor() else limparMonitors() end

if _posIntData then
    hCache = _posIntData.hCache
    if estadoJanela == "minimizado" or (_posIntData.minimizado and estadoJanela ~= "maximizado") then
        minimizado = true
        frame.Size = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
        tabBar.Visible = false
        for _, c in ipairs(conteudos) do c.Visible = false end
        minBtn.Text = "â–²"
    end
end

setResizeHandlesVisible(not minimizado)
booting = false

