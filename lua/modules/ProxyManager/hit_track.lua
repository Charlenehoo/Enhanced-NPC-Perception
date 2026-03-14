-- 命中追踪器（基于 GM:EntityFireBullets）
HitTracker = HitTracker or {}
local MAX_HISTORY = 16
-- 存储每个攻击者的射击事件队列（FIFO，最大 MAX_HISTORY）
-- 结构：attackerIdx -> { [1] = { [victimIdx1] = true, [victimIdx2] = true }, [2] = {}, ... }
local attackerEvents = {}

-- 钩子：在实体发射子弹时触发
hook.Add("EntityFireBullets", "HitTracker_Capture", function(ent, bullet)
    -- 只关心 NPC 发射的子弹
    if not IsValid(ent) or not ent:IsNPC() then return end

    -- 保存原始回调（如果存在）
    local originalCallback = bullet.Callback

    -- 注入我们的回调
    bullet.Callback = function(attacker, tr, dmgInfo)
        -- 先调用原始回调（如果存在），保证不影响原有逻辑
        if originalCallback then
            originalCallback(attacker, tr, dmgInfo)
        end

        -- 记录命中事件
        if IsValid(attacker) and attacker:IsNPC() and IsValid(tr.Entity) and tr.Entity:IsPlayer() then
            local attackerIdx = attacker:EntIndex()
            local victimIdx = tr.Entity:EntIndex()

            -- 初始化或获取攻击者的队列
            if not attackerEvents[attackerIdx] then
                attackerEvents[attackerIdx] = {}
            end
            local list = attackerEvents[attackerIdx]

            -- 当前射击事件：一个表，记录这次射击命中的所有受害者索引
            -- 注意：一次射击（Num>1）可能命中多个受害者，但通常 Num=1，这里简化为单次射击只记录一个受害者
            local currentShot = { [victimIdx] = true }

            -- 添加到队列
            table.insert(list, currentShot)

            -- 保持队列长度不超过 MAX_HISTORY
            if #list > MAX_HISTORY then
                table.remove(list, 1)
            end
        end
    end

    -- 注意：我们不需要显式返回修改后的 bullet，因为它是按引用传递的
end)

-- 查询接口：最近 shots 次射击中，是否至少命中 victim 一次
function HitTracker.HasHitRecently(attacker, victim, shots)
    shots = shots or MAX_HISTORY
    if not IsValid(attacker) or not IsValid(victim) then return false end
    local list = attackerEvents[attacker:EntIndex()]
    if not list or #list == 0 then return false end
    local victimIdx = victim:EntIndex()
    local start = math.max(1, #list - shots + 1)
    for i = start, #list do
        if list[i][victimIdx] then
            return true
        end
    end
    return false
end

-- 获取攻击者的历史射击次数（队列长度）
function HitTracker.GetHistoryCount(attacker)
    if not IsValid(attacker) then return 0 end
    local list = attackerEvents[attacker:EntIndex()]
    return list and #list or 0
end

-- 清理接口（例如 NPC 死亡时调用）
function HitTracker.Reset(attacker)
    if IsValid(attacker) then
        attackerEvents[attacker:EntIndex()] = nil
    end
end

-- 可选：定期清理无效攻击者（防止内存泄漏）
hook.Add("Think", "HitTracker_Cleanup", function()
    for idx in pairs(attackerEvents) do
        if not IsValid(Entity(idx)) then
            attackerEvents[idx] = nil
        end
    end
end)

-- 导出全局
_G.HitTracker = HitTracker
