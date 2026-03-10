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
local function FireMainStateChange(player, ragdoll, oldMain, newMain)
    for _, cb in ipairs(callbacks.onMainStateChange) do
        cb(player, ragdoll, oldMain, newMain)
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

-- 每帧更新状态
function EDAStateMachine.Update(player)
    if not IsValid(player) then return end

    local ragdoll = GetRagdoll(player)
    if not IsValid(ragdoll) then return end

    local fields = GetRagdollFields(ragdoll)
    local currentHp_c = fields.Hp_c
    local currentHp_d = fields.Hp_d

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
        }
        players[player] = record
    end

    -- 字段变化调试
    if EDAStateMachine.DEBUG then
        if record.lastHp_c ~= currentHp_c then
            print(string.format("[EDA] %s Hp_c: %s -> %s", player:Name(), tostring(record.lastHp_c),
                tostring(currentHp_c)))
        end
        if record.lastHp_d ~= currentHp_d then
            print(string.format("[EDA] %s Hp_d: %s -> %s", player:Name(), tostring(record.lastHp_d),
                tostring(currentHp_d)))
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

    -- 计算主状态
    -- local currentMainState
    -- if not currentHp_d then
    --     currentMainState = EDAStateMachine.MAIN_STATE.UNINTERVENED
    -- elseif not currentHp_c then
    --     if currentHp_d <= 0 then
    --         currentMainState = EDAStateMachine.MAIN_STATE.DIRECT_DEATH
    --     else
    --         currentMainState = EDAStateMachine.MAIN_STATE.DEATH_ANIM
    --     end
    -- else
    --     if currentHp_d <= 0 or currentHp_c <= 0 then
    --         currentMainState = EDAStateMachine.MAIN_STATE.FINAL_DEATH
    --     else
    --         currentMainState = EDAStateMachine.MAIN_STATE.STRUGGLE
    --     end
    -- end

    record.lastHp_c = currentHp_c
    record.lastHp_d = currentHp_d
    local currentMainState
    if currentHp_c ~= nil then
        currentMainState = (currentHp_c <= 0) and EDAStateMachine.MAIN_STATE.FINAL_DEATH or
            EDAStateMachine.MAIN_STATE.STRUGGLE
    elseif currentHp_d ~= nil then
        currentMainState = (currentHp_d <= 0) and EDAStateMachine.MAIN_STATE.DIRECT_DEATH or
            EDAStateMachine.MAIN_STATE.DEATH_ANIM
    else
        currentMainState = EDAStateMachine.MAIN_STATE.UNINTERVENED
    end

    -- 计算子状态（仅当主状态为 STRUGGLE 时）
    record.lastIsWrithing = fields.IsWrithing
    record.lastIsTwitching = fields.IsTwitching
    record.lastIsReviving = fields.IsReviving
    local currentSubState = EDAStateMachine.SUB_STATE.NONE
    if currentMainState == EDAStateMachine.MAIN_STATE.STRUGGLE then
        if fields.IsWrithing then
            currentSubState = EDAStateMachine.SUB_STATE.WRITHING
        elseif fields.IsTwitching then
            currentSubState = EDAStateMachine.SUB_STATE.TWITCHING
        elseif fields.IsReviving then
            currentSubState = EDAStateMachine.SUB_STATE.REVIVING
        end
    end

    -- 子状态变化处理
    if currentSubState ~= record.lastSubState then
        if EDAStateMachine.DEBUG then
            print(string.format("[EDA] Player %s sub state: %s -> %s (main=%s)",
                player:Name(), tostring(record.lastSubState), tostring(currentSubState), tostring(currentMainState)))
        end
        FireSubStateChange(player, ragdoll, record.lastSubState, currentSubState, currentMainState)
        record.lastSubState = currentSubState
    end

    -- 主状态变化处理
    if currentMainState ~= record.lastMainState then
        if EDAStateMachine.DEBUG then
            print(string.format("[EDA] Player %s main state: %s -> %s",
                player:Name(), tostring(record.lastMainState), tostring(currentMainState)))
        end
        FireMainStateChange(player, ragdoll, record.lastMainState, currentMainState)
        record.lastMainState = currentMainState
    end
end
