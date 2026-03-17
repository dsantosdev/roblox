local M = {}

local function safeStatus(ctx, msg, color)
    if type(ctx) ~= "table" then return end
    if type(ctx.setStatus) ~= "function" then return end
    pcall(ctx.setStatus, tostring(msg or ""), color)
end

local function getStrongState()
    local st = _G.__stronghold_module_state
    if type(st) == "table" then
        return st
    end
    return nil
end

local function callStateFn(st, fnName, ...)
    local fn = st and st[fnName]
    if type(fn) ~= "function" then
        return false, "missing"
    end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        return false, a
    end
    return true, a, b, c
end

local function getChestModelByName(name)
    local items = workspace:FindFirstChild("Items")
    local found = (items and items:FindFirstChild(name, true))
        or workspace:FindFirstChild(name, true)
    if not found then
        return nil
    end
    local cur = found
    while cur and cur ~= workspace do
        if cur:IsA("Model") then
            return cur
        end
        cur = cur.Parent
    end
    return nil
end

local function getInstanceBounds(inst)
    if not inst then
        return nil, nil
    end
    if inst:IsA("Model") then
        local ok, cf, size = pcall(function()
            return inst:GetBoundingBox()
        end)
        if ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
            return cf, size
        end
        local part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part.CFrame, part.Size
        end
        return nil, nil
    end
    if inst:IsA("BasePart") then
        return inst.CFrame, inst.Size
    end
    return nil, nil
end

local function flatUnit(vec, fallback)
    local v = Vector3.new(vec.X, 0, vec.Z)
    if v.Magnitude < 0.01 then
        return fallback
    end
    return v.Unit
end

local function computeDiamondFrontPos(sourcePos)
    local chest = getChestModelByName("Stronghold Diamond Chest")
    if not chest then
        return nil, nil
    end
    local cf, size = getInstanceBounds(chest)
    if typeof(cf) ~= "CFrame" then
        return nil, nil
    end

    local bbox = typeof(size) == "Vector3" and size or Vector3.new(4, 4, 4)
    local look = flatUnit(cf.LookVector, Vector3.new(0, 0, -1))
    local right = flatUnit(cf.RightVector, Vector3.new(1, 0, 0))

    local pad = tonumber(_G.KAH_DEV_STRONG_DIAMOND_FRONT_PAD) or 4.5
    local yOffset = tonumber(_G.KAH_DEV_STRONG_DIAMOND_FRONT_Y) or 1.8
    local halfLook = math.max(bbox.Z * 0.5, 1)
    local halfRight = math.max(bbox.X * 0.5, 1)
    local center = cf.Position

    local candidates = {
        center - look * (halfLook + pad),
        center + look * (halfLook + pad),
        center - right * (halfRight + pad),
        center + right * (halfRight + pad),
    }

    local ref = typeof(sourcePos) == "Vector3" and sourcePos or center
    local best = nil
    local bestDist = nil
    for _, c in ipairs(candidates) do
        local pos = Vector3.new(c.X, center.Y + yOffset, c.Z)
        local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(ref.X, 0, ref.Z)).Magnitude
        if not bestDist or d < bestDist then
            best = pos
            bestDist = d
        end
    end
    return best, center
end

function M.new(ctx)
    ctx = type(ctx) == "table" and ctx or {}
    local C = type(ctx.colors) == "table" and ctx.colors or {}

    local api = {}

    function api.getStepLabels()
        local st = getStrongState()
        if not st then
            return nil
        end
        local ok, labels = callStateFn(st, "getStepLabels")
        if not ok or type(labels) ~= "table" then
            return nil
        end
        return labels
    end

    function api.step(i)
        local idx = math.floor(tonumber(i) or 0)
        if idx < 1 then
            safeStatus(ctx, "Passo invalido.", C.yellow)
            return false
        end
        local st = getStrongState()
        if not st then
            safeStatus(ctx, "Stronghold module nao carregado.", C.red)
            return false
        end
        local ok, ret, err = callStateFn(st, "runStep", idx)
        if not ok or ret == false then
            safeStatus(ctx, "Falha ao acionar passo " .. tostring(idx) .. ".", C.red)
            return false, err
        end
        safeStatus(ctx, "Passo " .. tostring(idx) .. " acionado.", C.green)
        return true
    end

    function api.runAll()
        local st = getStrongState()
        if not st then
            safeStatus(ctx, "Stronghold module nao carregado.", C.red)
            return false
        end
        local ok, ret = callStateFn(st, "runAll")
        if not ok or ret == false then
            safeStatus(ctx, "Falha ao acionar run all.", C.red)
            return false
        end
        safeStatus(ctx, "Fluxo completo acionado.", C.green)
        return true
    end

    function api.stop()
        local st = getStrongState()
        if not st then
            safeStatus(ctx, "Stronghold module nao carregado.", C.red)
            return false
        end
        local ok, ret = callStateFn(st, "stop")
        if not ok then
            safeStatus(ctx, "Falha ao parar Stronghold.", C.red)
            return false
        end
        if ret then
            safeStatus(ctx, "Stronghold parado.", C.yellow)
        else
            safeStatus(ctx, "Stronghold ja estava parado.", C.muted or C.text)
        end
        return true
    end

    function api.teleport(kind, label)
        local st = getStrongState()
        if not st then
            safeStatus(ctx, "Stronghold module nao carregado.", C.red)
            return false
        end
        local sourcePos = nil
        do
            local player = ctx.player
            local ch = player and player.Character
            local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
            sourcePos = root and root.Position or nil
        end
        local ok, ret = callStateFn(st, "teleportDev", tostring(kind or ""))
        if not ok or ret == false then
            safeStatus(ctx, "Falha no teleport: " .. tostring(label or kind), C.red)
            return false
        end
        if tostring(kind) == "diamond" then
            local player = ctx.player
            local ch = player and player.Character
            local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
            if root and typeof(root.CFrame) == "CFrame" then
                local frontPos, lookAt = computeDiamondFrontPos(sourcePos)
                pcall(function()
                    if frontPos and typeof(lookAt) == "Vector3" then
                        root.CFrame = CFrame.new(frontPos, lookAt)
                    end
                    if root:IsA("BasePart") then
                        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    end
                end)
            end
            safeStatus(ctx, "Teleportado: " .. tostring(label or kind) .. " (frente/dev)", C.green)
            return true
        end
        safeStatus(ctx, "Teleportado: " .. tostring(label or kind), C.green)
        return true
    end

    function api.pingDiamond()
        local st = getStrongState()
        if not st then
            safeStatus(ctx, "Stronghold module nao carregado.", C.red)
            return false
        end
        local ok, ret = callStateFn(st, "pingDiamond")
        if not ok or ret == false then
            safeStatus(ctx, "Falha ao pingar Diamond Chest.", C.red)
            return false
        end
        safeStatus(ctx, "Diamond Chest pingado.", C.green)
        return true
    end

    function api.available()
        return getStrongState() ~= nil
    end

    return api
end

return M
