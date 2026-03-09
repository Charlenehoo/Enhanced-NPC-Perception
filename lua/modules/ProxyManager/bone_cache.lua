-- .\lua\modules\ProxyManager\bone_cache.lua
ProxyManager = ProxyManager or {}
ProxyManager.boneCacheTable = ProxyManager.boneCacheTable or {}

local IsValid = IsValid

local BONE_NAMES_WITH_SPINE4 = ProxyManager.BONE_NAMES_WITH_SPINE4
local BONE_NAMES_WITHOUT_SPINE4 = ProxyManager.BONE_NAMES_WITHOUT_SPINE4

function ProxyManager:ReInitializeBoneCache(victim)
    if not IsValid(victim) then
        return
    end

    local boneNames
    if victim:LookupBone("ValveBiped.Bip01_Spine4") then
        boneNames = BONE_NAMES_WITH_SPINE4
    elseif victim:LookupBone("ValveBiped.Bip01_Spine2") then
        boneNames = BONE_NAMES_WITHOUT_SPINE4
    else
        print(string.format(
            "[Enhanced NPC Perception] Error: Could not find bone 'Spine4' or 'Spine2' on entity %s. Cannot initialize bone cache.",
            tostring(victim)))
        return
    end

    ProxyManager.boneCacheTable[victim] = {}

    for _, boneName in ipairs(boneNames) do
        local boneIndex = victim:LookupBone(boneName) -- https://wiki.facepunch.com/gmod/Entity:LookupBone
        if boneIndex then
            -- 用 table.insert(ProxyManager.boneCacheTable[victim], boneIndex)
            -- 不用 ProxyManager.boneCacheTable[victim][_] = boneIndex
            -- 是为了保证 ProxyManager.boneCacheTable[victim] 密集
            -- #ProxyManager.boneCacheTable[victim] 可以小于 #boneNames
            -- 便于后续连续索引
            table.insert(ProxyManager.boneCacheTable[victim], boneIndex)
        else
            print(string.format("[Enhanced NPC Perception] Warning: Could not find bone '%s' on entity %s. Skipping.",
                boneName, tostring(victim)))
        end
    end
end

function ProxyManager:InitializeBoneCache(victim)
    if not IsValid(victim) then
        return
    end

    local boneCache = ProxyManager.boneCacheTable[victim]
    if not boneCache or #boneCache == 0 then
        ProxyManager:ReInitializeBoneCache(victim)
    end
end
