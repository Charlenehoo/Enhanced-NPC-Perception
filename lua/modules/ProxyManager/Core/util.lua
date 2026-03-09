-- lua\modules\ProxyManager\util.lua
ProxyManager = ProxyManager or {}
local DEFAULT_ATTACKER_CLASS_PATTERN = ProxyManager.DEFAULT_ATTACKER_CLASS_PATTERN
local REMOVE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX = ProxyManager.REMOVE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX

local IsValid = IsValid

function ProxyManager.CheckOrphanProxy(proxy)
    if not IsValid(proxy) then return end
    if IsValid(proxy.victim) and IsValid(proxy.attacker) then return end
    ProxyManager.RemoveProxy(proxy.victim, proxy.attacker)
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

local function GetRemoveProxiesDelayedTimerIdentifier(victim)
    return string.format("%s%d", REMOVE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX, victim:EntIndex())
end

function ProxyManager.CancelRemoveProxiesDelayed(victim)
    if not IsValid(victim) then
        return
    end

    local timerIdentifier = GetRemoveProxiesDelayedTimerIdentifier(victim)
    timer.Remove(timerIdentifier)
end

function ProxyManager.CreateProxiesDelayed(victim, delay)
    ProxyManager.CancelRemoveProxiesDelayed(victim)
    timer.Simple(delay, function()
        ProxyManager.CreateProxiesForVictimByClass(victim)
    end)
end

function ProxyManager.RemoveProxiesDelayed(victim, delay)
    if not IsValid(victim) then
        return
    end

    local timerIdentifier = GetRemoveProxiesDelayedTimerIdentifier(victim)
    if timer.Exists(timerIdentifier) then
        return
    end

    timer.Create(timerIdentifier, delay, 1, function()
        ProxyManager.RemoveProxiesForVictimByClass(victim)
    end)
end
