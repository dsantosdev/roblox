local M = {}
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

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

local function getLocalRootFromCtx(ctx)
    local player = (type(ctx) == "table" and ctx.player) or Players.LocalPlayer
    local ch = player and player.Character
    if not ch then
        return nil
    end
    return ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
end

local function copyToClipboard(text)
    local payload = tostring(text or "")
    if setclipboard then
        local ok = pcall(setclipboard, payload)
        if ok then
            return true
        end
    end
    if toclipboard then
        local ok = pcall(toclipboard, payload)
        if ok then
            return true
        end
    end
    return false
end

local function trimInline(v)
    return tostring(v or ""):gsub("[%c]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function vec3ToLine(v)
    if typeof(v) ~= "Vector3" then
        return "nil"
    end
    return string.format("(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
end

local function getModelRoot(model)
    if not model or not model:IsA("Model") then
        return nil
    end
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function isMobCandidate(model)
    if not model or not model:IsA("Model") then
        return false, nil
    end
    if Players:GetPlayerFromCharacter(model) then
        return false, nil
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then
        return false, nil
    end
    return true, hum
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
    local scanner = {
        running = false,
        startedAtClock = 0,
        sessionId = 0,
        conns = {},
        events = {},
        byName = {},
        byBetween = {},
        seenModels = setmetatable({}, { __mode = "k" }),
    }

    local function disconnectScanner()
        for _, c in ipairs(scanner.conns) do
            pcall(function()
                c:Disconnect()
            end)
        end
        scanner.conns = {}
    end

    local function resetScannerData()
        scanner.events = {}
        scanner.byName = {}
        scanner.byBetween = {}
        scanner.seenModels = setmetatable({}, { __mode = "k" })
    end

    local function getStrongFlowInfo()
        local st = getStrongState()
        if not st then
            return {
                running = false,
                currentIdx = 0,
                currentLabel = "",
                lastCompletedIdx = 0,
                lastCompletedLabel = "",
                debugTrying = "",
                debugDone = "",
                debugNext = "",
            }
        end
        local ok, info = callStateFn(st, "getFlowStepInfo")
        if not ok or type(info) ~= "table" then
            return {
                running = false,
                currentIdx = 0,
                currentLabel = "",
                lastCompletedIdx = 0,
                lastCompletedLabel = "",
                debugTrying = "",
                debugDone = "",
                debugNext = "",
            }
        end
        return info
    end

    local function buildBetweenLabel(flowInfo)
        local cur = math.max(0, math.floor(tonumber(flowInfo.currentIdx) or 0))
        local last = math.max(0, math.floor(tonumber(flowInfo.lastCompletedIdx) or 0))
        if cur > 0 and last > 0 and cur ~= last then
            return string.format("entre passo %d->%d", last, cur)
        end
        if cur > 0 then
            return string.format("durante passo %d", cur)
        end
        if last > 0 then
            return string.format("apos passo %d", last)
        end
        return "fora do fluxo"
    end

    local function getPosFromModel(model)
        local root = getModelRoot(model)
        if root then
            return root.Position
        end
        local ok, cf = pcall(function()
            return model:GetPivot()
        end)
        if ok and typeof(cf) == "CFrame" then
            return cf.Position
        end
        return nil
    end

    local function addMobEvent(model, reason)
        if not scanner.running then
            return false
        end
        if not model or not model.Parent or not model:IsA("Model") then
            return false
        end
        if scanner.seenModels[model] then
            return false
        end
        local okMob, hum = isMobCandidate(model)
        if not okMob then
            return false
        end

        scanner.seenModels[model] = true
        local flowInfo = getStrongFlowInfo()
        local between = buildBetweenLabel(flowInfo)
        local pos = getPosFromModel(model)
        local localRoot = getLocalRootFromCtx(ctx)
        local dist = nil
        if typeof(pos) == "Vector3" and localRoot then
            dist = (pos - localRoot.Position).Magnitude
        end
        local fullPath = "?"
        local parentPath = "?"
        pcall(function()
            fullPath = model:GetFullName()
        end)
        pcall(function()
            parentPath = model.Parent and model.Parent:GetFullName() or "?"
        end)

        local ev = {
            idx = #scanner.events + 1,
            t = os.clock(),
            reason = tostring(reason or "spawn"),
            name = tostring(model.Name or "?"),
            fullPath = tostring(fullPath or "?"),
            parentPath = tostring(parentPath or "?"),
            pos = pos,
            dist = dist,
            health = hum and tonumber(hum.Health) or nil,
            maxHealth = hum and tonumber(hum.MaxHealth) or nil,
            between = between,
            stepCurrent = math.max(0, math.floor(tonumber(flowInfo.currentIdx) or 0)),
            stepCurrentLabel = trimInline(flowInfo.currentLabel),
            stepLast = math.max(0, math.floor(tonumber(flowInfo.lastCompletedIdx) or 0)),
            stepLastLabel = trimInline(flowInfo.lastCompletedLabel),
            debugTrying = trimInline(flowInfo.debugTrying),
            debugDone = trimInline(flowInfo.debugDone),
            debugNext = trimInline(flowInfo.debugNext),
            strongRunning = flowInfo.running == true,
        }
        table.insert(scanner.events, ev)
        scanner.byName[ev.name] = (scanner.byName[ev.name] or 0) + 1
        scanner.byBetween[between] = (scanner.byBetween[between] or 0) + 1
        return true
    end

    local function bindScannerContainer(label, container)
        if not container then
            return
        end
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Model") then
                addMobEvent(child, label .. ":existing")
            end
        end
        table.insert(scanner.conns, container.ChildAdded:Connect(function(child)
            if child and child:IsA("Model") then
                addMobEvent(child, label .. ":child_added")
            end
        end))
    end

    local function buildScannerReport()
        local player = ctx.player or Players.LocalPlayer
        local flowNow = getStrongFlowInfo()
        local duration = 0
        if tonumber(scanner.startedAtClock) and scanner.startedAtClock > 0 then
            duration = os.clock() - scanner.startedAtClock
        end

        local lines = {}
        lines[#lines + 1] = "DEV_STRONG_MOB_SCANNER"
        lines[#lines + 1] = string.format(
            "session=%d | place=%s | job=%s | user=%s(%d)",
            tonumber(scanner.sessionId) or 0,
            tostring(game.PlaceId),
            tostring(game.JobId),
            tostring(player and player.Name or "?"),
            tonumber(player and player.UserId or 0)
        )
        lines[#lines + 1] = string.format(
            "started_clock=%.3f | duration_sec=%.3f | total_events=%d",
            tonumber(scanner.startedAtClock) or 0,
            tonumber(duration) or 0,
            #scanner.events
        )
        lines[#lines + 1] = string.format(
            "flow_now cur=%d:%s | last=%d:%s | running=%s",
            math.max(0, math.floor(tonumber(flowNow.currentIdx) or 0)),
            trimInline(flowNow.currentLabel),
            math.max(0, math.floor(tonumber(flowNow.lastCompletedIdx) or 0)),
            trimInline(flowNow.lastCompletedLabel),
            tostring(flowNow.running == true)
        )
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[BY_NAME]"
        do
            local names = {}
            for name, _ in pairs(scanner.byName) do
                names[#names + 1] = name
            end
            table.sort(names, function(a, b)
                return tostring(a):lower() < tostring(b):lower()
            end)
            if #names == 0 then
                lines[#lines + 1] = "none=0"
            else
                for _, name in ipairs(names) do
                    lines[#lines + 1] = string.format("%s=%d", trimInline(name), tonumber(scanner.byName[name]) or 0)
                end
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[BY_BETWEEN_STEP]"
        do
            local ranges = {}
            for key, _ in pairs(scanner.byBetween) do
                ranges[#ranges + 1] = key
            end
            table.sort(ranges, function(a, b)
                return tostring(a):lower() < tostring(b):lower()
            end)
            if #ranges == 0 then
                lines[#lines + 1] = "none=0"
            else
                for _, key in ipairs(ranges) do
                    lines[#lines + 1] = string.format("%s=%d", trimInline(key), tonumber(scanner.byBetween[key]) or 0)
                end
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[EVENTS]"
        if #scanner.events == 0 then
            lines[#lines + 1] = "(no events)"
        else
            for _, ev in ipairs(scanner.events) do
                lines[#lines + 1] = string.format(
                    "#%d t=%.3f name=%s reason=%s between=%s cur=%d:%s last=%d:%s pos=%s dist=%.1f hp=%.1f/%.1f parent=%s full=%s dbg_try=%s dbg_next=%s",
                    tonumber(ev.idx) or 0,
                    tonumber(ev.t) or 0,
                    trimInline(ev.name),
                    trimInline(ev.reason),
                    trimInline(ev.between),
                    tonumber(ev.stepCurrent) or 0,
                    trimInline(ev.stepCurrentLabel),
                    tonumber(ev.stepLast) or 0,
                    trimInline(ev.stepLastLabel),
                    vec3ToLine(ev.pos),
                    tonumber(ev.dist) or -1,
                    tonumber(ev.health) or -1,
                    tonumber(ev.maxHealth) or -1,
                    trimInline(ev.parentPath),
                    trimInline(ev.fullPath),
                    trimInline(ev.debugTrying),
                    trimInline(ev.debugNext)
                )
            end
        end

        local jsonRows = {}
        for _, ev in ipairs(scanner.events) do
            local pos = nil
            if typeof(ev.pos) == "Vector3" then
                pos = { x = ev.pos.X, y = ev.pos.Y, z = ev.pos.Z }
            end
            jsonRows[#jsonRows + 1] = {
                idx = ev.idx,
                t = ev.t,
                name = ev.name,
                reason = ev.reason,
                between = ev.between,
                stepCurrent = ev.stepCurrent,
                stepCurrentLabel = ev.stepCurrentLabel,
                stepLast = ev.stepLast,
                stepLastLabel = ev.stepLastLabel,
                pos = pos,
                dist = ev.dist,
                health = ev.health,
                maxHealth = ev.maxHealth,
                parentPath = ev.parentPath,
                fullPath = ev.fullPath,
                strongRunning = ev.strongRunning,
            }
        end
        local encoded = nil
        pcall(function()
            encoded = HttpService:JSONEncode({
                sessionId = scanner.sessionId,
                placeId = game.PlaceId,
                jobId = game.JobId,
                userId = player and player.UserId or nil,
                byName = scanner.byName,
                byBetween = scanner.byBetween,
                events = jsonRows,
            })
        end)
        if type(encoded) == "string" and #encoded > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "[JSON]"
            lines[#lines + 1] = encoded
        end

        return table.concat(lines, "\n")
    end

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

    function api.startMobScanner()
        if scanner.running then
            safeStatus(ctx, "Mob scanner ja esta ativo.", C.yellow)
            return true
        end
        disconnectScanner()
        resetScannerData()
        scanner.running = true
        scanner.sessionId = (tonumber(scanner.sessionId) or 0) + 1
        scanner.startedAtClock = os.clock()

        bindScannerContainer("workspace.Characters", workspace:FindFirstChild("Characters"))
        bindScannerContainer("workspace.Enemies", workspace:FindFirstChild("Enemies"))
        bindScannerContainer("workspace.NPCs", workspace:FindFirstChild("NPCs"))

        table.insert(scanner.conns, workspace.DescendantAdded:Connect(function(obj)
            if not scanner.running then
                return
            end
            if obj:IsA("Model") then
                addMobEvent(obj, "workspace:desc_model")
                return
            end
            if obj:IsA("Humanoid") then
                local model = obj.Parent
                if model and model:IsA("Model") then
                    addMobEvent(model, "workspace:desc_humanoid")
                end
            end
        end))

        safeStatus(ctx, "Mob scanner iniciado.", C.green)
        return true
    end

    function api.stopMobScanner()
        if not scanner.running then
            safeStatus(ctx, "Mob scanner nao estava ativo.", C.yellow)
            return false
        end
        scanner.running = false
        disconnectScanner()

        local report = buildScannerReport()
        local copied = copyToClipboard(report)
        if copied then
            safeStatus(
                ctx,
                "Mob scanner parado. Relatorio copiado (" .. tostring(#scanner.events) .. " eventos).",
                C.green
            )
        else
            safeStatus(
                ctx,
                "Mob scanner parado. Sem clipboard (" .. tostring(#scanner.events) .. " eventos).",
                C.yellow
            )
        end
        return true, report, copied
    end

    function api.mobScannerStatus()
        return {
            running = scanner.running == true,
            total = #scanner.events,
            sessionId = scanner.sessionId,
            startedAtClock = scanner.startedAtClock,
        }
    end

    function api.available()
        return getStrongState() ~= nil
    end

    return api
end

return M
