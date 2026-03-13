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
          - **薄墙（≤32 单位）**：认为子弹可以穿透此厚度的墙。代理被放置在墙表面（攻击者一侧），使攻击者可见代理（或至少感知到敌人在墙后方向），从而激发其使用武器的穿墙能力向墙后射击，实现压制。
          - **厚墙（>32 单位）**：子弹无法穿透。为避免攻击者徒劳攻击不可穿透的掩体，代理被放置在受害者位置（墙后），使攻击者无法看见代理，从而触发 Source 引擎的寻路行为，让攻击者绕墙寻找可见目标。

       此外，墙厚超过 32 单位（即可穿透的最大厚度）时，`IsSoundAudible` 会直接判定声音不可听见（听觉记忆失效），避免对不可穿透的墙体进行不必要的压制计算，进一步强化厚墙时应绕行的逻辑。

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

local PROXY_CLASS               = ProxyManager.PROXY_CLASS
local PROXY_FIELDS              = ProxyManager.PROXY_FIELDS
local COMBINE_RANGE             = ProxyManager.ATTACKER_RANGE
local SIGHT_MEMORY_DURATION     = ProxyManager.SIGHT_MEMORY_DURATION
local SOUND_MEMORY_DURATION     = ProxyManager.SOUND_MEMORY_DURATION
local FACE_COOLDOWN             = ProxyManager.FACE_COOLDOWN
local WALL_THICKNESS_THRESHOLD  = 256
local WALL_ATTENUATION_PER_UNIT = 0.1
local HEAR_THRESHOLD            = 10
local PROXY_OFFSET              = ProxyManager.PROXY_OFFSET
local DEBUG                     = ProxyManager.DEBUG

local IsValid                   = IsValid
local CurTime                   = CurTime
local util_TraceLine            = util.TraceLine
local MASK                      = MASK_VISIBLE

local HULL_SIZE                 = 8 -- 半边长，即从 -2 到 2
local hullMins                  = Vector(-HULL_SIZE / 2, -HULL_SIZE / 2, -HULL_SIZE / 2)
local hullMaxs                  = Vector(HULL_SIZE / 2, HULL_SIZE / 2, HULL_SIZE / 2)

-- 坐标量化辅助函数
local function QuantizeVector(v, gridSize)
    gridSize = gridSize or 10 -- 默认网格大小 10 单位
    return Vector(
        math.floor(v.x / gridSize) * gridSize,
        math.floor(v.y / gridSize) * gridSize,
        0
    -- math.floor(v.z / gridSize) * gridSize
    )
end

-- 生成感知任务键（用于调试打印控制和未来缓存）
local function GetPerceptionTaskKey(victimPos, attackerPos, victim, attacker, sourceSPL, gridSize)
    -- 量化坐标
    local qVictimPos = QuantizeVector(victimPos, gridSize)
    local qAttackerPos = QuantizeVector(attackerPos, gridSize)
    -- 构建键：实体索引 + 量化坐标 + 声压级（若无声音则用特殊值）
    local splKey = sourceSPL and string.format("%.0f", sourceSPL) or "nosound"
    return string.format("%d_%d_%s_%s_%s",
        victim:EntIndex(),
        attacker:EntIndex(),
        tostring(qVictimPos),
        tostring(qAttackerPos),
        splKey
    )
end

-- 用于存储上次打印的任务键（按受害者-攻击者对索引）
local _lastPrintKey = setmetatable({}, { __mode = "k" })

-- 材料衰减系数查询函数（占位，返回常数 -5dB）
local function GetMaterialAttenuation(materialType)
    return -5
end

--[[
    感知检测函数（视觉+听觉）
    参数:
        victimPos   - 受害者位置 (Vector)
        attackerPos - 攻击者位置 (Vector)
        victim      - 受害者实体 (Entity)
        attacker    - 攻击者实体 (Entity)
        sourceSPL   - 可选，声源在1米处的声压级 (dB)，若为 nil 则表示无声（仅执行视觉检测）
    返回:
        isVisible     - 视觉可见性 (boolean) —— 攻击者是否直接看到受害者
        isAudible     - 听觉可听性 (boolean) —— 攻击者是否能听到受害者发出的声音
        wallThickness - 累计穿过的墙体总厚度 (number) —— 声波路径上所有实体厚度的累加
        firstHitPos   - 从攻击者出发第一次击中的位置 (Vector)，若视觉可见则为 nil
--]]
local function IsPerceptive(victimPos, attackerPos, stableVictimPos, victim, attacker, sourceSPL)
    local pairKey = victim:EntIndex() * 10000 + attacker:EntIndex()
    local taskKey = GetPerceptionTaskKey(stableVictimPos, attackerPos, victim, attacker, sourceSPL, 16)
    local shouldPrint = DEBUG and (_lastPrintKey[pairKey] ~= taskKey)

    if shouldPrint then
        -- 更新打印键
        _lastPrintKey[pairKey] = taskKey
        -- 入口打印
        local distance = victimPos:Distance(attackerPos)
        MsgN("----------")
        MsgN("[IsPerceptive] Called with: taskKey=" .. taskKey)
        MsgN("distance=" .. distance ..
            ", victim=" .. victim:EntIndex() ..
            ", attacker=" .. attacker:EntIndex() ..
            ", sourceSPL=" .. tostring(sourceSPL or "nil") ..
            ".")
    end

    -- 1. 视觉检测：从攻击者向受害者发射射线，仅排除攻击者自身
    local visTrace = util_TraceLine({
        start = attackerPos,
        endpos = victimPos,
        -- maxs = hullMaxs,
        -- mins = hullMins,
        filter = attacker,
        mask = MASK,
    })

    -- 视觉可见条件：射线直接命中受害者实体
    local isVisible = (visTrace.Entity == victim)
    local firstHitPos = nil                                                     -- 默认无命中点

    local engineLineOfSightClear = attacker:IsLineOfSightClear(victim:EyePos()) -- 用稳定位置测试
    if shouldPrint then
        local hitEntity = visTrace.Entity
        local hitEntityInfo = "None"
        if IsValid(hitEntity) then
            hitEntityInfo = string.format("%s:%d", hitEntity:GetClass(), hitEntity:EntIndex())
        end
        MsgN("[Debug] Trace hit entity:", hitEntityInfo)
        MsgN("[Debug] IsLineOfSightClear result:", engineLineOfSightClear, "vs our isVisible:", isVisible)
    end

    -- 2. 若无声（sourceSPL 为 nil），则直接返回视觉结果，听觉为 false，墙厚为 0
    if sourceSPL == nil then
        local firstHitPos = isVisible and nil or visTrace.HitPos -- 视觉不可见时返回命中点
        if shouldPrint then
            MsgN("[IsPerceptive] No sound source, returning visual only: isVisible=" .. tostring(isVisible))
        end
        return isVisible, false, 0, firstHitPos
    end

    -- 3. 声音传播计算
    local distance = math.max(victimPos:Distance(attackerPos), 1)
    local distanceAttenuation = 20 * math.log10(distance) -- 距离衰减 dB
    local threshold = 0                                   -- 可听阈值 dB，可调整

    local totalObstacleAttenuation = 0                    -- 材料衰减累计（dB）
    local totalWallThickness = 0                          -- 墙厚累计（游戏单位）

    -- 如果视觉可见，则直接根据距离衰减判断可听性（墙厚为 0，firstHitPos = nil）
    if isVisible then
        local finalSPL = sourceSPL - distanceAttenuation
        local isAudible = finalSPL > threshold
        if shouldPrint then
            MsgN("[IsPerceptive] Visible, finalSPL=" .. finalSPL .. ", isAudible=" .. tostring(isAudible))
        end
        return true, isAudible, 0, nil
    end

    -- 视觉不可见：记录第一次命中点
    firstHitPos = visTrace.HitPos
    local startPos = firstHitPos
    local inside = true       -- 已进入第一个实体
    local entryPos = startPos -- 记录进入点
    totalObstacleAttenuation = totalObstacleAttenuation + GetMaterialAttenuation(visTrace.MatType)

    local dir = (victimPos - attackerPos):GetNormalized() -- 从攻击者指向受害者的方向
    local epsilon = 0.1                                   -- 微小偏移，避免卡在表面
    local maxIter, iter = 100, 0

    -- 后续追踪需要排除攻击者和受害者实体，避免将终点本身当作障碍物
    local filter = { victim, attacker }

    while iter < maxIter do
        iter = iter + 1
        dir = (victimPos - startPos):GetNormalized() -- 更新方向（起点移动后）

        local trace = util_TraceLine({               -- https://wiki.facepunch.com/gmod/util.TraceLine
            start = startPos + dir * epsilon,        -- 沿方向微移，避免卡在同一表面
            endpos = victimPos,
            filter = filter,
            mask = MASK,
        })

        if trace.Hit then
            -- 累计材料衰减
            totalObstacleAttenuation = totalObstacleAttenuation + GetMaterialAttenuation(trace.MatType)

            if inside then
                -- 退出当前实体：计算本次穿透厚度
                local thickness = trace.HitPos:Distance(entryPos)
                totalWallThickness = totalWallThickness + thickness
                inside = false
                entryPos = nil

                -- -- 提前返回：累计墙厚超过阈值则判定不可听见，节约计算性能
                -- if totalWallThickness > WALL_THICKNESS_THRESHOLD then
                --     if DEBUG and currentTick % IS_PERCEPTIVE_DEBUG_PRINT_RATE == 0 then
                --         MsgN("[IsPerceptive] Wall thickness > WALL_THICKNESS_THRESHOLD, aborting: thickness=" ..
                --             totalWallThickness)
                --     end
                --     return isVisible, false, totalWallThickness, firstHitPos
                -- end
            else
                -- 进入新实体
                entryPos = trace.HitPos
                inside = true
            end

            -- 声压级提前检查（距离衰减使用总距离，保持不变）
            if sourceSPL - distanceAttenuation + totalObstacleAttenuation <= threshold then
                if shouldPrint then
                    MsgN("[IsPerceptive] Sound pressure below threshold after obstacles, finalSPL=" ..
                        (sourceSPL - distanceAttenuation + totalObstacleAttenuation))
                end
                return isVisible, false, totalWallThickness, firstHitPos
            end

            -- 更新起点为击中点，准备下一次追踪
            startPos = trace.HitPos
        else
            -- 未击中任何物体，说明已到达目标（受害者位置），但因过滤了目标实体，所以不会命中目标本身
            break
        end
    end

    -- 计算最终声压级并判断可听性
    local finalSPL = sourceSPL - distanceAttenuation + totalObstacleAttenuation
    local isAudible = finalSPL > threshold
    if shouldPrint then
        MsgN("[IsPerceptive] Final decision: isVisible=" ..
            tostring(isVisible) .. ", isAudible=" .. tostring(isAudible) .. ", wallThickness=" .. totalWallThickness)
        MsgN("----------")
    end
    return isVisible, isAudible, totalWallThickness, firstHitPos
end

local function SyncProxiesForSingleVictim(victim, attackerProxyMapView)
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
        local isOrphan = ProxyManager.CheckOrphanProxy(proxy)
        if isOrphan then
            -- 安全说明：此循环遍历 attackerProxyMapView（键为 attacker，值为 proxy）。
            -- 循环体内调用 ProxyManager.CheckOrphanProxy(proxy) 检查代理是否孤儿。
            -- 若代理无效，CheckOrphanProxy 会调用 ProxyManager.RemoveProxy(proxy.victim, proxy.attacker)，
            -- 该函数从内部表 _attackersByVictim[victim] 中移除键 attacker，即当前迭代的键。
            -- 在 Lua 的 next/pairs 遍历中，删除当前迭代的键是安全的，不会导致跳过或重复。
            -- 警告：请勿在此循环中删除任何其他键（非当前 attacker），否则可能破坏迭代器状态。
            -- 若将来需要删除其他键，请改用“先收集键，后删除”模式。
            continue -- Gmod 支持此关键字
        end

        local attackerShootPos   = attacker:GetShootPos()
        local distance           = attackerShootPos:Distance(targetBonePos)
        local direction          = (targetBonePos - attackerShootPos):GetNormalized()

        local attackerSideTrace  = util_TraceLine({ -- https://wiki.facepunch.com/gmod/util.TraceLine
            start = attackerShootPos,
            endpos = targetBonePos,
            filter = attacker,
            mask = MASK_SHOT,
        })
        local attackerSideHitPos = attackerSideTrace.HitPos

        local victimSideTrace    = util_TraceLine({
            start = targetBonePos,
            endpos = attackerShootPos,
            filter = victim,
            mask = MASK_SHOT,
        })

        local victimSideHitPos   = victimSideTrace.HitPos

        local wallThickness      = attackerSideHitPos:Distance(victimSideHitPos)
        local lastSoundLevel     = proxy[PROXY_FIELDS.LAST_SOUND_LEVEL]
        local distAtten          = 20 * math.log10(math.max(distance, 1))
        local wallAtten          = wallThickness * WALL_ATTENUATION_PER_UNIT
        local finalSoundLevel    = lastSoundLevel - distAtten - wallAtten

        --[[
            简单声学模型参数说明（修订版）
            ================================
            声源声压级（SPL）参考值（1米处）：
            - 枪声：140 dB（对应 SNDLVL_140dB / SNDLVL_GUNFIRE，阈值痛觉）
            - 跑步：75 dB（对应 SNDLVL_75dB / SNDLVL_NORM，繁忙交通）
            - 走路：60 dB（对应 SNDLVL_60dB / SNDLVL_IDLE，正常交谈）
            - 蹲走：50 dB（接近安静交谈，略高于图书馆环境）

            墙体衰减系数：0.1 dB/单位（线性模型，即每游戏单位墙体厚度衰减0.1 dB）
            可听阈值：10 dB（最终声压级高于10 dB才认为可听见，模拟环境背景噪音）

            ================================================================================
            一、自由声场最大可听距离（无墙，阈值10 dB）
            --------------------------------------------------------------------------------
            声源类型 | 源SPL (dB) | 最大可听距离 (单位)
            ---------|------------|--------------------
            枪声     | 140        | ≈ 3,162,278
            跑步     | 75         | ≈ 1,778
            走路     | 60         | ≈ 316
            蹲走     | 50         | 100

            注：枪声传播距离极大，实际游戏中几乎全图可闻；其他声音距离适中。

            ================================================================================
            二、典型交战距离下“恰能听到”的墙体厚度（阈值10 dB）
            下表列出了在不同直线距离 D 处，要恰好让声音被听到（最终SPL = 10 dB）所需的墙体厚度（单位：游戏单位）。
            负值表示即使无墙也无法听到（距离衰减已使声压级低于10 dB）。

            距离 D   | 枪声 (140 dB) | 跑步 (75 dB) | 走路 (60 dB) | 蹲走 (50 dB)
            ---------|---------------|--------------|--------------|---------------
            200      | 839.8         | 189.8        | 39.8         | -60.2
            300      | 804.6         | 154.6        | 4.6          | -95.4
            400      | 779.6         | 129.6        | -20.4        | -120.4
            500      | 760.2         | 110.2        | -39.8        | -139.8
            600      | 744.4         | 94.4         | -55.6        | -155.6

            解读：
            - 枪声穿透力极强，在300单位距离时仍可穿透约805单位厚的墙。
            - 跑步声在300单位时可穿透约155单位厚墙，适合压制厚墙后的敌人。
            - 走路声在300单位时仅能穿透约5单位厚墙，轻微遮挡即可屏蔽。
            - 蹲走声在所有距离超过约180单位后即无法听到，仅在极近距离可能被听到。

            参数调整建议：
            - 若需增强蹲走战术价值，可将其SPL提高至55 dB，或降低阈值至5 dB。
            - 墙体衰减系数0.1可根据游戏节奏微调。
            - 阈值10 dB模拟了背景噪音，若需更灵敏听觉可降至5 dB。

            使用示例：
            local function isSoundAudible(attackerPos, targetPos, wallThickness, soundLevel)
                if not soundLevel or soundLevel <= 0 then return false end
                local dist = attackerPos:Distance(targetPos)
                local distAtten = 20 * math.log10(math.max(dist, 1))
                local wallAtten = wallThickness * 0.1
                local finalSPL = soundLevel - distAtten - wallAtten
                return finalSPL > 10
            end
        ]]

        local isAudible                      = finalSoundLevel > HEAR_THRESHOLD
        local isVisible                      = attacker:Visible(victim)
        local isRanged                       = distance > COMBINE_RANGE

        proxy[PROXY_FIELDS.LAST_SOUND_LEVEL] = 0

        if isVisible then
            proxy[PROXY_FIELDS.LAST_SIGHT_TIME] = currentTime
        end
        if isAudible then
            proxy[PROXY_FIELDS.LAST_SOUND_TIME] = currentTime
        end

        local hasRecentSight      = (currentTime - proxy[PROXY_FIELDS.LAST_SIGHT_TIME]) <= SIGHT_MEMORY_DURATION
        local hasRecentSound      = (currentTime - proxy[PROXY_FIELDS.LAST_SOUND_TIME]) <= SOUND_MEMORY_DURATION
        local hasRecentInfo       = hasRecentSound or hasRecentSight
        local shouldSuppress      = not isVisible and hasRecentInfo
        local shouldCloseSuppress = shouldSuppress and not isRanged

        local targetPos
        local placementReason

        if shouldSuppress then
            if isAudible then -- 本帧可听，设置转向，只需本帧设置一次
                local lastFace = proxy[PROXY_FIELDS.LAST_FACE_TIME]
                if currentTime - lastFace >= FACE_COOLDOWN then
                    local curSched = attacker:GetCurrentSchedule()
                    if curSched == SCHED_IDLE_STAND or curSched == SCHED_IDLE_WALK or SCHED_IDLE_WANDER then
                        if not IsValid(attacker:GetEnemy()) then
                            attacker:SetEnemy(proxy)
                            attacker:SetSchedule(SCHED_COMBAT_FACE)
                            proxy[PROXY_FIELDS.LAST_FACE_TIME] = currentTime
                        end
                    end
                end
            end

            if wallThickness > WALL_THICKNESS_THRESHOLD then
                targetPos = targetBonePos
                placementReason = "thick wall, proxy at victim"
            else
                if shouldCloseSuppress then
                    targetPos = attackerSideHitPos
                    placementReason = "thin wall, close suppress"
                else                              -- shouldRangedSuppress = shouldSuppress and isRanged
                    targetPos = attackerShootPos +
                        direction * COMBINE_RANGE -- COMBINE_RANGE = 1024 + PROXY_OFFSET，已经纳入考虑
                    placementReason = "thin wall, ranged suppress"
                end
            end
        elseif isVisible and isRanged then
            targetPos = attackerShootPos + direction * COMBINE_RANGE
            placementReason = "visible out of range"
        else
            targetPos = targetBonePos
            placementReason = "default (visible & in-range or no info)"
        end

        -- 获取或初始化代理的调试状态表
        if not proxy._debugState then
            proxy._debugState = {}
        end
        local oldState = proxy._debugState

        -- 构建当前状态表（用于检测变化）
        local newState = {
            isVisible = isVisible,
            isAudible = isAudible,
            hasRecentSight = hasRecentSight,
            hasRecentSound = hasRecentSound,
            hasRecentInfo = hasRecentInfo,
            shouldSuppress = shouldSuppress,
            isRanged = isRanged,
            placementReason = placementReason,
        }

        -- 状态变化时打印完整调试信息
        if DEBUG then
            -- 检测状态是否发生变化
            local stateChanged = false
            for k, v in pairs(newState) do
                if oldState[k] ~= v then
                    stateChanged = true
                    break
                end
            end

            if stateChanged then
                MsgN("=====" .. currentTime .. "=====")
                MsgN(string.format(
                    "[ProxySync] Attacker[%d] -> Victim[%d]: isVisible=%s, isAudible=%s, wallThickness=%.2f, hasRecentSight=%s, hasRecentSound=%s, hasRecentInfo=%s, shouldSuppress=%s, isRanged=%s, placementReason=%s",
                    attacker:EntIndex(), victim:EntIndex(),
                    tostring(isVisible), tostring(isAudible), wallThickness,
                    tostring(hasRecentSight), tostring(hasRecentSound), tostring(hasRecentInfo),
                    tostring(shouldSuppress), tostring(isRanged),
                    tostring(placementReason)))
                MsgN("==========")
                -- 更新存储的状态
                proxy._debugState = newState
            end
        end

        proxy:SetPos(targetPos - direction * PROXY_OFFSET)
        proxy:SetAngles(direction:Angle())
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
