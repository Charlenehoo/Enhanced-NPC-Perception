-- .\lua\modules\player_proxy.lua
local ProxyManager = ProxyManager
local SoundManager = SoundManager
local DEFAULT_ATTACKER_CLASS_PREFIX = ProxyManager.DEFAULT_ATTACKER_CLASS_PREFIX

local PLAYER_SPAWN_DELAY = 0.1
local RAGDOLL_REMOVE_DELAY = 4

local IsValid = IsValid
local player_GetHumans = player.GetHumans

local EDAStateMachine = EDAStateMachine

EDAStateMachine.OnMainStateChange(function(player, ragdoll, oldMain, newMain, oldSub)
    if newMain == EDAStateMachine.MAIN_STATE.DEATH_ANIM then
        ProxyManager.MoveProxies(player, ragdoll)
        ProxyManager.RemoveProxiesDelayed(ragdoll, RAGDOLL_REMOVE_DELAY)
    elseif newMain == EDAStateMachine.MAIN_STATE.STRUGGLE then
        local wasCancelled = ProxyManager.CancelRemoveProxiesDelayed(ragdoll)
        if not wasCancelled then
            ProxyManager.CreateProxiesForVictimByClass(ragdoll)
        end
    elseif newMain == EDAStateMachine.MAIN_STATE.FINAL_DEATH then
        player.ragdoll = ragdoll -- SoundManager 的要求
        SoundManager:Stop(player)
        if oldSub == EDAStateMachine.SUB_STATE.CRAWLING then
            SoundManager:Play(player, "finaldeath", false)
        end
        ProxyManager.RemoveProxiesDelayed(ragdoll, RAGDOLL_REMOVE_DELAY)
    end
end)

EDAStateMachine.OnSubStateChange(function(player, ragdoll, oldSub, newSub, mainState)
    player.ragdoll = ragdoll -- SoundManager 的要求
    if newSub == EDAStateMachine.SUB_STATE.TWITCHING or newSub == EDAStateMachine.SUB_STATE.WRITHING then
        SoundManager:Play(player, "bubble_loop", true)
    elseif newSub == EDAStateMachine.SUB_STATE.REVIVING then
        SoundManager:Stop(player)
    elseif newSub == EDAStateMachine.SUB_STATE.CRAWLING then
        SoundManager:Play(player, "help_loop", true)
    else
        SoundManager:Stop(player)
    end
end)

EDAStateMachine.OnPlayerSpawn(function(player, oldRagdoll)
    if IsValid(oldRagdoll) then
        player.ragdoll = oldRagdoll -- SoundManager 的要求
        SoundManager:Stop(player)
        if not ProxyManager.MoveProxies(oldRagdoll, player) then
            ProxyManager.CreateProxiesDelayed(player, PLAYER_SPAWN_DELAY)
        end
    else
        ProxyManager.CreateProxiesDelayed(player, PLAYER_SPAWN_DELAY)
    end
end)

hook.Add("PlayerSpawn", "ENP_PlayerSpawn", function(player)
    EDAStateMachine.FireOnPlayerSpawn(player)
end)

hook.Add("PlayerDeathThink", "ENP_PlayerDeathThink", function(player)
    EDAStateMachine.Update(player)
end)

function ProxyManager.IsAttacker(entity)
    if not IsValid(entity) or not entity:IsNPC() then
        return false
    end
    return entity:GetClass():find(DEFAULT_ATTACKER_CLASS_PREFIX, 1, true)
end

hook.Add("OnEntityCreated", "ENP_OnEntityCreated", function(entity)
    if entity:IsNPC() and entity:GetClass():find(DEFAULT_ATTACKER_CLASS_PREFIX, 1, true) then -- 改为遍历所有 Victim
        for _, player in ipairs(player_GetHumans()) do
            if player:Alive() then
                ProxyManager.CreateProxy(player, entity)
            end
        end
    end
end)

print("[SNT] Player Proxy loaded.")
