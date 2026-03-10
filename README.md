# Enhanced NPC Perception 2

Enhanced NPC Perception 2 是一个 Garry's Mod 服务器端插件，旨在大幅提升 NPC（特别是 Combine）的感知和战斗 AI。通过引入**代理实体**，NPC 能够在目标被遮挡、超出引擎射程、死亡或处于特殊动画状态时，依然保持追踪和攻击能力，从而带来更真实、更具挑战性的战斗体验。

## ✨ 核心特性

### 🎯 突破射程限制 – 让 NPC 发挥全部枪械实力

Source 引擎原版 NPC 的最大射击距离被硬编码为 1024 单位，导致许多枪械无法发挥应有威力。本插件通过将代理实体放置在**最大感知距离方向**，引导 NPC 持续向代理射击，**彻底突破 1024 单位限制**，让 NPC 的子弹真正飞向远处目标。

### 🧱 隔墙压制 – 智能的压制射击

当目标躲入掩体后，NPC 不会立即放弃。在 **压制时间（默认 8 秒）** 内，代理实体将被放置在**视线终点（墙壁表面）**，NPC 会持续向墙壁开火，模拟真实的火力压制。一旦目标再次露出，NPC 立刻切换为精准射击。

### 🦵 攻击部分身体 – 不再放过任何暴露部位

原版 NPC 经常忽略只露出部分身体的玩家。本插件通过**骨骼级代理**，在目标的头、四肢、躯干等关键部位生成代理点，即使只有一小部分身体可见，NPC 也会精确瞄准对应部位，让战斗更加真实致命。

### ⚰️ 完美配合 EDA – 攻击倒地与复活的玩家

与 [Enhanced Death Animations (EDA)](https://steamcommunity.com/sharedfiles/filedetails/?id=2779563179) 深度集成：

- 玩家处于死亡动画阶段 → 代理从玩家转移到布娃娃，NPC 继续攻击尸体。
- 玩家进入挣扎/爬行/被复活状态 → 代理保留在布娃娃上，防止玩家利用复活机制无风险起身。
- 玩家最终死亡 → 延迟移除代理，战斗结束。

此机制有效平衡了 EDA 提供的复活能力，让倒地不再安全，战斗更具紧张感。

### 🔊 听觉模拟 – 声音触发转向

当目标发出声音时，附近的 NPC 会强制转向声源位置（通过代理实现），即使原版声音系统无法触发 AI 反应。这使得潜行更加困难，而暴露位置则立刻招致火力。

### 🔁 多 NPC 同时追踪

每个目标可被多个 NPC 同时追踪，每个 NPC 拥有独立的代理实例，互不干扰，实现围攻效果。

## 🧠 工作原理（简略）

1. **骨骼级代理生成**  
   根据目标模型的骨骼结构，在关键部位生成不可见的代理实体 (`enp_proxy`)。代理与目标同步移动，但可独立设置位置。

2. **智能位置计算（每帧更新）**
   - **目标可见** → 代理位于目标骨骼点（加上偏移量），NPC 直接瞄准。
   - **目标不可见但处于压制期** → 代理位于视线终点（墙壁表面），引导 NPC 隔墙射击。
   - **目标超出最大距离** → 代理置于最大距离方向，突破射程限制。
   - **目标彻底丢失（压制期结束）** → 代理移除，NPC 恢复正常行为。

3. **与 EDA 状态机联动**  
   通过 `EDAStateMachine` 监听玩家的死亡状态（死亡动画、挣扎、爬行、复活、最终死亡），自动执行代理的创建、转移和移除。

4. **声音中继**  
   当目标实体发出声音时，`sound_relay.lua` 记录时间戳，附近 NPC 会通过代理强制转向声源（设置敌人为代理并执行 `SCHED_COMBAT_FACE`），模拟听觉反应。

## 🔧 依赖

- **必须安装 [Enhanced Death Animations (EDA)](https://steamcommunity.com/sharedfiles/filedetails/?id=2779563179)**  
  插件依赖 EDA 的玩家状态字段来判断何时创建、移动或移除代理。若未安装，插件将无法正常工作。

## 📦 安装

1. 下载本仓库的代码（或直接克隆）。
2. 将整个文件夹放置于服务器的 `garrysmod/addons/` 目录下。
3. 确保服务器已启用 EDA 模组（通过 Steam Workshop 或本地安装）。
4. 重启服务器或执行 `lua_run include("autorun/init.lua")` 手动加载。

文件结构示例：

```
garrysmod/addons/Enhanced NPC Perception 2/
├── lua/
│   ├── autorun/
│   │   └── init.lua
│   ├── entities/
│   │   └── enp_proxy.lua
│   └── modules/
│       ├── ProxyManager/
│       │   ├── Core/
│       │   │   ├── private.lua
│       │   │   ├── public.lua
│       │   │   └── util.lua
│       │   ├── bones.lua
│       │   ├── bone_cache.lua
│       │   ├── constants.lua
│       │   ├── hooks.lua
│       │   └── proxy_sync.lua
│       ├── 3rd_party/
│       │   └── soundmanager.lua
│       ├── eda_state_machine.lua
│       ├── player_proxy.lua
│       └── sound_relay.lua
└── README.md
```

## ⚙️ 配置

所有可调参数集中在 `lua/modules/ProxyManager/constants.lua` 中：

| 参数                            | 默认值        | 说明                                                                               |
| ------------------------------- | ------------- | ---------------------------------------------------------------------------------- |
| `ATTACKER_RANGE`                | 1040          | NPC 最大追踪距离（单位：游戏单位）。实际射击距离由枪械决定，此值仅为代理放置上限。 |
| `ATTACKER_SUPPRESSION_TIME`     | 8             | 目标消失后，NPC 继续“压制”的秒数（期间会隔墙射击）。                               |
| `PROXY_OFFSET`                  | 16            | 代理实体相对于目标骨骼点的偏移量，用于避免完全重合导致的视线误判。                 |
| `DEFAULT_ATTACKER_CLASS_PREFIX` | "npc_combine" | 受影响的 NPC 类别前缀（如 `npc_combine_s`、`npc_combine_camera`）。                |
| `DEBUG`                         | `true`        | 开启调试输出（服务器控制台）。                                                     |

如需让其他类型的 NPC 也能感知代理，只需修改 `DEFAULT_ATTACKER_CLASS_PREFIX` 或调用 `ProxyManager.CreateProxiesForVictimByClass(victim, "你的类别模式")`。

## 🚀 效果展示

- **远程对射**：Combine 可以在开阔地带对远处玩家持续射击，子弹不再在 1024 单位处消失。
- **掩体压制**：躲在墙后也会被持续射击，露出头手立刻被击中。
- **倒地追杀**：即使玩家倒地并尝试复活，NPC 也会持续攻击尸体，直到彻底死亡。
- **声音吸引**：开枪或跑步声会吸引附近 NPC 转向并开火。

## 👨‍💻 开发者说明

- 核心数据结构位于 `ProxyManager._private`，外部应通过 `public.lua` 提供的 API 操作，切勿直接修改私有表。
- 如需扩展支持其他 NPC 类型，可调用 `ProxyManager.CreateProxy(victim, attacker)` 手动建立关系。
- 调试信息可通过设置 `ProxyManager.DEBUG = false` 关闭。

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。  
（如无许可证文件，请自行添加。）

---

**注意**：本插件仅限服务器端使用，客户端无需安装任何文件。如有问题或建议，欢迎提交 Issue 或 Pull Request。
