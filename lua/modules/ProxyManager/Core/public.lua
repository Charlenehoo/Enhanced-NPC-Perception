-- lua\modules\ProxyManager\Core\public.lua
ProxyManager = ProxyManager or {}
ProxyManager._private = ProxyManager._private or {}

local IsValid = IsValid

function ProxyManager.CreateProxy(victim, attacker) return ProxyManager._private._CreateProxy(victim, attacker) end

function ProxyManager.RemoveProxy(victim, attacker) return ProxyManager._private._RemoveProxy(victim, attacker) end

function ProxyManager.GetAttackerProxyMapView(victim) return ProxyManager._private._GetAttackerProxyMapView(victim) end

function ProxyManager.GetVictimProxyMapView(attacker) return ProxyManager._private._GetVictimProxyMapView(attacker) end

function ProxyManager.IterateVictimsWithAttackerProxyMapView()
    return ProxyManager._private._IterateVictimsWithAttackerProxyMapView()
end

function ProxyManager.MoveProxies(oldVictim, newVictim)
    return ProxyManager._private._MoveProxies(oldVictim,
        newVictim)
end

function ProxyManager.RemoveAllProxiesByVictim(victim)
    if not victim then return end
    local view = ProxyManager.GetAttackerProxyMapView(victim) -- 只读视图

    local attackers = {}
    for attacker, _ in view.GetIterator() do
        table.insert(attackers, attacker)
    end
    for _, attacker in ipairs(attackers) do
        ProxyManager.RemoveProxy(victim, attacker)
    end
end

function ProxyManager.RemoveAllProxiesByAttacker(attacker)
    if not IsValid(attacker) then return end
    local view = ProxyManager.GetVictimProxyMapView(attacker)

    local victims = {}
    for victim, _ in view.GetIterator() do
        table.insert(victims, victim)
    end
    for _, victim in ipairs(victims) do
        ProxyManager.RemoveProxy(victim, attacker)
    end
end
