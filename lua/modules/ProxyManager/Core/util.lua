-- lua\modules\ProxyManager\util.lua
ProxyManager = ProxyManager or {}

local IsValid = IsValid

function ProxyManager.CheckOrphanProxy(proxy)
    if not IsValid(proxy) then return end
    if IsValid(proxy.victim) and IsValid(proxy.attacker) then return end
    ProxyManager.RemoveProxy(proxy.victim, proxy.attacker)
end
