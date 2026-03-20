-- lua\modules\wall\predict.lua
-- 定义穿透结果枚举
PenetrationResult = {
    CAN_PENETRATE = "一定能穿透",
    CANNOT_PENETRATE = "一定不能穿透",
    UNCERTAIN = "不确定"
}

--- 预测直射路径下的穿透结果
--- @param walls table 墙体列表（GetWallInfoAlongLine 返回）
--- @param pen number 武器的穿透值（GetProcessedValue("Penetration")）
--- @param maxLayers number 最大可穿透层数（SWEP.MaxPenetrationLayers）
--- @return string 枚举值，对应 PenetrationResult 中的某个成员
function PredictPenetration(walls, pen, maxLayers)
    local layers = 0
    local cost_min = 0     -- 最小消耗（随机因子 0.81）
    local cost_max = 0     -- 最大消耗（随机因子 1.21）
    local all_thick = true -- 墙体厚度是否均为有限值

    for _, wall in ipairs(walls) do
        if layers >= maxLayers then
            break
        end
        local mat_mult = ARC9.PenTable[wall.matType] or 1
        local thickness = wall.thickness
        if thickness == math.huge then
            all_thick = false
            break
        end
        cost_min = cost_min + thickness * mat_mult * 0.81
        cost_max = cost_max + thickness * mat_mult * 1.21
        layers = layers + 1
    end

    if not all_thick then
        return PenetrationResult.CANNOT_PENETRATE
    end

    if cost_min <= pen and layers == #walls and layers <= maxLayers then
        return PenetrationResult.CAN_PENETRATE
    elseif cost_max > pen or layers > maxLayers then
        return PenetrationResult.CANNOT_PENETRATE
    else
        return PenetrationResult.UNCERTAIN
    end
end
