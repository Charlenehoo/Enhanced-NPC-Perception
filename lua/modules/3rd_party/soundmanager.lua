-- lua\modules\3rd_party\soundmanager.lua

SoundManager = SoundManager or {}
SoundManager.ActiveSounds = SoundManager.ActiveSounds or {}
setmetatable(SoundManager.ActiveSounds, { __mode = "k" })
SoundManager.Cache = SoundManager.Cache or {}

local CurTime = CurTime
local IsValid = IsValid
local pairs = pairs
local CreateSound = CreateSound
local math = math
local pcall = pcall
local timer = timer
local hook = hook
local file = file
local SoundDuration = SoundDuration
local math_Rand = math.Rand
local math_sin = math.sin

local modelPatterns = {
    { pattern = "female",   folder = "Female/" },
    { pattern = "alyx",     folder = "Female/" },
    { pattern = "mossman",  folder = "Female/" },
    { pattern = "choi",     folder = "Female/" },
    { pattern = "ada",      folder = "Female/" },
    { pattern = "hackclaw", folder = "Female/" },
    { pattern = "combine",  folder = "Combine/" },
    { pattern = "police",   folder = "Combine/" },
    { pattern = "metrocop", folder = "Combine/" },
    { pattern = "cp_",      folder = "Combine/" },
}

local REACTION_CONFIG = {
    ["burn"]   = { minWait = 0.0, maxWait = 0.1, volume = 1.1, level = 85, attn = 2.0 },
    ["bullet"] = { minWait = 0.4, maxWait = 1.0, volume = 0.95, level = 80, attn = 1.5 },
    ["flying"] = { minWait = 0.05, maxWait = 0.2, volume = 0.9, level = 85, attn = 2.5 },
    ["death"]  = { minWait = 0.0, maxWait = 0.0, volume = 0.75, level = 85, attn = 1.8 },
}

local function SafeStopPatch(patch)
    if not patch then return end
    pcall(function() if patch.Stop then patch:Stop() end end)
end

function SoundManager:GetGenderFolder(ent)
    if not IsValid(ent) then return "Male/" end
    local model = ent:GetModel()
    if not model then return "Male/" end
    model = model:lower()
    for i = 1, #modelPatterns do
        if model:find(modelPatterns[i].pattern, 1, true) then return modelPatterns[i].folder end
    end
    return "Male/"
end

function SoundManager:FindSounds(ent, reactionType)
    local gender = self:GetGenderFolder(ent)
    local key = gender .. reactionType
    if self.Cache[key] then return self.Cache[key].files, self.Cache[key].path end

    local path = "SFX/" .. gender .. reactionType .. "/"
    local files = file.Find("sound/" .. path .. "*", "GAME")

    if (not files or #files == 0) and gender ~= "Male/" then
        path = "SFX/Male/" .. reactionType .. "/"
        files = file.Find("sound/" .. path .. "*", "GAME")
    end

    self.Cache[key] = { files = files or {}, path = path }
    return files or {}, path
end

function SoundManager:Play(ent, reactionType, isLooped)
    if not IsValid(ent) or not reactionType then return end

    if not self.ActiveSounds[ent] then
        self.ActiveSounds[ent] = {
            CurrentType = "",
            IsLooped = false,
            Patch = nil,
            NextPlayTime = 0,
            LastFile = "",
            FadingOut = false,
            TalkEndTime = 0,
            BaseVolume = 0,
            NoiseOffset = math.Rand(0, 100)
        }
    end

    local data = self.ActiveSounds[ent]
    if data.CurrentType ~= reactionType then
        SafeStopPatch(data.Patch)
        data.Patch = nil
        data.NextPlayTime = 0
        data.TalkEndTime = 0
    end

    data.CurrentType = reactionType
    data.IsLooped = isLooped or false
    data.FadingOut = false

    if data.NextPlayTime <= CurTime() then
        self:ExecutePlay(ent, reactionType)
    end
end

function SoundManager:ExecutePlay(ent, reactionType)
    if not IsValid(ent) then return end
    local files, folder = self:FindSounds(ent, reactionType)
    if not files or #files == 0 then return end

    local data = self.ActiveSounds[ent]
    if not data or data.FadingOut then return end

    local pick = files[1]
    if #files > 1 then
        for i = 1, 5 do
            pick = files[math.random(#files)]
            if pick ~= data.LastFile then break end
        end
    end

    data.LastFile = pick
    local fullPath = folder .. pick
    local cfg = REACTION_CONFIG[reactionType] or { minWait = 0.5, maxWait = 1.5, volume = 1.0, level = 75 }

    SafeStopPatch(data.Patch)
    local success, patch = pcall(CreateSound, ent, fullPath)
    if not success or not patch then return end

    data.Patch = patch
    patch:SetSoundLevel(cfg.level)
    patch:PlayEx(cfg.volume, math.random(95, 105))

    local duration = SoundDuration(fullPath) or 1.0
    if duration <= 0 then duration = 1.0 end

    data.TalkEndTime = CurTime() + duration
    data.BaseVolume = cfg.volume

    data.NextPlayTime = CurTime() + duration + math.Rand(cfg.minWait, cfg.maxWait)
end

function SoundManager:Stop(ent, fadeTime)
    if not IsValid(ent) then return end
    local data = self.ActiveSounds[ent]
    if not data then return end

    data.IsLooped = false
    data.FadingOut = true
    data.TalkEndTime = 0

    if RagdollFaceAnimator and RagdollFaceAnimator.LipsSyncs then
        RagdollFaceAnimator:LipsSyncs(ent, 0)
    end

    local patch = data.Patch
    if patch then
        if patch.FadeOut then patch:FadeOut(fadeTime or 0.2) else patch:Stop() end
    end

    timer.Simple((fadeTime or 0.2) + 0.1, function()
        if IsValid(ent) and SoundManager.ActiveSounds[ent] and SoundManager.ActiveSounds[ent].FadingOut then
            SoundManager.ActiveSounds[ent] = nil
        end
    end)
end

local nextThink = 0
hook.Add("Think", "SoundManager_LoopSystem", function()
    local ct = CurTime()
    if ct < nextThink then return end

    nextThink = ct + 0.05

    for ent, data in pairs(SoundManager.ActiveSounds) do
        if not IsValid(ent) then
            SafeStopPatch(data.Patch)
            SoundManager.ActiveSounds[ent] = nil
            continue
        end

        if not data.NoiseOffset then data.NoiseOffset = math.Rand(0, 100) end

        if RagdollFaceAnimator and RagdollFaceAnimator.LipsSyncs then
            if ct < data.TalkEndTime and not data.FadingOut then
                local jitter = math_Rand(0.4, 1.0)

                local swell = math_sin(ct * 5 + data.NoiseOffset) * 0.1
                local simulatedVolume = (data.BaseVolume * jitter) + swell

                if simulatedVolume > 1 then simulatedVolume = 1 end
                if simulatedVolume < 0 then simulatedVolume = 0 end

                RagdollFaceAnimator:LipsSyncs(ent, simulatedVolume)
            else
                RagdollFaceAnimator:LipsSyncs(ent, 0.0)
            end
        end

        if data.IsLooped and not data.FadingOut then
            if ct >= (data.NextPlayTime or 0) then
                SoundManager:ExecutePlay(ent, data.CurrentType)
            end
        end
    end
end)
