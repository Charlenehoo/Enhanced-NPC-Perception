-- .\lua\modules\ProxyManager\constants.lua
ProxyManager = ProxyManager or {}
ProxyManager.PROXY_CLASS = "enp_proxy"
ProxyManager.DEFAULT_ATTACKER_CLASS_PREFIX = "npc_combine"
ProxyManager.DEFAULT_ATTACKER_CLASS_PATTERN = string.format("%s*", ProxyManager.DEFAULT_ATTACKER_CLASS_PREFIX)
ProxyManager.REMOVE_PROXIES_DELAYED_TIMER_IDENTIFIER_PREFIX = "ENP_CreateProxies_"
ProxyManager.ATTACKER_RANGE = 1040
ProxyManager.ATTACKER_SUPPRESSION_TIME = 8
ProxyManager.PROXY_OFFSET = 16
ProxyManager.DEBUG = true
ProxyManager.DEBUG_PRINT_INTERVAL = 2
ProxyManager.UPDATE_PRINT_TABLE_TIMER_IDENTIFIER = "ENP_TrueOnPrintTable"
