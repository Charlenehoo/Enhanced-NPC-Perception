-- .\lua\modules\player_proxy.lua
local ProxyManager = ProxyManager
local DEFAULT_ATTACKER_CLASS_PREFIX = ProxyManager.DEFAULT_ATTACKER_CLASS_PREFIX
local PLAYER_SPAWN_DELAY = 0.1
local RAGDOLL_REMOVE_DELAY = 1
local IsValid = IsValid
local player_GetHumans = player.GetHumans

function ProxyManager.IsAttacker(entity)
    if not IsValid(entity) or not entity:IsNPC() then
        return false
    end
    return entity:GetClass():find(DEFAULT_ATTACKER_CLASS_PREFIX, 1, true)
end

hook.Add("PlayerSpawn", "ENP_PlayerSpawn", function(player)
    ProxyManager.CreateProxiesDelayed(player, PLAYER_SPAWN_DELAY)
end)

-- hook.Add("PlayerDeath", "ENP_PlayerDeath", function(player, _, _)
--     ProxyManager:RemoveProxies(player)
-- end)

local lastHp_c
local lastHp_d
hook.Add("PlayerDeathThink", "ENP_PlayerDeathThink", function(player)
    local ragdoll = player.ORag
    if not IsValid(ragdoll) then
        return
    end

    -- +d 代表正数，-d 代表负数

    --   |  1  |  2  |     |  4
    -- c | nil | nil |     | nil
    -- d | nil | +d1 |     | -d2

    --   |  1  |  2  |  3  |  4
    -- c | nil | nil | +d2 | -d3
    -- d | nil | +d1 | +d2 | +d2

    local currentHp_c = ragdoll.Hp_c
    local currentHp_d = ragdoll.Hp_d
    local now = CurTime()

    if lastHp_c ~= currentHp_c then
        print(string.format("[%d] Hp_c: %d -> %d", now, lastHp_c or 0, currentHp_c or 0))
    elseif lastHp_d ~= currentHp_d then
        print(string.format("[%d] Hp_d: %d -> %d", now, lastHp_d or 0, currentHp_d or 0))
    end

    lastHp_c = currentHp_c
    lastHp_d = currentHp_d

    local state = 1
    if currentHp_d and currentHp_d > 0 and not currentHp_c then
        state = 2
    elseif currentHp_c and currentHp_c > 0 then
        state = 3
    elseif (currentHp_c and currentHp_c < 0) or (currentHp_d and currentHp_d < 0) then
        state = 4
    end



    ProxyManager.MoveProxies(player, ragdoll)
    ProxyManager.RemoveProxiesDelayed(ragdoll, RAGDOLL_REMOVE_DELAY)
end)

hook.Add("OnEntityCreated", "ENP_OnEntityCreated", function(entity)
    if entity:IsNPC() and entity:GetClass():find(DEFAULT_ATTACKER_CLASS_PREFIX, 1, true) then
        for _, player in ipairs(player_GetHumans()) do
            ProxyManager.CreateProxy(player, entity)
        end
    end
end)

hook.Add("EntityRemoved", "ENP_EntityRemoved", function(entity)
    if ProxyManager.IsAttacker(entity) then
        debug.Trace()
        ProxyManager.RemoveAllProxiesByAttacker(entity)
    end
end)

print("[SNT] Player Proxy loaded.")
