-- ============================================
-- MÓDULO: PETS & CHAT
-- Renomear pets, histórico, chat do jogo
-- ============================================

local VERSION   = "1.0"
local CATEGORIA = "Player"

-- Não executa sem o hub
if not _G.Hub and not _G.HubFila then
    print('>>> pets_chat: hub não encontrado, abortando')
    return
end

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local TS      = game:GetService("TweenService")
local RS      = game:GetService("RunService")
local RE      = game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvents")
local player  = Players.LocalPlayer
local Chat    = game:GetService("Chat")

-- ============================================
-- CHAT DO JOGO
-- ============================================
local function falarNoChat(msg)
    pcall(function()
        local head = player.Character and player.Character:FindFirstChild("Head")
        Chat:Chat(head, msg, Enum.ChatColor.White)
    end)
end

-- ============================================
-- HISTÓRICO DE NOMES
-- { [petModel] = { {nome, hora, ownerName}, ... } }
-- ============================================
local histNomes      = {}
local petNomeSnap    = {}   -- [petModel] = nome atual

local function registrarNome(petModel, nome, ownerName)
    if not histNomes[petModel] then histNomes[petModel] = {} end
    local h = histNomes[petModel]
    if h[#h] and h[#h].nome == nome then return end
    table.insert(h, { nome = nome, hora = os.date("%H:%M:%S"), ownerName = ownerName or "?" })
end

-- ============================================
-- NOTIFICAÇÕES
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
    local ok = pcall(function() RE.WriteOnCollar:FireServer(petModel, novoNome) end)
    if not ok then pcall(function() RE.WriteOnCollar:FireServer(novoNome, petModel) end) end
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
    muted     = Color3.fromRGB(72, 82, 108),
    rowBg     = Color3.fromRGB(15, 17, 25),
    tabBg     = Color3.fromRGB(10, 12, 18),
    tabActive = Color3.fromRGB(18, 22, 32),
}
local FB = Enum.Font.GothamBold
local FM = Enum.Font.GothamMedium
local F  = Enum.Font.Gotham

-- Remove borda branca padrão do Roblox em qualquer texto
local function noStroke(lbl)
    lbl.TextStrokeTransparency = 1
    return lbl
end

local W        = 360
local H_HDR    = 34
local H_TAB    = 26
local H_ROW    = 40
local H_EDIT   = 68
local H_SCROLL = 260
local PAD      = 6

-- ============================================
-- GUI BASE
-- ============================================
local pg  = player:WaitForChild("PlayerGui")
do local a = pg:FindFirstChild("Interactions_hud"); if a then a:Destroy() end end

local gui = Instance.new("ScreenGui")
gui.Name = "Interactions_hud"; gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true; gui.Parent = pg

-- Remove borda branca de TODOS os textos automaticamente
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

local function salvarPosInt()
    if writefile then
        local ok, err = pcall(writefile, POS_KEY_INT, HS:JSONEncode({
            x = frame.Position.X.Offset, y = frame.Position.Y.Offset,
            minimizado = minimizado, hCache = hCache
        }))
        if not ok then warn("salvarPosInt erro: ", err) end
    end
end
local _posIntData = nil
local function carregarPosInt()
    if isfile and readfile and isfile(POS_KEY_INT) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(POS_KEY_INT)) end)
        if ok and d then
            frame.Position = UDim2.new(0, d.x, 0, d.y)
            _posIntData = d  -- guarda para aplicar minimizado depois da GUI estar pronta
        end
    end
end
carregarPosInt()

local topLine = Instance.new("Frame")
topLine.Size = UDim2.new(1, 0, 0, 2); topLine.BackgroundColor3 = C.orange
topLine.BorderSizePixel = 0; topLine.ZIndex = 6; topLine.Parent = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, H_HDR); header.BackgroundColor3 = C.header
header.BorderSizePixel = 0; header.ZIndex = 4; header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 6)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -80, 1, 0); titleLbl.Position = UDim2.new(0, 10, 0, 0)
titleLbl.Text = "⚡ INTERAÇÕES"; titleLbl.TextColor3 = C.orange
titleLbl.Font = FB; titleLbl.TextSize = 12; titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.ZIndex = 5; titleLbl.Parent = header
noStroke(titleLbl)

-- Badge de novas mensagens no histórico
local histBadge = Instance.new("Frame")
histBadge.Size = UDim2.new(0, 8, 0, 8); histBadge.Position = UDim2.new(0, 115, 0.5, -4)
histBadge.BackgroundColor3 = C.purple; histBadge.BorderSizePixel = 0
histBadge.ZIndex = 7; histBadge.Visible = false; histBadge.Parent = header
Instance.new("UICorner", histBadge).CornerRadius = UDim.new(1, 0)
local histBadgeCount = 0
local function marcarHistNovo()
    histBadgeCount = histBadgeCount + 1
    histBadge.Visible = true
    -- Pisca o badge e o botao da aba
    TS:Create(histBadge, TweenInfo.new(0.2), {BackgroundColor3 = C.accent}):Play()
    task.delay(0.4, function() TS:Create(histBadge, TweenInfo.new(0.3), {BackgroundColor3 = C.purple}):Play() end)
    -- Muda cor do botão da aba 3 para roxo se não estiver ativa
    if tabBtns and tabBtns[3] and abaAtiva ~= 3 then
        tabBtns[3].TextColor3 = C.purple
    end
end
local function limparHistBadge()
    histBadgeCount = 0
    histBadge.Visible = false
    -- Restaura cor do botão da aba 3
    if tabBtns and tabBtns[3] then
        tabBtns[3].TextColor3 = (abaAtiva == 3) and C.accent or C.muted
    end
end

local function mkBtn(parent, x, text, bgcol, tcol)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 22, 0, 22); b.Position = UDim2.new(1, x, 0.5, -11)
    b.Text = text; b.BackgroundColor3 = bgcol; b.TextColor3 = tcol
    b.Font = FB; b.TextSize = 11; b.BorderSizePixel = 0; b.ZIndex = 5; b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    Instance.new("UIStroke", b).Color = C.border
    return b
end
local minBtn   = mkBtn(header, -48, "—",  Color3.fromRGB(22,25,35), C.muted)
local closeBtn = mkBtn(header, -22, "✕",  C.redDim, C.red)
closeBtn:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(100,20,35)

-- ABAS
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, H_TAB); tabBar.Position = UDim2.new(0, 0, 0, H_HDR)
tabBar.BackgroundColor3 = C.tabBg; tabBar.BorderSizePixel = 0; tabBar.ZIndex = 3; tabBar.Parent = frame
local tabSepLine = Instance.new("Frame")
tabSepLine.Size = UDim2.new(1, 0, 0, 1); tabSepLine.Position = UDim2.new(0, 0, 1, -1)
tabSepLine.BackgroundColor3 = C.border; tabSepLine.BorderSizePixel = 0
tabSepLine.ZIndex = 4; tabSepLine.Parent = tabBar

local TAB_NAMES = { "PLAYERS", "PETS", "HISTÓRICO" }
local tabBtns   = {}
local abaAtiva  = 1
local conteudos = {}

for idx, nome in ipairs(TAB_NAMES) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, W/#TAB_NAMES, 1, 0)
    btn.Position = UDim2.new(0, (idx-1)*(W/#TAB_NAMES), 0, 0)
    btn.Text = nome; btn.BackgroundColor3 = C.tabBg; btn.TextColor3 = C.muted
    btn.Font = FB; btn.TextSize = 10; btn.BorderSizePixel = 0
    btn.ZIndex = 4; btn.Parent = tabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)
    tabBtns[idx] = btn

    local f = Instance.new("Frame")
    f.BackgroundTransparency = 1; f.BorderSizePixel = 0
    f.ZIndex = 3; f.Visible = false; f.Parent = frame
    conteudos[idx] = f
end

local W_MIN      = 240   -- largura minimizado
local minimizado = false
local hCache     = nil

local function setConteudoSize(idx, h)
    conteudos[idx].Size     = UDim2.new(1, 0, 0, h + PAD)
    conteudos[idx].Position = UDim2.new(0, 0, 0, H_HDR + H_TAB)
    if abaAtiva == idx and not minimizado then
        hCache = H_HDR + H_TAB + h + PAD
        frame.Size = UDim2.new(0, W, 0, hCache)
    end
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
    if not minimizado then
        frame.Size = UDim2.new(0, W, 0, H_HDR + H_TAB + h)
    end
end

for i, btn in ipairs(tabBtns) do btn.MouseButton1Click:Connect(function()
    ativarAba(i)
    if i == 3 then limparHistBadge() end
end) end

-- ============================================
-- ABA 1: PLAYERS
-- ============================================
local scrollPl = Instance.new("ScrollingFrame")
scrollPl.Size = UDim2.new(1, -PAD*2, 1, -PAD); scrollPl.Position = UDim2.new(0, PAD, 0, PAD)
scrollPl.BackgroundTransparency = 1; scrollPl.BorderSizePixel = 0
scrollPl.ScrollBarThickness = 3; scrollPl.ScrollBarImageColor3 = C.accent
scrollPl.AutomaticCanvasSize = Enum.AutomaticSize.Y; scrollPl.CanvasSize = UDim2.new(0,0,0,0)
scrollPl.ZIndex = 4; scrollPl.Parent = conteudos[1]
Instance.new("UIListLayout", scrollPl).Padding = UDim.new(0, 4)

local camRow = nil

local function refreshPlHeight()
    task.wait()
    local h = math.clamp(scrollPl.AbsoluteCanvasSize.Y, 36, H_SCROLL)
    scrollPl.Size = UDim2.new(1, -PAD*2, 0, h)
    setConteudoSize(1, h + PAD)
end

local function renderPlayers()
    for _, c in ipairs(scrollPl:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    local lista = {}
    for _, p in ipairs(Players:GetPlayers()) do if p~=player then table.insert(lista, p) end end

    if #lista == 0 then
        local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(1,0,0,34)
        lbl.BackgroundTransparency=1; lbl.Text="Nenhum jogador no servidor"
        lbl.TextColor3=C.muted; lbl.Font=FM; lbl.TextSize=11; lbl.LayoutOrder=1
        lbl.ZIndex=4; lbl.Parent=scrollPl; refreshPlHeight(); return
    end

    for i, p in ipairs(lista) do
        local row = Instance.new("Frame")
        row.Name="P_"..p.Name; row.Size=UDim2.new(1,0,0,H_ROW)
        row.BackgroundColor3=C.rowBg; row.BorderSizePixel=0
        row.LayoutOrder=i; row.ZIndex=4; row.Parent=scrollPl
        Instance.new("UICorner", row).CornerRadius=UDim.new(0,5)
        Instance.new("UIStroke", row).Color=C.border

        local lb=Instance.new("Frame"); lb.Name="LB"
        lb.Size=UDim2.new(0,2,1,-8); lb.Position=UDim2.new(0,0,0,4)
        lb.BackgroundColor3=C.border; lb.BorderSizePixel=0; lb.ZIndex=5; lb.Parent=row
        Instance.new("UICorner", lb).CornerRadius=UDim.new(0,2)

        local nl=Instance.new("TextLabel"); nl.Size=UDim2.new(1,-86,0.54,0)
        nl.Position=UDim2.new(0,10,0,4); nl.Text=p.DisplayName; nl.TextColor3=C.text
        nl.Font=FB; nl.TextSize=13; nl.BackgroundTransparency=1
        nl.TextXAlignment=Enum.TextXAlignment.Left; nl.TextTruncate=Enum.TextTruncate.AtEnd
        nl.ZIndex=5; nl.Parent=row

        local ul=Instance.new("TextLabel"); ul.Size=UDim2.new(1,-86,0.36,0)
        ul.Position=UDim2.new(0,10,0.6,0); ul.Text="@"..p.Name; ul.TextColor3=C.muted
        ul.Font=FM; ul.TextSize=10; ul.BackgroundTransparency=1
        ul.TextXAlignment=Enum.TextXAlignment.Left; ul.ZIndex=5; ul.Parent=row

        -- Botão câmera (único)
        local camBtn=Instance.new("TextButton")
        camBtn.Size=UDim2.new(0,24,0,24); camBtn.Position=UDim2.new(1,-28,0.5,-12)
        camBtn.Text="📷"; camBtn.BackgroundColor3=Color3.fromRGB(15,40,20); camBtn.TextColor3=C.green
        camBtn.Font=FB; camBtn.TextSize=13; camBtn.BorderSizePixel=0; camBtn.ZIndex=6; camBtn.Parent=row
        Instance.new("UICorner",camBtn).CornerRadius=UDim.new(0,4)
        Instance.new("UIStroke",camBtn).Color=Color3.fromRGB(30,100,50)

        camBtn.MouseButton1Click:Connect(function()
            if camTarget==p then
                resetCam(); camRow=nil
                TS:Create(row,TweenInfo.new(0.15),{BackgroundColor3=C.rowBg}):Play()
                TS:Create(lb,TweenInfo.new(0.15),{BackgroundColor3=C.border}):Play()
                camBtn.BackgroundColor3=Color3.fromRGB(15,40,20)
            else
                if camRow then
                    TS:Create(camRow,TweenInfo.new(0.15),{BackgroundColor3=C.rowBg}):Play()
                    local clb=camRow:FindFirstChild("LB"); if clb then TS:Create(clb,TweenInfo.new(0.15),{BackgroundColor3=C.border}):Play() end
                end
                camRow=row; iniciarCam(p)
                TS:Create(row,TweenInfo.new(0.15),{BackgroundColor3=Color3.fromRGB(12,35,18)}):Play()
                TS:Create(lb,TweenInfo.new(0.15),{BackgroundColor3=C.green}):Play()
                camBtn.BackgroundColor3=Color3.fromRGB(20,80,35)
            end
        end)
    end
    refreshPlHeight()
end

-- ============================================
-- ABA 2: PETS
-- ============================================
local scrollPets = Instance.new("ScrollingFrame")
scrollPets.Size = UDim2.new(1,-PAD*2,1,-PAD); scrollPets.Position = UDim2.new(0,PAD,0,PAD)
scrollPets.BackgroundTransparency=1; scrollPets.BorderSizePixel=0
scrollPets.ScrollBarThickness=3; scrollPets.ScrollBarImageColor3=C.purple
scrollPets.AutomaticCanvasSize=Enum.AutomaticSize.Y; scrollPets.CanvasSize=UDim2.new(0,0,0,0)
scrollPets.ZIndex=4; scrollPets.Parent=conteudos[2]
Instance.new("UIListLayout", scrollPets).Padding=UDim.new(0,4)

local function refreshPetsHeight()
    task.wait()
    local h = math.clamp(scrollPets.AbsoluteCanvasSize.Y, 36, H_SCROLL)
    scrollPets.Size = UDim2.new(1,-PAD*2,0,h)
    setConteudoSize(2, h+PAD)
end

local alguemEditando = false  -- bloqueia refresh enquanto input estiver aberto

local function renderPets()
    if alguemEditando then return end  -- não interrompe quem está digitando
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
        local petName = pet:GetAttribute("PetName") or pet.Name
        local petType = pet.Name
        local ownerId = tostring(pet:GetAttribute("OwnerId") or "?")
        local isMine  = (ownerId == myId)

        local ownerName = ownerId
        for _, p in ipairs(Players:GetPlayers()) do
            if tostring(p.UserId)==ownerId then ownerName=p.DisplayName; break end
        end

        registrarNome(pet, petName, ownerName)
        petNomeSnap[pet] = petName

        local row=Instance.new("Frame"); row.Name="Pet_"..i
        row.Size=UDim2.new(1,0,0,H_ROW); row.BackgroundColor3=isMine and Color3.fromRGB(18,14,28) or C.rowBg
        row.BorderSizePixel=0; row.LayoutOrder=i; row.ZIndex=4; row.Parent=scrollPets
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,5)
        local rs=Instance.new("UIStroke",row); rs.Color=isMine and Color3.fromRGB(60,30,100) or C.border

        local lb=Instance.new("Frame"); lb.Size=UDim2.new(0,2,1,-8); lb.Position=UDim2.new(0,0,0,4)
        lb.BackgroundColor3=isMine and C.purple or C.border; lb.BorderSizePixel=0; lb.ZIndex=5; lb.Parent=row
        Instance.new("UICorner",lb).CornerRadius=UDim.new(0,2)

        -- Área de texto
        local ta=Instance.new("Frame"); ta.Name="TextArea"
        ta.Size=UDim2.new(1,-42,1,0); ta.Position=UDim2.new(0,10,0,0)
        ta.BackgroundTransparency=1; ta.ZIndex=5; ta.Parent=row

        local nl=Instance.new("TextLabel"); nl.Name="NomeLbl"
        nl.Size=UDim2.new(1,0,0.54,0); nl.Position=UDim2.new(0,0,0,4)
        nl.Text=petName..(isMine and " ⭐" or "")
        nl.TextColor3=isMine and C.purple or C.text
        nl.Font=FB; nl.TextSize=13; nl.BackgroundTransparency=1
        nl.TextXAlignment=Enum.TextXAlignment.Left; nl.TextTruncate=Enum.TextTruncate.AtEnd
        nl.ZIndex=5; nl.Parent=ta

        local il=Instance.new("TextLabel"); il.Size=UDim2.new(1,0,0.36,0); il.Position=UDim2.new(0,0,0.62,0)
        il.Text=petType.." · "..ownerName; il.TextColor3=C.muted; il.Font=FM; il.TextSize=10
        il.BackgroundTransparency=1; il.TextXAlignment=Enum.TextXAlignment.Left; il.ZIndex=5; il.Parent=ta

        -- Input rename
        local ib=Instance.new("TextBox"); ib.Name="Input"
        ib.Size=UDim2.new(1,-44,0,28); ib.Position=UDim2.new(0,10,0.5,-14)
        ib.Text=""; ib.PlaceholderText="Novo nome..."
        ib.BackgroundColor3=Color3.fromRGB(35, 28, 52)
        ib.TextColor3=Color3.fromRGB(240, 230, 255)
        ib.PlaceholderColor3=C.muted; ib.Font=FB; ib.TextSize=13
        ib.BorderSizePixel=0; ib.ZIndex=7; ib.Visible=false
        ib.ClearTextOnFocus=false; ib.TextStrokeTransparency=1; ib.Parent=row
        Instance.new("UICorner",ib).CornerRadius=UDim.new(0,4)
        local ibStroke = Instance.new("UIStroke",ib)
        ibStroke.Color=C.purple; ibStroke.Thickness=1.5

        -- Botão renomear
        local rb=Instance.new("TextButton"); rb.Size=UDim2.new(0,26,0,26)
        rb.Position=UDim2.new(1,-30,0.5,-13); rb.Text="✎"
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
                -- Só renomeia se pressionou Enter
                local novo = ib.Text:match("^%s*(.-)%s*$")
                if novo and #novo > 0 then
                    renomearPet(pet, novo)
                    nl.Text = novo .. (isMine and " ⭐" or "")
                    registrarNome(pet, novo, ownerName)
                    if abaAtiva == 3 then task.spawn(renderHist) end
                end
                fecharEdit()
            else
                -- Perdeu foco sem Enter — fecha sem salvar
                fecharEdit()
            end
        end)
    end
    refreshPetsHeight()
end

-- ============================================
-- ABA 3: HISTÓRICO (estilo chat)
-- ============================================

-- Barra de renomear TODOS os pets (fixa no topo da aba)
local H_RENBAR = 36
local renBar = Instance.new("Frame")
renBar.Size = UDim2.new(1,-PAD*2,0,H_RENBAR); renBar.Position = UDim2.new(0,PAD,0,PAD)
renBar.BackgroundColor3 = Color3.fromRGB(18,14,28); renBar.BorderSizePixel = 0
renBar.ZIndex = 5; renBar.Parent = conteudos[3]
Instance.new("UICorner", renBar).CornerRadius = UDim.new(0,5)
Instance.new("UIStroke", renBar).Color = Color3.fromRGB(60,30,100)

local renAllBox = Instance.new("TextBox")
renAllBox.Size = UDim2.new(1,-PAD*2,0,24); renAllBox.Position = UDim2.new(0,PAD,0.5,-12)
renAllBox.Text = ""; renAllBox.PlaceholderText = "🐾 Renomear TODOS os meus pets... (Enter)"
renAllBox.BackgroundColor3 = Color3.fromRGB(12,9,20)
renAllBox.TextColor3 = Color3.fromRGB(220,200,255); renAllBox.PlaceholderColor3 = C.muted
renAllBox.Font = FB; renAllBox.TextSize = 11; renAllBox.BorderSizePixel = 0
renAllBox.ZIndex = 6; renAllBox.ClearTextOnFocus = false; renAllBox.TextStrokeTransparency = 1
renAllBox.Parent = renBar
Instance.new("UICorner", renAllBox).CornerRadius = UDim.new(0,4)
local renAllStroke = Instance.new("UIStroke", renAllBox)
renAllStroke.Color = Color3.fromRGB(70,35,110); renAllStroke.Thickness = 1.2

-- Label de feedback global
local renAllFb = Instance.new("TextLabel")
renAllFb.Size = UDim2.new(1,-PAD*2,0,16); renAllFb.Position = UDim2.new(0,PAD,0,H_RENBAR+2)
renAllFb.Text = ""; renAllFb.Font = FM; renAllFb.TextSize = 10
renAllFb.BackgroundTransparency = 1; renAllFb.TextXAlignment = Enum.TextXAlignment.Left
renAllFb.TextStrokeTransparency = 1; renAllFb.ZIndex = 5; renAllFb.Visible = false
renAllFb.Parent = conteudos[3]

renAllBox.FocusLost:Connect(function(enterPressed)
    if not enterPressed then return end
    local novo = renAllBox.Text:match("^%s*(.-)%s*$")
    if not novo or #novo == 0 then return end
    renAllBox.Text = ""

    -- Pega todos os meus pets
    local meuId = tostring(player.UserId)
    local chars = workspace:FindFirstChild("Characters")
    if not chars then
        renAllFb.Text = "⚠ Nenhum pet encontrado"; renAllFb.TextColor3 = C.yellow
        renAllFb.Visible = true; task.delay(3, function() renAllFb.Visible = false end); return
    end

    local meusPets = {}
    for _, m in ipairs(chars:GetChildren()) do
        if m:GetAttribute("PetCommand") ~= nil and tostring(m:GetAttribute("OwnerId")) == meuId then
            table.insert(meusPets, m)
        end
    end

    if #meusPets == 0 then
        renAllFb.Text = "⚠ Você não tem pets"; renAllFb.TextColor3 = C.yellow
        renAllFb.Visible = true; task.delay(3, function() renAllFb.Visible = false end); return
    end

    -- Renomeia todos e valida cada um
    renAllFb.Text = "⏳ Enviando para " .. #meusPets .. " pets..."; renAllFb.TextColor3 = C.accent
    renAllFb.Visible = true

    task.spawn(function()
        local aceitos = 0
        for _, pet in ipairs(meusPets) do
            local antes = pet:GetAttribute("PetName") or pet.Name
            renomearPet(pet, novo)
            task.wait(0.15)  -- pequeno delay entre requests
        end
        -- Aguarda confirmação do servidor
        task.wait(1.5)
        for _, pet in ipairs(meusPets) do
            local depois = pet:GetAttribute("PetName") or pet.Name
            if depois == novo then aceitos = aceitos + 1 end
        end
        if aceitos == #meusPets then
            renAllFb.Text = "✓ Todos aceitos! (" .. aceitos .. "/" .. #meusPets .. ")"
            renAllFb.TextColor3 = C.green
            mostrarNotif("✅ " .. aceitos .. " pets renomeados para \"" .. novo .. "\"", C.green)
        elseif aceitos > 0 then
            renAllFb.Text = "⚠ Parcial: " .. aceitos .. "/" .. #meusPets .. " aceitos"
            renAllFb.TextColor3 = C.yellow
            mostrarNotif("⚠ " .. aceitos .. "/" .. #meusPets .. " aceitos", C.yellow)
        else
            renAllFb.Text = "✗ Filtrado/recusado pelo servidor"
            renAllFb.TextColor3 = C.red
            mostrarNotif("❌ Nome bloqueado pelo filtro", C.red)
        end
        task.delay(4, function() renAllFb.Visible = false end)
    end)
end)

local H_REN_TOTAL = H_RENBAR + 20  -- altura reservada para a barra + feedback

local scrollHist = Instance.new("ScrollingFrame")
scrollHist.Size = UDim2.new(1,-PAD*2,1,-PAD); scrollHist.Position = UDim2.new(0,PAD,0,PAD + H_REN_TOTAL)
scrollHist.BackgroundColor3 = Color3.fromRGB(8,9,14)
scrollHist.BorderSizePixel = 0
scrollHist.ScrollBarThickness = 3; scrollHist.ScrollBarImageColor3 = C.muted
scrollHist.AutomaticCanvasSize = Enum.AutomaticSize.Y; scrollHist.CanvasSize = UDim2.new(0,0,0,0)
scrollHist.ZIndex = 4; scrollHist.Parent = conteudos[3]
Instance.new("UICorner", scrollHist).CornerRadius = UDim.new(0,4)
Instance.new("UIStroke", scrollHist).Color = C.border
local histLayout = Instance.new("UIListLayout", scrollHist)
histLayout.Padding = UDim.new(0,1); histLayout.SortOrder = Enum.SortOrder.LayoutOrder
Instance.new("UIPadding", scrollHist).PaddingLeft = UDim.new(0,6)

local histCount = 0

local function refreshHistHeight()
    task.wait()
    local maxH = H_SCROLL - H_REN_TOTAL  -- desconta a barra de renomear
    local h = math.clamp(scrollHist.AbsoluteCanvasSize.Y, 36, maxH)
    scrollHist.Size = UDim2.new(1,-PAD*2,0,h)
    setConteudoSize(3, h + H_REN_TOTAL + PAD)
    -- Auto-scroll para o fim
    scrollHist.CanvasPosition = Vector2.new(0, math.max(0, scrollHist.AbsoluteCanvasSize.Y - h))
end

-- Adiciona UMA linha ao chat (não recria tudo)
local function adicionarLinhaHist(hora, petType, nome, ownerName, isMine)
    histCount += 1

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 42)
    row.BackgroundTransparency = histCount % 2 == 0 and 0.92 or 1
    row.BackgroundColor3 = Color3.fromRGB(22, 18, 32)
    row.BorderSizePixel = 0; row.LayoutOrder = histCount; row.ZIndex = 4
    row.ClipsDescendants = false; row.Parent = scrollHist
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)

    -- Linha 1: [HH:MM:SS]  Tipo · Dono
    local horaLbl = Instance.new("TextLabel")
    horaLbl.Size = UDim2.new(0, 60, 0, 18); horaLbl.Position = UDim2.new(0, 4, 0, 3)
    horaLbl.Text = hora; horaLbl.TextColor3 = C.muted
    horaLbl.Font = FM; horaLbl.TextSize = 10; horaLbl.BackgroundTransparency = 1
    horaLbl.TextXAlignment = Enum.TextXAlignment.Left
    horaLbl.TextStrokeTransparency = 1; horaLbl.ZIndex = 5; horaLbl.Parent = row

    local metaLbl = Instance.new("TextLabel")
    metaLbl.Size = UDim2.new(1, -68, 0, 18); metaLbl.Position = UDim2.new(0, 66, 0, 3)
    metaLbl.Text = petType .. " · " .. ownerName
    metaLbl.TextColor3 = isMine and Color3.fromRGB(180,140,255) or C.muted
    metaLbl.Font = FM; metaLbl.TextSize = 10; metaLbl.BackgroundTransparency = 1
    metaLbl.TextXAlignment = Enum.TextXAlignment.Left
    metaLbl.TextTruncate = Enum.TextTruncate.AtEnd
    metaLbl.TextStrokeTransparency = 1; metaLbl.ZIndex = 5; metaLbl.Parent = row

    -- Linha 2: → NomeNovo
    local nomeLbl = Instance.new("TextLabel")
    nomeLbl.Size = UDim2.new(1, -10, 0, 20); nomeLbl.Position = UDim2.new(0, 6, 0, 20)
    nomeLbl.Text = "→ " .. nome
    nomeLbl.TextColor3 = isMine and C.purple or C.text
    nomeLbl.Font = FB; nomeLbl.TextSize = 12; nomeLbl.BackgroundTransparency = 1
    nomeLbl.TextXAlignment = Enum.TextXAlignment.Left
    nomeLbl.TextWrapped = true
    nomeLbl.AutomaticSize = Enum.AutomaticSize.Y
    nomeLbl.TextStrokeTransparency = 1; nomeLbl.ZIndex = 5; nomeLbl.Parent = row

    -- Ajusta altura do row após AutomaticSize calcular
    task.wait()
    local nH = nomeLbl.AbsoluteSize.Y
    row.Size = UDim2.new(1, -8, 0, 24 + nH + 4)

    -- Badge na aba se não estiver visualizando
    if abaAtiva ~= 3 then marcarHistNovo() end
    refreshHistHeight()
end

function renderHist()
    -- Só mostra placeholder se vazio
    for _, c in ipairs(scrollHist:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    histCount = 0

    -- Reconstrói do histórico acumulado em ordem cronológica
    local entradas = {}
    for petModel, lista in pairs(histNomes) do
        local petType = (petModel and petModel.Parent) and petModel.Name or "Pet"
        local ownerId = petModel and petModel:GetAttribute("OwnerId")
        local ownerName = tostring(ownerId or "?")
        for _, p in ipairs(Players:GetPlayers()) do
            if tostring(p.UserId) == ownerName then ownerName = p.DisplayName; break end
        end
        local myId = tostring(player.UserId)
        local isMine = tostring(ownerId) == myId
        for _, e in ipairs(lista) do
            table.insert(entradas, {
                hora=e.hora, petType=petType, nome=e.nome,
                ownerName=e.ownerName, isMine=isMine
            })
        end
    end

    if #entradas == 0 then
        local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(1,0,0,34)
        lbl.BackgroundTransparency=1; lbl.Text="Nenhuma mudança ainda"
        lbl.TextColor3=C.muted; lbl.Font=FM; lbl.TextSize=11; lbl.LayoutOrder=1
        lbl.TextStrokeTransparency=1; lbl.ZIndex=4; lbl.Parent=scrollHist
        refreshHistHeight(); return
    end

    for _, e in ipairs(entradas) do
        adicionarLinhaHist(e.hora, e.petType, e.nome, e.ownerName, e.isMine)
    end
end

-- ============================================
-- MONITOR automático de PetName
-- ============================================
local monitorConns={}
local function limparMonitors()
    for _, c in ipairs(monitorConns) do c:Disconnect() end; monitorConns={}
end
local function iniciarMonitor()
    limparMonitors()
    local chars=workspace:FindFirstChild("Characters"); if not chars then return end
    local myId=tostring(player.UserId)
    for _, pet in ipairs(chars:GetChildren()) do
        if pet:GetAttribute("PetCommand")~=nil then
            local conn=pet.AttributeChanged:Connect(function(attr)
                if attr~="PetName" then return end
                local novoNome=pet:GetAttribute("PetName") or pet.Name
                if petNomeSnap[pet]==novoNome then return end
                local ownerId=tostring(pet:GetAttribute("OwnerId") or "?")
                local ownerName=ownerId
                for _, p in ipairs(Players:GetPlayers()) do
                    if tostring(p.UserId)==ownerId then ownerName=p.DisplayName; break end
                end
                petNomeSnap[pet]=novoNome
                registrarNome(pet, novoNome, ownerName)
                local isMine=(ownerId==myId)
                mostrarNotif(
                    (isMine and "⭐ Seu " or "🐾 "..ownerName.."'s ")
                    ..pet.Name..' → "'..novoNome..'"',
                    isMine and C.purple or C.yellow
                )
                -- Adiciona linha no chat de histórico diretamente
                adicionarLinhaHist(os.date("%H:%M:%S"), pet.Name, novoNome, ownerName, isMine)
                if abaAtiva==2 then task.spawn(renderPets) end
            end)
            table.insert(monitorConns, conn)
        end
    end
end

-- Atualização a cada 10s
task.spawn(function()
    while gui.Parent do
        task.wait(10)
        renderPets()
        iniciarMonitor()
    end
end)

-- ============================================
-- ============================================
-- DRAG (mover)
-- ============================================
if _G.Snap then _G.Snap.registrar(frame, salvarPosInt) end

local dragInput, startPos, startMouse
header.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    dragInput = i; startPos = frame.Position; startMouse = i.Position
end)
UIS.InputChanged:Connect(function(i)
    if dragInput and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - startMouse
        local nx = startPos.X.Offset + d.X
        local ny = startPos.Y.Offset + d.Y
        if _G.Snap then _G.Snap.mover(frame, nx, ny)
        else frame.Position = UDim2.new(0, nx, 0, ny) end
    end
end)
UIS.InputEnded:Connect(function(i)
    if i == dragInput then
        dragInput = nil
        if _G.Snap then _G.Snap.soltar(frame)
        else salvarPosInt() end
    end
end)

-- ============================================
-- MINIMIZAR
-- ============================================
minBtn.MouseButton1Click:Connect(function()
    minimizado=not minimizado
    salvarPosInt()
    if minimizado then
        -- Salva altura atual antes de colapsar
        hCache = frame.Size.Y.Offset
        -- Minimiza para W_MIN x H_HDR
        frame.Size = UDim2.new(0, W_MIN, 0, H_HDR)
        tabBar.Visible=false; for _,c in ipairs(conteudos) do c.Visible=false end
        minBtn.Text="▲"
    else
        -- Expande de volta para W=360
        tabBar.Visible=true; conteudos[abaAtiva].Visible=true
        frame.Size = UDim2.new(0, W, 0, hCache or H_HDR + H_TAB + 200)
        minBtn.Text="—"
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    salvarPosInt()
    limparMonitors()
    gui.Enabled = false
    if _G.Hub then pcall(function() _G.Hub.desligar("Pets & Chat") end) end
end)

-- ============================================
-- HUB
-- ============================================
local function onToggle(ativo)
    if not ativo then limparMonitors() end
    if gui and gui.Parent then gui.Enabled = ativo end
end
if _G.Hub then _G.Hub.registrar("Pets & Chat", onToggle, CATEGORIA, true)
else
    _G.HubFila=_G.HubFila or {}
    table.insert(_G.HubFila, {nome="Pets & Chat", toggleFn=onToggle, categoria=CATEGORIA, jaAtivo=true})
end

-- ============================================
-- INIT
-- ============================================
ativarAba(1); renderPets(); renderHist(); iniciarMonitor()

-- Restaura estado minimizado salvo
if _posIntData then
    hCache = _posIntData.hCache
    if _posIntData.minimizado then
        minimizado = true
        frame.Size = UDim2.new(0, W_MIN, 0, H_HDR)
        tabBar.Visible = false
        for _, c in ipairs(conteudos) do c.Visible = false end
        minBtn.Text = "▲"
    end
end

print(">>> PETS & CHAT ATIVO")
