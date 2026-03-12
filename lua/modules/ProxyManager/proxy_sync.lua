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

    3. 代理可见性决定 NPC 的战术选择
       - **代理对 NPC 可见时**：NPC 会将代理视为敌人并尝试攻击（攻击代理）。此时代理位置决定了射击方向：
            * 如果代理位于墙表面（薄墙）或连线上，NPC 会向代理射击，进而触发其武器的穿墙能力向墙后压制。
            * 如果受害者可见但超出射程，代理被拉至 NPC 前方固定距离（1024 单位），使 NPC 保持在有效射程内射击。
       - **代理对 NPC 不可见时**：NPC 没有可攻击的目标，根据 Source 引擎的标准 AI 行为，它会尝试移动绕墙（寻路）来寻找可见的敌人。这正是墙厚分支的设计意图：
            * 当墙厚 > 32（太厚无法射穿），代理紧贴受害者（墙后），对 NPC 不可见 → NPC 会采取绕墙策略。
            * 当墙薄 ≤ 32，代理置于墙表面（NPC 可见）→ NPC 继续压制射击。

    4. 压制射击的机制：能力 + 意愿
       - **能力**：Source 引擎中，许多武器的子弹具备穿透薄墙的能力（由武器脚本定义）。这是引擎基础功能，本模块并未修改。
       - **意愿**：NPC 只有在拥有明确敌人（即代理）时才会尝试射击。通过将代理放置在薄墙表面（攻击者一侧），让 NPC 看见代理（或至少感知到敌人在墙后方向），从而激发其使用穿墙射击的意愿。
       - **结果**：当墙薄时，NPC 会向墙后的代理射击，子弹穿透墙壁，最终可能击中墙后的真实受害者（或至少实现压制效果）。当墙太厚时，代理不可见，NPC 放弃射击，转而绕墙——这正是战术模拟的核心。

    5. 基于 Source 引擎 AI 特性的行为引导与增强
       - 攻击者对距离 1024 单位内的敌人才会主动交战（COMBINE_RANGE 基于此设定）。超过此距离，即使武器具备远程射击能力（由武器 Base 定义），引擎也不会给予 NPC 远射的意愿，导致其不会攻击远处目标。
       - 本模块通过代理机制弥补这一缺陷：当受害者超出攻击者射程时（isRanged 分支），将代理置于攻击者前方 1024 单位处（沿攻击者到受害者的方向），使攻击者获得一个位于射程内的敌人，从而激发其交战意愿。此时 NPC 会向代理射击，而武器自身的弹道可能覆盖更远距离（取决于武器属性），最终可能命中远处的受害者或至少实现压制效果。
       - 声音记忆（lastSoundTimeTime）用于触发攻击者转向，但实际转向通过设置敌人（SetEnemy）和强制调度实现，避免依赖声音系统。

    6. 代理位置微调（PROXY_OFFSET）
       在计算出目标位置（targetPos）后，最终设置代理位置时使用 `proxy:SetPos(targetPos - direction * PROXY_OFFSET)`，其中 PROXY_OFFSET = 2 单位。
       该偏移量根据代理实体使用的模型（enp_proxy 中设置为 `models/editor/cube_small.mdl`，缩放 0.04）大小计算得出，目的是将代理从目标点向攻击者方向轻微回拉，避免代理陷入墙体或受害者模型中。
       这一微调确保代理紧贴目标点但不穿透，保持位置稳定，避免因模型穿插导致的视觉异常或物理冲突。

    这种设计使每个 NPC 的行为独立且可控，通过代理位置间接实现复杂的战术响应，同时保持与受害者方向的关联。
]]

ProxyManager = ProxyManager or {}
ProxyManager.loopCountTable = ProxyManager.loopCountTable or {}
setmetatable(ProxyManager.loopCountTable, { __mode = "k" })

local TravelDistManager        = TravelDistManager
local PROXY_FIELDS             = ProxyManager.PROXY_FIELDS
local COMBINE_RANGE            = ProxyManager.ATTACKER_RANGE
local SIGHT_MEMORY_DURATION    = ProxyManager.SIGHT_MEMORY_DURATION
local SOUND_MEMORY_DURATION    = ProxyManager.SOUND_MEMORY_DURATION
local FACE_COOLDOWN            = ProxyManager.FACE_COOLDOWN
local WALL_THICKNESS_THRESHOLD = 32

local PROXY_OFFSET             = ProxyManager.PROXY_OFFSET

local IsValid                  = IsValid
local CurTime                  = CurTime
local util_TraceLine           = util.TraceLine

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

        -- proxy:SetModelScale(0.4)

        -- 新增声音中继逻辑，见 lua/modules/sound_relay.lua
        local lastSoundAudibleTime  = proxy[PROXY_FIELDS.LAST_SOUND_AUDIBLE_TIME] or 0
        local hasRecentSound        = (currentTime - lastSoundAudibleTime) <= SOUND_MEMORY_DURATION

        -- local lastFace = proxy[PROXY_FIELDS.LAST_FACE_TIME]
        -- if currentTime - lastFace >= FACE_COOLDOWN then
        --     local curSched = attacker:GetCurrentSchedule()
        --     if curSched == SCHED_IDLE_STAND or curSched == SCHED_IDLE_WALK or SCHED_IDLE_WANDER then
        --         if not IsValid(attacker:GetEnemy()) then
        --             attacker:SetEnemy(proxy)
        --             attacker:SetSchedule(SCHED_COMBAT_FACE)
        --             proxy[PROXY_FIELDS.LAST_FACE_TIME] = currentTime
        --         end
        --     end
        -- end

        local attackerShootPos      = attacker:GetShootPos()
        local distance              = attackerShootPos:Distance(targetBonePos)
        local isRanged              = distance > COMBINE_RANGE

        local victimSideTraceResult = util_TraceLine({ -- https://wiki.facepunch.com/gmod/util.TraceLine
            start = targetBonePos,
            endpos = attackerShootPos,
            filter = victim,
            mask = MASK_SHOT -- https://wiki.facepunch.com/gmod/Enums/MASK
        })
        local victimSideHitPos      = victimSideTraceResult.HitPos

        local isVisible             = victimSideTraceResult.Entity == attacker

        if isVisible then
            proxy[PROXY_FIELDS.LAST_SIGHT_TIME] = currentTime
        end

        local hasRecentSight       = (currentTime - proxy[PROXY_FIELDS.LAST_SIGHT_TIME]) <= SIGHT_MEMORY_DURATION
        local hasRecentInfo        = hasRecentSound or hasRecentSight
        local shouldSuppress       = not isVisible and hasRecentInfo
        local shouldCloseSuppress  = shouldSuppress and not isRanged
        local shouldRangedSuppress = shouldSuppress and isRanged

        local direction            = (targetBonePos - attackerShootPos):GetNormalized()

        local targetPos
        if shouldSuppress then
            local attackerSideTraceResult = util_TraceLine({ -- https://wiki.facepunch.com/gmod/util.TraceLine
                start = attackerShootPos,
                endpos = targetBonePos,
                filter = attacker,
                mask = MASK_SHOT -- https://wiki.facepunch.com/gmod/Enums/MASK
            })
            local attackerSideHitPos = attackerSideTraceResult.HitPos
            local wallThickNess = attackerSideHitPos:Distance(victimSideHitPos)

            if wallThickNess > WALL_THICKNESS_THRESHOLD then
                targetPos = targetBonePos
            else
                if shouldCloseSuppress then
                    targetPos = attackerSideHitPos
                else                              -- shouldRangedSuppress
                    targetPos = attackerShootPos +
                        direction * COMBINE_RANGE -- COMBINE_RANGE = 1024 + PROXY_OFFSET，已经纳入考虑
                end
            end
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
