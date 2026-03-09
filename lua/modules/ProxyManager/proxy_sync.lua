-- .\lua\modules\ProxyManager\proxy_sync.lua
ProxyManager = ProxyManager or {}
ProxyManager.loopCountTable = ProxyManager.loopCountTable or {}

local COMBINE_RANGE = ProxyManager.ATTACKER_RANGE
local COMBINE_SUPPRESSION_TIME = ProxyManager.ATTACKER_SUPPRESSION_TIME
local PROXY_OFFSET = ProxyManager.PROXY_OFFSET
local ATTACKER_LAST_SIGHTING_TIME_KEY = ProxyManager.ATTACKER_LAST_SIGHTING_TIME_KEY
local MASK_SHOT_HULL = MASK_SHOT_HULL

local IsValid = IsValid
local CurTime = CurTime
local util_TraceLine = util.TraceLine

function ProxyManager.SyncProxiesForSingleVictim(victim, proxyTable)
    local currentTime = CurTime()

    ProxyManager.InitializeBoneCache(victim)
    local boneCache = ProxyManager.boneCacheTable[victim]
    -- 这里不加下面注释掉的检查是因为 boneCache or table.IsEmpty(boneCache) 是核心功能失效，
    -- 与其隐藏错误，不如 fail fast，而且 lua 虚拟机可以收集重复报错，而不是控制台刷屏
    -- if not boneCache or table.IsEmpty(boneCache) then
    --     return
    -- end

    local loopCount = ProxyManager.loopCountTable[victim] or 0 -- 0 ~ #boneCache
    local boneIndex = loopCount % #boneCache + 1               -- 1 ~ #boneCache
    ProxyManager.loopCountTable[victim] = boneIndex

    local targetBonePos, _ = victim:GetBonePosition(boneIndex) -- https://wiki.facepunch.com/gmod/Entity:GetBonePosition
    for attacker, proxy in proxyTable:Iterate() do
        -- if not IsValid(attacker) then
        --     continue -- GLua 是 Lua 的方言，支持此关键字
        -- end
        -- if not IsValid(proxy) then
        --     continue
        -- end

        local attackerShootPos = attacker:GetShootPos()
        local distance = attackerShootPos:Distance(targetBonePos)
        local isRanged = distance > COMBINE_RANGE

        local isVisible = attacker:IsLineOfSightClear(victim)

        attacker[ATTACKER_LAST_SIGHTING_TIME_KEY] = attacker[ATTACKER_LAST_SIGHTING_TIME_KEY] or {}

        if isVisible then
            attacker[ATTACKER_LAST_SIGHTING_TIME_KEY][victim] = currentTime -- 此属性由 attacker 持有更好，避免弱引用问题
        end

        -- 初始化时，如果 victim 被玩家看见，lastSightTime = currentTime，符合设计
        -- 如果没有被玩家看见，lastSightTime = 0，是一个极早的时间，isSuppressionExpired 为 false，也符合设计
        local lastSightTime = attacker[ATTACKER_LAST_SIGHTING_TIME_KEY][victim] or 0
        local isSuppressionExpired = (currentTime - lastSightTime) > COMBINE_SUPPRESSION_TIME

        local shouldSuppress = not isVisible and not isSuppressionExpired
        local shouldCloseSuppress = shouldSuppress and not isRanged
        local shouldRangedSuppress = shouldSuppress and isRanged

        local direction = (targetBonePos - attackerShootPos):GetNormalized()

        local targetPos
        if shouldCloseSuppress then
            local traceResult = util_TraceLine({ -- https://wiki.facepunch.com/gmod/util.TraceLine
                start = attackerShootPos,
                endpos = targetBonePos,
                filter = attacker,
                mask = MASK_SHOT_HULL -- https://wiki.facepunch.com/gmod/Enums/MASK
            })
            targetPos = traceResult.HitPos
        elseif (isVisible and isRanged) or shouldRangedSuppress then
            targetPos = attackerShootPos + direction * COMBINE_RANGE -- COMBINE_RANGE = 1024 + PROXY_OFFSET，已经纳入考虑
        else
            targetPos = targetBonePos
        end

        proxy:SetPos(targetPos - direction * PROXY_OFFSET)
        proxy:SetAngles(direction:Angle())
    end
end

function ProxyManager.SyncAllProxies()
    for victim, attackerProxyMap in ProxyManager.IterateVictimsWithAttackerProxyMapView() do
        if IsValid(victim) then
            ProxyManager.SyncProxiesForSingleVictim(victim, attackerProxyMap)
        end
    end
end
