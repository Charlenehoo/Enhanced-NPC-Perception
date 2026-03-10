-- lua/modules/eda_state_machine.lua
EDAStateMachine = EDAStateMachine or {}

--[[
    EDA State Machine – 封装对 Enhanced Death Animations (EDA) MOD 的依赖

    本模块负责读取 EDA MOD 在玩家和布娃娃实体上设置的自定义字段，
    并根据这些字段计算出玩家当前所处的死亡状态（主状态与子状态），
    通过回调通知外部模块（如 player_proxy.lua）执行相应逻辑。

    所有“魔法字段”均来自 EDA MOD，含义如下：

    - player.ORag : 玩家死亡后对应的布娃娃实体（EDA 在玩家死亡时设置）。
    - ragdoll.Hp_c : 爬行/挣扎/复活动画中的“生命值”，当该值 ≤ 0 时进入最终死亡。
    - ragdoll.Hp_d : 死亡动画中的“生命值”，当该值 ≤ 0 时结束死亡动画，可能进入爬行。
    - ragdoll.IsWrithing  : 布尔值，表示布娃娃正在播放“挣扎”动画（子状态）。
    - ragdoll.IsTwitching  : 布尔值，表示布娃娃正在播放“抽搐”动画（子状态）。
    - ragdoll.IsReviving   : 布尔值，表示布娃娃正在被复活（子状态）。

    若将来需要替换或移除 EDA MOD，只需修改本文件底部的两个内部函数：
        - GetRagdoll(player)      : 返回玩家对应的布娃娃实体。
        - GetRagdollFields(ragdoll): 返回包含上述字段的表。
    其余逻辑（状态计算、回调触发）无需改动。
]]

EDAStateMachine.MAIN_STATE = {
    UNINTERVENED = "Unintervened",
    DIRECT_DEATH = "DirectDeath",
    DEATH_ANIM   = "DeathAnim",
    STRUGGLE     = "Struggle",
    FINAL_DEATH  = "FinalDeath",
}

EDAStateMachine.SUB_STATE = {
    NONE      = "None",
    WRITHING  = "Writhing",
    TWITCHING = "Twitching",
    REVIVING  = "Reviving",
    CRAWLING  = "Crawling"
}

EDAStateMachine.DEBUG = (ProxyManager and ProxyManager.DEBUG) or false -- 复用全局调试标志

local players = setmetatable({}, { __mode = "k" })                     -- 弱键，防止内存泄漏
local callbacks = {
    onMainStateChange = {},
    onSubStateChange = {},
    onPlayerSpawn = {}, -- 玩家重生回调列表
}

-- 内部函数：获取 ragdoll（封装对 EDA 的依赖）
local function GetRagdoll(player)
    return player.ORag -- EDA 字段，未来可替换
end

local function GetRagdollFields(ragdoll)
    return {
        Hp_c = ragdoll.Hp_c,
        Hp_d = ragdoll.Hp_d,
        IsWrithing = ragdoll.IsWrithing,
        IsTwitching = ragdoll.IsTwitching,
        IsReviving = ragdoll.IsReviving,
        iSCrawling = ragdoll:GetNW2Int("Animation_State", nil) == 3
    }
end

-- 回调注册接口
function EDAStateMachine.OnMainStateChange(callback)
    table.insert(callbacks.onMainStateChange, callback)
end

function EDAStateMachine.OnSubStateChange(callback)
    table.insert(callbacks.onSubStateChange, callback)
end

function EDAStateMachine.OnPlayerSpawn(callback)
    table.insert(callbacks.onPlayerSpawn, callback)
end

-- 内部触发函数
local function FireMainStateChange(player, ragdoll, oldMain, newMain, oldSub)
    for _, cb in ipairs(callbacks.onMainStateChange) do
        cb(player, ragdoll, oldMain, newMain, oldSub)
    end
end

local function FireSubStateChange(player, ragdoll, oldSub, newSub, mainState)
    for _, cb in ipairs(callbacks.onSubStateChange) do
        cb(player, ragdoll, oldSub, newSub, mainState)
    end
end

-- 玩家重生触发函数（由外部钩子调用）
function EDAStateMachine.FireOnPlayerSpawn(player)
    if not IsValid(player) then return end

    local oldRagdoll = GetRagdoll(player) -- 获取旧的 ragdoll（如果存在）
    players[player] = nil                 -- 清除状态记录

    -- 触发所有已注册的玩家重生回调
    for _, cb in ipairs(callbacks.onPlayerSpawn) do
        cb(player, oldRagdoll)
    end
end

-- ==================== 辅助函数（拆分 Update 逻辑）====================

-- 获取或初始化玩家的记录表
local function GetOrCreateRecord(player)
    local record = players[player]
    if not record then
        record = {
            lastMainState = nil,
            lastSubState = nil,
            lastHp_c = nil,
            lastHp_d = nil,
            lastIsWrithing = nil,
            lastIsTwitching = nil,
            lastIsReviving = nil,
            lastiSCrawling = nil,
        }
        players[player] = record
    end
    return record
end

-- 更新记录中的原始字段值（用于调试和后续比较）
local function UpdateRecordFields(record, fields)
    record.lastHp_c = fields.Hp_c
    record.lastHp_d = fields.Hp_d
    record.lastIsWrithing = fields.IsWrithing
    record.lastIsTwitching = fields.IsTwitching
    record.lastIsReviving = fields.IsReviving
    record.lastiSCrawling = fields.iSCrawling
end

local function ComputeMainState(Hp_c, Hp_d)
    -- 根据 Hp_c 和 Hp_d 计算主状态（遵循真值表）
    -- | c    | d    | state                      |
    -- | ---- | ---- | -------------------------- |
    -- | nil  | nil  | 未介入                     |
    -- | nil  | > 0  | 死亡动画                   |
    -- | nil  | <= 0 | 直接死亡                   |
    -- | > 0  | nil  | 不可能发生 （归入挣扎）    |
    -- | > 0  | > 0  | 挣扎                       |
    -- | > 0  | <= 0 | 最终死亡                   |
    -- | <= 0 | nil  | 不可能发生（归入最终死亡） |
    -- | <= 0 | > 0  | 不可能发生（归入最终死亡） |
    -- | <= 0 | <= 0 | 最终死亡                   |
    if Hp_c == nil then
        -- 情况：c 不存在
        if Hp_d == nil then
            return EDAStateMachine.MAIN_STATE.UNINTERVENED
        elseif Hp_d > 0 then
            return EDAStateMachine.MAIN_STATE.DEATH_ANIM
        else
            return EDAStateMachine.MAIN_STATE.DIRECT_DEATH
        end
    else
        -- 情况：c 存在
        if Hp_c <= 0 then
            return EDAStateMachine.MAIN_STATE.FINAL_DEATH
        else
            if Hp_d == nil or Hp_d > 0 then
                return EDAStateMachine.MAIN_STATE.STRUGGLE
            else
                return EDAStateMachine.MAIN_STATE.FINAL_DEATH
            end
        end
    end
end

-- 根据主状态和字段计算子状态（仅当主状态为 STRUGGLE 时有效）
local function ComputeSubState(mainState, fields)
    if mainState ~= EDAStateMachine.MAIN_STATE.STRUGGLE then
        return EDAStateMachine.SUB_STATE.NONE
    end

    if fields.IsWrithing then
        return EDAStateMachine.SUB_STATE.WRITHING
    elseif fields.IsTwitching then
        return EDAStateMachine.SUB_STATE.TWITCHING
    elseif fields.IsReviving then
        return EDAStateMachine.SUB_STATE.REVIVING
    elseif fields.iSCrawling then
        return EDAStateMachine.SUB_STATE.CRAWLING
    else
        return EDAStateMachine.SUB_STATE.NONE
    end
end

-- 触发子状态变化回调（如果发生变化）
local function FireSubStateIfChanged(player, ragdoll, record, newSub, newMain)
    if newSub == record.lastSubState then return end

    if EDAStateMachine.DEBUG then
        print(string.format("[EDA] Player %s sub state: %s -> %s (main=%s)",
            player:Name(), tostring(record.lastSubState), tostring(newSub), tostring(newMain)))
    end

    FireSubStateChange(player, ragdoll, record.lastSubState, newSub, newMain)
    record.lastSubState = newSub
end

-- 触发主状态变化回调（如果发生变化），使用传入的 oldSub（必须是在更新前保存的旧子状态）
local function FireMainStateIfChanged(player, ragdoll, record, newMain, oldSub)
    if newMain == record.lastMainState then return end

    if EDAStateMachine.DEBUG then
        print(string.format("[EDA] Player %s main state: %s -> %s",
            player:Name(), tostring(record.lastMainState), tostring(newMain)))
    end

    FireMainStateChange(player, ragdoll, record.lastMainState, newMain, oldSub)
    record.lastMainState = newMain
end

-- ==================== 每帧更新（主入口）====================

function EDAStateMachine.Update(player)
    if not IsValid(player) then return end

    local ragdoll = GetRagdoll(player)
    if not IsValid(ragdoll) then return end

    local fields = GetRagdollFields(ragdoll)
    local record = GetOrCreateRecord(player)

    -- 调试：字段变化输出
    if EDAStateMachine.DEBUG then
        if record.lastHp_c ~= fields.Hp_c then
            print(string.format("[EDA] %s Hp_c: %s -> %s", player:Name(), tostring(record.lastHp_c),
                tostring(fields.Hp_c)))
        end
        if record.lastHp_d ~= fields.Hp_d then
            print(string.format("[EDA] %s Hp_d: %s -> %s", player:Name(), tostring(record.lastHp_d),
                tostring(fields.Hp_d)))
        end
        if record.lastIsWrithing ~= fields.IsWrithing then
            print(string.format("[EDA] %s IsWrithing: %s -> %s", player:Name(), tostring(record.lastIsWrithing),
                tostring(fields.IsWrithing)))
        end
        if record.lastIsTwitching ~= fields.IsTwitching then
            print(string.format("[EDA] %s IsTwitching: %s -> %s", player:Name(), tostring(record.lastIsTwitching),
                tostring(fields.IsTwitching)))
        end
        if record.lastIsReviving ~= fields.IsReviving then
            print(string.format("[EDA] %s IsReviving: %s -> %s", player:Name(), tostring(record.lastIsReviving),
                tostring(fields.IsReviving)))
        end
    end

    -- 保存旧子状态（用于主状态回调）
    local oldSubState = record.lastSubState

    -- 更新记录中的原始字段（用于下次比较）
    UpdateRecordFields(record, fields)

    -- 计算新状态
    local newMain = ComputeMainState(fields.Hp_c, fields.Hp_d)
    local newSub = ComputeSubState(newMain, fields)

    -- 触发回调（子状态优先，主状态其次）
    FireSubStateIfChanged(player, ragdoll, record, newSub, newMain)
    FireMainStateIfChanged(player, ragdoll, record, newMain, oldSubState)
end
