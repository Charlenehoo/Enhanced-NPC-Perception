-- .\lua\modules\player_proxy.lua
local ProxyManager = ProxyManager
local DEFAULT_ATTACKER_CLASS_PREFIX = ProxyManager.DEFAULT_ATTACKER_CLASS_PREFIX
local PLAYER_SPAWN_DELAY = 0.1
local RAGDOLL_REMOVE_DELAY = 4
local IsValid = IsValid
local player_GetHumans = player.GetHumans

function ProxyManager.IsAttacker(entity)
    if not IsValid(entity) or not entity:IsNPC() then
        return false
    end
    return entity:GetClass():find(DEFAULT_ATTACKER_CLASS_PREFIX, 1, true)
end

local lastHp_c
local lastHp_d
local lastState

hook.Add("PlayerSpawn", "ENP_PlayerSpawn", function(player)
    lastHp_c = nil
    lastHp_d = nil
    lastState = -1
    if IsValid(player.ORag) then
        ProxyManager.MoveProxies(player.ORag, player)
    else
        ProxyManager.CreateProxiesDelayed(player, PLAYER_SPAWN_DELAY)
    end
    print("===============================")
end)

hook.Add("PlayerDeathThink", "ENP_PlayerDeathThink", function(player)
    local ragdoll = player.ORag
    if not IsValid(ragdoll) then
        return
    end

    local currentHp_c = ragdoll.Hp_c
    local currentHp_d = ragdoll.Hp_d
    local now = CurTime()

    -- 打印血量变化（始终执行，用于观察）
    if lastHp_c ~= currentHp_c then
        print(string.format("[%d] Hp_c: %d -> %d", now, lastHp_c or 0, currentHp_c or 0))
        print("===============================")
    elseif lastHp_d ~= currentHp_d then
        print(string.format("[%d] Hp_d: %d -> %d", now, lastHp_d or 0, currentHp_d or 0))
        print("===============================")
    end

    lastHp_c = currentHp_c
    lastHp_d = currentHp_d

    -- 确定当前状态（仅赋值，不执行操作）
    local currentState
    if currentHp_d then
        if currentHp_d <= 0 then
            if currentHp_c == nil then
                currentState = 3 -- 直接死亡
            else                 --  currentHp_c <= 0 then
                currentState = 5 -- 最终死亡
            end
        else
            if currentHp_c == nil then
                currentState = 2 -- 死亡动画
            elseif currentHp_c <= 0 then
                currentState = 5 -- 最终死亡
            else
                currentState = 4 -- 爬行
            end
        end
    else
        currentState = 1 -- 未介入
    end


    -- 状态变化时执行对应操作
    if lastState ~= currentState then
        if currentState == 1 then
            print("尚未介入")
            print("Isdead_d: " .. tostring(ragdoll.Isdead_d))
            print("Isdead_c: " .. tostring(ragdoll.Isdead_c))
            print("IsWrithing: " .. tostring(ragdoll.IsWrithing))
            print("IsTwitching: " .. tostring(ragdoll.IsTwitching))
            print("IsReviving: " .. tostring(ragdoll.IsReviving))
            print("IsSelfRevive: " .. tostring(ragdoll.IsSelfRevive))
            print("===============================")
        elseif currentState == 2 then
            print("死亡动画")
            print("Isdead_d: " .. tostring(ragdoll.Isdead_d))
            print("Isdead_c: " .. tostring(ragdoll.Isdead_c))
            print("IsWrithing: " .. tostring(ragdoll.IsWrithing))
            print("IsTwitching: " .. tostring(ragdoll.IsTwitching))
            print("IsReviving: " .. tostring(ragdoll.IsReviving))
            print("IsSelfRevive: " .. tostring(ragdoll.IsSelfRevive))
            print("===============================")
            ProxyManager.MoveProxies(player, ragdoll)
            ProxyManager.RemoveProxiesDelayed(ragdoll, RAGDOLL_REMOVE_DELAY)
        elseif currentState == 3 then
            print("直接死亡")
            print("Isdead_d: " .. tostring(ragdoll.Isdead_d))
            print("Isdead_c: " .. tostring(ragdoll.Isdead_c))
            print("IsWrithing: " .. tostring(ragdoll.IsWrithing))
            print("IsTwitching: " .. tostring(ragdoll.IsTwitching))
            print("IsReviving: " .. tostring(ragdoll.IsReviving))
            print("IsSelfRevive: " .. tostring(ragdoll.IsSelfRevive))
            print("===============================")
        elseif currentState == 4 then
            print("爬行挣扎")
            print("Isdead_d: " .. tostring(ragdoll.Isdead_d))
            print("Isdead_c: " .. tostring(ragdoll.Isdead_c))
            print("IsWrithing: " .. tostring(ragdoll.IsWrithing))
            print("IsTwitching: " .. tostring(ragdoll.IsTwitching))
            print("IsReviving: " .. tostring(ragdoll.IsReviving))
            print("IsSelfRevive: " .. tostring(ragdoll.IsSelfRevive))
            print("===============================")
            ProxyManager.CancelRemoveProxiesDelayed(ragdoll)
        elseif currentState == 5 then
            print("最终死亡")
            print("Isdead_d: " .. tostring(ragdoll.Isdead_d))
            print("Isdead_c: " .. tostring(ragdoll.Isdead_c))
            print("IsWrithing: " .. tostring(ragdoll.IsWrithing))
            print("IsTwitching: " .. tostring(ragdoll.IsTwitching))
            print("IsReviving: " .. tostring(ragdoll.IsReviving))
            print("IsSelfRevive: " .. tostring(ragdoll.IsSelfRevive))
            print("===============================")
            ProxyManager.RemoveProxiesDelayed(ragdoll, RAGDOLL_REMOVE_DELAY)
        end
    end

    lastState = currentState
end)

hook.Add("OnEntityCreated", "ENP_OnEntityCreated", function(entity)
    if entity:IsNPC() and entity:GetClass():find(DEFAULT_ATTACKER_CLASS_PREFIX, 1, true) then -- 改为遍历所有 Victim
        for _, player in ipairs(player_GetHumans()) do
            ProxyManager.CreateProxy(player, entity)
        end
    end
end)

hook.Add("EntityRemoved", "ENP_EntityRemoved", function(entity)
    if ProxyManager.IsAttacker(entity) then
        ProxyManager.RemoveAllProxiesByAttacker(entity)
    end
end)

print("[SNT] Player Proxy loaded.")
