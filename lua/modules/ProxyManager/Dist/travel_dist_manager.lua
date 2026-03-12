-- ============================================================================
-- TravelDistManager - 异步导航距离请求系统（基于子模块重构版）
-- 功能：通过导航网格计算两点间的路径长度，支持缓存、优先队列、超时丢弃和动态计算速率
-- 子模块依赖：
--   - LRUCache (来自 LRU_cache.lua)
--   - PathDistanceCalculator (来自 path_distance_calculator.lua)
--   - AsyncTaskQueue (来自 async_task_queue.lua)
-- ============================================================================

TravelDistManager                             = TravelDistManager or {}

-- ==================== 配置（可调） ====================
TravelDistManager.QUANTIZE_STEP               = 20            -- 量化步长
TravelDistManager.CACHE_SIZE                  = 256           -- 缓存最大条目数
TravelDistManager.BASE_MAX_CALC_PER_FRAME     = 5             -- 基础每帧计算数
TravelDistManager.PRIORITY_INCREMENT_PER_TASK = 2             -- 每个优先任务额外增加的计算数
TravelDistManager.MAX_CALC_LIMIT              = 20            -- 每帧计算数上限
TravelDistManager.NORMAL_TIMEOUT              = 2.0           -- 普通任务超时时间（秒）
TravelDistManager.TICK_RATE                   = 66.6          -- 服务器 Tick 率（帧/秒）
TravelDistManager.PRIORITY_INSERT_FACTOR      = 1.0           -- 插队阈值因子（等待时间 > 因子 * 预期处理时间 则插队）
TravelDistManager.INSERT_STRATEGY             = "head_if_old" -- 插入策略："tail"（始终队尾）或 "head_if_old"（智能判断）

-- ==================== 内部数据结构 ====================
-- LRU 缓存实例
TravelDistManager.lru                         = LRUCache:new(TravelDistManager.CACHE_SIZE)

-- 异步任务队列实例
TravelDistManager.taskQueue                   = AsyncTaskQueue:new({
    baseMaxCalc       = TravelDistManager.BASE_MAX_CALC_PER_FRAME,
    priorityIncrement = TravelDistManager.PRIORITY_INCREMENT_PER_TASK,
    maxCalcLimit      = TravelDistManager.MAX_CALC_LIMIT,
    normalTimeout     = TravelDistManager.NORMAL_TIMEOUT,
    tickRate          = TravelDistManager.TICK_RATE,
    insertFactor      = TravelDistManager.PRIORITY_INSERT_FACTOR,
    insertStrategy    = TravelDistManager.INSERT_STRATEGY,
})

TravelDistManager.isHookSet                   = false

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

-- ==================== 缓存系统（基于 LRU） ====================
function TravelDistManager:cacheLookup(pos1, pos2)
    local key = getTaskKey(pos1, pos2)
    return self.lru:get(key)
end

function TravelDistManager:cacheStore(pos1, pos2, dist)
    local key = getTaskKey(pos1, pos2)
    self.lru:put(key, dist)
end

-- ==================== Think 钩子 ====================
function TravelDistManager:thinkHandler()
    -- 只需调用队列的 process 方法，传入处理器
    self.taskQueue:process(function(data)
        -- data 包含 pos1, pos2
        local dist = PathDistanceCalculator.Compute(data.pos1, data.pos2, nil)
        if dist == nil then
            dist = math.huge -- 不可达
        end
        -- 存入缓存
        self:cacheStore(data.pos1, data.pos2, dist)
        return dist
    end)
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
    local taskData = { pos1 = pos1, pos2 = pos2 }

    -- 3. 添加到队列
    self.taskQueue:addTask(key, taskData, priority, { callback })

    -- 4. 确保 Think 钩子已注册
    if not self.isHookSet then
        hook.Add("Think", "TravelDistManager", function() self:thinkHandler() end)
        self.isHookSet = true
    end
end

--- 设置基础每帧计算数
function TravelDistManager:SetBaseCalcRate(rate)
    self.BASE_MAX_CALC_PER_FRAME = math.max(1, rate)
    self.taskQueue:SetBaseMaxCalc(self.BASE_MAX_CALC_PER_FRAME)
end

--- 设置每个优先任务额外增加的计算数
function TravelDistManager:SetPriorityIncrement(inc)
    self.PRIORITY_INCREMENT_PER_TASK = math.max(0, inc)
    self.taskQueue:SetPriorityIncrement(self.PRIORITY_INCREMENT_PER_TASK)
end

--- 设置每帧计算数上限
function TravelDistManager:SetMaxCalcLimit(limit)
    self.MAX_CALC_LIMIT = math.max(1, limit)
    self.taskQueue:SetMaxCalcLimit(self.MAX_CALC_LIMIT)
end

--- 设置普通任务超时时间（秒）
function TravelDistManager:SetNormalTimeout(timeout)
    self.NORMAL_TIMEOUT = math.max(0.1, timeout)
    self.taskQueue:SetNormalTimeout(self.NORMAL_TIMEOUT)
end

--- 设置 Tick 率（帧/秒）
function TravelDistManager:SetTickRate(rate)
    self.TICK_RATE = math.max(1, rate)
    self.taskQueue:SetTickRate(self.TICK_RATE)
end

--- 设置优先级插入策略
--- @param strategy string "tail" 或 "head_if_old"
function TravelDistManager:SetInsertStrategy(strategy)
    if strategy == "tail" or strategy == "head_if_old" then
        self.INSERT_STRATEGY = strategy
        self.taskQueue:SetInsertStrategy(self.INSERT_STRATEGY)
    end
end

--- 设置插队阈值因子（仅当 strategy="head_if_old" 时有效）
function TravelDistManager:SetInsertFactor(factor)
    self.PRIORITY_INSERT_FACTOR = math.max(0, factor)
    self.taskQueue:SetInsertFactor(self.PRIORITY_INSERT_FACTOR)
end

--- 清空所有队列和缓存（例如地图切换时）
function TravelDistManager:ClearAll()
    self.taskQueue:clear()
    self.lru:clear()
end

-- ==================== 返回表 ====================
return TravelDistManager
