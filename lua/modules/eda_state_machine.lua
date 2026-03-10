-- lua/modules/eda_state_machine.lua
EDAStateMachine = EDAStateMachine or {}

EDAStateMachine.MAIN_STATE = {
    UNINTERVENED = "UNINTERVENED",
    DIRECT_DEATH = "DIRECT_DEATH",
    DEATH_ANIM   = "DEATH_ANIM",
    CRAWLING     = "CRAWLING",
    FINAL_DEATH  = "FINAL_DEATH",
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

    record.lastHp_c = currentHp_c
    record.lastHp_d = currentHp_d
    record.lastIsWrithing = fields.IsWrithing
    record.lastIsTwitching = fields.IsTwitching
    record.lastIsReviving = fields.IsReviving

    -- 计算主状态
    local currentMainState
    if not currentHp_d then
        currentMainState = EDAStateMachine.MAIN_STATE.UNINTERVENED
    elseif not currentHp_c then
        if currentHp_d <= 0 then
            currentMainState = EDAStateMachine.MAIN_STATE.DIRECT_DEATH
        else
            currentMainState = EDAStateMachine.MAIN_STATE.DEATH_ANIM
        end
    else
        if currentHp_d <= 0 or currentHp_c <= 0 then
            currentMainState = EDAStateMachine.MAIN_STATE.FINAL_DEATH
        else
            currentMainState = EDAStateMachine.MAIN_STATE.CRAWLING
        end
    end

    -- 计算子状态（仅当主状态为 CRAWLING 时）
    local currentSubState = EDAStateMachine.SUB_STATE.NONE
    if currentMainState == EDAStateMachine.MAIN_STATE.CRAWLING then
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
