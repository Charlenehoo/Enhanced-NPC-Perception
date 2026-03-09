-- .\lua\modules\ProxyManager\bones.lua
ProxyManager = ProxyManager or {}

ProxyManager.BONE_NAMES_WITH_SPINE4 = {
    "ValveBiped.Bip01_Spine4", -- 起点（上中心）
    -- 头部开始
    "ValveBiped.Bip01_Neck1", -- 下行
    "ValveBiped.Bip01_Head1", -- 叶子
    "ValveBiped.Bip01_Neck1", -- 上行
    -- 头部结束
    "ValveBiped.Bip01_Spine4", -- 共同祖先
    -- 左手开始
    "ValveBiped.Bip01_L_Clavicle", "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm", -- 下行
    "ValveBiped.Bip01_L_Hand", -- 叶子
    "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Clavicle", -- 上行
    -- 左手结束
    -- 
    -- 桥接上下中心开始
    "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine",
    "ValveBiped.Bip01_Pelvis", --
    -- 桥接结束
    -- 
    -- 左脚开始
    "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_Calf", -- 下行
    "ValveBiped.Bip01_L_Foot", -- 叶子
    "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_L_Thigh", -- 上行
    -- 左脚结束
    "ValveBiped.Bip01_Pelvis", -- 共同祖先
    -- 右脚开始
    "ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf", -- 下行
    "ValveBiped.Bip01_R_Foot", -- 叶子
    "ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Thigh", -- 上行
    -- 右脚结束
    --
    -- 桥接上下中心开始
    "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2",
    "ValveBiped.Bip01_Spine4", --
    -- 桥接结束
    -- 
    -- 右手开始
    "ValveBiped.Bip01_R_Clavicle", "ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm", -- 下行
    "ValveBiped.Bip01_R_Hand", -- 叶子
    "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Clavicle" -- 上行
    -- 右手结束
    -- 下一轮起点（上中心）也是右手和头部的共同祖先
}

ProxyManager.BONE_NAMES_WITHOUT_SPINE4 = {
    "ValveBiped.Bip01_Spine2", -- 起点（上中心）
    -- 头部开始
    "ValveBiped.Bip01_Neck1", -- 下行
    "ValveBiped.Bip01_Head1", -- 叶子
    "ValveBiped.Bip01_Neck1", -- 上行
    -- 头部结束
    "ValveBiped.Bip01_Spine2", -- 共同祖先
    -- 左手开始
    "ValveBiped.Bip01_L_Clavicle", "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm", -- 下行
    "ValveBiped.Bip01_L_Hand", -- 叶子
    "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Clavicle", -- 上行
    -- 左手结束
    -- 
    -- 桥接上下中心开始
    "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Pelvis", --
    -- 桥接结束
    -- 
    -- 左脚开始
    "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_Calf", -- 下行
    "ValveBiped.Bip01_L_Foot", -- 叶子
    "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_L_Thigh", -- 上行
    -- 左脚结束
    "ValveBiped.Bip01_Pelvis", -- 共同祖先
    -- 右脚开始
    "ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf", -- 下行
    "ValveBiped.Bip01_R_Foot", -- 叶子
    "ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_R_Thigh", -- 上行
    -- 右脚结束
    --
    -- 桥接上下中心开始
    "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2", --
    -- 桥接结束
    --   
    -- 右手开始
    "ValveBiped.Bip01_R_Clavicle", "ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm", -- 下行
    "ValveBiped.Bip01_R_Hand", -- 叶子
    "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Clavicle" -- 上行
    -- 右手结束
    -- 下一轮起点（上中心）也是右手和头部的共同祖先
}
