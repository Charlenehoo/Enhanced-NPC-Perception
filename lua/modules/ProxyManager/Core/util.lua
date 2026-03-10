-- lua\modules\ProxyManager\util.lua
ProxyManager = ProxyManager or {}
local DEFAULT_ATTACKER_CLASS_PATTERN = ProxyManager.DEFAULT_ATTACKER_CLASS_PATTERN
local CREATE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX = ProxyManager.CREATE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX
local REMOVE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX = ProxyManager.REMOVE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX

local IsValid = IsValid

function ProxyManager.CheckOrphanProxy(proxy)
    assert(IsValid(proxy), "Proxy entity is invalid in CheckOrphanProxy") -- 代理无效则崩溃
    if IsValid(proxy.victim) and IsValid(proxy.attacker) then
        return false                                                      -- 正常，不移除
    end
    ProxyManager.RemoveProxy(proxy.victim, proxy.attacker)
    return true -- 已移除，调用者应跳过本次迭代
end

function ProxyManager.CreateProxiesForVictimByClass(victim, classNamePattern)
    local classNamePattern = classNamePattern or DEFAULT_ATTACKER_CLASS_PATTERN
    for i, attacker in ipairs(ents.FindByClass(classNamePattern)) do
        ProxyManager.CreateProxy(victim, attacker)
    end
end

function ProxyManager.RemoveProxiesForVictimByClass(victim, classNamePattern)
    local classNamePattern = classNamePattern or DEFAULT_ATTACKER_CLASS_PATTERN
    for i, attacker in ipairs(ents.FindByClass(classNamePattern)) do
        ProxyManager.RemoveProxy(victim, attacker)
    end
end

local function GetCreateProxiesDelayedTimerIdentifier(victim)
    return string.format("%s%d", CREATE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX, victim:EntIndex())
end

local function GetRemoveProxiesDelayedTimerIdentifier(victim)
    return string.format("%s%d", REMOVE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX, victim:EntIndex())
end

function ProxyManager.CancelCreateProxiesDelayed(victim)
    if not IsValid(victim) then return false end

    local timerIdentifier = GetCreateProxiesDelayedTimerIdentifier(victim)
    if timer.Exists(timerIdentifier) then
        timer.Remove(timerIdentifier)
        return true
    end
    return false
end

function ProxyManager.CancelRemoveProxiesDelayed(victim)
    if not IsValid(victim) then return end

    local timerIdentifier = GetRemoveProxiesDelayedTimerIdentifier(victim)
    if timer.Exists(timerIdentifier) then
        timer.Remove(timerIdentifier)
        return true
    end
    return false
end

function ProxyManager.CreateProxiesDelayed(victim, delay)
    if not IsValid(victim) then return end

    ProxyManager.CancelRemoveProxiesDelayed(victim)

    local timerIdentifier = GetCreateProxiesDelayedTimerIdentifier(victim)
    if timer.Exists(timerIdentifier) then
        return
    end

    timer.Create(timerIdentifier, delay, 1, function()
        if IsValid(victim) then
            ProxyManager.CreateProxiesForVictimByClass(victim)
        end
    end)
end

function ProxyManager.RemoveProxiesDelayed(victim, delay)
    if not IsValid(victim) then return end

    ProxyManager.CancelCreateProxiesDelayed(victim)

    local timerIdentifier = GetRemoveProxiesDelayedTimerIdentifier(victim)
    if timer.Exists(timerIdentifier) then
        return
    end

    timer.Create(timerIdentifier, delay, 1, function()
        if IsValid(victim) then
            ProxyManager.RemoveProxiesForVictimByClass(victim)
        end
    end)
end
