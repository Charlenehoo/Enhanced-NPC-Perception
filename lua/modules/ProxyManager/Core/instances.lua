-- lua\modules\ProxyManager\Core\instances.lua
ProxyManager = ProxyManager or {}

local IsValid = IsValid
local table_IsEmpty = table.IsEmpty
local table_GetKeys = table.GetKeys

local PROXY_CLASS = ProxyManager.PROXY_CLASS

--[[
    ProxyManager 核心实例管理模块

    设计原则：
    1. 私表（_attackersByVictim / _victimsByAttacker）只能通过本模块提供的接口（如 CreateProxy、RemoveProxy 等）进行修改，
       外部代码可通过只读视图（如 GetAttackerProxyMapView ）安全访问表内容，视图通过元表禁止任何写入操作。
    2. 所有直接读写私表的函数都必须是 local 函数，并以 "_" 开头命名（如 _CreateProxyImpl），表示模块内部私有，不对外暴露。
    3. 私表是系统状态的唯一事实来源（Single Source of Truth）。任何与表记录不一致的实体状态（如代理实体失效但表中仍有条目）
       都应被视为系统错误，需立即修复（重建代理或清理条目）或触发断言。
    4. 快速失败（Fail Fast）：当检测到私表内部状态不一致（例如正向表有记录但反向表缺失）时，应通过 assert 直接报错终止，
       以便尽早暴露 bug，防止脏数据扩散。
    5. 最小化私密访问：私有函数数量应尽可能少，以降低私表被意外操作的风险。内部实现应优先复用现有的公开接口
       （如 ProxyManager.RemoveProxy）而非编写新的私有函数，仅在无法满足性能或功能需求时才新增私有实现。
    6. 实体生命周期管控：只有私有函数（以 "_" 开头）可直接调用 ents.Create(PROXY_CLASS) 创建代理实体，
    或直接调用 proxy:Remove() 销毁代理实体。公开接口必须通过私有函数间接操作，确保实体状态与私表始终同步。
]]

local _attackersByVictim = {} -- {key: victim, value: {key: attacker, value: proxy}}
local _victimsByAttacker = {} -- {key: attacker, value: {key: victim, value: proxy}}

local function SetupRelationshipsVictim(victim, attacker)
    attacker:AddEntityRelationship(victim, D_NU, 99)
end

local function SetupRelationshipsProxy(attacker, proxy)
    attacker:AddRelationship(string.format("%s D_NU 0", PROXY_CLASS))
    attacker:AddEntityRelationship(proxy, D_HT, 99)
end

local function SetupRelationships(victim, attacker, proxy)
    SetupRelationshipsVictim(victim, attacker)
    SetupRelationshipsProxy(attacker, proxy)
end

local function _CreateProxyImpl(victim, attacker)
    if not IsValid(victim) then return end
    if not IsValid(attacker) or not attacker:IsNPC() then return end -- 保证 AddRelationship 等方法有效
    if victim:GetClass() == PROXY_CLASS then return end
    if attacker:GetClass() == PROXY_CLASS then return end            -- 防止递归
    if victim == attacker then return end

    if not _attackersByVictim[victim] then
        _attackersByVictim[victim] = {} -- {key: attacker, value: proxy}
    end
    if not _victimsByAttacker[attacker] then
        _victimsByAttacker[attacker] = {} -- {key: victim, value: proxy}
    end

    local existingProxy = _attackersByVictim[victim][attacker]
    if IsValid(existingProxy) then return end -- 幂等

    local newProxy = ents.Create(PROXY_CLASS)
    if not IsValid(newProxy) then return end

    newProxy.victim = victim
    newProxy.attacker = attacker
    _attackersByVictim[victim][attacker] = newProxy
    _victimsByAttacker[attacker][victim] = newProxy

    newProxy:Spawn()
    SetupRelationships(victim, attacker, newProxy)
end

function ProxyManager.CreateProxy(victim, attacker) return _CreateProxyImpl(victim, attacker) end

local function _RemoveProxyImpl(victim, attacker)
    -- 注意：此处先清表后移除实体。
    -- 当 proxy:Remove() 触发 EntityRemoved 钩子时，
    -- 表中条目已被清除，因此钩子中再次调用本函数会因找不到条目而直接返回，
    -- 从而避免递归。
    if not victim or not attacker then return end

    local attackerProxyMap = _attackersByVictim[victim] -- {key: attacker, value: proxy}
    if not attackerProxyMap then return end
    local victimProxyMap = _victimsByAttacker[attacker] -- {key: victim, value: proxy}
    if not victimProxyMap then return end

    local proxy = attackerProxyMap[attacker]
    if not proxy then return end -- 幂等

    attackerProxyMap[attacker] = nil
    victimProxyMap[victim] = nil
    if table_IsEmpty(attackerProxyMap) then
        _attackersByVictim[victim] = nil
    end
    if table_IsEmpty(victimProxyMap) then
        _victimsByAttacker[attacker] = nil
    end -- 此时对 proxy 实体的引用仍且仅由 local proxy 持有

    if IsValid(proxy) then
        proxy:Remove()
    end
end

function ProxyManager.RemoveProxy(victim, attacker) return _RemoveProxyImpl(victim, attacker) end

function ProxyManager.GetAttackerProxyMapView(victim)
    local attackerProxyMap = _attackersByVictim[victim] or {}
    local view = {}
    local mt = {
        __index = attackerProxyMap,
        __newindex = function(_, key, value)
            error("attempt to modify read-only table", 2)
        end,
        __pairs = function() return pairs(attackerProxyMap) end,
        __ipairs = function() return ipairs(attackerProxyMap) end,
        __len = function() return #attackerProxyMap end,
        __metatable = false
    }
    setmetatable(view, mt)
    return view
end

function ProxyManager.RemoveAllProxiesForVictim(victim)
    if not victim then return end
    local view = ProxyManager.GetAttackerProxyMapView(victim) -- 只读视图
    -- 收集所有攻击者（遍历过程中会修改表，需提前收集）
    local attackers = {}
    for attacker, _ in pairs(view) do
        table.insert(attackers, attacker)
    end
    for _, attacker in ipairs(attackers) do
        ProxyManager.RemoveProxy(victim, attacker)
    end
end

local function _MoveProxiesImpl(oldVictim, newVictim)
    -- 1. 参数有效性检查
    if not IsValid(oldVictim) or not IsValid(newVictim) then return end
    if oldVictim == newVictim then return end

    local attackerProxyMap = _attackersByVictim[oldVictim]
    if not attackerProxyMap then return end -- 无可移动代理

    -- 2. 彻底清除新受害者上原有的所有代理（避免冲突）
    ProxyManager.RemoveAllProxiesForVictim(newVictim)

    -- 3. 遍历旧受害者对应的所有攻击者
    for attacker, proxy in pairs(attackerProxyMap) do
        -- 3.1 先清理反向索引中关于 oldVictim 的条目
        -- 根据设计，只要 attacker 在正向表中，反向表必然存在
        local victimProxyMap = _victimsByAttacker[attacker]
        assert(victimProxyMap, string.format(
            "Inconsistent state: attacker %s in forward map but missing in reverse map",
            tostring(attacker)
        ))
        victimProxyMap[oldVictim] = nil
        if table_IsEmpty(victimProxyMap) then
            _victimsByAttacker[attacker] = nil
        end

        -- 3.2 检查攻击者有效性
        if not IsValid(attacker) then
            -- 攻击者无效：该条目应完全清除
            if IsValid(proxy) then
                proxy:Remove()
            end
            -- 无需再处理 attackerProxyMap 中的键（整个表即将被丢弃）
            continue -- Gmod 支持此关键字
        end

        -- 3.3 攻击者有效，处理代理
        if IsValid(proxy) then
            -- 代理有效：直接移动
            proxy.victim = newVictim

            -- 确保新受害者的正向映射表存在
            local newVictimMap = _attackersByVictim[newVictim]
            if not newVictimMap then
                newVictimMap = {}
                _attackersByVictim[newVictim] = newVictimMap
            end
            newVictimMap[attacker] = proxy

            -- 确保攻击者的反向映射表存在，并插入新受害者
            if not _victimsByAttacker[attacker] then
                _victimsByAttacker[attacker] = {}
            end
            _victimsByAttacker[attacker][newVictim] = proxy

            -- 建立攻击者与新受害者的关系
            SetupRelationshipsVictim(newVictim, attacker)
        else
            -- 代理无效：根据事实来源（attacker 有效）重建代理
            ProxyManager.CreateProxy(newVictim, attacker) -- 自动更新两个表
        end
    end

    -- 4. 丢弃旧受害者的映射表（所有条目已处理）
    _attackersByVictim[oldVictim] = nil
end

function ProxyManager.MoveProxy(oldVictim, newVictim) return _MoveProxiesImpl(oldVictim, newVictim) end

function ProxyManager.CheckOrphanProxy(proxy)
    if not IsValid(proxy) then return end
    if IsValid(proxy.victim) and IsValid(proxy.attacker) then return end
    ProxyManager.RemoveProxy(proxy.victim, proxy.attacker)
end
