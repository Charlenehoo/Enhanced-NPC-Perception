-- lua\modules\ProxyManager\Core\private.lua
local PROXY_CLASS = ProxyManager.PROXY_CLASS

local _private = {}

local IsValid = IsValid
local table_IsEmpty = table.IsEmpty

--[[
    ProxyManager 核心实例管理模块设计原则

    文件组织：
    - private.lua: 包含私有数据（ _attackersByVictim, _victimsByAttacker ）和内部实现函数，
      返回一个表 _private，供 public.lua 调用。外部代码不得直接访问此文件。
    - public.lua: 提供公开 API （ CreateProxy, RemoveProxy, MoveProxy, GetAttackerProxyMapView ），
      通过 require 引入 private.lua，在其闭包中操作私有数据，并将函数挂载到全局 ProxyManager 表。
    - util.lua: 存放辅助函数（如 CheckOrphanProxy ）
      这些函数仅通过公开 API 与核心交互，不直接访问私有数据。

    核心设计原则：
    1. 私表为单一事实来源
       私有表 _attackersByVictim 和 _victimsByAttacker 是系统状态的唯一存储。
       任何与表记录不一致的实体状态（如代理实体失效但表中仍有条目）都视为系统错误，
       应立即修复（重建代理或清理条目）或通过 assert 触发快速失败。

    2. 私有表访问严格受控
       私表只能由 private.lua 中的内部函数直接读写。public.lua 不得直接访问私表，
       必须通过调用 _private 表中的函数间接操作。外部代码（包括 Utils 及其他模块）
       只能通过 public.lua 提供的公开接口访问系统功能。

    3. 内部函数命名规范
       所有 private.lua 中定义的内部函数（包括公开接口的底层实现）均以 "_" 开头，
       并作为 _private 表的方法（如 _private._CreateProxyImpl）。这明确标识其私有性质，
       防止被外部意外调用。

    4. 快速失败与状态一致性
       在内部函数中，当检测到私表状态不一致（如正向表存在某键但反向表缺失）时，
       应立即通过 assert 报错终止，以暴露潜在 bug，防止脏数据扩散。

    5. 最小化内部实现
       内部函数数量应尽可能少。优先复用现有的公开接口（如 ProxyManager.RemoveProxy）
       实现功能，仅在无法满足性能或功能需求时才新增私有实现。Utils 中的辅助函数
       应完全基于公开接口构建，绝不直接访问私表。

    6. 实体生命周期与表状态同步
       只有 private.lua 中的内部函数可以直接调用 ents.Create(PROXY_CLASS) 创建代理实体，
       或直接调用 proxy:Remove() 销毁代理实体。公开接口必须通过调用这些内部函数间接操作，
       确保实体创建/销毁与私表更新在同一个原子操作中完成，维持状态同步。
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

local function CreateReadOnlyView(t)
    local view = {}
    local mt = {
        __index = t,
        __newindex = function() error("attempt to modify read-only table view.", 2) end,
        __pairs = function() return pairs(t) end,
        __metatable = false
    }
    setmetatable(view, mt)
    return view
end

function _private._CreateProxyImpl(victim, attacker)
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

function _private._RemoveProxyImpl(victim, attacker)
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

function _private._GetAttackerProxyMapViewImpl(victim)
    local attackerProxyMap = _attackersByVictim[victim] or {}
    return CreateReadOnlyView(attackerProxyMap)
end

function _private._IterateVictimsWithAttackerProxyMapViewImpl()
    local nextVictim, state, currentVictim = next, _attackersByVictim, nil
    return function()
        local attackerProxyMap
        currentVictim, attackerProxyMap = nextVictim(state, currentVictim)
        if not currentVictim then return nil end
        return currentVictim, CreateReadOnlyView(attackerProxyMap)
    end
end

function _private._MoveProxiesImpl(oldVictim, newVictim)
    -- 1. 参数有效性检查
    if not IsValid(oldVictim) or not IsValid(newVictim) then return end
    if oldVictim == newVictim then return end

    local attackerProxyMap = _attackersByVictim[oldVictim]
    if not attackerProxyMap then return end -- 无可移动代理

    -- 2. 彻底清除新受害者上原有的所有代理（避免冲突）
    ProxyManager.RemoveAllProxiesByVictim(newVictim)

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

return _private
