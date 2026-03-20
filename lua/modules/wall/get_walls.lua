-- lua\modules\wall\get_walls.lua

local PENETRATION_EPSILON = 1.0
local MAX_PENETRATION_ITERATIONS = 128
local INITIAL_STEP = 2.0
local BINARY_SEARCH_PRECISION = 2.0

-- 状态枚举
local TaskState = {
    START = "START",
    TRACE_WALL = "TRACE_WALL",
    MEASURE_THICKNESS = "MEASURE_THICKNESS",
    DONE = "DONE"
}

local ThicknessPhase = {
    EXPONENTIAL = "EXPONENTIAL",
    BINARY = "BINARY"
}

--- 根据 ARC9 规则计算实体的扩展 AABB（将原包围盒从中心向外扩展 25%）。
--- @param ent Entity
--- @return Vector, Vector
local function GetExpandedAABB(ent)
    local mins, maxs = ent:WorldSpaceAABB()
    local wsc = ent:WorldSpaceCenter()
    local expMins = mins + (mins - wsc) * 0.25
    local expMaxs = maxs + (maxs - wsc) * 0.25
    return expMins, expMaxs
end

--- 判断射线点是否仍在指定实体（或世界）内部，完全贴合 ARC9 的 IsPenetrating 逻辑。
--- @param ptr TraceResult
--- @param ptrent Entity
--- @return boolean
local function IsPenetrating(ptr, ptrent)
    if ptrent:IsWorld() then
        return not ptr.StartSolid or ptr.AllSolid
    elseif IsValid(ptrent) then
        local mins, maxs = GetExpandedAABB(ptrent)
        local withinbounding = ptr.HitPos:WithinAABox(mins, maxs)
        if withinbounding then
            return true
        end
    end
    return false
end

--- 入射角计算（0° 掠射，90° 垂直）。
--- @param hitNormal Vector
--- @param shotDir Vector
--- @return number
local function GetIncidentAngle(hitNormal, shotDir)
    local dot = shotDir:Dot(hitNormal)
    local cosAngle = math.abs(dot)
    local angleRad = math.acos(math.Clamp(cosAngle, -1, 1))
    return 90 - math.deg(angleRad)
end

--- 射线与 AABB 快速求交（无 trace 开销）。
--- @param origin Vector
--- @param dir Vector
--- @param mins Vector
--- @param maxs Vector
--- @return number, number
local function RayIntersectAABB(origin, dir, mins, maxs)
    local t1 = (mins.x - origin.x) / dir.x
    local t2 = (maxs.x - origin.x) / dir.x
    local tmin = math.min(t1, t2)
    local tmax = math.max(t1, t2)

    local ty1 = (mins.y - origin.y) / dir.y
    local ty2 = (maxs.y - origin.y) / dir.y
    tmin = math.max(tmin, math.min(ty1, ty2))
    tmax = math.min(tmax, math.max(ty1, ty2))

    local tz1 = (mins.z - origin.z) / dir.z
    local tz2 = (maxs.z - origin.z) / dir.z
    tmin = math.max(tmin, math.min(tz1, tz2))
    tmax = math.min(tmax, math.max(tz1, tz2))

    return tmin, tmax
end

--- 异步计算任务对象。
local WallInfoTask = {}
WallInfoTask.__index = WallInfoTask

--- 创建新任务，返回空结果表和任务对象。
--- @param attacker Entity
--- @param victim Entity
--- @param attackerPos Vector
--- @param victimPos Vector
--- @return table, WallInfoTask
function WallInfoTask.New(attacker, victim, attackerPos, victimPos)
    local self = setmetatable({}, WallInfoTask)
    self.attacker = attacker
    self.victim = victim
    self.attackerPos = attackerPos
    self.victimPos = victimPos
    self.walls = {} -- 结果表，逐步填充
    self.currentPos = attackerPos
    self.dir = (victimPos - attackerPos):GetNormalized()
    self.remainingDist = attackerPos:Distance(victimPos)
    self.iter = 0
    self.filterEnts = { attacker, victim }
    self.state = TaskState.START -- 主状态机状态
    self.done = false
    -- 厚度测量临时数据
    self.thickness_state = nil
    -- 当前墙体临时数据
    self.current_wall = nil
    return self, self.walls
end

--- 执行一步，只进行一次 util.TraceLine。
--- @return boolean 是否完成
function WallInfoTask:Step()
    if self.done then return true end

    -- 主状态机
    if self.state == TaskState.START then
        if self.remainingDist <= 0 or self.iter >= MAX_PENETRATION_ITERATIONS then
            self.done = true
            self.state = TaskState.DONE
            return true
        else
            self.state = TaskState.TRACE_WALL
        end
    end

    if self.state == TaskState.TRACE_WALL then
        -- 执行一次射线，寻找下一个墙体
        local trace = util.TraceLine({
            start = self.currentPos,
            endpos = self.victimPos,
            mask = MASK_SHOT,
            filter = self.filterEnts
        })
        if not trace.Hit or trace.HitSky then
            self.done = true
            self.state = TaskState.DONE
            return true
        end

        local hitEnt = trace.Entity
        local isWorld = hitEnt:IsWorld()
        local incidentAngle = GetIncidentAngle(trace.HitNormal, self.dir)

        -- 保存当前墙体信息，待厚度测量完成后写入结果
        self.current_wall = {
            trace = trace,
            hitEnt = hitEnt,
            isWorld = isWorld,
            incidentAngle = incidentAngle,
            className = isWorld and "world" or hitEnt:GetClass()
        }

        local startPos = trace.HitPos + self.dir * PENETRATION_EPSILON

        if isWorld then
            -- 世界墙体：直接进入通用厚度测量
            self:_initThicknessMeasurement(startPos, self.dir, hitEnt, self.remainingDist, trace.MatType)
            self.state = TaskState.MEASURE_THICKNESS
        else
            -- 实体墙体：尝试快速 AABB 求交
            local expMins, expMaxs = GetExpandedAABB(hitEnt)
            if startPos:WithinAABox(expMins, expMaxs) then
                local tmin, tmax = RayIntersectAABB(startPos, self.dir, expMins, expMaxs)
                if tmax > tmin and tmax > 0 then
                    -- 快速路径成功，无需额外 trace
                    local thickness = tmax
                    local exitPos = startPos + self.dir * tmax
                    local matType = trace.MatType or 0
                    self:_recordWall(thickness, exitPos, matType)
                    self.currentPos = exitPos + self.dir * PENETRATION_EPSILON
                    self.remainingDist = self.victimPos:Distance(self.currentPos)
                    self.iter = self.iter + 1
                    self.state = TaskState.START -- 进入下一面墙体
                    return false
                end
            end
            -- 快速路径失败，回退到通用测量
            self:_initThicknessMeasurement(startPos, self.dir, hitEnt, self.remainingDist, trace.MatType)
            self.state = TaskState.MEASURE_THICKNESS
        end
        return false
    end

    if self.state == TaskState.MEASURE_THICKNESS then
        local ts = self.thickness_state
        if ts.phase == ThicknessPhase.EXPONENTIAL then
            -- 指数步进阶段：一次射线
            if ts.traveled >= ts.maxDist then
                -- 未找到出口，直接记录当前厚度
                local thickness = ts.traveled
                local exitPos = ts.currentPos
                local matType = ts.firstMatType
                self:_recordWall(thickness, exitPos, matType)
                self.currentPos = exitPos + self.dir * PENETRATION_EPSILON
                self.remainingDist = self.victimPos:Distance(self.currentPos)
                self.iter = self.iter + 1
                self.state = TaskState.START
                return false
            end

            local nextPos = ts.currentPos + ts.dir * ts.step
            local trace = util.TraceLine({
                start = ts.currentPos,
                endpos = nextPos,
                mask = MASK_SHOT
            })
            local inside = (trace.Entity == ts.target) and IsPenetrating(trace, ts.target)

            if inside then
                ts.traveled = ts.traveled + ts.step
                ts.currentPos = nextPos
                ts.lastInsidePos = nextPos
                ts.lastInsideTrace = trace
                ts.step = ts.step * 2
                return false -- 继续指数步进
            else
                -- 找到出口，切换到二分搜索阶段
                ts.left = ts.lastInsidePos
                ts.right = nextPos
                ts.leftTrace = ts.lastInsideTrace
                ts.rightTrace = trace
                ts.phase = ThicknessPhase.BINARY
                return false
            end
        elseif ts.phase == ThicknessPhase.BINARY then
            -- 二分搜索阶段：一次射线
            if ts.right:Distance(ts.left) < BINARY_SEARCH_PRECISION then
                -- 精度达到，测量完成
                local exitPos = ts.right
                local thickness = ts.startPos:Distance(exitPos)
                local matType = ts.rightTrace.MatType or ts.firstMatType
                self:_recordWall(thickness, exitPos, matType)
                self.currentPos = exitPos + self.dir * PENETRATION_EPSILON
                self.remainingDist = self.victimPos:Distance(self.currentPos)
                self.iter = self.iter + 1
                self.state = TaskState.START
                return false
            end

            local mid = ts.left + (ts.right - ts.left) * 0.5
            local trace = util.TraceLine({
                start = ts.left,
                endpos = mid,
                mask = MASK_SHOT
            })
            local midInside = (trace.Entity == ts.target) and IsPenetrating(trace, ts.target)

            if midInside then
                ts.left = mid
                ts.leftTrace = trace
            else
                ts.right = mid
                ts.rightTrace = trace
            end
            return false
        end
    end

    if self.state == TaskState.DONE then
        self.done = true
        return true
    end

    return false
end

--- 初始化厚度测量状态机。
--- @param startPos Vector
--- @param dir Vector
--- @param target Entity
--- @param maxDist number
--- @param firstMatType number
function WallInfoTask:_initThicknessMeasurement(startPos, dir, target, maxDist, firstMatType)
    self.thickness_state = {
        phase = ThicknessPhase.EXPONENTIAL,
        startPos = startPos,
        dir = dir,
        target = target,
        maxDist = maxDist,
        firstMatType = firstMatType,
        currentPos = startPos,
        lastInsidePos = startPos,
        lastInsideTrace = nil,
        step = INITIAL_STEP,
        traveled = 0,
        left = nil,
        right = nil,
        leftTrace = nil,
        rightTrace = nil,
    }
end

--- 将当前墙体信息写入结果表。
--- @param thickness number
--- @param exitPos Vector
--- @param matType number
function WallInfoTask:_recordWall(thickness, exitPos, matType)
    local wall = self.current_wall
    table.insert(self.walls, {
        className = wall.className,
        thickness = thickness,
        hitPos = wall.trace.HitPos,
        exitPos = exitPos,
        matType = matType,
        incidentAngle = wall.incidentAngle
    })
end

--- 对外注册函数：创建异步任务，返回空结果表和任务对象。
--- @param attacker Entity
--- @param victim Entity
--- @param attackerPos Vector
--- @param victimPos Vector
--- @return table, WallInfoTask
function RegisterWallInfoAlongLine(attacker, victim, attackerPos, victimPos)
    return WallInfoTask.New(attacker, victim, attackerPos, victimPos)
end

-- 使用说明
-- -- 注册任务，立即获得空结果表 walls
-- local walls, task = GetWallInfoAlongLine(attacker, victim, attackerPos, victimPos)

-- -- 每帧调用一次 Step，直至返回 true
-- function OnTick()
--     if task:Step() then
--         -- 计算完成，walls 表已被完全填充
--         print("完成", walls)
--     else
--         -- 计算中，walls 表可能已有部分墙体信息
--         print("当前已穿透墙体数", #walls)
--     end
-- end
