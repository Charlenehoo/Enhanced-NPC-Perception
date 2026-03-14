-- lua\modules\ProxyManager\util.lua
ProxyManager = ProxyManager or {}
local PROXY_FIELDS = ProxyManager.PROXY_FIELDS
local DEFAULT_ATTACKER_CLASS_PATTERN = ProxyManager.DEFAULT_ATTACKER_CLASS_PATTERN
local CREATE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX = ProxyManager.CREATE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX
local REMOVE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX = ProxyManager.REMOVE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX

local IsValid = IsValid

function ProxyManager.CheckOrphanProxy(proxy)
    assert(IsValid(proxy), "Proxy entity is invalid in CheckOrphanProxy")
    if IsValid(proxy[PROXY_FIELDS.VICTIM]) and IsValid(proxy[PROXY_FIELDS.ATTACKER]) then
        return false
    end
    ProxyManager.RemoveProxy(proxy[PROXY_FIELDS.VICTIM], proxy[PROXY_FIELDS.ATTACKER])
    return true
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
    if not IsValid(victim) then return false end

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
