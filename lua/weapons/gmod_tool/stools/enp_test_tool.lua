local MAT_NAMES = {
    [65] = "MAT_ANTLION",
    [66] = "MAT_BLOODYFLESH",
    [67] = "MAT_CONCRETE",
    [68] = "MAT_DIRT",
    [69] = "MAT_EGGSHELL",
    [70] = "MAT_FLESH",
    [71] = "MAT_GRATE",
    [72] = "MAT_ALIENFLESH",
    [73] = "MAT_CLIP",
    [74] = "MAT_SNOW",
    [76] = "MAT_PLASTIC",
    [77] = "MAT_METAL",
    [78] = "MAT_SAND",
    [79] = "MAT_FOLIAGE",
    [80] = "MAT_COMPUTER",
    [83] = "MAT_SLOSH",
    [84] = "MAT_TILE",
    [85] = "MAT_GRASS",
    [86] = "MAT_VENT",
    [87] = "MAT_WOOD",
    [88] = "MAT_DEFAULT",
    [89] = "MAT_GLASS",
    [90] = "MAT_WARPSHIELD",
}

TOOL.Category = "Test"
TOOL.Name = "Material Inspector"

local function GetMaterialNameFromTrace(trace)
    if not trace.Hit then return "未命中" end

    -- 如果击中的是有效实体，优先使用实体材质
    if IsValid(trace.Entity) then
        local matType = trace.Entity:GetMaterialType()
        return MAT_NAMES[matType] or string.format("未知 (%d)", matType)
    end

    -- 否则尝试通过表面属性获取
    if trace.SurfaceProps then
        local surfaceData = util.GetSurfaceData(trace.SurfaceProps)
        if surfaceData and surfaceData.material then
            return MAT_NAMES[surfaceData.material] or string.format("未知材质 (%d)", surfaceData.material)
        end
    end

    return "无法获取材质"
end

function TOOL:LeftClick(trace)
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end

    local startPos = ply:EyePos()
    local dir = ply:GetAimVector()
    local endPos = startPos + dir * 8192

    -- 使用 ents.FindAlongRay 获取射线上的所有实体
    local entities = ents.FindAlongRay(startPos, endPos, Vector(-1, -1, -1), Vector(1, 1, 1))

    print("=== 左键射线 (长度 8192 ) 沿线实体 ===")
    print(string.format("起点: %s", tostring(startPos)))
    print(string.format("终点: %s", tostring(endPos)))
    print(string.format("共找到 %d 个实体:", #entities))

    for i, ent in ipairs(entities) do
        print(string.format("  %d. 索引: %d | 类名: %s | IsWorld: %s",
            i,
            ent:EntIndex(),
            ent:GetClass(),
            tostring(ent:IsWorld())
        ))
    end
    print("==================================")

    return true
end

function TOOL:RightClick(trace)
    print("=== 右键命中信息 ===")
    print("命中: " .. tostring(trace.Hit))
    if trace.Hit then
        print("命中位置: " .. tostring(trace.HitPos))
    end

    local ent = trace.Entity
    if IsValid(ent) then
        local matType = ent:GetMaterialType()
        local matName = MAT_NAMES[matType] or string.format("未知 (%d)", matType)
        print(string.format("实体有效 | 索引: %d | 材质类型: %s",
            ent:EntIndex(),
            matName
        ))
    else
        print("实体无效，无法获取材质类型")
        if trace.Hit then
            print("这可能击中了 world，但 world 的材质类型通常需要通过其他方式获取（如 trace 的表面属性）")
        end
    end
    print("====================")

    return true
end

function TOOL:Reload(trace)
end

function TOOL:Think()
end
