# 《余烬守望》协作说明

本文件按项目所有者要求命名为 `AGNET.MD`。根目录 `AGENTS.md` 是工具的标准入口，指向本文件。交流、说明和交接请使用汉语。

> **必须执行：每次更新文件后，提交并推送到 GitHub。**
> 主机A与从机B均适用，包括代码、美术资产、派工文件和任务状态。每轮结束前检查实际推送结果与远端分支提交；本地保存或提交不能代替推送。缺少远端、认证失败或发生冲突时，保留工作、说明未推送原因并在解决后补推，不得强推或声称已经同步。

## 项目与当前状态

- 原创单机末日据点防守游戏，Godot 4.6.2、Blender 4.5、GDScript。
- 实际入口为 `scenes/nightfall.tscn`，配置见 `project.godot`。旧三路 MOBA 场景仅作为历史代码保留，不是当前游戏。
- 远端初始导入为0.8.17，本机最新已验证可玩版为0.8.18；源码含待验的0.8.19工作。后续版本、已验证进度以 `optimization-progress.json` 为准，当前派工见 `agent.md`。
- 当前完成的是三夜守城玩法切片。完整剧情、NPC 对话、永久存档及大型开放世界尚未实现，不要把设计稿写成已完成功能。

## 必须保留的产品方向

- 单机、末日、灯火据点、外出探索、塔防守家；不恢复 MOBA，不新增多人联网或装备商店。
- 角色通过局内三选一卡强化属性与能力，没有装备系统；第三夜结束当前一局。
- 开局选卡后直接进入黑夜。当前夜晚 105 秒、白昼 90 秒。
- 据点高于荒原约 5 单位，三面封闭，仅南门一个入口；大量怪物沿该入口进攻。
- 玩家移动时镜头方向固定。打击反馈允许小幅平移，不允许镜头随人物旋转。
- 夜间环境应暗，依靠局部灯光读图；仍须看清敌人预警、技能边界和南门压力。
- 用户重视精美造型、材质、自然动作和直接的操作响应，不能仅用增加面数或强发光代替设计。
- 不新增开发日志、录屏或 PDF。内部验证截图可以用于检查实际效果。
- 在项目所有者电脑上做测试时，不抢焦点、不外放声音；图形验证采用隐藏窗口、屏幕外位置和 Dummy 音频驱动。只有用户明确要求展示游戏时才前台启动。

## 主要目录与模块

| 路径 | 用途 |
| --- | --- |
| `scripts/nightfall.gd` | 游戏阶段、玩家输入、移动、敌人、塔防、技能、奖励与卡牌接入 |
| `scripts/nightfall_world.gd` | 场景布置、地形、局部灯光与昼夜氛围 |
| `scripts/unit.gd` | 单位生命、护盾、独立关节步态及动作；不是完整蒙皮骨骼动画 |
| `scripts/nightfall_hud.gd` | HUD、选卡、暂停、来源面板、连击与浮字 |
| `scripts/combat_feedback.gd` | 剑气、命中碎光、原创合成音效、奖励浮字与轻微震动 |
| `scripts/music_director.gd` | 本地配乐、昼夜/战斗切换、音量与静音偏好 |
| `scripts/run_build.gd` | 命运卡、流派和属性统计 |
| `scripts/day_expeditions.gd` | 发电机守圈、救援与护送 |
| `scripts/wild_discoveries.gd`、`neutral_wildlife.gd` | 刷新互动点、中立生物和探索反馈 |
| `assets/` | Godot 运行资源：GLB、图片、着色器、配乐与署名 |
| `art_source/` | 可编辑 Blender 源文件和原创资产制作脚本 |
| `tests/` | 实际场景、行为、渲染及混音验证 |
| `tools/` | 辅助制作、音频准备及验证脚本；不会自动运行 |

## 开发与素材流程

1. 克隆仓库前安装 Git LFS；克隆后运行 `git lfs pull`，确认 `.blend`、`.glb`、`.ogg` 等是完整文件而不是 LFS 指针。
2. 安装 Godot 4.6.2，打开 `project.godot`，等待导入后按 F5。首次克隆没有本地 `build/`，请直接从 Godot 运行或自行导出。
3. 运行现有 GLB 不需要安装 Blender；编辑/重新制作三维资产时安装 Blender 4.5，并保留对应 `.blend` 与 GLB。
4. 生成脚本位于 `art_source/`。例如使用 Blender 后台模式执行 `art_source/create_ashwarden.py`；先查看脚本的输入源、输出范围及入口参数，避免一次重生成所有资产覆盖别人正在编辑的模型。
5. 动作依赖模型的关节名称与父子关系。主角肩、肘、髋、膝、脚踝和衣摆节点，怪物头部和四肢枢轴不能随意删除、改名或全部合并。
6. 材质以导出的 glTF PBR 为准；在 Godot 实际镜头、昼夜光照和动作中验证，Blender 展示图不能替代实机检查。
7. 当前主要验证平台是 Windows；界面使用系统字体，没有将 Windows 字体打包。不要声称其他平台已经完整验证。

## 操作与战斗约定

- `ZASD` / 方向键移动，右键寻路；上行键为 Z，W 已用于屏障。
- `Q/W/E/R/X` 为斩光、屏障、突进、灯焰、治疗。R 当前消耗 85 法力，基础冷却 28 秒。
- `F` 搜集/建造/升级/修灯，`H` 修塔，`G` 塔目标模式，`C` 集火，`T` 南门机关，`B` 路障。
- `M` 配乐开关，`[` / `]` 配乐音量，`F1` 音乐来源，`F2` 减弱震动和闪光，`Esc` 暂停。
- 普攻按实际动作时序命中，基准约 0.14 秒；高攻速同时缩短动作和剑气传播。只提交原目标一次，死目标或离开范围应取消。
- 连续三段普攻的第三段伤害提高 30%，2.8 秒没有命中重置。暴击仍为 175% 伤害。
- 六秒内普攻或其连锁附伤亲自击杀，3/6/10 连斩额外奖励零件 5/8/12、记忆 4/6/10。塔、脉冲、技能和反伤不得冒充普攻连斩。
- 选卡与暂停不消耗攻击/连斩窗口；昼夜交接重置。R 不得被自动普攻打断；移动和技能不能被反馈动画锁住。
- 姿势停顿是局部视觉效果，不修改全局 `Engine.time_scale`；减少反馈选项不降低真实伤害和奖励。

## 验证与交付

只运行与修改相关的验证。普通行为验证使用：

```powershell
godot --headless --audio-driver Dummy --path . --script tests/nightfall_attack_feedback.gd
godot --headless --audio-driver Dummy --path . --script tests/nightfall_movement_response.gd
godot --headless --audio-driver Dummy --path . --script tests/nightfall_r_skill_controls.gd
godot --headless --audio-driver Dummy --path . --script tests/nightfall_loop.gd
```

需要实际渲染的用例不能用 headless 代替。Windows 后台启动示例：

```powershell
Start-Process -FilePath '你的Godot可执行文件路径' -WindowStyle Hidden -ArgumentList @('--path','.','--position','10000,10000','--audio-driver','Dummy','--script','tests/nightfall_attack_visual.gd')
```

检查退出码、脚本错误及实际画面/混音；测试结束释放进程。音频用例卸载场景后需让音频线程完成清理。不能只看打印的 `OK` 而忽略 `SCRIPT ERROR` 或其他错误。

Windows 导出使用 `export_presets.cfg` 的 `Windows Desktop`，并安装同版本导出模板。生成物放 `build/`；可玩版本通过后再更新 `启动游戏.cmd`。源码仓库不提交本地缓存与历次导出包，分发成品使用仓库 Release。

优化目标为 100 次。仅实质可玩改进完成实现、相关验证及可启动版本交付后才增加 `optimization-progress.json.completed`；文档整理和本次上传不计数，不恢复定时自动续跑。

## 协作与授权

- 2026年10月3日起按项目所有者最新要求，每台电脑只保留一个主对话。本机为主机A，负责安排任务、玩法、共享文件接入、审核合并与发布；另一台为从机B，执行被分配的画面任务。唯一动态看板是根目录 `agent.md`，派工、状态、提交/PR与验收回执均在该文件通过Git共享。旧四窗口分工和ZIP同步方案已取消。

- 使用独立功能分支，通过 PR 合并；Codex 创建的分支使用 `codex/` 前缀。不要强推、重置或覆盖其他人的未提交工作。
- 开始前确定负责文件。`nightfall.gd`、`unit.gd`、HUD、同一个 Blender 文件多人同时编辑时，先协调范围；二进制模型不可依靠文本冲突自动合并。
- `.blend` 是制作源，`.glb` 是运行资源；需要修改模型时同步提交两者及必要纹理，不能只交截图。
- 不提交 `.godot/`、`.tools/`、`build/`、临时下载、重复 `.blend1`、账号凭据或设备相关设置。不要把机器路径当成所有协作者的安装路径。
- 原创代码和资产的开源许可证尚未由所有者选择，不要擅自标为 MIT、GPL 或 CC0。公开与协作权限以所有者的仓库设置为准。
- 第三方音乐是 Rusted Music Studio / Fabien C. 的 CC BY 4.0 曲目，必须保留 `assets/audio/music/CREDITS.txt`、作者/来源/许可链接及改动说明。两首作者标注 AI 辅助、一首人工创作；不能说成本项目新生成的音乐。
- 详细来源见 `ASSETS.md`；当前规则见 `DESIGN.md`；世界观与未实施剧情见 `STORY.md`。不使用其他游戏、小说或短剧的现成人物、台词、模型、音乐与贴图。
