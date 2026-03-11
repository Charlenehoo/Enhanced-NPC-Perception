-- ============================================================================
-- TravelDistManager - 异步导航距离请求系统
-- 功能：通过导航网格计算两点间的路径长度，支持缓存、优先队列、超时丢弃和动态计算速率
-- 新增：智能优先级提升（根据等待时间与预期处理时间比较决定是否插队）
-- ============================================================================

TravelDistManager = TravelDistManager or {}

-- ==================== 配置（可调） ====================
TravelDistManager.QUANTIZE_STEP = 20                -- 量化步长
TravelDistManager.CACHE_SIZE   = 256                 -- 环形缓冲区大小
TravelDistManager.BASE_MAX_CALC_PER_FRAME = 5        -- 基础每帧计算数
TravelDistManager.PRIORITY_INCREMENT_PER_TASK = 2    -- 每个优先任务额外增加的计算数
TravelDistManager.MAX_CALC_LIMIT = 20                 -- 每帧计算数上限
TravelDistManager.NORMAL_TIMEOUT = 2.0                -- 普通任务超时时间（秒）
TravelDistManager.TICK_RATE = 66.6                    -- 服务器 Tick 率（帧/秒）
TravelDistManager.PRIORITY_INSERT_FACTOR = 1.0        -- 插队阈值因子（等待时间 > 因子 * 预期处理时间 则插队）
TravelDistManager.INSERT_STRATEGY = "head_if_old"     -- 插入策略："tail"（始终队尾）或 "head_if_old"（智能判断）

-- ==================== 内部数据结构 ====================
TravelDistManager.cache = {}          -- 环形缓存
TravelDistManager.cacheIdx = 1
TravelDistManager.pendingTasks = {}    -- key -> { pos1, pos2, callbacks, timestamp, inQueue }
TravelDistManager.priorityQueue = {}   -- 优先队列（存储 key）
TravelDistManager.normalQueue = {}     -- 普通队列（存储 key）
TravelDistManager.isHookSet = false

-- ==================== 内部辅助函数 ====================
local function quantize(v)
    return math.floor(v / TravelDistManager.QUANTIZE_STEP + 0.5)
end

local function compareQuantized(x1, y1, z1, x2, y2, z2)
    if x1 ~= x2 then return x1 < x2 end
    if y1 ~= y2 then return y1 < y2 end
    return z1 < z2
end

-- 生成任务唯一标识（基于量化坐标和 NavArea ID，nil 统一转为 0）
local function getTaskKey(pos1, pos2)
    local q1x, q1y, q1z = quantize(pos1.x), quantize(pos1.y), quantize(pos1.z)
    local q2x, q2y, q2z = quantize(pos2.x), quantize(pos2.y), quantize(pos2.z)

    local area1 = navmesh.GetNearestNavArea(pos1)
    local area2 = navmesh.GetNearestNavArea(pos2)
    local id1 = area1 and area1:GetID() or 0
    local id2 = area2 and area2:GetID() or 0

    -- 规范化顺序，使 A->B 与 B->A 使用同一 key
    if not compareQuantized(q1x, q1y, q1z, q2x, q2y, q2z) then
        q1x, q1y, q1z, q2x, q2y, q2z = q2x, q2y, q2z, q1x, q1y, q1z
        id1, id2 = id2, id1
    end

    return string.format("%d_%d_%d_%d_%d_%d_%d_%d", q1x, q1y, q1z, q2x, q2y, q2z, id1, id2)
end

-- 实际计算距离（同步）
local function computeDistance(pos1, pos2)
    -- 快速失败：起点或终点不在导航网格上
    if not navmesh.GetNearestNavArea(pos1) or not navmesh.GetNearestNavArea(pos2) then
        return math.huge
    end

    local path = navmesh.FindPath(pos1, pos2)
    if not path or #path == 0 then
        return math.huge
    end
    local total = 0
    for _, seg in ipairs(path) do
        total = total + seg.start:Distance(seg.end)
    end
    return total
end

-- ==================== 缓存系统 ====================
function TravelDistManager:cacheLookup(pos1, pos2)
    local q1x, q1y, q1z = quantize(pos1.x), quantize(pos1.y), quantize(pos1.z)
    local q2x, q2y, q2z = quantize(pos2.x), quantize(pos2.y), quantize(pos2.z)

    local area1 = navmesh.GetNearestNavArea(pos1)
    local area2 = navmesh.GetNearestNavArea(pos2)
    local id1 = area1 and area1:GetID() or 0
    local id2 = area2 and area2:GetID() or 0

    -- 规范化顺序
    if not compareQuantized(q1x, q1y, q1z, q2x, q2y, q2z) then
        q1x, q1y, q1z, q2x, q2y, q2z = q2x, q2y, q2z, q1x, q1y, q1z
        id1, id2 = id2, id1
    end

    for i = 1, #self.cache do
        local e = self.cache[i]
        if e.q1x == q1x and e.q1y == q1y and e.q1z == q1z
           and e.q2x == q2x and e.q2y == q2y and e.q2z == q2z
           and e.id1 == id1 and e.id2 == id2 then
            return e.dist
        end
    end
    return nil
end

function TravelDistManager:cacheStore(pos1, pos2, dist)
    local q1x, q1y, q1z = quantize(pos1.x), quantize(pos1.y), quantize(pos1.z)
    local q2x, q2y, q2z = quantize(pos2.x), quantize(pos2.y), quantize(pos2.z)

    local area1 = navmesh.GetNearestNavArea(pos1)
    local area2 = navmesh.GetNearestNavArea(pos2)
    local id1 = area1 and area1:GetID() or 0
    local id2 = area2 and area2:GetID() or 0

    if not compareQuantized(q1x, q1y, q1z, q2x, q2y, q2z) then
        q1x, q1y, q1z, q2x, q2y, q2z = q2x, q2y, q2z, q1x, q1y, q1z
        id1, id2 = id2, id1
    end

    self.cache[self.cacheIdx] = {
        q1x = q1x, q1y = q1y, q1z = q1z,
        q2x = q2x, q2y = q2y, q2z = q2z,
        id1 = id1, id2 = id2,
        dist = dist,
    }
    self.cacheIdx = (self.cacheIdx % self.CACHE_SIZE) + 1
end

-- ==================== 核心逻辑 ====================
-- 动态计算当前每帧最大计算数
function TravelDistManager:getDynamicMaxCalc()
    local priorityCount = #self.priorityQueue
    local rate = self.BASE_MAX_CALC_PER_FRAME + priorityCount * self.PRIORITY_INCREMENT_PER_TASK
    return math.min(rate, self.MAX_CALC_LIMIT)
end

-- 处理普通队列超时（只检查队首）
function TravelDistManager:processNormalTimeouts()
    local now = CurTime()
    while #self.normalQueue > 0 do
        local key = self.normalQueue[1]
        local task = self.pendingTasks[key]
        if not task then
            table.remove(self.normalQueue, 1)   -- 清理无效任务
        else
            local elapsed = now - task.timestamp
            if elapsed > self.NORMAL_TIMEOUT then
                table.remove(self.normalQueue, 1)   -- 移除超时任务
                -- 触发所有回调，传入 nil 表示超时
                for _, cb in ipairs(task.callbacks) do
                    pcall(cb, nil)
                end
                self.pendingTasks[key] = nil
            else
                break   -- 队首未超时，后面也不会超时
            end
        end
    end
end

-- 从指定队列取出一个任务并计算（如果存在）
function TravelDistManager:processQueue(queue, isPriority)
    if #queue == 0 then return false end
    local key = table.remove(queue, 1)   -- 从队首取出
    local task = self.pendingTasks[key]
    if not task then return true end      -- 任务已消失，返回 true 表示已处理一个槽位

    -- 标记已不在队列
    task.inQueue = false

    -- 执行计算
    local dist = computeDistance(task.pos1, task.pos2)

    -- 存入缓存
    self:cacheStore(task.pos1, task.pos2, dist)

    -- 触发所有回调
    for _, cb in ipairs(task.callbacks) do
        pcall(cb, dist)
    end

    self.pendingTasks[key] = nil
    return true
end

-- Think 钩子函数
function TravelDistManager:thinkHandler()
    -- 1. 先处理普通队列超时
    self:processNormalTimeouts()

    -- 2. 获取动态计算速率
    local maxCalc = self:getDynamicMaxCalc()
    local count = 0

    -- 3. 优先处理优先队列
    while count < maxCalc and #self.priorityQueue > 0 do
        if self:processQueue(self.priorityQueue, true) then
            count = count + 1
        end
    end

    -- 4. 再处理普通队列
    while count < maxCalc and #self.normalQueue > 0 do
        if self:processQueue(self.normalQueue, false) then
            count = count + 1
        end
    end
end

-- ==================== 对外接口 ====================

--- 请求两点间的旅行距离（异步）
--- @param pos1 Vector 起点
--- @param pos2 Vector 终点
--- @param callback function 回调函数，接收一个参数：距离（number），若不可达返回 math.huge，超时返回 nil
--- @param priority boolean (可选) 是否优先处理，默认 false
function TravelDistManager:Request(pos1, pos2, callback, priority)
    priority = priority or false

    -- 1. 尝试从缓存获取
    local cached = self:cacheLookup(pos1, pos2)
    if cached ~= nil then
        callback(cached)
        return
    end

    -- 2. 生成任务标识
    local key = getTaskKey(pos1, pos2)
    local task = self.pendingTasks[key]

    if task then
        -- 任务已存在，加入回调列表
        table.insert(task.callbacks, callback)

        -- 优先级提升：如果新请求是优先的，且任务当前在普通队列中，则移至优先队列
        if priority and task.inQueue then
            -- 尝试从普通队列中移除
            for i, k in ipairs(self.normalQueue) do
                if k == key then
                    table.remove(self.normalQueue, i)

                    -- 决定插入优先队列的位置（队首或队尾）
                    local insertAtHead = false
                    if self.INSERT_STRATEGY == "head_if_old" then
                        -- 计算已等待时间
                        local waitTime = CurTime() - task.timestamp
                        -- 获取当前动态计算速率
                        local maxCalc = self:getDynamicMaxCalc()
                        -- 获取当前优先队列长度（移动前）
                        local prioLen = #self.priorityQueue
                        -- 估算处理完当前优先队列所需时间（秒）
                        local estimatedTime = prioLen / (maxCalc * self.TICK_RATE)
                        -- 如果等待时间超过阈值，则插队
                        if waitTime > self.PRIORITY_INSERT_FACTOR * estimatedTime then
                            insertAtHead = true
                        end
                    end

                    if insertAtHead then
                        -- 插入队首
                        table.insert(self.priorityQueue, 1, key)
                    else
                        -- 默认插队尾
                        table.insert(self.priorityQueue, key)
                    end

                    -- 更新任务时间戳（可选，保留原时间戳以便后续可能再次提升）
                    -- 这里不重置时间戳，因为优先队列不检查超时
                    break
                end
            end
            -- 如果已经在优先队列中，无需操作
        end
    else
        -- 新任务
        self.pendingTasks[key] = {
            pos1 = pos1,
            pos2 = pos2,
            callbacks = { callback },
            timestamp = CurTime(),
            inQueue = true,
        }
        -- 根据优先级放入相应队列
        if priority then
            table.insert(self.priorityQueue, key)
        else
            table.insert(self.normalQueue, key)
        end
    end

    -- 3. 确保 Think 钩子已注册
    if not self.isHookSet then
        hook.Add("Think", "TravelDistManager", function() self:thinkHandler() end)
        self.isHookSet = true
    end
end

--- 设置基础每帧计算数
function TravelDistManager:SetBaseCalcRate(rate)
    self.BASE_MAX_CALC_PER_FRAME = math.max(1, rate)
end

--- 设置每个优先任务额外增加的计算数
function TravelDistManager:SetPriorityIncrement(inc)
    self.PRIORITY_INCREMENT_PER_TASK = math.max(0, inc)
end

--- 设置每帧计算数上限
function TravelDistManager:SetMaxCalcLimit(limit)
    self.MAX_CALC_LIMIT = math.max(1, limit)
end

--- 设置普通任务超时时间（秒）
function TravelDistManager:SetNormalTimeout(timeout)
    self.NORMAL_TIMEOUT = math.max(0.1, timeout)
end

--- 设置 Tick 率（帧/秒）
function TravelDistManager:SetTickRate(rate)
    self.TICK_RATE = math.max(1, rate)
end

--- 设置优先级插入策略
--- @param strategy string "tail" 或 "head_if_old"
function TravelDistManager:SetInsertStrategy(strategy)
    if strategy == "tail" or strategy == "head_if_old" then
        self.INSERT_STRATEGY = strategy
    end
end

--- 设置插队阈值因子（仅当 strategy="head_if_old" 时有效）
function TravelDistManager:SetInsertFactor(factor)
    self.PRIORITY_INSERT_FACTOR = math.max(0, factor)
end

--- 清空所有队列和缓存（例如地图切换时）
function TravelDistManager:ClearAll()
    self.priorityQueue = {}
    self.normalQueue = {}
    self.pendingTasks = {}
    self.cache = {}
    self.cacheIdx = 1
    -- 注意：Think 钩子继续保留，但队列空了就不会做任何事
end

-- ==================== 返回表 ====================
return TravelDistManager