-- lua\modules\ProxyManager\Dist\LRU_cache.lua
LRUCache = {}
LRUCache.__index = LRUCache

function LRUCache:new(maxSize)
    local self = setmetatable({}, LRUCache)
    self.maxSize = maxSize or 100
    self.size = 0
    self.cache = {} -- key -> node
    self.head = nil -- 最近使用节点
    self.tail = nil -- 最久未使用节点
    return self
end

-- 获取值，并将节点移动到头部
function LRUCache:get(key)
    local node = self.cache[key]
    if not node then return nil end
    self:_moveToHead(node)
    return node.value
end

-- 插入/更新值
function LRUCache:put(key, value)
    local node = self.cache[key]
    if node then
        node.value = value
        self:_moveToHead(node)
        return
    end

    -- 创建新节点
    node = { key = key, value = value, prev = nil, next = nil }
    self.cache[key] = node
    self.size = self.size + 1

    -- 插入头部
    if not self.head then
        self.head = node
        self.tail = node
    else
        node.next = self.head
        self.head.prev = node
        self.head = node
    end

    -- 淘汰尾部
    if self.size > self.maxSize then
        self:_evictTail()
    end
end

-- 删除指定键
function LRUCache:delete(key)
    local node = self.cache[key]
    if not node then return end

    if node.prev then
        node.prev.next = node.next
    else
        self.head = node.next
    end
    if node.next then
        node.next.prev = node.prev
    else
        self.tail = node.prev
    end

    self.cache[key] = nil
    self.size = self.size - 1
end

-- 清空缓存
function LRUCache:clear()
    self.cache = {}
    self.head = nil
    self.tail = nil
    self.size = 0
end

-- 内部：将节点移动到头部
function LRUCache:_moveToHead(node)
    if node == self.head then return end

    -- 从原位置移除
    if node.prev then
        node.prev.next = node.next
    else
        self.head = node.next
    end
    if node.next then
        node.next.prev = node.prev
    else
        self.tail = node.prev
    end

    -- 插入头部
    node.prev = nil
    node.next = self.head
    if self.head then
        self.head.prev = node
    end
    self.head = node
    if not self.tail then self.tail = node end
end

-- 内部：淘汰最久未使用的尾部节点
function LRUCache:_evictTail()
    if not self.tail then return end
    self:delete(self.tail.key) -- 复用 delete
end
