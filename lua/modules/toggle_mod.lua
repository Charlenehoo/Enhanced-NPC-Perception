-- lua\modules\toggle_mod.lua
ModToggleManager = ModToggleManager or {}
local hookTable
local TARGET_HOOK_MAP = {
    PlayerFootstep = "dstep_main",
    OnPlayerHitGround = "dstep_fall",
    PlayerTick = "dstep_fidget"
}

local savedCallbacks = {}

local function initialize()
    local hookTable = hook.GetTable()
    for hookName, identifier in pairs(TARGET_HOOK_MAP) do
        local hookEntries = hookTable[hookName]
        if hookEntries and hookEntries[identifier] then
            -- 确保存储表存在
            if not savedCallbacks[hookName] then
                savedCallbacks[hookName] = {}
            end
            -- 保存回调
            savedCallbacks[hookName][identifier] = hookEntries[identifier]
            -- 可选：立即移除，以实现默认“禁用”状态，或根据你的需求决定
            -- hook.Remove(hookName, identifier)
        else
            -- 处理目标钩子未找到的情况（可选：记录警告）
            -- print(string.format("[ModToggleManager] Warning: Hook %s (%s) not found.", hookName, identifier))
        end
    end
end

function ModToggleManager.DisableFootStep()
    for hookName, identifier in pairs(TARGET_HOOK_MAP) do
        hook.Remove(hookName, identifier)
    end
    print("[ModToggleManager] Mod disabled.")
end

-- 启用模组：重新添加保存的回调
function ModToggleManager.EnableFootStep()
    for hookName, callbacksForHook in pairs(savedCallbacks) do
        for identifier, callback in pairs(callbacksForHook) do
            hook.Add(hookName, identifier, callback)
        end
    end
    print("[ModToggleManager] Mod enabled.")
end

hook.Add("InitPostEntity", "ENP_SAVE_HOOK", function()
    timer.Simple(0.15, function()
        initialize()
    end)
end)
