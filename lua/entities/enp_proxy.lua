-- .\lua\entities\enp_proxy.lua
AddCSLuaFile()
ENT.Base = "base_ai"
ENT.Type = "ai"
ENT.AutomaticFrameAdvance = true

function ENT:Initialize() -- https://wiki.facepunch.com/gmod/ENTITY:Initialize
    self:SetModel("models/editor/cube_small.mdl")
    self:SetModelScale(0.04)
    -- self:SetNoDraw(true)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
end
