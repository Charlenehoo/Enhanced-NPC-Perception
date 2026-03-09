-- .\lua\modules\ProxyManager\bone_cache.lua
ProxyManager = ProxyManager or {}
ProxyManager.boneCacheByModel = ProxyManager.boneCacheByModel or {}
ProxyManager.boneCacheTable = ProxyManager.boneCacheTable or {}
setmetatable(ProxyManager.boneCacheTable, { __mode = "k" })

local IsValid = IsValid
local table_IsEmpty = table.IsEmpty

local BONE_NAMES_WITH_SPINE4 = ProxyManager.BONE_NAMES_WITH_SPINE4
local BONE_NAMES_WITHOUT_SPINE4 = ProxyManager.BONE_NAMES_WITHOUT_SPINE4

function ProxyManager.InitializeBoneCache(victim)
    if not IsValid(victim) then return end

    if ProxyManager.boneCacheTable[victim] then return end
    local model = victim:GetModel()
    if not model or model == "" then
        print("[Enhanced NPC Perception] Warning: Entity has no model, cannot initialize bone cache.")
        return
    end

    if ProxyManager.boneCacheByModel[model] then
        ProxyManager.boneCacheTable[victim] = ProxyManager.boneCacheByModel[model]
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

    local newCache = {}
    for _, boneName in ipairs(boneNames) do
        local boneIndex = victim:LookupBone(boneName) -- https://wiki.facepunch.com/gmod/Entity:LookupBone
        if boneIndex then
            -- 用 table.insert(ProxyManager.boneCacheTable[victim], boneIndex)
            -- 不用 ProxyManager.boneCacheTable[victim][_] = boneIndex
            -- 是为了保证 ProxyManager.boneCacheTable[victim] 密集
            -- #ProxyManager.boneCacheTable[victim] 可以小于 #boneNames
            -- 便于后续连续索引
            table.insert(newCache, boneIndex)
        else
            print(string.format("[Enhanced NPC Perception] Warning: Could not find bone '%s' on entity %s. Skipping.",
                boneName, tostring(victim)))
        end
    end

    ProxyManager.boneCacheByModel[model] = newCache
    ProxyManager.boneCacheTable[victim] = newCache
end
