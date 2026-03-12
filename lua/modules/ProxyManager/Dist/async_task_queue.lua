-- lua\modules\ProxyManager\Dist\async_task_queue.lua
-- ============================================================================
-- AsyncTaskQueue - 通用异步任务队列模块
-- 功能：管理普通/优先级任务队列，支持超时、动态速率、优先级提升策略
-- ============================================================================

AsyncTaskQueue = {}
AsyncTaskQueue.__index = AsyncTaskQueue

--- 创建新队列实例
--- @param config table 配置参数
---   - baseMaxCalc: 基础每帧计算数
---   - priorityIncrement: 每个优先任务额外增加的计算数
---   - maxCalcLimit: 每帧计算数上限
---   - normalTimeout: 普通任务超时时间（秒）
---   - tickRate: 服务器 Tick 率（用于插队估算）
---   - insertFactor: 插队阈值因子（等待时间 > 因子 * 预期处理时间 则插队）
---   - insertStrategy: 插入策略 "tail" 或 "head_if_old"
function AsyncTaskQueue:new(config)
    config = config or {}
    local self = setmetatable({}, AsyncTaskQueue)

    -- 配置
    self.baseMaxCalc = config.baseMaxCalc or 5
    self.priorityIncrement = config.priorityIncrement or 2
    self.maxCalcLimit = config.maxCalcLimit or 20
    self.normalTimeout = config.normalTimeout or 2.0
    self.tickRate = config.tickRate or 66.6
    self.insertFactor = config.insertFactor or 1.0
    self.insertStrategy = config.insertStrategy or "head_if_old"

    -- 内部状态
    self.pendingTasks = {}  -- key -> { data, callbacks, timestamp, inQueue }
    self.priorityQueue = {} -- 优先队列（存储 key）
    self.normalQueue = {}   -- 普通队列（存储 key）

    return self
end

-- ==================== 配置更新 ====================

function AsyncTaskQueue:SetBaseMaxCalc(value)
    self.baseMaxCalc = math.max(1, value)
end

function AsyncTaskQueue:SetPriorityIncrement(value)
    self.priorityIncrement = math.max(0, value)
end

function AsyncTaskQueue:SetMaxCalcLimit(value)
    self.maxCalcLimit = math.max(1, value)
end

function AsyncTaskQueue:SetNormalTimeout(value)
    self.normalTimeout = math.max(0.1, value)
end

function AsyncTaskQueue:SetTickRate(value)
    self.tickRate = math.max(1, value)
end

function AsyncTaskQueue:SetInsertStrategy(strategy)
    if strategy == "tail" or strategy == "head_if_old" then
        self.insertStrategy = strategy
    end
end

function AsyncTaskQueue:SetInsertFactor(value)
    self.insertFactor = math.max(0, value)
end

-- ==================== 核心方法 ====================

--- 获取当前动态每帧最大计算数
function AsyncTaskQueue:getDynamicMaxCalc()
    local priorityCount = #self.priorityQueue
    local rate = self.baseMaxCalc + priorityCount * self.priorityIncrement
    return math.min(rate, self.maxCalcLimit)
end

--- 添加任务到队列
--- @param key string 任务唯一标识
--- @param data any 任务相关数据（将在处理时传给处理器）
--- @param priority boolean 是否优先
--- @param callbacks table 回调函数列表（每个函数接收处理结果）
function AsyncTaskQueue:addTask(key, data, priority, callbacks)
    local task = self.pendingTasks[key]

    if task then
        -- 任务已存在，合并回调
        for _, cb in ipairs(callbacks) do
            table.insert(task.callbacks, cb)
        end

        -- 优先级提升：如果新请求优先且任务当前在普通队列中，则移至优先队列
        if priority and task.inQueue and self:_isInNormalQueue(key) then
            self:_moveToPriorityQueue(key, task)
        end
    else
        -- 新任务
        task = {
            data = data,
            callbacks = callbacks,
            timestamp = CurTime(),
            inQueue = true,
        }
        self.pendingTasks[key] = task

        if priority then
            table.insert(self.priorityQueue, key)
        else
            table.insert(self.normalQueue, key)
        end
    end
end

--- 处理队列（每帧调用）
--- @param processor function 处理器函数，接受任务数据，返回处理结果
function AsyncTaskQueue:process(processor)
    -- 1. 处理普通队列超时
    self:_processNormalTimeouts()

    -- 2. 获取动态计算速率
    local maxCalc = self:getDynamicMaxCalc()
    local count = 0

    -- 3. 先处理优先队列
    while count < maxCalc and #self.priorityQueue > 0 do
        if self:_processQueue(self.priorityQueue, processor) then
            count = count + 1
        end
    end

    -- 4. 再处理普通队列
    while count < maxCalc and #self.normalQueue > 0 do
        if self:_processQueue(self.normalQueue, processor) then
            count = count + 1
        end
    end
end

--- 清空所有队列和任务
function AsyncTaskQueue:clear()
    self.pendingTasks = {}
    self.priorityQueue = {}
    self.normalQueue = {}
end

-- ==================== 内部方法 ====================

-- 检查 key 是否在普通队列中
function AsyncTaskQueue:_isInNormalQueue(key)
    for _, k in ipairs(self.normalQueue) do
        if k == key then return true end
    end
    return false
end

-- 将任务从普通队列移至优先队列（根据策略决定插入位置）
function AsyncTaskQueue:_moveToPriorityQueue(key, task)
    -- 从普通队列移除
    for i, k in ipairs(self.normalQueue) do
        if k == key then
            table.remove(self.normalQueue, i)
            break
        end
    end

    -- 决定插入优先队列的位置
    local insertAtHead = false
    if self.insertStrategy == "head_if_old" then
        local waitTime = CurTime() - task.timestamp
        local maxCalc = self:getDynamicMaxCalc()
        local prioLen = #self.priorityQueue
        -- 估算处理完当前优先队列所需时间（秒）
        local estimatedTime = prioLen / (maxCalc * self.tickRate)
        if waitTime > self.insertFactor * estimatedTime then
            insertAtHead = true
        end
    end

    if insertAtHead then
        table.insert(self.priorityQueue, 1, key)
    else
        table.insert(self.priorityQueue, key)
    end
    -- 任务时间戳保持不变（已存储在 task 中）
end

-- 处理普通队列超时（只检查队首）
function AsyncTaskQueue:_processNormalTimeouts()
    local now = CurTime()
    while #self.normalQueue > 0 do
        local key = self.normalQueue[1]
        local task = self.pendingTasks[key]
        if not task then
            table.remove(self.normalQueue, 1)
        else
            local elapsed = now - task.timestamp
            if elapsed > self.normalTimeout then
                table.remove(self.normalQueue, 1)
                -- 触发所有回调，传入 nil 表示超时
                for _, cb in ipairs(task.callbacks) do
                    pcall(cb, nil)
                end
                self.pendingTasks[key] = nil
            else
                break
            end
        end
    end
end

-- 从指定队列取出一个任务并处理
function AsyncTaskQueue:_processQueue(queue, processor)
    if #queue == 0 then return false end
    local key = table.remove(queue, 1)
    local task = self.pendingTasks[key]
    if not task then return true end

    task.inQueue = false

    -- 调用处理器计算结果
    local result = processor(task.data)

    -- 触发所有回调
    for _, cb in ipairs(task.callbacks) do
        pcall(cb, result)
    end

    self.pendingTasks[key] = nil
    return true
end
