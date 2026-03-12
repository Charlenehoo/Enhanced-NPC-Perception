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
local TravelDistManager = TravelDistManager

local PROXY_FIELDS = ProxyManager.PROXY_FIELDS

local IsValid = IsValid
local CurTime = CurTime

local SOUND_AUDIBLE_DIST = 8192
local DEBUG = ProxyManager.DEBUG or false

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

    local attackerProxyMap = ProxyManager.GetAttackerProxyMapView(victim)
    if not attackerProxyMap then return end
    local soundPos = data.Pos or victim:GetPos()

    for attacker, proxy in attackerProxyMap.GetIterator() do
        if not IsValid(attacker) or not IsValid(proxy) then
            continue
        end

        -- ---- 为本次声音事件生成唯一ID（使用实体普通字段，无需纳入PROXY_FIELDS）----
        proxy[PROXY_FIELDS.SOUND_COUNTER] = (proxy[PROXY_FIELDS.SOUND_COUNTER] or 0) + 1
        local soundID = proxy[PROXY_FIELDS.SOUND_COUNTER]
        local emitTime = CurTime()

        if DEBUG then
            print(string.format("[SoundRelay] Victim %s emitted sound #%d at time %.2f",
                victim:EntIndex(), soundID, emitTime))
        end

        -- 记录最新声音事件的元数据（用于调试和过期判断，非决策必需）
        proxy[PROXY_FIELDS.LAST_SOUND_EMIT_TIME] = emitTime
        proxy[PROXY_FIELDS.LAST_SOUND_EMIT_ID] = soundID
        proxy[PROXY_FIELDS.LAST_SOUND_POS] = soundPos

        -- ---- 异步计算声音可听性 ----
        TravelDistManager:Request(soundPos, attacker:GetPos(), function(dist)
            if not IsValid(proxy) then return end

            -- 仅当距离小于阈值且声音可听时考虑更新记忆
            if dist >= SOUND_AUDIBLE_DIST then
                if DEBUG then
                    print(string.format("[SoundRelay] Sound #%d is INAUDIBLE (dist=%.0f), memory unchanged",
                        soundID, dist))
                end
                return
            end

            -- 可听：检查是否比当前记录的可听声音更新
            local currentAudibleID = proxy[PROXY_FIELDS.LAST_SOUND_AUDIBLE_ID] or 0
            if soundID > currentAudibleID then
                -- 是更新的可听声音，刷新记忆
                proxy[PROXY_FIELDS.LAST_SOUND_AUDIBLE_ID] = soundID
                proxy[PROXY_FIELDS.LAST_SOUND_AUDIBLE_TIME] = emitTime
                if DEBUG then
                    print(string.format("[SoundRelay] Sound #%d is AUDIBLE (dist=%.0f) and newer, memory refreshed",
                        soundID, dist))
                end
            else
                -- 有更新的可听声音已存在，忽略本次
                if DEBUG then
                    print(string.format("[SoundRelay] Sound #%d is AUDIBLE but older than current audible #%d, ignored",
                        soundID, currentAudibleID))
                end
            end
        end, true) -- 优先处理
    end
end)

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
