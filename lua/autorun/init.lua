if SERVER then
    include("modules/ProxyManager/constants.lua")
    include("modules/ProxyManager/bones.lua")
    include("modules/ProxyManager/bone_cache.lua")
    include("modules/ProxyManager/Core/private.lua")
    include("modules/ProxyManager/Core/public.lua")
    include("modules/ProxyManager/Core/util.lua")
    include("modules/ProxyManager/proxy_sync.lua")
    include("modules/ProxyManager/hooks.lua")
    include("modules/3rd_party/soundmanager.lua")
    include("modules/eda_state_machine.lua")
    include("modules/player_proxy.lua")
    include("modules/sound_relay.lua")
end
