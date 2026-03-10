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

local PROXY_CLASS = ProxyManager.PROXY_CLASS

local FACE_COOLDOWN = 0.5
local DEBUG = true -- 大量调试输出，单独控制

local IsValid = IsValid

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

    local proxies = GetProxiesByVictim(victim)

    for _, proxy in ipairs(proxies) do
        local attacker = proxy.attacker
        if not IsValid(attacker) or not attacker:IsNPC() then
            continue -- Gmod 支持此关键字
        end
        local nextFaceTime = proxy.nextFaceTime or 0
        local curTime = CurTime()
        if curTime < nextFaceTime then
            continue -- Gmod 支持此关键字
        end
        if attacker:GetCurrentSchedule() ~= SCHED_DIE then
            attacker:SetEnemy(proxy)
            attacker:SetSchedule(SCHED_COMBAT_FACE)
            proxy.nextFaceTime = curTime + FACE_COOLDOWN
        end
    end
end)
