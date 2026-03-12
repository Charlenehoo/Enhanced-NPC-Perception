-- lua\modules\ProxyManager\Dist\path_distance_calculator.lua
-- ============================================================================
-- PathDistanceCalculator - 独立路径距离计算模块
-- 功能：管理一个隐藏的 NextBot 用于计算两点间路径距离，并提供备用降级方案
-- ============================================================================

PathDistanceCalculator = PathDistanceCalculator or {}

-- 模块内部状态
local calcBot = nil                      -- 隐藏的计算用 NextBot
local botClassName = "pathdist_calc_bot" -- 自定义实体类名

-- ==================== 内部：定义隐藏的 NextBot 实体 ====================
if SERVER then
    -- 定义一个极简的 NextBot 实体，仅用于路径计算
    local ENT = {}
    ENT.Type = "nextbot"
    ENT.Base = "base_nextbot"
    ENT.PrintName = "PathDist Bot"
    ENT.Spawnable = false

    function ENT:Initialize()
        self:SetNoDraw(true)            -- 不可见
        self:SetSolid(SOLID_NONE)       -- 无碰撞
        self:SetMoveType(MOVETYPE_NONE) -- 禁止移动
        -- 可选：设置一个极简模型，避免模型缺失警告
        -- self:SetModel("models/hunter/blocks/cube1x1x1.mdl")
    end

    -- NextBot 必须有一个运行的协程
    function ENT:RunBehaviour()
        while true do
            coroutine.wait(1.0) -- 永久等待，不做任何事
        end
    end

    scripted_ents.Register(ENT, botClassName)
end

-- ==================== 内部工具函数 ====================

-- 获取或创建隐藏的 NextBot
local function GetBot()
    if not SERVER then return nil end

    if IsValid(calcBot) then
        return calcBot
    end

    calcBot = ents.Create(botClassName)
    if IsValid(calcBot) then
        calcBot:SetPos(vector_origin)
        calcBot:Spawn()
        return calcBot
    else
        print("[PathDistanceCalculator] 错误：无法创建隐藏的 NextBot")
        return nil
    end
end

-- 核心计算方法：基于 NextBot + Path 对象
local function computeWithNextBot(pos1, pos2)
    local bot = GetBot()
    if not bot then return nil end

    -- 将机器人移动到起点
    bot:SetPos(pos1)

    -- 创建路径对象并计算
    local path = Path("Follow")
    path:SetMinLookAheadDistance(0)
    path:Compute(bot, pos2)

    if not path:IsValid() then
        return nil
    end

    -- 累加路径段距离
    local total = 0
    local lastPos = pos1
    local seg = path:GetCurrentGoal()
    while seg do
        local segPos = seg.pos
        total = total + lastPos:DistTo(segPos)
        lastPos = segPos
        seg = seg:GetNext()
    end
    return total
end

-- 备用计算方法：基于 NPC 类的原生方法 (降级方案)
-- 需要提供一个有效的 NPC 实体作为上下文
local function computeWithNPC(npc, pos1, pos2)
    if not IsValid(npc) then return nil end
    -- 注意：此方法计算的是从 NPC 当前位置到目标点的路径距离
    -- 因此需要先将 NPC 移动到起点（如果可能），但移动 NPC 可能产生副作用。
    -- 更安全的用法是直接使用 npc:GetPos() 作为起点。
    -- 这里我们假设传入的 npc 位置已经是 pos1，或者我们接受计算从 npc 当前位置到 pos2 的距离。
    -- 为了通用性，这个降级方案需要调用者确保上下文正确。
    return npc:GetPathDistanceToGoal(pos2)
end

-- ==================== 对外接口 ====================

--- 计算两点间的路径距离（自动降级）
--- @param pos1 Vector 起点
--- @param pos2 Vector 终点
--- @param fallbackNPC Entity|nil 可选的 NPC 实体，用于降级计算
--- @return number|nil 路径距离，失败返回 nil
function PathDistanceCalculator.Compute(pos1, pos2, fallbackNPC)
    -- 首先尝试主方法：基于 NextBot
    local dist = computeWithNextBot(pos1, pos2)
    if dist then
        return dist
    end

    -- 主方法失败，尝试降级方案
    if fallbackNPC and IsValid(fallbackNPC) then
        -- 注意：此方法计算的是从 fallbackNPC 当前位置到 pos2 的距离
        -- 因此我们需确保 fallbackNPC 的位置是合理的，或接受这种近似
        return fallbackNPC:GetPathDistanceToGoal(pos2)
    end

    return nil -- 全部失败
end

--- 清理内部资源（如地图切换时调用）
function PathDistanceCalculator.Cleanup()
    if IsValid(calcBot) then
        calcBot:Remove()
        calcBot = nil
    end
end

-- 可选：在切换地图时自动清理
hook.Add("InitPostEntity", "PathDistanceCalculatorCleanup", function()
    PathDistanceCalculator.Cleanup()
end)
