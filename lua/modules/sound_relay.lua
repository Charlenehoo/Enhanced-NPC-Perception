-- lua/modules/sound_relay.lua

local ProxyManager = ProxyManager
local PROXY_CLASS = ProxyManager.PROXY_CLASS
local DEBUG = ProxyManager.DEBUG or false

local IsValid = IsValid

-- 辅助函数：获取受害者对应的所有代理实体
local function GetProxiesByVictim(victim)
    local proxies = {}
    local view = ProxyManager.GetAttackerProxyMapView(victim)
    if view then
        for attacker, proxy in view.GetIterator() do
            table.insert(proxies, proxy)
        end
    end
    return proxies
end

local function Deserialize(data)
    return data.SoundName, data.SoundLevel, data.Pitch, 0,
        data.Channel, data.Flags, data.DSP
end

local function DebugPrint(data, victim, proxies)
    if DEBUG then
        print(string.format("[SNT_SoundRelay] Relaying sound '%s' from victim %d to %d proxies",
            data.SoundName, victim:EntIndex(), #proxies))
    end
end

hook.Add("EntityEmitSound", "SNT_EntityEmitSound", function(data)
    local entity = data.Entity
    if not IsValid(entity) or entity:GetClass() == PROXY_CLASS then
        return -- 忽略代理自身发出的声音
    end

    local victim
    if ProxyManager.IsVictim(entity) then
        victim = entity
    elseif ProxyManager.IsVictim(entity:GetOwner()) then
        victim = entity:GetOwner()
    else
        return
    end

    local proxies = GetProxiesByVictim(victim)

    DebugPrint(data, victim, proxies)

    for _, proxy in ipairs(proxies) do
        -- 原样传递声音参数
        proxy:EmitSound(
            Deserialize(data)
        )
    end
end)
