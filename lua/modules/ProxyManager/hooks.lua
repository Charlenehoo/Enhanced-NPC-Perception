-- lua\modules\ProxyManager\hooks.lua
local ProxyManager = ProxyManager
hook.Add("Tick", "ENP_ProxyManagerSync", function()
    ProxyManager.SyncAllProxies()
    -- ProxyManager.UpdatePrintTableTimer()
end)
