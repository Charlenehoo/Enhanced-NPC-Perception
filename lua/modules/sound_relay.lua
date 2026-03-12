-- lua/modules/sound_relay.lua

-- 注意：最初尝试通过 proxy:EmitSound 播放受害者原声来自然吸引 NPC 攻击者，
-- 但实测发现：
-- 1. 由于 Entity:EmitSound 存在引擎限制：当播放声音脚本时，脚本内定义的参数（如音量等级）会覆盖代码中传入的值，
--    导致即使我们尝试增加音量（+50），实际播放的音量依然不足（声音脚本可能定义为低音量如 SNDLVL_NORM）。
-- 2. 通过调试输出 NPC:GetCurrentSchedule() 发现，攻击者在声音播放后仍处于 SCHED_IDLE_STAND (1)，
--    并未切换到 SCHED_ALERT_FACE (5) 或 SCHED_INVESTIGATE_SOUND (11) 等响应调度的计划，
--    证明 NPC 并未将中继的声音视为有效的听觉刺激。
-- 3. 尝试强制设置 SCHED_ALERT_FACE 也无效，因为该调度需要 NPC 内部存在有效的“最佳声音”信息，
--    而直接设置调度无法自动创建此信息。
--
-- 因此，放弃依赖声音吸引的方案，改用直接操控 NPC AI 的“粗暴”方法：
-- - 将代理实体设为攻击者的敌人 (SetEnemy)
-- - 强制攻击者进入战斗面向调度 (SCHED_COMBAT_FACE)
-- 此方法能可靠地让攻击者转身面向代理（代理位置应与受害者同步），
-- 虽然绕过了声音系统，但在当前环境下是稳定有效的解决方案。

local ProxyManager = ProxyManager
local PROXY_FIELDS = ProxyManager.PROXY_FIELDS

local IsValid = IsValid
local CurTime = CurTime

-- 用于存储上一次打印事件的唯一标识
local lastPrintKey = nil

local function DebugSoundPrinter(data)
    if not data or not data.SoundName then return end

    local ent = data.Entity
    local soundName = data.SoundName
    local channel = data.Channel
    local level = data.SoundLevel
    local pitch = data.Pitch
    local volume = data.Volume
    local flags = data.Flags
    local dsp = data.DSP

    -- 实体信息
    local entInfo = "NULL"
    if IsValid(ent) then
        entInfo = string.format("%s:%d", ent:GetClass(), ent:EntIndex())
    end

    -- 获取玩家速度（如果实体是玩家）
    local playerSpeed = nil
    if ent and ent:IsPlayer() then
        local vel = ent:GetVelocity()
        playerSpeed = vel:Length() -- 速度大小，单位：游戏单位/秒
    end

    -- 声道名称映射（基于官方 CHAN 枚举）
    local channelNames = {
        [-1]  = "CHAN_REPLACE",
        [0]   = "CHAN_AUTO",
        [1]   = "CHAN_WEAPON",
        [2]   = "CHAN_VOICE",
        [3]   = "CHAN_ITEM",
        [4]   = "CHAN_BODY",
        [5]   = "CHAN_STREAM",
        [6]   = "CHAN_STATIC",
        [7]   = "CHAN_VOICE2",
        [8]   = "CHAN_VOICE_BASE",
        [136] = "CHAN_USER_BASE",
    }
    local channelName = channelNames[channel] or string.format("未知(%d)", channel)

    -- 计算理论最大传播距离（基于你的公式 D = 2^(L/5) 单位）
    local maxDistUnits = 2 ^ (level / 5)
    local maxDistMeters = maxDistUnits * 0.0254

    -- 构建唯一标识，包含速度（如果存在）以防止刷屏，同时速度变化会触发新打印
    local currentKey = string.format("%s|%s|%d|%d|%d|%d|%d|%d|%s",
        entInfo,
        soundName,
        channel or 0,
        level or 0,
        pitch or 0,
        volume or 0,
        flags or 0,
        dsp or 0,
        playerSpeed and string.format("%.2f", playerSpeed) or "nospeed"
    )

    if lastPrintKey == currentKey then
        return
    end
    lastPrintKey = currentKey

    -- 打印
    print("========== [声音事件] ==========")
    print("实体:     " .. entInfo)
    if playerSpeed then
        print("玩家速度: " .. string.format("%.2f 单位/秒", playerSpeed))
    end
    print("声音名称: " .. tostring(soundName))
    print("声道:     " .. channelName .. " (" .. tostring(channel) .. ")")
    print("声音级别: " .. tostring(level) .. " dB")
    print("音高:     " .. tostring(pitch))
    print("音量:     " .. tostring(volume))
    print("标志:     " .. tostring(flags))
    print("DSP:      " .. tostring(dsp))
    print("理论最大传播距离: " .. string.format("%.0f 单位 (≈ %.2f 米)", maxDistUnits, maxDistMeters))
    print("================================\n")
end


local function GetProxiesByVictim(victim)
    local proxies = {}
    local view = ProxyManager.GetAttackerProxyMapView(victim)
    if view then
        for attacker, proxy in view.GetIterator() do
            table.insert(proxies, proxy)
        end
    end
    return proxies
end

hook.Add("EntityEmitSound", "SNT_EntityEmitSound", function(data)
    local entity = data.Entity
    if not IsValid(entity) then return end

    local victim
    if ProxyManager.IsVictim(entity) then
        victim = entity
    elseif ProxyManager.IsVictim(entity:GetOwner()) then
        victim = entity:GetOwner()
    else
        return
    end

    -- DebugSoundPrinter(data)

    local proxies = GetProxiesByVictim(victim)

    for _, proxy in ipairs(proxies) do
        proxy[PROXY_FIELDS.LAST_SOUND_TIME] = CurTime()
        proxy[PROXY_FIELDS.LAST_SOUND_LEVEL] = data.SoundLevel
    end
end)
