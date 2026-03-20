-- .\lua\modules\ProxyManager\proxy_sync.lua

--[[
    代理同步核心逻辑说明

    本模块通过动态放置代理实体（enp_proxy）来间接操控 NPC 攻击者的行为，实现战术压制、绕墙等效果。
    核心设计基于以下关键点：

    1. 每个攻击者拥有专属代理（一对一关系）
       对于每一对 (受害者, 攻击者)，系统创建一个唯一的代理实体。核心实现在 Core/private.lua 中：
       - 通过 _attackersByVictim[victim][attacker] = proxy 和 _victimsByAttacker[attacker][victim] = proxy
         建立双向索引，确保每个攻击者-受害者对只对应一个代理。
       - 通过 _SetupRelationshipsProxy(attacker, proxy) 设置攻击者与代理的实体关系：
            attacker:AddRelationship("enp_proxy D_NU 0")  -- 设置类关系
            attacker:AddEntityRelationship(proxy, D_HT, 99) -- 设置实例关系，使代理成为攻击者的敌人
       - 这种设计确保：
           * 每个代理仅被对应的攻击者仇恨，不受其他攻击者干扰。
           * 攻击者只会对自己专属的代理产生敌对反应（移动、瞄准、射击），不会受其他代理影响。
           * 调整代理的位置即可精准引导对应攻击者的行为。

    2. 三点一线原则
       在放置代理时，始终保证“攻击者、代理、受害者”三点大致共线（通过方向向量 direction 实现）。
       代理位置通常位于攻击者与受害者的连线上，只是根据战术需求在连线上前后移动。
       这一原则确保攻击者朝向代理射击时，子弹轨迹最终落在受害者方向附近，实现间接瞄准。

    3. 攻击者对受害者的感知与战术选择
       攻击者是否拥有受害者的“信息”决定了其是否会尝试压制（射击掩体）。信息来源于：
          - **视觉可见性**：通过 `IsSoundAudible` 函数返回的第一个布尔值（`isVisible`）确定攻击者是否直接看到受害者。若可见，则攻击者已获得直接信息。
          - **听觉记忆**：通过 `IsSoundAudible` 的第二个返回值（`isAudible`）判断攻击者是否听到受害者发出的声音（基于声压级、距离和墙体衰减）。即使视觉不可见，可听见的声音仍提供信息。
          - **近期记忆**：`LAST_SIGHT_TIME` 和 `LAST_SOUND_TIME` 记录最近一次视觉/听觉事件，用于在信息丢失后保持一段时间的记忆（`SIGHT_MEMORY_DURATION` 和 `SOUND_MEMORY_DURATION`）。

       只有当攻击者拥有受害者信息（`hasRecentInfo = (isAudible and hasRecentSound) or hasRecentSight`）时，才会进入“压制”状态，尝试向受害者所在方向射击（即使被墙遮挡）。否则，攻击者不会无缘无故向掩体射击，而是可能保持闲置或执行其他行为。

    4. 压制射击的条件：墙厚决定能否穿透
       当攻击者拥有受害者信息且视觉不可见时（即受害者位于掩体后），通过 `IsSoundAudible` 返回的累计墙厚（`wallThickness`）来判断掩体是否可穿透：
          - **薄墙（≤256 单位）**：认为子弹可以穿透此厚度的墙。代理被放置在墙表面（攻击者一侧），使攻击者可见代理（或至少感知到敌人在墙后方向），从而激发其使用武器的穿墙能力向墙后射击，实现压制。
          - **厚墙（>256 单位）**：子弹无法穿透。为避免攻击者徒劳攻击不可穿透的掩体，代理被放置在受害者位置（墙后），使攻击者无法看见代理，从而触发 Source 引擎的寻路行为，让攻击者绕墙寻找可见目标。

       此外，墙厚超过 256 单位（即可穿透的最大厚度）时，`IsSoundAudible` 会直接判定声音不可听见（听觉记忆失效），避免对不可穿透的墙体进行不必要的压制计算，进一步强化厚墙时应绕行的逻辑。

    5. 基于 Source 引擎 AI 特性的行为引导与增强
       - 攻击者对距离 1024 单位内的敌人才会主动交战（COMBINE_RANGE 基于此设定）。超过此距离，即使武器具备远程射击能力（由武器 Base 定义），引擎也不会给予 NPC 远射的意愿，导致其不会攻击远处目标。
       - 本模块通过代理机制弥补这一缺陷：当受害者超出攻击者射程时（isRanged 分支），将代理置于攻击者前方 1024 单位处（沿攻击者到受害者的方向），使攻击者获得一个位于射程内的敌人，从而激发其交战意愿。此时 NPC 会向代理射击，而武器自身的弹道可能覆盖更远距离（取决于武器属性），最终可能命中远处的受害者或至少实现压制效果。
       - 声音记忆（lastSoundTime）用于触发攻击者转向，但实际转向通过设置敌人（SetEnemy）和强制调度实现，避免依赖声音系统。

    6. 代理位置微调（PROXY_OFFSET）
       在计算出目标位置（targetPos）后，最终设置代理位置时使用 `proxy:SetPos(targetPos - direction * PROXY_OFFSET)`，其中 PROXY_OFFSET = 2 单位。
       该偏移量根据代理实体使用的模型（enp_proxy 中设置为 `models/editor/cube_small.mdl`，缩放 0.04）大小计算得出，目的是将代理从目标点向攻击者方向轻微回拉，避免代理陷入墙体或受害者模型中。
       这一微调确保代理紧贴目标点但不穿透，保持位置稳定，避免因模型穿插导致的视觉异常或物理冲突。

    这种设计使每个 NPC 的行为独立且可控，通过代理位置间接实现复杂的战术响应，同时保持与受害者方向的关联。
]]

ProxyManager = ProxyManager or {}
ProxyManager.loopCountTable = ProxyManager.loopCountTable or {}
setmetatable(ProxyManager.loopCountTable, { __mode = "k" })

local PROXY_CLASS                   = ProxyManager.PROXY_CLASS
local PROXY_FIELDS                  = ProxyManager.PROXY_FIELDS
local COMBINE_RANGE                 = ProxyManager.ATTACKER_RANGE
local SIGHT_INFO_CERTAINTY_DURATION = ProxyManager.SIGHT_MEMORY_DURATION
local SOUND_INFO_CERTAINTY_DURATION = ProxyManager.SOUND_MEMORY_DURATION
local MEMORY_DURATION               = 30
local FACE_COOLDOWN                 = ProxyManager.FACE_COOLDOWN
local WALL_THICKNESS_THRESHOLD      = 256
local WALL_ATTENUATION_PER_UNIT     = 0.1
local HEAR_THRESHOLD                = 10
local SOUND_CERTAINTY_BASE          = 0.5
local VEC_UP                        = Vector(0, 0, 1)
local MAX_JITTER                    = 32
local HORIZONTAL_FACTOR             = 1.0
local VERTICAL_FACTOR               = 0.2

local PROXY_OFFSET                  = ProxyManager.PROXY_OFFSET
local DEBUG                         = ProxyManager.DEBUG

local IsValid                       = IsValid
local CurTime                       = CurTime
local util_TraceLine                = util.TraceLine



-- 辅助函数：获取受害者的目标位置（骨骼循环）
local function GetTargetPosition(victim)
    ProxyManager.InitializeBoneCache(victim)

    local targetBonePos
    local boneCache = ProxyManager.boneCacheTable[victim]
    if boneCache and #boneCache > 0 then
        local loopCount = ProxyManager.loopCountTable[victim] or 0
        local boneIndex = loopCount % #boneCache + 1
        ProxyManager.loopCountTable[victim] = boneIndex
        targetBonePos, _ = victim:GetBonePosition(boneIndex)
    else
        targetBonePos = victim:EyePos()
    end
    return targetBonePos
end

-- 计算与时间无关的基础数据（方向、墙厚、可视、可听、距离等）
local function ComputeBaseData(attacker, victim, targetPos, lastSoundLevel)
    local attackerShootPos = attacker:GetShootPos()
    local distance = attackerShootPos:Distance(targetPos)
    local direction = (targetPos - attackerShootPos):GetNormalized()

    -- 从攻击者到受害者的射线
    local attackerTrace = util_TraceLine({
        start = attackerShootPos,
        endpos = targetPos,
        filter = attacker,
        mask = MASK_SHOT,
    })
    local attackerSideHitPos = attackerTrace.HitPos

    -- 从受害者到攻击者的反向射线（计算墙厚）
    local victimTrace = util_TraceLine({
        start = targetPos,
        endpos = attackerShootPos,
        filter = victim,
        mask = MASK_SHOT,
    })
    local wallThickness = attackerSideHitPos:Distance(victimTrace.HitPos)

    -- 声学计算
    local distAtten = 20 * math.log10(math.max(distance, 1))
    local wallAtten = wallThickness * WALL_ATTENUATION_PER_UNIT
    local finalSoundLevel = lastSoundLevel - distAtten - wallAtten
    local isAudible = finalSoundLevel > HEAR_THRESHOLD

    -- 视觉检测
    local isVisible = attacker:Visible(victim)

    -- 距离是否超出交战范围
    local isRanged = distance > COMBINE_RANGE

    return {
        isVisible = isVisible,
        isAudible = isAudible,
        isRanged = isRanged,
        direction = direction,
        wallThickness = wallThickness,
        attackerShootPos = attackerShootPos,
        attackerSideHitPos = attackerSideHitPos,
        distance = distance,
    }
end

local function ComputeConfidence(proxy, base, currentTime)
    local lastSight = proxy[PROXY_FIELDS.LAST_SIGHT_TIME] or 0
    local lastSound = proxy[PROXY_FIELDS.LAST_SOUND_TIME] or 0
    local sightDur = SIGHT_INFO_CERTAINTY_DURATION
    local soundDur = SOUND_INFO_CERTAINTY_DURATION
    local soundBase = SOUND_CERTAINTY_BASE

    -- 视觉置信度
    local visualConf
    if base.isVisible then
        visualConf = 1
    else
        local timeSinceSight = currentTime - lastSight
        visualConf = math.max(0, 1 - timeSinceSight / sightDur)
    end

    -- 听觉置信度
    local audioConf
    if base.isAudible then
        audioConf = soundBase
    else
        local timeSinceSound = currentTime - lastSound
        audioConf = math.max(0, soundBase * (1 - timeSinceSound / soundDur))
    end

    return math.max(visualConf, audioConf)
end


local function ComputeJitteredPosition(basePos, direction, confidence)
    local maxJitter = MAX_JITTER * (1 - math.Clamp(confidence, 0, 1))
    if maxJitter <= 0 then return basePos end

    -- 在单位圆内均匀分布（面积均匀）
    local angle = math.random() * 2 * math.pi
    local radius = math.sqrt(math.random())

    -- 检查视线是否几乎垂直（与 VEC_UP 夹角很小）
    local dirNorm = direction:GetNormalized()
    local dotUp = math.abs(dirNorm:Dot(VEC_UP))
    if dotUp > 0.99 then
        -- 视线近乎竖直：偏移在水平面内圆形均匀
        local offset = Vector(
            radius * math.cos(angle) * maxJitter,
            radius * math.sin(angle) * maxJitter,
            0
        )
        return basePos + offset
    else
        -- 正常情况：构建垂直于视线的平面基向量
        -- right：水平向右（垂直于视线和世界向上）
        local right = direction:Cross(VEC_UP):GetNormalized()
        -- up：垂直于视线的垂直方向（在视线与 right 构成的平面内）
        local up = direction:Cross(right):GetNormalized()

        -- 应用椭圆比例
        local hOffset = radius * math.cos(angle) * HORIZONTAL_FACTOR
        local vOffset = radius * math.sin(angle) * VERTICAL_FACTOR
        local offset = right * (hOffset * maxJitter) + up * (vOffset * maxJitter)
        return basePos + offset
    end
end

-- 根据标志决策代理放置位置（完全复制旧实现逻辑）
local function DecideProxyPlacement(base, targetPos, shouldSuppress, isVisible, isRanged)
    if shouldSuppress then
        if base.wallThickness > WALL_THICKNESS_THRESHOLD then
            return targetPos, "thick wall, proxy at victim"
        else
            local distToHit = base.attackerShootPos:Distance(base.attackerSideHitPos)
            if distToHit < COMBINE_RANGE then
                return base.attackerSideHitPos, "thin wall, close suppress"
            elseif distToHit < 2 * PROXY_OFFSET then
                return targetPos, "attacker too close to wall, fallback to default"
            else
                return base.attackerShootPos + base.direction * COMBINE_RANGE, "thin wall, ranged suppress"
            end
        end
    elseif isVisible and isRanged then
        return base.attackerShootPos + base.direction * COMBINE_RANGE, "visible out of range"
    else
        return targetPos, "default (visible & in-range or no info)"
    end
end

-- 调试状态更新函数（检测变化并突出显示）
local function UpdateProxyDebugState(proxy, currentTime, attacker, victim, base, hasRecentSight, hasRecentSound,
                                     hasRecentInfo, shouldSuppress, reason)
    if not DEBUG then return end
    if not proxy._debugState then proxy._debugState = {} end
    local oldState = proxy._debugState
    local newState = {
        isVisible = base.isVisible,
        isAudible = base.isAudible,
        hasRecentSight = hasRecentSight,
        hasRecentSound = hasRecentSound,
        hasRecentInfo = hasRecentInfo,
        shouldSuppress = shouldSuppress,
        isRanged = base.isRanged,
        placementReason = reason,
    }

    -- 收集变化的字段
    local changes = {}
    for k, v in pairs(newState) do
        if oldState[k] ~= v then
            changes[k] = { old = oldState[k], new = v }
        end
    end

    if next(changes) then -- 有变化才打印
        print("========== [代理同步] ==========")
        print(string.format("攻击者: [%d] %s", attacker:EntIndex(), attacker:GetClass()))
        print(string.format("受害者: [%d] %s", victim:EntIndex(), victim:GetClass()))
        print(string.format("当前时间: %.2f", currentTime))

        -- 突出显示变化字段
        print("--- 变化字段 ---")
        for k, change in pairs(changes) do
            print(string.format("%s: %s -> %s", k, tostring(change.old), tostring(change.new)))
        end

        -- 打印完整状态（可选，便于查看上下文）
        print("--- 完整状态 ---")
        print(string.format("视觉可见: %s", tostring(base.isVisible)))
        print(string.format("听觉可听: %s", tostring(base.isAudible)))
        print(string.format("墙体厚度: %.2f 单位", base.wallThickness))
        print(string.format("最近视觉记忆: %s", tostring(hasRecentSight)))
        print(string.format("最近听觉记忆: %s", tostring(hasRecentSound)))
        print(string.format("拥有信息: %s", tostring(hasRecentInfo)))
        print(string.format("压制状态: %s", tostring(shouldSuppress)))
        print(string.format("超出范围: %s", tostring(base.isRanged)))
        print(string.format("放置原因: %s", tostring(reason)))
        print("================================\n")

        proxy._debugState = newState
    end
end

local function SyncProxiesForSingleVictim(victim, attackerProxyMapView)
    local currentTime = CurTime()
    local targetPos = GetTargetPosition(victim)

    for attacker, proxy in attackerProxyMapView.GetIterator() do
        if ProxyManager.CheckOrphanProxy(proxy) then continue end
        local lastSoundLevel = proxy[PROXY_FIELDS.LAST_SOUND_LEVEL]
        local base = ComputeBaseData(attacker, victim, targetPos, lastSoundLevel)

        if base.isVisible then
            proxy[PROXY_FIELDS.LAST_SIGHT_TIME] = currentTime
        end
        if base.isAudible then
            proxy[PROXY_FIELDS.LAST_SOUND_TIME] = currentTime
        end

        proxy[PROXY_FIELDS.LAST_SOUND_LEVEL] = 0

        local confidence = ComputeConfidence(proxy, base, currentTime)
        proxy[PROXY_FIELDS.CONFIDENCE] = confidence

        local hasRecentInfo = confidence > 0
        local shouldSuppress = not base.isVisible and hasRecentInfo

        -- 新增：异步穿透判断相关变量
        local canPenetrate = nil

        if shouldSuppress then
            -- 获取武器相关参数（用于异步任务）
            local wep = attacker:GetActiveWeapon()
            local isArc9 = IsValid(wep) and wep.ARC9

            -- 处理已有的异步任务
            local task = proxy._penetrationTask
            if task then
                local finished = task:Step()
                if finished then
                    -- 任务完成，使用缓存的武器参数计算结果
                    local params = proxy._penetrationParams
                    if params and task.walls then
                        local result = PredictPenetration(task.walls, params.pen, params.maxLayers)
                        canPenetrate = (result == PenetrationResult.CAN_PENETRATE or result == PenetrationResult.UNCERTAIN)
                        proxy._lastCanPenetrate = canPenetrate
                    end
                    -- 清理任务和参数
                    proxy._penetrationTask = nil
                    proxy._penetrationParams = nil
                else
                    -- 任务未完成，使用上次结果（如果有）
                    canPenetrate = proxy._lastCanPenetrate
                end
            end

            -- 如果没有任务（或任务刚完成清理），且武器有效，则创建新任务
            if not proxy._penetrationTask and isArc9 then
                local pen = wep:GetProcessedValue("Penetration")
                local maxLayers = wep.MaxPenetrationLayers or 3
                -- 创建异步任务
                local walls, newTask = RegisterWallInfoAlongLine(attacker, victim, base.attackerShootPos, targetPos)
                proxy._penetrationTask = newTask
                proxy._penetrationParams = { pen = pen, maxLayers = maxLayers }
                -- 将任务对象与结果表关联（以便完成后获取 walls）
                newTask.walls = walls
                -- 此时任务尚未完成，canPenetrate 还未计算，先不设置
            end

            -- 若 canPenetrate 仍为 nil，则使用旧阈值回退
            if canPenetrate == nil then
                canPenetrate = (base.wallThickness <= WALL_THICKNESS_THRESHOLD)
            end

            -- 根据 canPenetrate 决定 targetPos
            if canPenetrate then
                local distToHit = base.attackerShootPos:Distance(base.attackerSideHitPos)
                if distToHit < COMBINE_RANGE then
                    targetPos = base.attackerSideHitPos
                    placementReason = "thin wall, close suppress"
                else
                    targetPos = base.attackerShootPos + base.direction * COMBINE_RANGE
                    placementReason = "thin wall, ranged suppress"
                end
            else
                targetPos = targetPos -- 原 targetPos 是 targetBonePos
                placementReason = "thick wall, proxy at victim"
            end
        else
            -- 非压制状态，清除异步任务缓存
            if proxy._penetrationTask then
                proxy._penetrationTask = nil
                proxy._penetrationParams = nil
                proxy._lastCanPenetrate = nil
            end
            -- 原有逻辑：非压制时按旧规则放置
            if base.isVisible and base.isRanged then
                targetPos = base.attackerShootPos + base.direction * COMBINE_RANGE
                placementReason = "visible out of range"
            else
                targetPos = targetPos
                placementReason = "default (visible & in-range or no info)"
            end
        end

        -- 以下代码不变：设置代理位置、角度、敌人关系、调试等
        local idealPos = targetPos - base.direction * PROXY_OFFSET
        local finalPos = ComputeJitteredPosition(idealPos, base.direction, confidence)

        if hasRecentInfo then
            attacker:SetEnemy(proxy)
            attacker:UpdateEnemyMemory(proxy, proxy:GetPos())
        end

        UpdateProxyDebugState(proxy, currentTime, attacker, victim, base, hasRecentSight, hasRecentSound, hasRecentInfo,
            shouldSuppress, placementReason)

        proxy:SetPos(finalPos)
        proxy:SetAngles(base.direction:Angle())
    end
end

local function SyncAllProxies()
    for victim, attackerProxyMapView in ProxyManager.IterateVictimsWithAttackerProxyMapView() do
        if IsValid(victim) then
            SyncProxiesForSingleVictim(victim, attackerProxyMapView)
        end
    end
end

hook.Add("Tick", "ENP_ProxyManagerSync", function()
    SyncAllProxies()
    -- ProxyManager.UpdatePrintTableTimer()
end)
