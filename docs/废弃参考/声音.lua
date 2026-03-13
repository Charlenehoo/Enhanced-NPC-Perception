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
