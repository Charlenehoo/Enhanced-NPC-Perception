-- .\lua\modules\ProxyManager\proxy_sync.lua
ProxyManager = ProxyManager or {}
ProxyManager.loopCountTable = ProxyManager.loopCountTable or {}
setmetatable(ProxyManager.loopCountTable, { __mode = "k" })

local COMBINE_RANGE = ProxyManager.ATTACKER_RANGE
local COMBINE_SUPPRESSION_TIME = ProxyManager.ATTACKER_SUPPRESSION_TIME
local PROXY_OFFSET = ProxyManager.PROXY_OFFSET
local MASK_SHOT_HULL = MASK_SHOT_HULL

local IsValid = IsValid
local CurTime = CurTime
local util_TraceLine = util.TraceLine

function ProxyManager.SyncProxiesForSingleVictim(victim, attackerProxyMapView)
    local currentTime = CurTime()

    ProxyManager.InitializeBoneCache(victim)

    local targetBonePos
    local boneCache = ProxyManager.boneCacheTable[victim]
    if boneCache and #boneCache > 0 then
        local loopCount = ProxyManager.loopCountTable[victim] or 0 -- 0 ~ #boneCache
        local boneIndex = loopCount % #boneCache + 1               -- 1 ~ #boneCache
        ProxyManager.loopCountTable[victim] = boneIndex
        targetBonePos, _ = victim:GetBonePosition(boneIndex)       -- https://wiki.facepunch.com/gmod/Entity:GetBonePosition
    else
        targetBonePos = victim:EyePos()                            -- 降级
    end

    for attacker, proxy in attackerProxyMapView.GetIterator() do
        if ProxyManager.CheckOrphanProxy(proxy) then
            -- 安全说明：此循环遍历 attackerProxyMapView（键为 attacker，值为 proxy）。
            -- 循环体内调用 ProxyManager.CheckOrphanProxy(proxy) 检查代理是否孤儿。
            -- 若代理无效，CheckOrphanProxy 会调用 ProxyManager.RemoveProxy(proxy.victim, proxy.attacker)，
            -- 该函数从内部表 _attackersByVictim[victim] 中移除键 attacker，即当前迭代的键。
            -- 在 Lua 的 next/pairs 遍历中，删除当前迭代的键是安全的，不会导致跳过或重复。
            -- 警告：请勿在此循环中删除任何其他键（非当前 attacker），否则可能破坏迭代器状态。
            -- 若将来需要删除其他键，请改用“先收集键，后删除”模式。
            continue -- Gmod 支持此关键字
        end

        local attackerShootPos = attacker:GetShootPos()
        local distance = attackerShootPos:Distance(targetBonePos)
        local isRanged = distance > COMBINE_RANGE

        local isVisible = attacker:IsLineOfSightClear(victim)

        if isVisible then
            proxy.lastSightTime = currentTime
        end

        local isSuppressionExpired = (currentTime - proxy.lastSightTime) > COMBINE_SUPPRESSION_TIME

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
    for victim, attackerProxyMapView in ProxyManager.IterateVictimsWithAttackerProxyMapView() do
        if IsValid(victim) then
            ProxyManager.SyncProxiesForSingleVictim(victim, attackerProxyMapView)
        end
    end
end
