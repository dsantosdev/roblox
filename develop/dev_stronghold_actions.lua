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
        local ok, ret = callStateFn(st, "teleportDev", tostring(kind or ""))
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

    function api.available()
        return getStrongState() ~= nil
    end

    return api
end

return M
