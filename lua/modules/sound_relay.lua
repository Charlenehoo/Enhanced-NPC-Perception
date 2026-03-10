-- lua/modules/sound_relay.lua

local ProxyManager = ProxyManager
local PROXY_CLASS = ProxyManager.PROXY_CLASS

-- 辅助函数：获取受害者对应的所有代理实体
local function GetProxiesForVictim(victim)
    local proxies = {}
    local view = ProxyManager.GetAttackerProxyMapView(victim)
    if view then
        for attacker, proxy in view.GetIterator() do
            table.insert(proxies, proxy)
        end
    end
    return proxies
end

hook.Add("EntityEmitSound", "SNT_EntityEmitSound", function(data)
    local entity = data.Entity
    if not IsValid(entity) or entity:GetClass() == PROXY_CLASS then
        return     -- 忽略代理自身发出的声音
    end

    -- 尝试找到该实体作为受害者（或受害者持有物）对应的代理
    -- 注意：遍历所有受害者可能效率较低，但受害者数量通常有限
    for victim, _ in ProxyManager.IterateVictimsWithAttackerProxyMapView() do
        if entity == victim or entity:GetOwner() == victim then
            local proxies = GetProxiesForVictim(victim)
            for _, proxy in ipairs(proxies) do
                -- 原样传递声音参数
                proxy:EmitSound(
                    data.SoundName,
                    data.SoundLevel,
                    data.Pitch,
                    data.Channel or 0,
                    data.Flags or 0,
                    data.DSP or 0
                )
            end
            return     -- 最多匹配一个受害者，找到后立即返回
        end
    end
end)
