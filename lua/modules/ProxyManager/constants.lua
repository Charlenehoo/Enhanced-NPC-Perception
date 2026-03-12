-- .\lua\modules\ProxyManager\constants.lua
ProxyManager = ProxyManager or {}
ProxyManager.PROXY_CLASS = "enp_proxy"
ProxyManager.PROXY_FIELDS = {
    VICTIM = "victim",
    ATTACKER = "attacker",
    LAST_SIGHT_TIME = "lastSightTime",
    LAST_SOUND_TIME = "lastSoundTime",
    LAST_SOUND_LEVEL = "lastSoundLevel",
    LAST_FACE_TIME = "lastFaceTime",
}

ProxyManager.PLAYER_SPAWN_DELAY = 0.15 -- 10 Tick
ProxyManager.RAGDOLL_REMOVE_DELAY = 3

ProxyManager.SIGHT_MEMORY_DURATION = 3
ProxyManager.SOUND_MEMORY_DURATION = 3
ProxyManager.FACE_COOLDOWN = 15
ProxyManager.PROXY_OFFSET = 2
ProxyManager.ATTACKER_RANGE = ProxyManager.PROXY_OFFSET + 1024

ProxyManager.DEFAULT_ATTACKER_CLASS_PREFIX = "npc_combine"
ProxyManager.DEFAULT_ATTACKER_CLASS_PATTERN = string.format("%s*", ProxyManager.DEFAULT_ATTACKER_CLASS_PREFIX)
ProxyManager.REMOVE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX = "ENP_RemoveProxies_"
ProxyManager.CREATE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX = "ENP_CreateProxies_"

ProxyManager.ATTACKER_SUPPRESSION_TIME = 8

ProxyManager.DEBUG = true
ProxyManager.DEBUG_PRINT_INTERVAL = 2
ProxyManager.UPDATE_PRINT_TABLE_TIMER_IDENTIFIER = "ENP_TrueOnPrintTable"
