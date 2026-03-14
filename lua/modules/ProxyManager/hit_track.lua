hook.Add("EntityFireBullets", "HitTracker_Proxy", function(ent, bullet)
    if not IsValid(ent) or not ProxyManager.IsAttacker(ent) then return end
    local originalCallback = bullet.Callback
    bullet.Callback = function(attacker, tr, dmgInfo)
        if originalCallback then
            originalCallback(attacker, tr, dmgInfo)
        end
        -- 具体实现
    end
end)
