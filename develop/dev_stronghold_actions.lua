local M = {}
local Players = game:GetService("Players")

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

local function getChestPromptWorldPos(chestModel)
    if not chestModel then
        return nil
    end
    local bestPos, bestDist = nil, nil
    local ref = nil
    local hrp = nil
    do
        local lp = Players.LocalPlayer
        local ch = lp and lp.Character
        hrp = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
    end
    ref = hrp and hrp.Position or nil

    for _, d in ipairs(chestModel:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local p = nil
            local parent = d.Parent
            if parent then
                if parent:IsA("Attachment") then
                    p = parent.WorldPosition
                elseif parent:IsA("BasePart") then
                    p = parent.Position
                else
                    local part = parent:FindFirstAncestorWhichIsA("BasePart")
                    if part then
                        p = part.Position
                    end
                end
            end
            if typeof(p) == "Vector3" then
                local dist = ref and (p - ref).Magnitude or 0
                if (not bestPos) or (dist < bestDist) then
                    bestPos = p
                    bestDist = dist
                end
            end
        end
    end
    return bestPos
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

    local pad = tonumber(_G.KAH_DEV_STRONG_DIAMOND_FRONT_PAD) or 4.5
    local yOffset = tonumber(_G.KAH_DEV_STRONG_DIAMOND_FRONT_Y) or 1.8
    local center = cf.Position
    local ref = typeof(sourcePos) == "Vector3" and sourcePos or center
    local look2D = flatUnit(cf.LookVector, Vector3.new(0, 0, -1))
    local promptPos = getChestPromptWorldPos(chest)

    if typeof(promptPos) == "Vector3" then
        local away = Vector3.new(promptPos.X - center.X, 0, promptPos.Z - center.Z)
        if away.Magnitude < 0.01 then
            away = look2D
        else
            away = away.Unit
        end
        local target = Vector3.new(
            promptPos.X + away.X * pad,
            promptPos.Y + yOffset,
            promptPos.Z + away.Z * pad
        )
        return target, promptPos
    end

    local bbox = typeof(size) == "Vector3" and size or Vector3.new(4, 4, 4)
    local halfLook = math.max(bbox.Z * 0.5, 1)
    local a = center - look2D * (halfLook + pad)
    local b = center + look2D * (halfLook + pad)
    local pick = ((a - ref).Magnitude <= (b - ref).Magnitude) and a or b
    local target = Vector3.new(pick.X, center.Y + yOffset, pick.Z)
    return target, center
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
        local kindStr = tostring(kind or "")
        if kindStr == "diamond" then
            local player = ctx.player
            local ch = player and player.Character
            local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
            local sourcePos = root and root.Position or nil
            local frontPos, lookAt = computeDiamondFrontPos(sourcePos)

            if root and frontPos then
                local targetCF = (typeof(lookAt) == "Vector3") and CFrame.new(frontPos, lookAt) or CFrame.new(frontPos)
                local function applyFrontTp()
                    root.CFrame = targetCF
                    if root:IsA("BasePart") then
                        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                    end
                end
                pcall(applyFrontTp)
                task.delay(0.06, function()
                    if root and root.Parent then
                        pcall(applyFrontTp)
                    end
                end)
                task.delay(0.18, function()
                    if root and root.Parent then
                        pcall(applyFrontTp)
                    end
                end)
                safeStatus(ctx, "Teleportado: " .. tostring(label or kind) .. " (frente/dev)", C.green)
                return true
            end

            -- Fallback se nao localizar o chest/bounds.
            local ok, ret = callStateFn(st, "teleportDev", kindStr)
            if not ok or ret == false then
                safeStatus(ctx, "Falha no teleport: " .. tostring(label or kind), C.red)
                return false
            end
            safeStatus(ctx, "Teleportado: " .. tostring(label or kind) .. " (fallback)", C.yellow)
            return true
        end

        local ok, ret = callStateFn(st, "teleportDev", kindStr)
        if not ok or ret == false then
            safeStatus(ctx, "Falha no teleport: " .. tostring(label or kind), C.red)
            return false
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

    function api.chestFarmBurst()
        local st = getStrongState()
        if not st then
            safeStatus(ctx, "Stronghold module nao carregado.", C.red)
            return false
        end
        local ok, ret = callStateFn(st, "chestFarmBurst")
        if not ok or ret == false then
            safeStatus(ctx, "Falha ao acionar Chest Farm Burst.", C.red)
            return false
        end
        safeStatus(ctx, "Chest Farm Burst acionado.", C.green)
        return true
    end

    function api.available()
        return getStrongState() ~= nil
    end

    return api
end

return M
