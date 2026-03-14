print('[KAH][LOAD] teleporter.lua')
-- ============================================
-- MÓDULO: TELEPORTER
-- ============================================

local VERSION   = "1.0.7"
local CATEGORIA = "Utility"
local MODULE_NAME = "Teleporte"
local ADMIN_BOOT_KEY = "__kah_admin_loaded_by_teleporter"
local ADMIN_URL = "https://raw.githubusercontent.com/dsantosdev/roblox/refs/heads/main/adminCommands.lua"

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local TS      = game:GetService("TweenService")
local HS      = game:GetService("HttpService")
local RS      = game:GetService("RunService")
local player  = Players.LocalPlayer

local function ensureAdminCommandsLoaded()
    local ok, content = pcall(game.HttpGet, game, ADMIN_URL)
    if not ok or not content or #content == 0 then
        warn("[KAH][WARN][Teleporter] falha ao baixar adminCommands.lua")
        return
    end
    local fn, err = loadstring(content)
    if not fn then
        warn("[KAH][WARN][Teleporter] sintaxe em adminCommands.lua: " .. tostring(err))
        return
    end
    local runOk, runErr = pcall(fn)
    if not runOk then
        warn("[KAH][WARN][Teleporter] erro ao executar adminCommands.lua: " .. tostring(runErr))
        return
    end
    _G[ADMIN_BOOT_KEY] = { url = ADMIN_URL, loadedAt = os.clock() }
end

ensureAdminCommandsLoaded()

-- ============================================
-- INFO DO JOGO
-- ============================================
local PLACE_ID   = tostring(game.PlaceId)
local PLACE_NAME = (function()
    local ok, name = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
    end)
    return (ok and name) or "Jogo " .. PLACE_ID
end)()

-- ============================================
-- PERSISTÊNCIA
-- ============================================
local SAVE_KEY = "tp_slots_" .. PLACE_ID .. ".json"

local function salvar(slots)
    if not writefile then return end
    local dados = {}
    for _, s in ipairs(slots) do
        local p  = s.cf.Position
        local lv = s.cf.LookVector
        table.insert(dados, { nome = s.nome, px = p.X, py = p.Y, pz = p.Z, lx = lv.X, ly = lv.Y, lz = lv.Z })
    end
    pcall(writefile, SAVE_KEY, HS:JSONEncode(dados))
end

local function carregar()
    if not (isfile and readfile and isfile(SAVE_KEY)) then return {} end
    local ok, dados = pcall(function() return HS:JSONDecode(readfile(SAVE_KEY)) end)
    if not ok or type(dados) ~= "table" then return {} end
    local slots = {}
    for _, d in ipairs(dados) do
        local cf = CFrame.new(d.px, d.py, d.pz) * CFrame.Angles(0, math.atan2(-d.lx, -d.lz), 0)
        table.insert(slots, { nome = d.nome, cf = cf })
    end
    return slots
end

local slots = carregar()
local systemSlots = {}
local BANCADA_CFRAME = CFrame.new(25, 3, -2)
local renderedSlotsCount = 0
local strongLockedCFrame = nil
local templeLockedCFrame = nil
local templeLockedCount = nil
local coliseumLockedCFrame = nil
local isEditingSlotName = false
local pendingSystemRender = false
local STRONG_DESC_GREEN = Color3.fromRGB(50, 220, 100)
local STRONG_DESC_YELLOW = Color3.fromRGB(255, 200, 50)
local STRONG_DESC_RED = Color3.fromRGB(220, 50, 70)

-- ============================================
-- HELPERS
-- ============================================
local function getHRP()
    local c = player.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function syncCameraToCFrame(cf)
    local cam = workspace.CurrentCamera
    if not cam or not cf then return end
    local focusPos = cf.Position + (cf.LookVector * 4)
    local camPos = cf.Position - (cf.LookVector * 4) + Vector3.new(0, 8, 0)
    cam.CFrame = CFrame.lookAt(camPos, focusPos)
end

local function teleportar(cf, syncCamera)
    local hrp = getHRP()
    if not hrp then return end
    local lock = true
    local conn
    conn = RS.Heartbeat:Connect(function()
        if not lock then conn:Disconnect(); return end
        local h = getHRP()
        if h then
            h.CFrame = cf
            if syncCamera then
                syncCameraToCFrame(cf)
            end
        end
    end)
    task.delay(1.2, function() lock = false end)
end

local function getFlatYawFromLook(lookVec)
    local flat = Vector3.new(lookVec.X, 0, lookVec.Z)
    if flat.Magnitude < 0.001 then return nil end
    flat = flat.Unit
    return math.atan2(-flat.X, -flat.Z)
end

local function buildBancadaRelativeCFrame()
    local targetPos = BANCADA_CFRAME.Position
    local hrp = getHRP()
    if not hrp then
        return BANCADA_CFRAME
    end
    local yaw = getFlatYawFromLook(hrp.CFrame.LookVector)
    if not yaw then
        return BANCADA_CFRAME
    end
    return CFrame.new(targetPos) * CFrame.Angles(0, yaw + math.rad(110), 0)
end

local function getByPath(root, ...)
    local cur = root
    for _, name in ipairs({...}) do
        if not cur then return nil end
        cur = cur:FindFirstChild(name)
    end
    return cur
end

local function parseClockSeconds(text)
    if type(text) ~= "string" then return nil end
    local m, s = string.match(text, "(%d+)%s*[mM]%s*(%d+)%s*[sS]")
    if m and s then
        return (tonumber(m) or 0) * 60 + (tonumber(s) or 0)
    end
    local mm, ss = string.match(text, "(%d+)%s*:%s*(%d+)")
    if mm and ss then
        return (tonumber(mm) or 0) * 60 + (tonumber(ss) or 0)
    end
    return nil
end

local function formatClock(secs)
    secs = math.max(0, math.floor(tonumber(secs) or 0))
    return string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
end

local function readStrongholdSignSeconds()
    local body = getByPath(workspace, "Map", "Landmarks", "Stronghold", "Functional", "Sign", "SurfaceGui", "Frame", "Body")
    if body and body:IsA("TextLabel") then
        local secs = parseClockSeconds(body.Text)
        if secs ~= nil then
            return secs
        end
    end

    local sign = getByPath(workspace, "Map", "Landmarks", "Stronghold", "Functional", "Sign")
    if sign then
        for _, d in ipairs(sign:GetDescendants()) do
            if d:IsA("TextLabel") then
                local secs = parseClockSeconds(d.Text)
                if secs ~= nil then
                    return secs
                end
            end
        end
    end
    return nil
end

local function getStrongholdApiInfo()
    local api = _G.__kah_stronghold_api
    if type(api) ~= "table" or type(api.getTimerInfo) ~= "function" then
        return nil
    end
    local ok, info = pcall(api.getTimerInfo)
    if not ok or type(info) ~= "table" then
        return nil
    end
    return info
end

local function getStrongholdDescVisual()
    local info = getStrongholdApiInfo()
    if info then
        local status = tostring(info.status or "closed")
        local rem = tonumber(info.remaining)
        if status == "ready" then
            return "Pronto", STRONG_DESC_GREEN
        end
        if status == "almost" then
            if rem and rem > 0 then
                return "Quase abrindo " .. formatClock(rem), STRONG_DESC_YELLOW
            end
            return "Quase abrindo", STRONG_DESC_YELLOW
        end
        if rem and rem > 0 then
            return "Fechado " .. formatClock(rem), STRONG_DESC_RED
        end
        return "Fechado", STRONG_DESC_RED
    end

    local secs = readStrongholdSignSeconds()
    if secs == nil then
        return "Fechado", STRONG_DESC_RED
    end
    if secs <= 0 then
        return "Pronto", STRONG_DESC_GREEN
    end
    if secs <= 60 then
        return "Quase abrindo " .. formatClock(secs), STRONG_DESC_YELLOW
    end
    return "Fechado " .. formatClock(secs), STRONG_DESC_RED
end

local function sameColor(a, b)
    if a == b then return true end
    if not a or not b then return false end
    return math.abs(a.R - b.R) < 0.001
        and math.abs(a.G - b.G) < 0.001
        and math.abs(a.B - b.B) < 0.001
end

local function findStrongholdTeleportCFrame()
    local right = getByPath(workspace, "Map", "Landmarks", "Stronghold", "Functional", "EntryDoors", "DoorRight", "Main")
    local left = getByPath(workspace, "Map", "Landmarks", "Stronghold", "Functional", "EntryDoors", "DoorLeft", "Main")
    if not (right and right:IsA("BasePart")) then right = nil end
    if not (left and left:IsA("BasePart")) then left = nil end
    if not right and not left then return nil end

    local center = right and left and ((right.Position + left.Position) * 0.5) or (right or left).Position
    local basis = right and left and (left.Position - right.Position) or Vector3.new(1, 0, 0)
    local planar = Vector3.new(basis.X, 0, basis.Z)
    if planar.Magnitude < 0.001 then
        planar = Vector3.new(1, 0, 0)
    end
    local tangent = planar.Unit
    local normal = Vector3.new(-tangent.Z, 0, tangent.X)

    local signPart = getByPath(workspace, "Map", "Landmarks", "Stronghold", "Functional", "Sign")
    local signPos = nil
    if signPart then
        if signPart:IsA("BasePart") then
            signPos = signPart.Position
        elseif signPart:IsA("Model") then
            local ok, p = pcall(function() return signPart:GetPivot().Position end)
            if ok then signPos = p end
        end
    end

    local c1 = center + normal * 1
    local c2 = center - normal * 1
    local outside = c1
    if signPos then
        if (c2 - signPos).Magnitude < (c1 - signPos).Magnitude then
            outside = c2
        end
    end
    outside = Vector3.new(outside.X, center.Y + 1, outside.Z)
    return CFrame.lookAt(outside, Vector3.new(center.X, outside.Y, center.Z))
end

local function getObjectWorldPosition(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then
        return obj.Position
    end
    if obj:IsA("Model") then
        local ok, pivot = pcall(function() return obj:GetPivot() end)
        if ok and pivot then
            return pivot.Position
        end
        local base = obj:FindFirstChildWhichIsA("BasePart", true)
        if base then
            return base.Position
        end
    end
    local base = obj:FindFirstChildWhichIsA("BasePart", true)
    if base then
        return base.Position
    end
    return nil
end

local function findColiseumTeleportCFrame()
    -- Tenta via ProximityPrompt (ponto exato de interação)
    local pit
    pcall(function()
        pit = workspace.Map.Landmarks["Jungle Fight Pit"]
    end)
    if not pit then return nil end

    local prompt = pit:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        local att = prompt.Parent
        local pos
        if att and att:IsA("Attachment") then
            pos = att.WorldPosition
        elseif att and att:IsA("BasePart") then
            pos = att.Position
        end
        if pos then
            return CFrame.new(pos + Vector3.new(0, 4, 0))
        end
    end

    -- Fallback: primeira BasePart do landmark
    local part = pit:FindFirstChildWhichIsA("BasePart", true)
    if part then
        return CFrame.new(part.Position + Vector3.new(0, 4, 0))
    end

    return nil
end

local function findTempleTeleportCFrame()
    local sum = Vector3.new(0, 0, 0)
    local total = 0

    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name == "JungleGemPodium" then
            local pos = getObjectWorldPosition(d)
            if pos then
                sum += pos
                total += 1
            end
        end
    end

    if total <= 0 then
        return nil, 0
    end

    local center = sum / total
    local target = center + Vector3.new(0, 5, 0)
    return CFrame.new(target), total
end

local function slotChanged(a, b)
    if (a == nil) ~= (b == nil) then return true end
    if not a and not b then return false end
    if a.nome ~= b.nome then return true end
    if a.desc ~= b.desc then return true end
    if not sameColor(a.descColor, b.descColor) then return true end
    local pa, pb = a.cf.Position, b.cf.Position
    if (pa - pb).Magnitude > 0.2 then return true end
    if a.cf.LookVector:Dot(b.cf.LookVector) < 0.995 then return true end
    return false
end

local function rebuildSystemSlots()
    local nextSlots = {}

    nextSlots.bancada = {
        key = "bancada",
        nome = "Bancada",
        desc = "Atalho fixo",
        cf = BANCADA_CFRAME,
        system = true,
    }

    local strongCf = strongLockedCFrame
    if not strongCf then
        strongCf = findStrongholdTeleportCFrame()
        if strongCf then
            strongLockedCFrame = strongCf
        end
    end
    if strongCf then
        local strongDesc, strongDescColor = getStrongholdDescVisual()
        nextSlots.fortaleza = {
            key = "fortaleza",
            nome = "Fortaleza",
            desc = strongDesc,
            descColor = strongDescColor,
            cf = strongCf,
            system = true,
        }
    end

    local templeCf, podiumCount
    if templeLockedCFrame then
        templeCf = templeLockedCFrame
        podiumCount = templeLockedCount
    else
        templeCf, podiumCount = findTempleTeleportCFrame()
        if templeCf then
            templeLockedCFrame = templeCf
            templeLockedCount = podiumCount
        end
    end
    if templeCf then
        nextSlots.templo = {
            key = "templo",
            nome = "Templo",
            desc = "Centro JungleGemPodium (" .. tostring(podiumCount) .. ")",
            cf = templeCf,
            system = true,
        }
    end

    local coliseuCf = coliseumLockedCFrame
    if not coliseuCf then
        coliseuCf = findColiseumTeleportCFrame()
        if coliseuCf then
            coliseumLockedCFrame = coliseuCf
        end
    end
    if coliseuCf then
        nextSlots.coliseu = {
            key = "coliseu",
            nome = "Coliseu",
            desc = "Jungle Fight Pit",
            cf = coliseuCf,
            system = true,
        }
    end

    local changed = slotChanged(systemSlots.bancada, nextSlots.bancada)
        or slotChanged(systemSlots.fortaleza, nextSlots.fortaleza)
        or slotChanged(systemSlots.templo, nextSlots.templo)
        or slotChanged(systemSlots.coliseu, nextSlots.coliseu)
    systemSlots = nextSlots
    return changed
end

local function getDisplaySlots()
    local out = {}
    if systemSlots.bancada then table.insert(out, systemSlots.bancada) end
    if systemSlots.fortaleza then table.insert(out, systemSlots.fortaleza) end
    if systemSlots.templo then table.insert(out, systemSlots.templo) end
    if systemSlots.coliseu then table.insert(out, systemSlots.coliseu) end
    for i, slot in ipairs(slots) do
        out[#out + 1] = {
            key = "user_" .. i,
            nome = slot.nome,
            cf = slot.cf,
            system = false,
            userIndex = i,
        }
    end
    return out
end

-- ============================================
-- CORES
-- ============================================
local C = {
    bg      = Color3.fromRGB(10, 11, 15),
    panel   = Color3.fromRGB(18, 20, 30),
    header  = Color3.fromRGB(12, 14, 20),
    border  = Color3.fromRGB(28, 32, 48),
    accent  = Color3.fromRGB(0, 220, 255),
    green   = Color3.fromRGB(50, 220, 100),
    greenDim= Color3.fromRGB(15, 55, 25),
    red     = Color3.fromRGB(220, 50, 70),
    redDim  = Color3.fromRGB(55, 12, 18),
    yellow  = Color3.fromRGB(255, 200, 50),
    text    = Color3.fromRGB(180, 190, 210),
    muted   = Color3.fromRGB(120, 130, 155),
    rowBg   = Color3.fromRGB(18, 20, 28),
    rowHov  = Color3.fromRGB(22, 26, 38),
}

local ICONS = {
    title = "rbxassetid://6031094678",
    min = "rbxassetid://6031090990",
    close = "rbxassetid://6031091004",
    edit = "rbxassetid://6031094677",
    delete = "rbxassetid://6031091004",
}

local function attachButtonIcon(btn, imageId, color)
    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.new(0.5, 0, 0.5, 0)
    icon.Size = UDim2.new(0, 12, 0, 12)
    icon.BackgroundTransparency = 1
    icon.Image = imageId
    icon.ImageColor3 = color or Color3.new(1, 1, 1)
    icon.ZIndex = btn.ZIndex + 1
    icon.Parent = btn
    btn.Text = ""
    return icon
end

-- ============================================
-- CONSTANTES DE LAYOUT
-- ============================================
local TP_SIZE_KEY = "teleport_size_" .. PLACE_ID .. ".json"
local function carregarDimTp()
    if isfile and readfile and isfile(TP_SIZE_KEY) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(TP_SIZE_KEY)) end)
        if ok and type(d) == "table" then
            return tonumber(d.w) or 240, tonumber(d.hExtra) or 0
        end
    end
    return 240, 0
end
local function salvarDimTp(w, hExtra)
    if not writefile then return end
    pcall(writefile, TP_SIZE_KEY, HS:JSONEncode({ w = w, hExtra = hExtra }))
end

local savedW, savedHExtra = carregarDimTp()
local BASE_W     = 240
local MIN_W      = 220
local MAX_W      = 420
local W          = math.clamp(savedW, MIN_W, MAX_W)
local MIN_EXTRA_H = 0
local MAX_EXTRA_H = 420
local H_EXTRA     = math.clamp(savedHExtra, MIN_EXTRA_H, MAX_EXTRA_H)

local function getMinimizedWidth()
    if _G.KAHUiDefaults and _G.KAHUiDefaults.getMinWidth then
        local ok, v = pcall(_G.KAHUiDefaults.getMinWidth)
        if ok and tonumber(v) then
            return math.clamp(math.floor(tonumber(v)), 220, 420)
        end
    end
    return 240
end
local H_HDR      = 34
local H_SUBHDR   = 20   -- faixa do nome do jogo
local H_SAVEBTN  = 28
local H_SLOT     = 36
local H_SCROLL_MAX = 260
local PAD        = 6

-- ============================================
-- GUI
-- ============================================
local pg = player:WaitForChild("PlayerGui")
local ant = pg:FindFirstChild("TeleportModule_hud")
if ant then ant:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name          = "TeleportModule_hud"
gui.ResetOnSpawn  = false
gui.IgnoreGuiInset = true
gui.Parent        = pg

-- O frame se posiciona colado à direita do hub.
-- O hub está em (posX, posY) com largura 240.
-- Usamos um script de ancoragem dinâmica abaixo.
local frame = Instance.new("Frame")
frame.Name             = "TeleFrame"
frame.Size             = UDim2.new(0, W, 0, H_HDR)
frame.Position         = UDim2.new(0, 390, 0, 20)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel  = 0
frame.Parent           = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color        = C.border

local teleScale = Instance.new("UIScale")
teleScale.Name = "__TeleResizeScale"
teleScale.Scale = math.clamp((W / BASE_W) ^ 0.55, 0.9, 1.35)
teleScale.Parent = frame

-- Accent topo
local topLine = Instance.new("Frame")
topLine.Size             = UDim2.new(1, 0, 0, 2)
topLine.BackgroundColor3 = C.accent
topLine.BorderSizePixel  = 0
topLine.ZIndex           = 5
topLine.Parent           = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

-- ============================================
-- HEADER
-- ============================================
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, H_HDR)
header.BackgroundColor3 = C.header
header.BorderSizePixel  = 0
header.Active           = true
header.ZIndex           = 3
header.Parent           = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size               = UDim2.new(1, -96, 1, 0)
titleLbl.Position           = UDim2.new(0, 26, 0, 0)
titleLbl.Text               = "TELEPORTE"
titleLbl.TextColor3         = C.accent
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 11
titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.ZIndex             = 4
titleLbl.Parent             = header

local titleIcon = Instance.new("ImageLabel")
titleIcon.Size = UDim2.new(0, 13, 0, 13)
titleIcon.Position = UDim2.new(0, 9, 0.5, -6)
titleIcon.BackgroundTransparency = 1
titleIcon.Image = ICONS.title
titleIcon.ImageColor3 = C.accent
titleIcon.ZIndex = 4
titleIcon.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size             = UDim2.new(0, 20, 0, 20)
minBtn.Position         = UDim2.new(1, -44, 0.5, -10)
minBtn.Text             = ""
minBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
minBtn.TextColor3       = C.muted
minBtn.Font             = Enum.Font.GothamBold
minBtn.TextSize         = 10
minBtn.BorderSizePixel  = 0
minBtn.ZIndex           = 4
minBtn.Parent           = header
Instance.new("UIStroke", minBtn).Color        = C.border
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 3)
attachButtonIcon(minBtn, ICONS.min, C.muted)

local closeBtn2 = Instance.new("TextButton")
closeBtn2.Size             = UDim2.new(0, 20, 0, 20)
closeBtn2.Position         = UDim2.new(1, -20, 0.5, -10)
closeBtn2.Text             = ""
closeBtn2.BackgroundColor3 = C.redDim
closeBtn2.TextColor3       = C.red
closeBtn2.Font             = Enum.Font.GothamBold
closeBtn2.TextSize         = 10
closeBtn2.BorderSizePixel  = 0
closeBtn2.ZIndex           = 4
closeBtn2.Parent           = header
Instance.new("UIStroke", closeBtn2).Color        = Color3.fromRGB(100, 20, 35)
Instance.new("UICorner", closeBtn2).CornerRadius = UDim.new(0, 3)
attachButtonIcon(closeBtn2, ICONS.close, C.red)

local resizeHandle = Instance.new("TextButton")
resizeHandle.Name             = "ResizeHandle"
resizeHandle.Size             = UDim2.new(0, 14, 0, 14)
resizeHandle.Position         = UDim2.new(1, -14, 1, -14)
resizeHandle.Text             = ""
resizeHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeHandle.BorderSizePixel  = 0
resizeHandle.AutoButtonColor  = true
resizeHandle.ZIndex           = 8
resizeHandle.Parent           = frame
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
resizeHHandle.Name             = "ResizeHeightHandle"
resizeHHandle.Size             = UDim2.new(0, 24, 0, 8)
resizeHHandle.Position         = UDim2.new(0.5, -12, 1, -8)
resizeHHandle.Text             = ""
resizeHHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeHHandle.BorderSizePixel  = 0
resizeHHandle.AutoButtonColor  = true
resizeHHandle.ZIndex           = 8
resizeHHandle.Parent           = frame
Instance.new("UICorner", resizeHHandle).CornerRadius = UDim.new(1, 0)
local rsHStroke = Instance.new("UIStroke", resizeHHandle)
rsHStroke.Color = C.border
rsHStroke.Thickness = 1

local resizeLHandle = Instance.new("TextButton")
resizeLHandle.Name             = "ResizeLeftHandle"
resizeLHandle.Size             = UDim2.new(0, 8, 0, 36)
resizeLHandle.Position         = UDim2.new(0, 0, 0.5, -18)
resizeLHandle.Text             = ""
resizeLHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeLHandle.BorderSizePixel  = 0
resizeLHandle.AutoButtonColor  = true
resizeLHandle.ZIndex           = 8
resizeLHandle.Parent           = frame
Instance.new("UICorner", resizeLHandle).CornerRadius = UDim.new(1, 0)
local rsLStroke = Instance.new("UIStroke", resizeLHandle)
rsLStroke.Color = C.border
rsLStroke.Thickness = 1

local resizeRHandle = Instance.new("TextButton")
resizeRHandle.Name             = "ResizeRightHandle"
resizeRHandle.Size             = UDim2.new(0, 8, 0, 36)
resizeRHandle.Position         = UDim2.new(1, -8, 0.5, -18)
resizeRHandle.Text             = ""
resizeRHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeRHandle.BorderSizePixel  = 0
resizeRHandle.AutoButtonColor  = true
resizeRHandle.ZIndex           = 8
resizeRHandle.Parent           = frame
Instance.new("UICorner", resizeRHandle).CornerRadius = UDim.new(1, 0)
local rsRStroke = Instance.new("UIStroke", resizeRHandle)
rsRStroke.Color = C.border
rsRStroke.Thickness = 1

-- ============================================
-- SUBHEADER — NOME DO JOGO
-- ============================================
local subHdr = Instance.new("Frame")
subHdr.Size             = UDim2.new(1, 0, 0, H_SUBHDR)
subHdr.Position         = UDim2.new(0, 0, 0, H_HDR)
subHdr.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
subHdr.BorderSizePixel  = 0
subHdr.ZIndex           = 2
subHdr.Parent           = frame

local subLine = Instance.new("Frame")
subLine.Size             = UDim2.new(1, 0, 0, 1)
subLine.Position         = UDim2.new(0, 0, 1, -1)
subLine.BackgroundColor3 = C.border
subLine.BorderSizePixel  = 0
subLine.ZIndex           = 3
subLine.Parent           = subHdr

local gameLbl = Instance.new("TextLabel")
gameLbl.Size               = UDim2.new(1, -16, 1, 0)
gameLbl.Position           = UDim2.new(0, 8, 0, 0)
gameLbl.Text               = "// " .. PLACE_NAME
gameLbl.TextColor3         = C.muted
gameLbl.Font               = Enum.Font.Code
gameLbl.TextSize           = 9
gameLbl.BackgroundTransparency = 1
gameLbl.TextXAlignment     = Enum.TextXAlignment.Left
gameLbl.TextTruncate       = Enum.TextTruncate.AtEnd
gameLbl.ZIndex             = 3
gameLbl.Parent             = subHdr

-- ============================================
-- BOTÃO SALVAR
-- ============================================
local SAVE_Y = H_HDR + H_SUBHDR + PAD

local saveBtn = Instance.new("TextButton")
saveBtn.Size             = UDim2.new(1, -PAD*2, 0, H_SAVEBTN)
saveBtn.Position         = UDim2.new(0, PAD, 0, SAVE_Y)
saveBtn.Text             = "+ SALVAR POSIÇÃO ATUAL"
saveBtn.BackgroundColor3 = C.greenDim
saveBtn.TextColor3       = C.green
saveBtn.Font             = Enum.Font.GothamBold
saveBtn.TextSize         = 10
saveBtn.BorderSizePixel  = 0
saveBtn.ZIndex           = 3
saveBtn.Parent           = frame
Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", saveBtn).Color        = Color3.fromRGB(30, 100, 50)

-- ============================================
-- SCROLL
-- ============================================
local SCROLL_Y = SAVE_Y + H_SAVEBTN + PAD

local scroll = Instance.new("ScrollingFrame")
scroll.Size                   = UDim2.new(1, -PAD*2, 0, 0)
scroll.Position               = UDim2.new(0, PAD, 0, SCROLL_Y)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel        = 0
scroll.ScrollBarThickness     = 3
scroll.ScrollBarImageColor3   = C.accent
scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
scroll.ZIndex                 = 3
scroll.Parent                 = frame

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.Padding   = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- ============================================
-- DRAG + PERSISTÊNCIA DE POSIÇÃO
-- ============================================
local POS_KEY_TP = "teleport_pos_" .. PLACE_ID .. ".json"
local minimizado = false
local hFullCache = nil
local _tpData = nil
local estadoJanela = "maximizado"
local function setEstadoJanela(v)
    estadoJanela = v
    if _G.KAHWindowState and _G.KAHWindowState.set then
        _G.KAHWindowState.set(MODULE_NAME, v)
    end
end
local function salvarPosTp()
    if writefile then
        pcall(writefile, POS_KEY_TP, HS:JSONEncode({
            x = frame.Position.X.Offset, y = frame.Position.Y.Offset,
            minimizado = minimizado, hCache = hFullCache, windowState = estadoJanela
        }))
    end
end
local function carregarPosTp()
    if isfile and readfile and isfile(POS_KEY_TP) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(POS_KEY_TP)) end)
        if ok and d then
            frame.Position = UDim2.new(0, d.x, 0, d.y)
            _tpData = d
        end
    end
end
carregarPosTp()

do
    local saved = (_G.KAHWindowState and _G.KAHWindowState.get) and _G.KAHWindowState.get(MODULE_NAME, nil) or nil
    if saved then
        estadoJanela = saved
    elseif _tpData and (_tpData.windowState == "maximizado" or _tpData.windowState == "minimizado" or _tpData.windowState == "fechado") then
        estadoJanela = _tpData.windowState
    elseif _tpData and _tpData.minimizado then
        estadoJanela = "minimizado"
    end
end

local function setResizeHandlesVisible(v)
    resizeHandle.Visible = v
    resizeHHandle.Visible = v
    resizeLHandle.Visible = v
    resizeRHandle.Visible = v
end

local function aplicarLarguraTp(novaW, novaExtraH, salvar)
    W = math.clamp(math.floor((tonumber(novaW) or W) + 0.5), MIN_W, MAX_W)
    if tonumber(novaExtraH) ~= nil then
        H_EXTRA = math.floor(tonumber(novaExtraH) + 0.5)
    end
    H_EXTRA = math.clamp(H_EXTRA, MIN_EXTRA_H, MAX_EXTRA_H)
    teleScale.Scale = math.clamp((W / BASE_W) ^ 0.55, 0.9, 1.35)

    local contentH = renderedSlotsCount * (H_SLOT + 4)
    local baseScrollH = math.min(contentH, H_SCROLL_MAX)
    if renderedSlotsCount == 0 then baseScrollH = 0 end
    local padPreview = (baseScrollH > 0 or H_EXTRA > 0) and PAD or 0
    local sh = workspace.CurrentCamera.ViewportSize.Y
    local maxExtraView = math.max(0, sh - (SCROLL_Y + baseScrollH + padPreview) - 8)
    H_EXTRA = math.clamp(H_EXTRA, MIN_EXTRA_H, math.min(MAX_EXTRA_H, maxExtraView))
    local scrollH = math.max(0, baseScrollH + H_EXTRA)
    scroll.Size = UDim2.new(1, -PAD*2, 0, scrollH)

    if minimizado then
        frame.Size = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
    else
        local extra = (scrollH > 0) and PAD or 0
        frame.Size = UDim2.new(0, W, 0, SCROLL_Y + scrollH + extra)
    end
    setResizeHandlesVisible(not minimizado)

    local sw = workspace.CurrentCamera.ViewportSize.X
    local nx = math.clamp(frame.Position.X.Offset, 4, sw - frame.Size.X.Offset - 4)
    local ny = math.clamp(frame.Position.Y.Offset, 4, sh - frame.Size.Y.Offset - 4)
    frame.Position = UDim2.new(0, nx, 0, ny)

    if salvar then
        salvarDimTp(W, H_EXTRA)
        salvarPosTp()
    end
    if _G.Snap and _G.Snap.atualizarTamanho then
        pcall(function() _G.Snap.atualizarTamanho(frame) end)
    end
end

local dragInput, dragStartPos, dragStartMouse, dragging
local resizing, resizeMode, resizeStartMouse, resizeStartW, resizeStartHExtra, resizeStartRightX, resizeStartFrameH
header.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if resizing then return end
    dragging = true
    dragInput = i
    dragStartPos = frame.Position
    dragStartMouse = i.Position
end)
resizeHandle.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if minimizado then return end
    resizing = true
    resizeMode = "both"
    dragging = false
    resizeStartMouse = i.Position
    resizeStartW = W
    resizeStartHExtra = H_EXTRA
    resizeStartFrameH = frame.Size.Y.Offset
end)
resizeHHandle.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if minimizado then return end
    resizing = true
    resizeMode = "height"
    dragging = false
    resizeStartMouse = i.Position
    resizeStartW = W
    resizeStartHExtra = H_EXTRA
    resizeStartFrameH = frame.Size.Y.Offset
end)
resizeLHandle.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if minimizado then return end
    resizing = true
    resizeMode = "left"
    dragging = false
    resizeStartMouse = i.Position
    resizeStartW = W
    resizeStartHExtra = H_EXTRA
    resizeStartRightX = frame.Position.X.Offset + frame.Size.X.Offset
    resizeStartFrameH = frame.Size.Y.Offset
end)
resizeRHandle.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if minimizado then return end
    resizing = true
    resizeMode = "right"
    dragging = false
    resizeStartMouse = i.Position
    resizeStartW = W
    resizeStartHExtra = H_EXTRA
    resizeStartFrameH = frame.Size.Y.Offset
end)
UIS.InputChanged:Connect(function(i)
    if resizing and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local dx = i.Position.X - resizeStartMouse.X
        local dy = i.Position.Y - resizeStartMouse.Y
        if resizeMode == "height" then
            aplicarLarguraTp(W, resizeStartHExtra + dy, false)
        elseif resizeMode == "left" then
            aplicarLarguraTp(resizeStartW - dx, resizeStartHExtra, false)
            if resizeStartFrameH and frame.Size.Y.Offset ~= resizeStartFrameH then
                local delta = resizeStartFrameH - frame.Size.Y.Offset
                aplicarLarguraTp(W, H_EXTRA + delta, false)
            end
            local sw = workspace.CurrentCamera.ViewportSize.X
            local nx = math.clamp(resizeStartRightX - frame.Size.X.Offset, 4, sw - frame.Size.X.Offset - 4)
            frame.Position = UDim2.new(0, nx, 0, frame.Position.Y.Offset)
        elseif resizeMode == "right" then
            aplicarLarguraTp(resizeStartW + dx, resizeStartHExtra, false)
            if resizeStartFrameH and frame.Size.Y.Offset ~= resizeStartFrameH then
                local delta = resizeStartFrameH - frame.Size.Y.Offset
                aplicarLarguraTp(W, H_EXTRA + delta, false)
            end
        else
            aplicarLarguraTp(resizeStartW + dx, resizeStartHExtra + dy, false)
        end
        return
    end
    if not dragging then return end
    if i.UserInputType ~= Enum.UserInputType.MouseMovement
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if dragInput and dragInput.UserInputType == Enum.UserInputType.Touch
    and i.UserInputType == Enum.UserInputType.Touch
    and i ~= dragInput then
        return
    end
    local d = i.Position - dragStartMouse
    local nx = dragStartPos.X.Offset + d.X
    local ny = dragStartPos.Y.Offset + d.Y
    if _G.Snap then _G.Snap.mover(frame, nx, ny)
    else frame.Position = UDim2.new(0, nx, 0, ny) end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if resizing then
        resizing = false
        resizeMode = nil
        aplicarLarguraTp(W, H_EXTRA, true)
        return
    end
    if dragging then
        if _G.Snap then _G.Snap.soltar(frame)
        else salvarPosTp() end
    end
    dragging = false
    dragInput = nil
end)

-- ============================================
-- RENDERIZAR SLOTS
-- ============================================
local function atualizarAltura()
    aplicarLarguraTp(W, H_EXTRA, false)
end

local function renderSlots()
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end

    local displaySlots = getDisplaySlots()
    renderedSlotsCount = #displaySlots

    for i, slot in ipairs(displaySlots) do
        local isSystem = slot.system == true

        local row = Instance.new("Frame")
        row.Name             = "Slot_" .. tostring(slot.key or i)
        row.Size             = UDim2.new(1, 0, 0, H_SLOT)
        row.BackgroundColor3 = C.rowBg
        row.BorderSizePixel  = 0
        row.LayoutOrder      = i
        row.ZIndex           = 4
        row.Parent           = scroll
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", row).Color        = C.border

        local nameBtn = Instance.new("TextButton")
        nameBtn.Name               = "NameBtn"
        nameBtn.Size               = UDim2.new(1, isSystem and 0 or -72, 1, 0)
        nameBtn.Position           = UDim2.new(0, 0, 0, 0)
        nameBtn.BackgroundTransparency = 1
        nameBtn.Text               = ""
        nameBtn.ZIndex             = 6
        nameBtn.Parent             = row

        local nomeLbl = Instance.new("TextLabel")
        nomeLbl.Name               = "NomeLbl"
        nomeLbl.Size               = UDim2.new(1, -10, 0.55, 0)
        nomeLbl.Position           = UDim2.new(0, 8, 0, 4)
        nomeLbl.Text               = slot.nome
        nomeLbl.TextColor3         = C.text
        nomeLbl.Font               = Enum.Font.GothamBold
        nomeLbl.TextSize           = 10
        nomeLbl.BackgroundTransparency = 1
        nomeLbl.TextXAlignment     = Enum.TextXAlignment.Left
        nomeLbl.TextTruncate       = Enum.TextTruncate.AtEnd
        nomeLbl.ZIndex             = 5
        nomeLbl.Parent             = row

        local pos = slot.cf.Position
        local descLbl = Instance.new("TextLabel")
        descLbl.Name               = "DescLbl"
        descLbl.Size               = UDim2.new(1, -10, 0.4, 0)
        descLbl.Position           = UDim2.new(0, 8, 0.58, 0)
        descLbl.Text               = slot.desc or string.format("X%.0f  Y%.0f  Z%.0f", pos.X, pos.Y, pos.Z)
        descLbl.TextColor3         = slot.descColor or C.muted
        descLbl.Font               = Enum.Font.Code
        descLbl.TextSize           = 8
        descLbl.BackgroundTransparency = 1
        descLbl.TextXAlignment     = Enum.TextXAlignment.Left
        descLbl.ZIndex             = 5
        descLbl.Parent             = row

        local renBtn = Instance.new("TextButton")
        renBtn.Size             = UDim2.new(0, 22, 0, 22)
        renBtn.Position         = UDim2.new(1, -48, 0.5, -11)
        renBtn.Text             = "E"
        renBtn.BackgroundColor3 = Color3.fromRGB(50, 40, 15)
        renBtn.TextColor3       = C.yellow
        renBtn.Font             = Enum.Font.GothamBold
        renBtn.TextSize         = 11
        renBtn.BorderSizePixel  = 0
        renBtn.ZIndex           = 7
        renBtn.Parent           = row
        Instance.new("UICorner", renBtn).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", renBtn).Color        = Color3.fromRGB(100, 80, 20)
        attachButtonIcon(renBtn, ICONS.edit, C.yellow)

        local delBtn = Instance.new("TextButton")
        delBtn.Size             = UDim2.new(0, 22, 0, 22)
        delBtn.Position         = UDim2.new(1, -22, 0.5, -11)
        delBtn.Text             = "X"
        delBtn.BackgroundColor3 = C.redDim
        delBtn.TextColor3       = C.red
        delBtn.Font             = Enum.Font.GothamBold
        delBtn.TextSize         = 10
        delBtn.BorderSizePixel  = 0
        delBtn.ZIndex           = 7
        delBtn.Parent           = row
        Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", delBtn).Color        = Color3.fromRGB(100, 20, 35)
        attachButtonIcon(delBtn, ICONS.delete, C.red)

        local inputBox = Instance.new("TextBox")
        inputBox.Size               = UDim2.new(1, -80, 0, 22)
        inputBox.Position           = UDim2.new(0, 6, 0.5, -11)
        inputBox.Text               = slot.nome
        inputBox.BackgroundColor3   = Color3.fromRGB(20, 24, 38)
        inputBox.TextColor3         = C.accent
        inputBox.Font               = Enum.Font.GothamBold
        inputBox.TextSize           = 10
        inputBox.BorderSizePixel    = 0
        inputBox.ZIndex             = 8
        inputBox.Visible            = false
        inputBox.ClearTextOnFocus   = false
        inputBox.PlaceholderText    = "Nome do slot..."
        inputBox.PlaceholderColor3  = C.muted
        inputBox.Parent             = row
        Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", inputBox).Color        = C.accent

        if isSystem then
            renBtn.Visible = false
            delBtn.Visible = false
            inputBox.Visible = false
        end

        nameBtn.MouseEnter:Connect(function()
            TS:Create(nomeLbl, TweenInfo.new(0.1), { TextColor3 = C.accent }):Play()
        end)
        nameBtn.MouseLeave:Connect(function()
            TS:Create(nomeLbl, TweenInfo.new(0.1), { TextColor3 = C.text }):Play()
        end)

        nameBtn.MouseButton1Click:Connect(function()
            local targetCf = slot.cf
            local syncBenchCamera = false
            if slot.key == "bancada" then
                targetCf = buildBancadaRelativeCFrame()
                syncBenchCamera = true
            end
            teleportar(targetCf, syncBenchCamera)
            TS:Create(row, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(15, 40, 25) }):Play()
            task.delay(0.35, function()
                TS:Create(row, TweenInfo.new(0.2), { BackgroundColor3 = C.rowBg }):Play()
            end)
        end)

        if not isSystem then
            local editando = false

            renBtn.MouseButton1Click:Connect(function()
                editando = not editando
                inputBox.Visible = editando
                nomeLbl.Visible  = not editando
                descLbl.Visible  = not editando
                nameBtn.Visible  = not editando
                if editando then
                    isEditingSlotName = true
                    inputBox.Text = ""
                    inputBox:CaptureFocus()
                else
                    isEditingSlotName = false
                end
            end)

            inputBox.FocusLost:Connect(function()
                local novo = inputBox.Text:match("^%s*(.-)%s*$")
                if novo and #novo > 0 then
                    local userSlot = slots[slot.userIndex]
                    if userSlot then
                        userSlot.nome = novo
                        nomeLbl.Text = novo
                        salvar(slots)
                    end
                end
                editando         = false
                isEditingSlotName = false
                inputBox.Visible = false
                nomeLbl.Visible  = true
                descLbl.Visible  = true
                nameBtn.Visible  = true
                if pendingSystemRender then
                    pendingSystemRender = false
                    task.defer(renderSlots)
                end
            end)

            delBtn.MouseButton1Click:Connect(function()
                if slots[slot.userIndex] then
                    table.remove(slots, slot.userIndex)
                    salvar(slots)
                    renderSlots()
                    atualizarAltura()
                end
            end)
        end
    end

    atualizarAltura()
end

-- ============================================
-- BOTAO SALVAR
-- ============================================
saveBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if not hrp then return end

    table.insert(slots, {
        nome = "Posição " .. (#slots + 1),
        cf   = hrp.CFrame,
    })
    salvar(slots)
    renderSlots()

    -- Feedback
    TS:Create(saveBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(20, 90, 45) }):Play()
    task.delay(0.4, function()
        TS:Create(saveBtn, TweenInfo.new(0.2), { BackgroundColor3 = C.greenDim }):Play()
    end)
end)

-- ============================================
-- MINIMIZAR
-- ============================================
minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    if minimizado then
        hFullCache = frame.Size.Y.Offset
        TS:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
        }):Play()
        subHdr.Visible  = false
        saveBtn.Visible = false
        scroll.Visible  = false
        minBtn.Text = ""
    else
        subHdr.Visible  = true
        saveBtn.Visible = true
        scroll.Visible  = true
        TS:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, W, 0, hFullCache or (SCROLL_Y + 100))
        }):Play()
        minBtn.Text = ""
    end
    setResizeHandlesVisible(not minimizado)
    setEstadoJanela(minimizado and "minimizado" or "maximizado")
    salvarPosTp()
end)

closeBtn2.MouseButton1Click:Connect(function()
    setEstadoJanela("fechado")
    salvarPosTp()
    gui.Enabled = false
    if _G.Hub then
        pcall(function() _G.Hub.desligar(MODULE_NAME) end)
    end
end)

-- ============================================
-- REGISTRA NO HUB
-- ============================================
local booting = true
local function onToggle(ativo)
    if not ativo then
        isEditingSlotName = false
    end
    if gui and gui.Parent then gui.Enabled = ativo end
    if not booting then
        if ativo then
            setEstadoJanela(minimizado and "minimizado" or "maximizado")
            if pendingSystemRender then
                pendingSystemRender = false
                renderSlots()
            end
        else
            setEstadoJanela("fechado")
        end
        salvarPosTp()
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

if _G.Snap then
    _G.Snap.registrar(frame, salvarPosTp, function(targetW, mode)
        if mode == "minimize" then
            minimizado = true
            hFullCache = hFullCache or frame.Size.Y.Offset
            frame.Size = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
            subHdr.Visible = false
            saveBtn.Visible = false
            scroll.Visible = false
            setResizeHandlesVisible(false)
            setEstadoJanela("minimizado")
            salvarPosTp()
            return
        end
        minimizado = false
        if tonumber(targetW) then
            W = math.clamp(math.floor(tonumber(targetW)), MIN_W, MAX_W)
        end
        subHdr.Visible = true
        saveBtn.Visible = true
        scroll.Visible = true
        aplicarLarguraTp(W, H_EXTRA, true)
        setEstadoJanela("maximizado")
    end)
end

-- ============================================
-- INIT
-- ============================================
rebuildSystemSlots()
renderSlots()
atualizarAltura()
aplicarLarguraTp(W, H_EXTRA, false)

-- Restaura estado minimizado salvo
if estadoJanela == "minimizado" or (_tpData and _tpData.minimizado and estadoJanela ~= "maximizado") then
    hFullCache = _tpData.hCache or frame.Size.Y.Offset
    minimizado = true
    frame.Size = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
    subHdr.Visible  = false
    saveBtn.Visible = false
    scroll.Visible  = false
    setResizeHandlesVisible(false)
    minBtn.Text = ""
end

booting = false

task.spawn(function()
    while gui and gui.Parent do
        local changed = rebuildSystemSlots()
        if changed then
            if isEditingSlotName then
                pendingSystemRender = true
            else
                renderSlots()
            end
        elseif pendingSystemRender and not isEditingSlotName then
            pendingSystemRender = false
            renderSlots()
        end
        task.wait(1.2)
    end
end)

_G.KAHtp = {
    teleportar = teleportar,
    bancada    = function() teleportar(buildBancadaRelativeCFrame(), true) end,
    getSlotCf = function(name)
        local query = string.lower(tostring(name or ""))
        if query == "" then return nil end
        local function matches(slotName)
            local n = string.lower(tostring(slotName or ""))
            if n == "" then return false end
            if n == query then return true end
            if string.find(n, query, 1, true) then return true end
            if string.find(query, n, 1, true) then return true end
            return false
        end
        for _, sys in pairs(systemSlots or {}) do
            if sys and sys.cf and matches(sys.nome) then
                return sys.cf
            end
        end
        for _, s in ipairs(slots or {}) do
            if s and s.cf and matches(s.nome) then
                return s.cf
            end
        end
        return nil
    end,
    getColiseuCf = function()
        if systemSlots and systemSlots.coliseu and systemSlots.coliseu.cf then
            return systemSlots.coliseu.cf
        end
        if coliseumLockedCFrame then
            return coliseumLockedCFrame
        end
        return findColiseumTeleportCFrame()
    end,
    getTemploCf = function()
        if systemSlots and systemSlots.templo and systemSlots.templo.cf then
            return systemSlots.templo.cf
        end
        if templeLockedCFrame then
            return templeLockedCFrame
        end
        for _, s in ipairs(slots or {}) do
            local n = string.lower(tostring(s.nome or ""))
            if n == "templo" or string.find(n, "templo", 1, true) or string.find(n, "jungle", 1, true) then
                templeLockedCFrame = s.cf
                return s.cf
            end
        end
        return nil
    end,
}
 
-- Processa fila de módulos que chamaram usarTp() antes do teleporter carregar
if _G.KAHtpFila then
    for _, fn in ipairs(_G.KAHtpFila) do pcall(fn) end
    _G.KAHtpFila = nil
end
