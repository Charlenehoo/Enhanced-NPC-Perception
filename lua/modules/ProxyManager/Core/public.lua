-- lua\modules\ProxyManager\Core\public.lua
ProxyManager = ProxyManager or {}

local _private = require("modules.ProxyManager.Core.private")
local IsValid = IsValid

function ProxyManager.CreateProxy(victim, attacker) return _private._CreateProxyImpl(victim, attacker) end

function ProxyManager.RemoveProxy(victim, attacker) return _private._RemoveProxyImpl(victim, attacker) end

function ProxyManager.GetAttackerProxyMapView(victim) return _private._GetAttackerProxyMapViewImpl(victim) end

function ProxyManager.MoveProxy(oldVictim, newVictim) return _private._MoveProxiesImpl(oldVictim, newVictim) end

function ProxyManager.RemoveAllProxiesByVictim(victim)
    if not victim then return end
    local view = ProxyManager.GetAttackerProxyMapView(victim) -- 只读视图
    -- 收集所有攻击者（遍历过程中会修改表，需提前收集）
    local attackers = {}
    for attacker, _ in pairs(view) do
        table.insert(attackers, attacker)
    end
    for _, attacker in ipairs(attackers) do
        ProxyManager.RemoveProxy(victim, attacker)
    end
end

function ProxyManager.IterateVictims() return _private._IterateVictimsImpl() end
