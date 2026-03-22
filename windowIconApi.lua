print("[KAH][LOAD] windowIconApi.lua")

local VERSION = "1.0.0"
local API_KEY = "__KAHMiniWindowAPI"
local SAVE_PATH = "kah_window_iconify_state.json"

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local HS = game:GetService("HttpService")
local player = Players.LocalPlayer

local function loadStateMap()
    if isfile and readfile and isfile(SAVE_PATH) then
        local ok, data = pcall(function()
            return HS:JSONDecode(readfile(SAVE_PATH))
        end)
        if ok and type(data) == "table" then
            return data
        end
    end
    return {}
end

local stateMap = loadStateMap()
local controllers = {}

local function saveStateMap()
    if not writefile then
        return
    end
    pcall(writefile, SAVE_PATH, HS:JSONEncode(stateMap))
end

local function getViewportSize()
    local cam = workspace.CurrentCamera
    if cam then
        return cam.ViewportSize
    end
    return Vector2.new(1920, 1080)
end

local function getMenuSafeRect()
    local top = UIS.TouchEnabled and 58 or 42
    local left = UIS.TouchEnabled and 176 or 156
    return {
        l = 0,
        t = 0,
        r = left,
        b = top,
    }
end

local function overlapsRect(nx, ny, fw, fh, rect)
    return nx < rect.r and (nx + fw) > rect.l and ny < rect.b and (ny + fh) > rect.t
end

local function clampIconPos(x, y, w, h)
    local vp = getViewportSize()
    local minX = 4
    local minY = 4
    local maxX = math.max(minX, vp.X - w - 4)
    local maxY = math.max(minY, vp.Y - h - 4)

    x = math.clamp(x, minX, maxX)
    y = math.clamp(y, minY, maxY)

    local rect = getMenuSafeRect()
    if not overlapsRect(x, y, w, h, rect) then
        return x, y
    end

    local rightX = math.clamp(rect.r + 8, minX, maxX)
    local belowY = math.clamp(rect.b + 8, minY, maxY)

    if rightX <= maxX then
        return rightX, y
    end
    return x, belowY
end

local function clampFramePos(pos, frame)
    local vp = getViewportSize()
    local fw = frame.Size.X.Offset
    local fh = frame.Size.Y.Offset
    local nx = math.clamp(pos.X.Offset, 4, math.max(4, vp.X - fw - 4))
    local ny = math.clamp(pos.Y.Offset, 4, math.max(4, vp.Y - fh - 4))
    return UDim2.new(0, nx, 0, ny)
end

local function findScreenGui(inst)
    local cur = inst
    while cur do
        if cur:IsA("ScreenGui") then
            return cur
        end
        cur = cur.Parent
    end
    return nil
end

local function getSavedStateEntry(key)
    local entry = stateMap[key]
    if type(entry) ~= "table" then
        return nil
    end
    return entry
end

local function setSavedStateEntry(key, entry)
    stateMap[key] = entry
    saveStateMap()
end

local function disconnectAll(conns)
    for i = #conns, 1, -1 do
        local c = conns[i]
        conns[i] = nil
        pcall(function()
            c:Disconnect()
        end)
    end
end

local function destroyController(ctrl, reason)
    if not ctrl or ctrl._destroyed then
        return
    end
    ctrl._destroyed = true
    disconnectAll(ctrl._conns or {})
    if ctrl._icon and ctrl._icon.Parent then
        pcall(function()
            ctrl._icon:Destroy()
        end)
    end
    if ctrl.key and controllers[ctrl.key] == ctrl then
        controllers[ctrl.key] = nil
    end
    if type(ctrl.onDestroy) == "function" then
        pcall(ctrl.onDestroy, reason or "destroy")
    end
end

local function registerMiniWindow(opts)
    if type(opts) ~= "table" then
        return nil, "opts deve ser table"
    end

    local frame = opts.frame
    if not frame or not frame:IsA("GuiObject") then
        return nil, "opts.frame invalido"
    end

    local key = tostring(opts.key or opts.id or opts.stateKey or frame.Name or "")
    if key == "" then
        return nil, "opts.key obrigatorio"
    end

    if controllers[key] then
        destroyController(controllers[key], "replace")
    end

    local iconParent = opts.iconParent
    if not (iconParent and (iconParent:IsA("LayerCollector") or iconParent:IsA("GuiObject"))) then
        iconParent = findScreenGui(frame) or (player and player:FindFirstChildOfClass("PlayerGui"))
    end
    if not iconParent then
        return nil, "nao foi possivel resolver iconParent"
    end

    local iconW = math.clamp(math.floor(tonumber(opts.iconWidth) or 42), 28, 180)
    local iconH = math.clamp(math.floor(tonumber(opts.iconHeight) or 38), 24, 120)
    local iconText = tostring(opts.iconText or "KAH")
    local iconName = tostring(opts.iconName or ("MiniIcon_" .. key))
    local hideFrame = opts.hideFrameWhenMinimized ~= false
    local remember = opts.remember ~= false

    local icon = Instance.new("TextButton")
    icon.Name = iconName
    icon.Size = UDim2.new(0, iconW, 0, iconH)
    icon.Position = UDim2.new(0, frame.Position.X.Offset, 0, frame.Position.Y.Offset)
    icon.BackgroundColor3 = opts.iconBgColor or Color3.fromRGB(12, 14, 20)
    icon.TextColor3 = opts.iconTextColor or Color3.fromRGB(0, 220, 255)
    icon.Font = opts.iconFont or Enum.Font.GothamBold
    icon.TextSize = tonumber(opts.iconTextSize) or 14
    icon.Text = iconText
    icon.BorderSizePixel = 0
    icon.AutoButtonColor = true
    icon.ZIndex = tonumber(opts.iconZIndex) or 50
    icon.Visible = false
    icon.Parent = iconParent
    Instance.new("UICorner", icon).CornerRadius = UDim.new(0, math.clamp(math.floor(iconH * 0.2), 4, 10))
    local stroke = Instance.new("UIStroke")
    stroke.Color = opts.iconStrokeColor or Color3.fromRGB(28, 32, 48)
    stroke.Thickness = 1
    stroke.Parent = icon

    local saved = getSavedStateEntry(key)
    local restorePos = frame.Position
    if saved and tonumber(saved.x) and tonumber(saved.y) then
        restorePos = UDim2.new(0, math.floor(saved.x), 0, math.floor(saved.y))
    elseif type(opts.restorePos) == "table" and tonumber(opts.restorePos.x) and tonumber(opts.restorePos.y) then
        restorePos = UDim2.new(0, math.floor(opts.restorePos.x), 0, math.floor(opts.restorePos.y))
    elseif typeof(opts.restorePos) == "UDim2" then
        restorePos = UDim2.new(0, opts.restorePos.X.Offset, 0, opts.restorePos.Y.Offset)
    end

    local minimized = false
    if type(opts.startMinimized) == "boolean" then
        minimized = opts.startMinimized
    elseif saved and saved.state == "minimizado" then
        minimized = true
    elseif opts.stateKey and _G.KAHWindowState and _G.KAHWindowState.get then
        local st = _G.KAHWindowState.get(opts.stateKey, nil)
        minimized = (st == "minimizado")
    end

    local conns = {}
    local dragging = false
    local dragMoved = false
    local dragStartPos = nil
    local iconStartPos = nil

    local controller = {
        key = key,
        frame = frame,
        _icon = icon,
        _conns = conns,
        _destroyed = false,
    }

    local function persistState()
        local stateLabel = minimized and "minimizado" or "maximizado"
        if remember then
            setSavedStateEntry(key, {
                state = stateLabel,
                x = restorePos.X.Offset,
                y = restorePos.Y.Offset,
                updatedAt = os.clock(),
            })
        end
        if opts.stateKey and _G.KAHWindowState and _G.KAHWindowState.set then
            _G.KAHWindowState.set(opts.stateKey, stateLabel)
        end
    end

    local function applyVisual()
        if controller._destroyed then
            return
        end
        if minimized then
            local x, y = clampIconPos(restorePos.X.Offset, restorePos.Y.Offset, iconW, iconH)
            icon.Position = UDim2.new(0, x, 0, y)
            icon.Visible = true
            if hideFrame then
                frame.Visible = false
            end
        else
            icon.Visible = false
            restorePos = clampFramePos(restorePos, frame)
            frame.Position = restorePos
            frame.Visible = true
        end
        if type(opts.onStateChange) == "function" then
            pcall(opts.onStateChange, minimized, minimized and "minimizado" or "maximizado", frame, icon)
        end
    end

    function controller.isMinimized()
        return minimized == true
    end

    function controller.minimize()
        if controller._destroyed or minimized then
            return
        end
        restorePos = frame.Position
        minimized = true
        persistState()
        applyVisual()
    end

    function controller.restore()
        if controller._destroyed or (not minimized) then
            return
        end
        minimized = false
        persistState()
        applyVisual()
    end

    function controller.toggle()
        if minimized then
            controller.restore()
        else
            controller.minimize()
        end
    end

    function controller.syncPositionFromFrame()
        if controller._destroyed then
            return
        end
        if not minimized then
            restorePos = frame.Position
            persistState()
        end
    end

    function controller.setRestorePos(pos)
        if controller._destroyed then
            return
        end
        if typeof(pos) == "UDim2" then
            restorePos = UDim2.new(0, pos.X.Offset, 0, pos.Y.Offset)
        elseif type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) then
            restorePos = UDim2.new(0, math.floor(pos.x), 0, math.floor(pos.y))
        end
        persistState()
        applyVisual()
    end

    function controller.destroy(reason)
        destroyController(controller, reason or "manual")
    end

    table.insert(conns, icon.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragMoved = false
            dragStartPos = i.Position
            iconStartPos = icon.Position
        end
    end))

    table.insert(conns, UIS.InputChanged:Connect(function(i)
        if not dragging then
            return
        end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local d = i.Position - dragStartPos
        local nx = iconStartPos.X.Offset + d.X
        local ny = iconStartPos.Y.Offset + d.Y
        nx, ny = clampIconPos(nx, ny, iconW, iconH)
        icon.Position = UDim2.new(0, nx, 0, ny)
        if math.abs(d.X) > 4 or math.abs(d.Y) > 4 then
            dragMoved = true
        end
    end))

    table.insert(conns, UIS.InputEnded:Connect(function(i)
        if not dragging then
            return
        end
        if i.UserInputType ~= Enum.UserInputType.MouseButton1 and i.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        dragging = false
        local nx, ny = clampIconPos(icon.Position.X.Offset, icon.Position.Y.Offset, iconW, iconH)
        icon.Position = UDim2.new(0, nx, 0, ny)
        if dragMoved then
            restorePos = UDim2.new(0, nx, 0, ny)
            persistState()
            return
        end
        controller.toggle()
    end))

    table.insert(conns, frame.Destroying:Connect(function()
        destroyController(controller, "frame_destroyed")
    end))

    controllers[key] = controller
    persistState()
    applyVisual()
    return controller
end

local function unregisterMiniWindow(key)
    local id = tostring(key or "")
    if id == "" then
        return false
    end
    local ctrl = controllers[id]
    if not ctrl then
        return false
    end
    destroyController(ctrl, "unregister")
    return true
end

local function getMiniWindow(key)
    local id = tostring(key or "")
    if id == "" then
        return nil
    end
    return controllers[id]
end

local function cleanupMiniWindowApi(reason)
    for key, ctrl in pairs(controllers) do
        if controllers[key] == ctrl then
            destroyController(ctrl, reason or "cleanup")
        end
    end
end

local oldApi = _G.KAHMiniWindowAPI
if type(oldApi) == "table" and type(oldApi.cleanup) == "function" then
    pcall(oldApi.cleanup, "reload")
end

_G.KAHMiniWindowAPI = {
    version = VERSION,
    register = registerMiniWindow,
    unregister = unregisterMiniWindow,
    get = getMiniWindow,
    cleanup = cleanupMiniWindowApi,
}

_G[API_KEY] = _G.KAHMiniWindowAPI
