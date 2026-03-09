-- .\lua\modules\player_proxy.lua
local ProxyManager = ProxyManager
local DEFAULT_ATTACKER_CLASS_PREFIX = ProxyManager.DEFAULT_ATTACKER_CLASS_PREFIX
local PLAYER_SPAWN_DELAY = 0.1
local RAGDOLL_REMOVE_DELAY = 4
local IsValid = IsValid
local player_GetHumans = player.GetHumans

local MAIN_STATE = {
    UNINTERVENED = "UNINTERVENED", -- 未介入
    DIRECT_DEATH = "DIRECT_DEATH", -- 直接死亡
    DEATH_ANIM   = "DEATH_ANIM",   -- 死亡动画
    CRAWLING     = "CRAWLING",     -- 爬行
    FINAL_DEATH  = "FINAL_DEATH",  -- 最终死亡
}

local SUB_STATE = {
    NONE      = "None",
    WRITHING  = "Writhing",
    TWITCHING = "Twitching",
    REVIVING  = "Reviving",
}

function ProxyManager.IsAttacker(entity)
    if not IsValid(entity) or not entity:IsNPC() then
        return false
    end
    return entity:GetClass():find(DEFAULT_ATTACKER_CLASS_PREFIX, 1, true)
end

local function OnSubStateChanged(player, oldSubState, newSubState)
    -- 可以打印或留空
    print(string.format("Player %s sub state changed from %s to %s", player:Name(), tostring(oldSubState),
        tostring(newSubState)))
    -- 这里可以添加后续逻辑
end

-- 辅助函数：打印 ragdoll 状态信息
local function PrintRagdollInfo(stateName, ragdoll)
    print(stateName)
    print("Isdead_d: " .. tostring(ragdoll.Isdead_d))
    print("Isdead_c: " .. tostring(ragdoll.Isdead_c))
    print("IsWrithing: " .. tostring(ragdoll.IsWrithing))
    print("IsTwitching: " .. tostring(ragdoll.IsTwitching))
    print("IsReviving: " .. tostring(ragdoll.IsReviving))
    print("IsSelfRevive: " .. tostring(ragdoll.IsSelfRevive))
    print("===============================")
end

local lastHp_c
local lastHp_d
local lastState

hook.Add("PlayerSpawn", "ENP_PlayerSpawn", function(player)
    player.lastHp_c = nil
    player.lastHp_d = nil
    player.lastMainState = nil -- 上次主状态，初始为 nil 确保首次触发
    player.lastSubState = nil  -- 上次子状态，初始为 nil

    if IsValid(player.ORag) then
        if not ProxyManager.MoveProxies(player.ORag, player) then
            ProxyManager.CreateProxiesDelayed(player, PLAYER_SPAWN_DELAY)
        end
    else
        ProxyManager.CreateProxiesDelayed(player, PLAYER_SPAWN_DELAY)
    end
    print("===============================")
end)

hook.Add("PlayerDeathThink", "ENP_PlayerDeathThink", function(player)
    local ragdoll = player.ORag
    if not IsValid(ragdoll) then return end

    local currentHp_c = ragdoll.Hp_c
    local currentHp_d = ragdoll.Hp_d
    local now = CurTime()

    -- 血量变化检测
    local lastHp_c = player.lastHp_c
    local lastHp_d = player.lastHp_d
    if lastHp_c ~= currentHp_c then
        print(string.format("[%d] Hp_c: %s -> %s", now, tostring(lastHp_c), tostring(currentHp_c)))
        print("===============================")
    elseif lastHp_d ~= currentHp_d then
        print(string.format("[%d] Hp_d: %s -> %s", now, tostring(lastHp_d), tostring(currentHp_d)))
        print("===============================")
    end
    player.lastHp_c = currentHp_c
    player.lastHp_d = currentHp_d

    -- 确定当前主状态（使用枚举字符串）
    local currentMainState
    if not currentHp_d then
        currentMainState = MAIN_STATE.UNINTERVENED -- 未介入
    elseif not currentHp_c then
        if currentHp_d <= 0 then
            currentMainState = MAIN_STATE.DIRECT_DEATH -- 直接死亡
        else
            currentMainState = MAIN_STATE.DEATH_ANIM   -- 死亡动画
        end
    else
        if currentHp_d <= 0 or currentHp_c <= 0 then
            currentMainState = MAIN_STATE.FINAL_DEATH -- 最终死亡
        else
            currentMainState = MAIN_STATE.CRAWLING    -- 爬行
        end
    end

    -- 确定当前子状态（仅在爬行状态下有效，否则为 None）
    local currentSubState
    if currentMainState == MAIN_STATE.CRAWLING then
        -- 互斥优先级：Writhing > Twitching > Reviving > None
        if ragdoll.IsWrithing then
            currentSubState = SUB_STATE.WRITHING
        elseif ragdoll.IsTwitching then
            currentSubState = SUB_STATE.TWITCHING
        elseif ragdoll.IsReviving then
            currentSubState = SUB_STATE.REVIVING
        else
            currentSubState = SUB_STATE.NONE
        end
    else
        currentSubState = SUB_STATE.NONE
    end

    -- 子状态变化处理（包括进出爬行状态时的自然变化）
    local lastSubState = player.lastSubState
    if currentSubState ~= lastSubState then
        OnSubStateChanged(player, lastSubState, currentSubState)
        player.lastSubState = currentSubState
    end

    -- 主状态变化处理
    local lastMainState = player.lastMainState
    if lastMainState ~= currentMainState then
        -- 打印状态信息（使用辅助函数）
        PrintRagdollInfo(currentMainState, ragdoll)

        -- 执行与主状态相关的操作
        if currentMainState == MAIN_STATE.DEATH_ANIM then
            ProxyManager.MoveProxies(player, ragdoll)
            ProxyManager.RemoveProxiesDelayed(ragdoll, RAGDOLL_REMOVE_DELAY)
        elseif currentMainState == MAIN_STATE.CRAWLING then
            ProxyManager.CancelRemoveProxiesDelayed(ragdoll)
        elseif currentMainState == MAIN_STATE.FINAL_DEATH then
            ProxyManager.RemoveProxiesDelayed(ragdoll, RAGDOLL_REMOVE_DELAY)
        end
        -- 其他状态（UNINTERVENED、DIRECT_DEATH）不需要额外操作

        -- 更新主状态
        player.lastMainState = currentMainState
    end
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
