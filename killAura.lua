-- ============================================
-- MODULO: MOB KILLER
-- Mata mobs automaticamente com qualquer arma
-- Interface com selecao de arma + auto-best
-- ============================================

local VERSION = "1.1"
local CATEGORIA = "Combat"
local MODULE_NAME = "Mob Killer"

if not _G.Hub and not _G.HubFila then
    print('>>> mob_killer: hub nao encontrado, abortando')
    return
end

local Players  = game:GetService("Players")
local RS       = game:GetService("RunService")
local UIS      = game:GetService("UserInputService")
local TS       = game:GetService("TweenService")
local HS       = game:GetService("HttpService")
local RE       = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents") or game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvents", 10)
local player   = Players.LocalPlayer

-- ============================================
-- CONFIG PERSISTENTE
-- ============================================
local CFG_KEY = "mobkiller_cfg.json"
local cfg = {
    ativo       = false,
    killDist    = 70,
    autoBest    = true,
    weaponName  = nil,
    interval    = 0.2,
}

local function salvarCfg()
    if writefile then
        local ok, e = pcall(writefile, CFG_KEY, HS:JSONEncode(cfg))
        if not ok then warn("mobkiller salvarCfg:", e) end
    end
end

local function carregarCfg()
    if isfile and readfile and isfile(CFG_KEY) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(CFG_KEY)) end)
        if ok and d then
            for k in pairs(cfg) do
                if d[k] ~= nil then cfg[k] = d[k] end
            end
        end
    end
end

carregarCfg()

-- ============================================
-- ARMAS
-- ============================================
local WEAPON_DAMAGE_ATTR = "WeaponDamage"
local WEAPON_PROJ_ATTR   = "ProjectileDamage"

local function getDano(item)
    if not item then return 0 end
    return item:GetAttribute(WEAPON_DAMAGE_ATTR)
        or item:GetAttribute(WEAPON_PROJ_ATTR)
        or 0
end

local function getInventario()
    local inv = player:FindFirstChild("Inventory")
    if not inv then return {} end
    local lista = {}
    for _, item in ipairs(inv:GetChildren()) do
        if getDano(item) > 0 then
            table.insert(lista, item)
        end
    end
    table.sort(lista, function(a, b)
        return getDano(a) > getDano(b)
    end)
    return lista
end

local function getMelhorArma()
    return getInventario()[1]
end

local function getArmaSelecionada()
    if cfg.autoBest then return getMelhorArma() end
    if cfg.weaponName then
        local inv = player:FindFirstChild("Inventory")
        return inv and inv:FindFirstChild(cfg.weaponName)
    end
    return getMelhorArma()
end

-- ============================================
-- LOOP DE KILL
-- ============================================
local killThread = nil
local totalKills = 0

local function getMobHum(mob)
    return mob:FindFirstChildWhichIsA("Humanoid")
end

-- Pega a ferramenta equipada no character no momento
local function getArmaEquipada()
    local char = player.Character
    if not char then return nil end
    -- Tool equipada fica direto no character (não no Backpack)
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA("Tool") then return v end
    end
    return nil
end

local function iniciarKill()
    if killThread then task.cancel(killThread); killThread = nil end
    killThread = task.spawn(function()
        while cfg.ativo do
            local char       = player.Character
            local hrp        = char and char:FindFirstChild("HumanoidRootPart")
            local characters = workspace:FindFirstChild("Characters")
            -- Usa SEMPRE a arma que está equipada no character agora
            local weapon     = getArmaEquipada()

            if hrp and characters and weapon then
                -- Coleta todos os mobs vivos no raio
                local alvos = {}
                for _, mob in ipairs(characters:GetChildren()) do
                    if mob:IsA("Model") and mob ~= char and mob.PrimaryPart then
                        local hum = getMobHum(mob)
                        if hum and hum.Health > 0 then
                            local dist = (mob.PrimaryPart.Position - hrp.Position).Magnitude
                            if dist <= cfg.killDist then
                                table.insert(alvos, mob)
                            end
                        end
                    end
                end

                -- Ataca cada alvo até morrer
                for _, mob in ipairs(alvos) do
                    if not cfg.ativo then break end
                    local hum = getMobHum(mob)
                    while cfg.ativo and hum and hum.Health > 0 do
                        -- Reatualiza arma equipada a cada hit
                        char   = player.Character
                        hrp    = char and char:FindFirstChild("HumanoidRootPart")
                        weapon = getArmaEquipada()
                        if not hrp or not weapon then break end
                        pcall(function()
                            RE.ToolDamageObject:InvokeServer(mob, weapon, 999, hrp.CFrame)
                        end)
                        task.wait(cfg.interval)
                    end
                    if hum and hum.Health <= 0 then
                        totalKills = totalKills + 1
                    end
                end
            end

            task.wait(cfg.interval)
        end
    end)
end

local function pararKill()
    cfg.ativo = false
    if killThread then task.cancel(killThread); killThread = nil end
end

-- ============================================
-- CORES
-- ============================================
local C = {
    bg       = Color3.fromRGB(10, 11, 15),
    header   = Color3.fromRGB(12, 14, 20),
    border   = Color3.fromRGB(28, 32, 48),
    green    = Color3.fromRGB(50, 220, 100),
    greenDim = Color3.fromRGB(15, 55, 25),
    red      = Color3.fromRGB(220, 50, 70),
    redDim   = Color3.fromRGB(55, 12, 18),
    yellow   = Color3.fromRGB(255, 200, 50),
    accent   = Color3.fromRGB(0, 200, 255),
    text     = Color3.fromRGB(210, 218, 235),
    muted    = Color3.fromRGB(72, 82, 108),
    rowBg    = Color3.fromRGB(15, 17, 25),
    rowSel   = Color3.fromRGB(15, 40, 20),
}
local FB = Enum.Font.GothamBold
local FM = Enum.Font.GothamMedium

local W     = 240
local H_HDR = 34
local PAD   = 6

-- ============================================
-- GUI
-- ============================================
local pg = player:WaitForChild("PlayerGui")
do local a = pg:FindFirstChild("MobKiller_hud"); if a then a:Destroy() end end

local gui = Instance.new("ScreenGui")
gui.Name = "MobKiller_hud"; gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true; gui.Parent = pg

local frame = Instance.new("Frame")
frame.Name = "MKFrame"
frame.Size = UDim2.new(0, W, 0, H_HDR)
frame.Position = UDim2.new(0, 20, 0, 540)
frame.BackgroundColor3 = C.bg; frame.BorderSizePixel = 0; frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", frame).Color = C.border

local topLine = Instance.new("Frame")
topLine.Size = UDim2.new(1, 0, 0, 2); topLine.BackgroundColor3 = C.red
topLine.BorderSizePixel = 0; topLine.ZIndex = 6; topLine.Parent = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, H_HDR); header.BackgroundColor3 = C.header
header.BorderSizePixel = 0; header.ZIndex = 4; header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 6)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -80, 1, 0); titleLbl.Position = UDim2.new(0, 10, 0, 0)
titleLbl.Text = "[X] MOB KILLER"; titleLbl.TextColor3 = C.red
titleLbl.Font = FB; titleLbl.TextSize = 12; titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.ZIndex = 5; titleLbl.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 22, 0, 22); minBtn.Position = UDim2.new(1, -48, 0.5, -11)
minBtn.Text = "^"; minBtn.BackgroundColor3 = Color3.fromRGB(22, 25, 35)
minBtn.TextColor3 = C.muted; minBtn.Font = FB; minBtn.TextSize = 11
minBtn.BorderSizePixel = 0; minBtn.ZIndex = 5; minBtn.Parent = header
Instance.new("UIStroke", minBtn).Color = C.border
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22); closeBtn.Position = UDim2.new(1, -22, 0.5, -11)
closeBtn.Text = "X"; closeBtn.BackgroundColor3 = C.redDim; closeBtn.TextColor3 = C.red
closeBtn.Font = FB; closeBtn.TextSize = 11; closeBtn.BorderSizePixel = 0
closeBtn.ZIndex = 5; closeBtn.Parent = header
Instance.new("UIStroke", closeBtn).Color = Color3.fromRGB(100, 20, 35)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

-- CONTEUDO
local content = Instance.new("Frame")
content.Name = "Content"
content.BackgroundTransparency = 1; content.ZIndex = 3; content.Parent = frame

-- Status
local statusBg = Instance.new("Frame")
statusBg.Size = UDim2.new(1, -PAD*2, 0, 20)
statusBg.Position = UDim2.new(0, PAD, 0, PAD)
statusBg.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
statusBg.BorderSizePixel = 0; statusBg.ZIndex = 4; statusBg.Parent = content
Instance.new("UICorner", statusBg).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", statusBg).Color = C.border

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -10, 1, 0); statusLbl.Position = UDim2.new(0, 6, 0, 0)
statusLbl.Text = "// DESATIVADO"; statusLbl.TextColor3 = C.muted
statusLbl.Font = FM; statusLbl.TextSize = 10; statusLbl.BackgroundTransparency = 1
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.ZIndex = 5; statusLbl.Parent = statusBg

-- Info arma + kills
local infoBg = Instance.new("Frame")
infoBg.Size = UDim2.new(1, -PAD*2, 0, 28)
infoBg.Position = UDim2.new(0, PAD, 0, PAD + 22)
infoBg.BackgroundColor3 = C.rowBg; infoBg.BorderSizePixel = 0
infoBg.ZIndex = 4; infoBg.Parent = content
Instance.new("UICorner", infoBg).CornerRadius = UDim.new(0, 5)
Instance.new("UIStroke", infoBg).Color = C.border

local weaponLbl = Instance.new("TextLabel")
weaponLbl.Size = UDim2.new(0.6, 0, 1, 0); weaponLbl.Position = UDim2.new(0, 8, 0, 0)
weaponLbl.Text = "Arma: --"; weaponLbl.TextColor3 = C.muted
weaponLbl.Font = FM; weaponLbl.TextSize = 10; weaponLbl.BackgroundTransparency = 1
weaponLbl.TextXAlignment = Enum.TextXAlignment.Left
weaponLbl.ZIndex = 5; weaponLbl.Parent = infoBg

local killsLbl = Instance.new("TextLabel")
killsLbl.Size = UDim2.new(0.4, -8, 1, 0); killsLbl.Position = UDim2.new(0.6, 0, 0, 0)
killsLbl.Text = "Kills: 0"; killsLbl.TextColor3 = C.muted
killsLbl.Font = FM; killsLbl.TextSize = 10; killsLbl.BackgroundTransparency = 1
killsLbl.TextXAlignment = Enum.TextXAlignment.Right
killsLbl.ZIndex = 5; killsLbl.Parent = infoBg

-- Auto-best row
local bestBg = Instance.new("Frame")
bestBg.Size = UDim2.new(1, -PAD*2, 0, 30)
bestBg.Position = UDim2.new(0, PAD, 0, PAD + 22 + 30)
bestBg.BackgroundColor3 = C.rowBg; bestBg.BorderSizePixel = 0
bestBg.ZIndex = 4; bestBg.Parent = content
Instance.new("UICorner", bestBg).CornerRadius = UDim.new(0, 5)
Instance.new("UIStroke", bestBg).Color = C.border

local bestLbl = Instance.new("TextLabel")
bestLbl.Size = UDim2.new(1, -60, 1, 0); bestLbl.Position = UDim2.new(0, 8, 0, 0)
bestLbl.Text = "Usar melhor arma auto"; bestLbl.TextColor3 = C.text
bestLbl.Font = FM; bestLbl.TextSize = 10; bestLbl.BackgroundTransparency = 1
bestLbl.TextXAlignment = Enum.TextXAlignment.Left
bestLbl.ZIndex = 5; bestLbl.Parent = bestBg

local bestPill = Instance.new("Frame")
bestPill.Size = UDim2.new(0, 40, 0, 18); bestPill.Position = UDim2.new(1, -48, 0.5, -9)
bestPill.BorderSizePixel = 0; bestPill.ZIndex = 5; bestPill.Parent = bestBg
Instance.new("UICorner", bestPill).CornerRadius = UDim.new(0, 9)

local bestDot = Instance.new("Frame")
bestDot.Size = UDim2.new(0, 12, 0, 12); bestDot.BorderSizePixel = 0
bestDot.ZIndex = 6; bestDot.Parent = bestPill
Instance.new("UICorner", bestDot).CornerRadius = UDim.new(0, 6)

local bestTxt = Instance.new("TextLabel")
bestTxt.Size = UDim2.new(1, 0, 1, 0); bestTxt.Font = FB; bestTxt.TextSize = 8
bestTxt.BackgroundTransparency = 1; bestTxt.ZIndex = 7; bestTxt.Parent = bestPill

local bestBtn = Instance.new("TextButton")
bestBtn.Size = UDim2.new(1, 0, 1, 0); bestBtn.BackgroundTransparency = 1
bestBtn.Text = ""; bestBtn.ZIndex = 8; bestBtn.Parent = bestBg

local function atualizarBestPill(animado)
    local on     = cfg.autoBest
    local dotPos = on and UDim2.new(1, -15, 0.5, -6) or UDim2.new(0, 3, 0.5, -6)
    local bgCol  = on and C.greenDim or C.redDim
    local dotCol = on and C.green    or C.red
    local stroke = on and Color3.fromRGB(20, 100, 35) or Color3.fromRGB(100, 20, 35)
    if animado then
        TS:Create(bestPill, TweenInfo.new(0.15), { BackgroundColor3 = bgCol }):Play()
        TS:Create(bestDot,  TweenInfo.new(0.15), { BackgroundColor3 = dotCol, Position = dotPos }):Play()
    else
        bestPill.BackgroundColor3 = bgCol
        bestDot.BackgroundColor3  = dotCol
        bestDot.Position          = dotPos
    end
    bestTxt.Text           = on and "ON " or "OFF"
    bestTxt.TextColor3     = on and C.green or C.red
    bestTxt.TextXAlignment = on and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
    local s = bestPill:FindFirstChildOfClass("UIStroke")
    if not s then s = Instance.new("UIStroke", bestPill) end
    s.Color = stroke
end
atualizarBestPill(false)

-- Separador
local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, -PAD*2, 0, 1)
sep.Position = UDim2.new(0, PAD, 0, PAD + 22 + 30 + 32)
sep.BackgroundColor3 = C.border; sep.BorderSizePixel = 0
sep.ZIndex = 4; sep.Parent = content

local listLabel = Instance.new("TextLabel")
listLabel.Size = UDim2.new(1, -PAD*2, 0, 16)
listLabel.Position = UDim2.new(0, PAD, 0, PAD + 22 + 30 + 34)
listLabel.Text = "SELECIONAR ARMA:"; listLabel.TextColor3 = C.muted
listLabel.Font = FM; listLabel.TextSize = 9; listLabel.BackgroundTransparency = 1
listLabel.TextXAlignment = Enum.TextXAlignment.Left
listLabel.ZIndex = 4; listLabel.Parent = content

-- ScrollingFrame das armas
local SCROLL_Y    = PAD + 22 + 30 + 34 + 18
local MAX_SCROLL_H = 180
local H_ITEM      = 30

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -PAD*2, 0, 0)
scroll.Position = UDim2.new(0, PAD, 0, SCROLL_Y)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = C.accent
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ZIndex = 3; scroll.Parent = content

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.Padding = UDim.new(0, 3)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- Botao ativar (posicionado depois do layout)
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -PAD*2, 0, 30)
toggleBtn.BackgroundColor3 = C.redDim; toggleBtn.TextColor3 = C.red
toggleBtn.Text = "[>] ATIVAR KILL"; toggleBtn.Font = FB; toggleBtn.TextSize = 11
toggleBtn.BorderSizePixel = 0; toggleBtn.ZIndex = 4; toggleBtn.Parent = content
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 5)
Instance.new("UIStroke", toggleBtn).Color = Color3.fromRGB(100, 20, 35)

-- ============================================
-- LAYOUT DINAMICO
-- ============================================
local minimizado = false
local hCache = nil
local estadoJanela = "minimizado"
local function setEstadoJanela(v)
    estadoJanela = v
    if _G.KAHWindowState and _G.KAHWindowState.set then
        _G.KAHWindowState.set(MODULE_NAME, v)
    end
end

local function atualizarLayout()
    local scrollH = scroll.Size.Y.Offset
    local btnY    = SCROLL_Y + scrollH + PAD
    toggleBtn.Position = UDim2.new(0, PAD, 0, btnY)
    local totalH = H_HDR + btnY + 30 + PAD
    content.Size     = UDim2.new(1, 0, 0, totalH - H_HDR)
    content.Position = UDim2.new(0, 0, 0, H_HDR)
    if not minimizado then
        frame.Size = UDim2.new(0, W, 0, totalH)
        hCache = totalH
    end
end

-- ============================================
-- RENDER LISTA DE ARMAS
-- ============================================
local function renderWeaponList()
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
    end

    local lista = getInventario()

    if #lista == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 28); empty.BackgroundTransparency = 1
        empty.Text = "Nenhuma arma no inventario"; empty.TextColor3 = C.muted
        empty.Font = FM; empty.TextSize = 10; empty.ZIndex = 4; empty.Parent = scroll
        scroll.Size = UDim2.new(1, -PAD*2, 0, 28)
        atualizarLayout()
        return
    end

    local melhor = lista[1]

    for i, item in ipairs(lista) do
        local dano        = getDano(item)
        local isMelhor    = (item == melhor)
        local isSelecionado = (not cfg.autoBest) and (cfg.weaponName == item.Name)

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, H_ITEM)
        row.BackgroundColor3 = isSelecionado and C.rowSel or C.rowBg
        row.BorderSizePixel = 0; row.LayoutOrder = i; row.ZIndex = 4; row.Parent = scroll
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
        local rowStroke = Instance.new("UIStroke", row)
        rowStroke.Color = isSelecionado and C.green or C.border

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(0, 2, 1, -8); bar.Position = UDim2.new(0, 0, 0, 4)
        bar.BackgroundColor3 = isSelecionado and C.green or (isMelhor and C.yellow or C.border)
        bar.BorderSizePixel = 0; bar.ZIndex = 5; bar.Parent = row
        Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(1, -80, 1, 0); nameLbl.Position = UDim2.new(0, 10, 0, 0)
        nameLbl.Text = item.Name .. (isMelhor and " *" or "")
        nameLbl.TextColor3 = isSelecionado and C.green or (isMelhor and C.yellow or C.text)
        nameLbl.Font = isSelecionado and FB or FM; nameLbl.TextSize = 10
        nameLbl.BackgroundTransparency = 1
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.ZIndex = 5; nameLbl.Parent = row

        local danoLbl = Instance.new("TextLabel")
        danoLbl.Size = UDim2.new(0, 60, 1, 0); danoLbl.Position = UDim2.new(1, -64, 0, 0)
        danoLbl.Text = "DMG: " .. dano
        danoLbl.TextColor3 = isSelecionado and C.green or C.muted
        danoLbl.Font = FM; danoLbl.TextSize = 9; danoLbl.BackgroundTransparency = 1
        danoLbl.TextXAlignment = Enum.TextXAlignment.Right
        danoLbl.ZIndex = 5; danoLbl.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1
        btn.Text = ""; btn.ZIndex = 6; btn.Parent = row

        row.MouseEnter:Connect(function()
            if not isSelecionado then
                TS:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(20, 23, 33) }):Play()
            end
        end)
        row.MouseLeave:Connect(function()
            if not isSelecionado then
                TS:Create(row, TweenInfo.new(0.1), { BackgroundColor3 = C.rowBg }):Play()
            end
        end)

        btn.MouseButton1Click:Connect(function()
            cfg.autoBest   = false
            cfg.weaponName = item.Name
            atualizarBestPill(true)
            salvarCfg()
            renderWeaponList()
        end)
    end

    local totalH = #lista * (H_ITEM + 3)
    scroll.Size = UDim2.new(1, -PAD*2, 0, math.min(totalH, MAX_SCROLL_H))
    atualizarLayout()
end

bestBtn.MouseButton1Click:Connect(function()
    cfg.autoBest = not cfg.autoBest
    atualizarBestPill(true)
    salvarCfg()
    renderWeaponList()
end)

-- ============================================
-- TOGGLE ATIVO
-- ============================================
local function setAtivo(v)
    cfg.ativo = v
    salvarCfg()
    if v then
        titleLbl.TextColor3        = C.green
        statusLbl.Text             = "// ATIVO"
        statusLbl.TextColor3       = C.green
        toggleBtn.Text             = "[-] DESATIVAR"
        toggleBtn.BackgroundColor3 = C.greenDim
        toggleBtn.TextColor3       = C.green
        local s = toggleBtn:FindFirstChildOfClass("UIStroke")
        if s then s.Color = Color3.fromRGB(20, 100, 35) end
        iniciarKill()
    else
        titleLbl.TextColor3        = C.red
        statusLbl.Text             = "// DESATIVADO"
        statusLbl.TextColor3       = C.muted
        toggleBtn.Text             = "[>] ATIVAR KILL"
        toggleBtn.BackgroundColor3 = C.redDim
        toggleBtn.TextColor3       = C.red
        local s = toggleBtn:FindFirstChildOfClass("UIStroke")
        if s then s.Color = Color3.fromRGB(100, 20, 35) end
        pararKill()
    end
end

toggleBtn.MouseButton1Click:Connect(function()
    setAtivo(not cfg.ativo)
end)

-- Info em tempo real
task.spawn(function()
    while gui.Parent do
        task.wait(0.5)
        local w = getArmaSelecionada()
        weaponLbl.Text = "Arma: " .. (w and w.Name or "--")
        killsLbl.Text  = "Kills: " .. totalKills
    end
end)

-- Atualiza lista a cada 3s
task.spawn(function()
    while gui.Parent do
        task.wait(3)
        renderWeaponList()
    end
end)

-- ============================================
-- DRAG
-- ============================================
local POS_KEY_MK = "mobkiller_pos.json"
local _mkData = nil
local function salvarPos()
    if writefile then
        local ok, e = pcall(writefile, POS_KEY_MK, HS:JSONEncode({
            x = frame.Position.X.Offset, y = frame.Position.Y.Offset,
            minimizado = minimizado, hCache = hCache, windowState = estadoJanela
        }))
        if not ok then warn("mobkiller salvarPos:", e) end
    end
end
local function carregarPos()
    if isfile and readfile and isfile(POS_KEY_MK) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(POS_KEY_MK)) end)
        if ok and d then
            frame.Position = UDim2.new(0, d.x, 0, d.y)
            _mkData = d
        end
    end
end
carregarPos()

do
    local saved = (_G.KAHWindowState and _G.KAHWindowState.get) and _G.KAHWindowState.get(MODULE_NAME, nil) or nil
    if saved then
        estadoJanela = saved
    elseif _mkData and (_mkData.windowState == "maximizado" or _mkData.windowState == "minimizado" or _mkData.windowState == "fechado") then
        estadoJanela = _mkData.windowState
    elseif _mkData and _mkData.minimizado then
        estadoJanela = "minimizado"
    end
end

if _G.Snap then _G.Snap.registrar(frame, salvarPos) end

local dragInput, dragStartPos, dragStartMouse
header.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    dragInput = i; dragStartPos = frame.Position; dragStartMouse = i.Position
end)
UIS.InputChanged:Connect(function(i)
    if dragInput and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStartMouse
        local nx = dragStartPos.X.Offset + d.X
        local ny = dragStartPos.Y.Offset + d.Y
        if _G.Snap then _G.Snap.mover(frame, nx, ny)
        else frame.Position = UDim2.new(0, nx, 0, ny) end
    end
end)
UIS.InputEnded:Connect(function(i)
    if i == dragInput then
        dragInput = nil
        if _G.Snap then _G.Snap.soltar(frame)
        else salvarPos() end
    end
end)

-- ============================================
-- MINIMIZAR - inicia minimizado
-- ============================================
minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    if minimizado then
        hCache = frame.Size.Y.Offset
        TS:Create(frame, TweenInfo.new(0.18), { Size = UDim2.new(0, W, 0, H_HDR) }):Play()
        content.Visible = false; minBtn.Text = "^"
    else
        content.Visible = true
        atualizarLayout()
        minBtn.Text = "-"
    end
    setEstadoJanela(minimizado and "minimizado" or "maximizado")
    salvarPos()
end)

closeBtn.MouseButton1Click:Connect(function()
    setEstadoJanela("fechado")
    salvarPos(); setAtivo(false); gui.Enabled = false
    if _G.Hub then pcall(function() _G.Hub.desligar(MODULE_NAME) end) end
end)

-- ============================================
-- HUB
-- ============================================
local booting = true
local function onToggle(ativo)
    if gui and gui.Parent then gui.Enabled = ativo end
    if not ativo then setAtivo(false) end
    if not booting then
        if ativo then
            setEstadoJanela(minimizado and "minimizado" or "maximizado")
        else
            setEstadoJanela("fechado")
        end
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

-- ============================================
-- INIT
-- ============================================
renderWeaponList()
if estadoJanela == "minimizado" or (_mkData and _mkData.minimizado and estadoJanela ~= "maximizado") then
    minimizado = true
    hCache = (_mkData and _mkData.hCache) or hCache
    content.Visible = false
    frame.Size = UDim2.new(0, W, 0, H_HDR)
    minBtn.Text = "^"
else
    minimizado = false
    content.Visible = true
    atualizarLayout()
    minBtn.Text = "-"
end
booting = false
print(">>> MOB KILLER ATIVO")
