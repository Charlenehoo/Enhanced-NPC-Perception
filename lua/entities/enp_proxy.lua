-- .\lua\entities\enp_proxy.lua
ProxyManager = ProxyManager or {} -- enp_proxy.lua 早于 autorun 加载
local PROXY_MODEL = "models/editor/cube_small.mdl"
local PROXY_FIELDS = ProxyManager.PROXY_FIELDS

AddCSLuaFile()
ENT.Base = "base_ai"
ENT.Type = "ai"
ENT.AutomaticFrameAdvance = true

function ENT:Initialize() -- https://wiki.facepunch.com/gmod/ENTITY:Initialize
    self:SetModel(PROXY_MODEL)
    self:SetModelScale(0.04)
    -- self:SetNoDraw(true)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
end

function ENT:Init(v, a)
    self[PROXY_FIELDS.VICTIM] = v
    self[PROXY_FIELDS.ATTACKER] = a
    self[PROXY_FIELDS.LAST_SIGHT_TIME] = 0

    self[PROXY_FIELDS.LAST_FACE_TIME] = 0

    self[PROXY_FIELDS.SOUND_COUNTER] = 0
    self[PROXY_FIELDS.LAST_SOUND_POS] = 0

    self[PROXY_FIELDS.LAST_SOUND_EMIT_TIME] = 0
    self[PROXY_FIELDS.LAST_SOUND_EMIT_ID] = 0
    self[PROXY_FIELDS.LAST_SOUND_AUDIBLE_TIME] = 0
    self[PROXY_FIELDS.LAST_SOUND_AUDIBLE_ID] = 0
end
