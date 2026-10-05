## 当前源码：投蚀体玩法原型

2026-10-06投蚀体复用已追踪的原创`assets/models/night_stalker_v2.glb`及原关节动作，不修改该GLB或Blender源；`scripts/nightfall_lobber.gd`在完整原模型上附加原生蚀液囊、背刺与抛物弹几何，使远程角色可辨认。落点危险圈和进度、弹体及小地图三角标记由程序生成，没有引入第三方模型、贴图或音效。本轮交付是有真实远程行为的可玩原型，不声明已完成专业新角色GLB、PBR纹理或蒙皮动画。

## 当前源码：扩建城堡地形

2026-10-05按城内自由建塔需求新增原创`assets/models/castle_ground.glb`，可编辑源为`art_source/outpost/castle_ground.blend`，定向生成器为`art_source/create_castle_ground.py`。使用Blender4.5.3制作；生成器只制作这张地形，不重生成其他资产，直接读取`scripts/outpost_layout.gd`的数值。城内地面26×26、5米高地，保留三面封闭、正Z唯一南门、12米长坡及两侧挡墙；灰烬地表、Weathered concrete/Concrete fracture材质仍走原风化着色流程。旧`outpost_ground`源和运行资源作为历史输入保留，当前世界加载`castle_ground`。

Blender坐标使用`(world x, -world z, world height)`，经glTF转换后南门仍朝Godot正Z；不镜像坡道。运行资源与`.blend`按Git LFS共享，`assets/models/castle_ground.glb.import`必须一起追踪并保留`meshes/force_disable_compression=true`，避免坡边量化导致视觉高程与判定不一致。Godot4.7.2导入后522660个三角顶点最大高程误差0.0000501米，面内插值抽样误差小于0.008米；已在隐藏Metal Forward+昼夜及红/绿建塔预览实看验证。新增塔预览复用现有`auto_turret.glb`，没有新增第三方模型或贴图。

## 既有资产记录

0.8.11 原创资产：art_source/create_ashwarden.py 生成 hero_ashwarden_blue/red.blend 与对应 GLB；art_source/create_light_eater.py 生成 outpost/night_light_eater.blend 与 GLB。人物和噬灯蛾均保留动作节点，已接入 Godot。R 使用原创 lantern_inferno.gdshader 程序火纹。

0.8.9 破城体：`art_source/create_outpost.py` 定向生成 `art_source/outpost/night_breaker_v2.blend` 与 `assets/models/night_breaker_v2.glb`。专属背甲、肩甲、护腿、撞角和裂隙材质均为原创；保留头部和四肢动作枢轴，已接入夜间破城体。

0.8.5 灰烬猎犬：`art_source/create_outpost.py` 定向生成 `art_source/outpost/night_stalker_v2.blend` 与 `assets/models/night_stalker_v2.glb`，替换当前主场景夜行体。分层背甲、骨刺、关节护甲和发光眼为 Blender 原创；按动画父节点与材质合并网格，保留头部和四肢动作接口。

0.7.8 封印夜巢：`art_source/create_outpost.py` 生成 `art_source/outpost/sealed_nest.blend` 和 `assets/models/sealed_nest.glb`。石质封印、破碎甲壳和低亮度青色纹路均为本项目原创；Godot 实机画面已检查。

0.7.0 夜巢：art_source/create_outpost.py 生成 night_nest.blend 与 night_nest.glb。模型采用低反光甲壳、暗红裂隙与少量骨质尖端；Godot 添加局部红色光源。游戏实机截图已用于检查正常镜头的轮廓与发光强度。

0.6.0 画面更新：灰烬地表着色器为陡坡与崖壁加入岩层色差；Godot 场景在南门两侧增加哨灯与动态灯光。疾行体和破城体复用本项目原创夜行体模型，以比例、光环、速度和攻击行为区分。

堡垒高地更新：灰烬地形中央台地抬高至 5 单位，增加三面陡崖、石质挡墙、亮色墙沿、南门长坡与坡道侧墙与随坡道抬高的道路。Blender 源文件及 Godot GLB 已重新导出。

## 0.5.0 新增资产

Blender 原创生成的塔座、自动防御塔、通信塔残骸和运输车位于 art_source/outpost/，对应 GLB 位于 assets/models/。灰烬地形重新生成至约 252×220 单位；夜行体保留四肢与头部枢轴，Godot 实时驱动动作。

# 素材与工具记录

## 0.4.0 余烬哨站（主场景基础）

`art_source/create_outpost.py` 在 Blender 中生成灰烬地形、灯塔、栅栏、废料箱、枯树、残屋与夜行体。每种资产的可编辑 `.blend` 位于 `art_source/outpost/`，游戏 GLB 位于 `assets/models/`。Godot 用 `assets/shaders/wasteland.gdshader` 表现尘土地表，并通过 `scripts/nightfall_world.gd` 的光照与雾效切换昼夜。角色沿用本项目原创展示骑士 `hero_showcase_blue.glb`；命运卡沿用本项目原有数据。以下 0.3.x 资料记录旧版制作过程，三路竞技场已不在当前主场景中运行。参考作品没有提供任何模型、贴图、音频或剧照。

## 原创三维与声音

Blender 脚本 `art_source/create_assets.py` 生成 13 个模型：蓝红英雄、小兵、防御塔、核心，以及 pine、rock、golem、oak、fern。GLB 位于 `assets/models/`，Blender 源文件位于 `art_source/`。模型为程序化原创资源；步行动画由代码驱动。

地形、道路、技能效果和图标由代码生成。地表与河水着色器位于 `assets/shaders/`。音效由游戏中的 `make_tone()` 合成。

## AI 原创图像

使用内置 imagegen 工具生成，没有使用第三方游戏图片。实际提示词保存在 `art_source/image_prompts.md`。

- `assets/art/menu_v03.png`：奇幻森林与原创骑士菜单背景，属于插画，不代表实机画质。
- `assets/art/forest_ground_v03.png`：用于实机场景的俯视草地纹理，配合重复采样与 mipmap。

## 工具与字体

Godot 4.7.2（https://godotengine.org/license/），Blender 4.5.0（https://download.blender.org/release/Blender4.5/）。便携 Blender 位于 `.tools/`，不随游戏分发。

界面使用 Windows 系统字体 Microsoft YaHei / Microsoft YaHei UI 和 Bahnschrift / Segoe UI。没有复制或分发字体文件。

## 配乐

白昼探索使用 Rusted Music Studio / Fabien C. 的《Wet Sand》（Dark Ambient Piano），黑夜警戒使用《Perish Lane》（Apocalypse Z），守城战斗使用《Dark Sorcery Siege》（Orchestral Fantasy WAR）。三组原页均注明 CC BY 4.0；作者将钢琴与 WAR 包标注为 AI 辅助音频，Apocalypse Z 标注为未使用生成式 AI。本项目选择作者已有作品，没有在 Suno、Stable Audio 或 AIVA 本次生成音乐。

三首均调整响度并处理循环衔接，运行文件位于 `assets/audio/music/`，完整署名、原页与改动说明保存在该目录的 `CREDITS.txt`，游戏内 F1 也可查看。下载使用作者提供的免费入口，不需登录或付款。配乐经独立总线播放，不影响拾取音效；暂停会暂停音乐，选卡与拾取时降低配乐音量。

普通攻击的弧形剑气、命中碎光和奖励光环由 `scripts/combat_feedback.gd` 生成；挥剑、碰撞、暴击、重击、击杀与连斩音效由同一模块合成原创 PCM 音频，不引用第三方游戏录音。原有 Blender 主角模型仍用独立关节节点驱动动作，新增左右挥砍与第三段重击姿势。

敌人死亡效果由 `scripts/death_effects.gd` 驱动已有 Blender 导出的怪物模型，保留其原材质和节点关节，未替换成另一个展示模型。落地支撑点由实际网格凸包缓存；飘散灰烬是本地生成的几何实例，不使用外部粒子贴图，也不是物理布娃娃或蒙皮动画。

据点石材细节由原创 `assets/shaders/outpost_masonry.gdshader` 在 Godot 中生成，接到 `outpost_ground.glb` 的两种石材表面，保留原基色与荒原/铁锈材质。三向世界坐标投影生成烟灰、细裂、颗粒凹凸、墙脚积灰和竖向雨痕；不使用第三方纹理或自发光，也不声称新增了雕刻几何。

## 0.3.2 模型替换

蓝红英雄与防御塔由 art_source/refined_models.py 制作，create_assets.py 调用。英雄采用连续截面胸甲、头盔、分段护具、菱形剑刃与连续褶皱披风；防御塔采用砌石、尖拱和悬浮晶体。Blender 源文件与 GLB 已同步更新。静态网格按材质合并，保留四肢节点与披风动画接口；当前仍采用节点驱动动作，尚非蒙皮骨骼动画。其余模型保留。

## 0.3.4 展示骑士接入
art_source/integrate_knight_study.py 将 showcase/knight_study.blend 的头盔、胸甲、肩甲、披风与已有四肢和武器合成完整角色。输出 hero_showcase_blue/red.glb 及对应 Blender 文件。去除展台和棚拍灯光，程序材质转换为 glTF PBR 常量，保留发光眼睛和宝石；没有烘焙离线微表面纹理。英雄使用这些材质，不再套用通用石材着色器。

## 新兵线单位模型
蓝红小兵由 art_source/refined_models.py 中 minion() 制作，包含披风、头盔、腿甲、盾牌与长枪。Godot 在实例化后保留世界变换并把盾牌、肩甲和长枪挂到手臂节点，便于随步行动作摆动。测试场景用于检查模型实机外观；资产仍为程序化风格化模型。

## 0.3.6 主角设计更新

`art_source/create_starblade.py` 曾制作另一种收腰长腿、折面肩甲的蓝红主角，并保存为 `hero_starblade_blue/red.blend` 与对应 GLB。实机比较后，用户更喜欢圆弧肩甲、闭合头盔的展示骑士造型，因此当前游戏仍使用 `hero_showcase_*`。两套可编辑源文件均保留，便于后续对照修改。当前动作仍由节点驱动，尚未制作骨骼蒙皮动画。

## 0.3.8 地图模型

`art_source/create_terrain.py` 使用 Blender 生成整张低起伏地图、河道凹槽、三路独立石块、压实路基和分层河岸。可编辑源文件是 `art_source/arena_terrain.blend`，游戏导入 `assets/models/arena_terrain.glb`。草地仍用原有地表贴图配合模型起伏；石路在 Godot 中使用 `assets/shaders/weathered_stone.gdshader` 增加世界坐标的颜色与表面颗粒变化，河水材质调整为较暗、较粗糙的外观。导航与单位移动仍基于 `BattleMap` 的平面坐标；地图起伏是视觉表现，不是带坡度的物理地形。

## 0.3.9 场景物件

`art_source/create_map_props.py` 在 Blender 中生成两种乔木、岩石、蕨类、灌丛、野花、蘑菇、遗迹石柱、灵灯、蓝红旗帜、月泉、星碑、遗珍匣，以及新版蓝红防御塔和基地核心。每种资产都有可编辑的 `art_source/map_props/*.blend` 和游戏使用的 `assets/models/*.glb`。造型、材质和摆放均为本项目原创，没有使用《英雄联盟》模型或贴图。材质以暗绿植被、风化石材、旧金属和小面积魔法发光区分层次；仍属程序化风格化资产，并非写实影视级雕刻与扫描素材。

## 0.3.10 植物精细化

沿用 `art_source/create_map_props.py`，重做游戏实际使用的全部五类植物：阔叶树改为枝叉支撑的分簇折面叶冠，杉树改为多层下垂针叶枝；蕨类加入弧形叶轴、成对小羽片和卷叶；灌丛加入分叉枝条及不同朝向的折面叶；野花加入茎叶、两色花瓣和花心；蘑菇加入渐细菌柄、菌褶与拱起的斑驳菌盖。保存了更新后的独立 `.blend` 和 `.glb`。这些是针对俯视游戏镜头的原创实时模型，未使用照片扫描或第三方游戏素材。

## 0.3.11 树冠与风摆

阔叶树分枝叶簇增加至 27 簇、约 918 片折面叶，强化远景树冠轮廓。`assets/shaders/foliage_wind.gdshader` 为所有在用植物的叶、花和蘑菇表面加入不同频率的风摆；树冠随高度增加摆幅，地被植物使用较小幅度。`scripts/world.gd` 在实例化植物时复用同类材质的着色器，树干和遗迹保持稳定。风摆只改变渲染网格，不改变树林阻挡与寻路。

## 0.8.12 远征道具

`art_source/create_day_expedition.py` 使用 Blender 生成原创风格化发电机与哨兵营地。源文件为 `art_source/outpost/day_generator.blend`、`survivor_camp.blend`，运行资产为 `assets/models/day_generator.glb`、`survivor_camp.glb`。发电机保留绕组、独立仪表、护栏与排气管；营地包含开口帐篷、急救箱和信号旗。均使用 glTF PBR 材质及地面原点，没有引用第三方游戏素材。哨兵复用灰烬守望者模型。0.8.13 在 `art_source/create_ashwarden.py` 中补充独立肘关节，保存蓝、红守望者的 `.blend` 和 `.glb`；Godot 使用手工姿态曲线驱动髋、膝、脚踝、肩、肘及衣摆节点，实现跑步、挥剑与灯焰动作，尚非蒙皮骨骼动画。

守望者保留现有 Blender 模型与 PBR 材质。运行时加入独立骨盆枢轴，以实际移动距离推进步态；脚部接触阶段随地面位移后退，摆腿阶段折膝回收，胸甲与骨盆反向摆动，披风和衣摆带有延迟跟随。动作仍由独立关节节点驱动。

## 荧光探索与中立生物

`art_source/create_luminous_discoveries.py` 制作原创余烬花、记忆晶簇、遗落补给箱和引路灯碑；可编辑源位于 `art_source/discoveries/`，运行资产为 `assets/models/ember_bloom.glb`、`memory_crystal.glb`、`supply_cache.glb`、`waylight.glb`。采用可导出的 PBR 和局部发光材质，GLB 按材质合并静态网格，Godot 另外添加照明与互动效果。

`art_source/create_neutral_wildlife.py` 制作原创荧角鹿与苔背甲虫，可编辑源为 `art_source/outpost/lantern_stag.blend`、`mossback_beetle.blend`，运行 GLB 同名。颜色、粗糙度与微法线纹理由脚本绘制并嵌入 GLB，发光角和甲壳缝隙保留独立材质。四腿／六腿、头、耳与尾由 Godot 节点驱动，没有使用第三方动物模型或蒙皮动作。新增拾取提示音由代码生成。

## 0.3.12 场景层次

`art_source/create_terrain.py` 让石路的石块间距、长宽、角度和缺口有更自然的变化，继续保存整张 Blender 地形源文件。`art_source/create_map_props.py` 新增可编辑的 `grass_tuft` 和 `river_reeds`；Godot 使用 MultiMesh 批量摆放草丛，芦苇集中在河岸并留出桥梁。草丛沿噪声分布形成疏密区域。`assets/shaders/water.gdshader` 加入沿河流方向移动的波纹、岸边浅水颜色与细微水痕。以上为实时渲染效果，不是离线渲染贴图。








2026-10-05三兵种玩法：`scripts/outpost_squads.gd`复用已追踪原创卫兵运行模型，盾卫保留盾牌，弩手和工程员隐藏原盾/长柄武器、增加弩/修理工具几何及独立胸徽。选择圈仅所选编组显示；远程和工程反馈由程序几何制作。兵营复用`survivor_camp.glb`、工坊复用`day_generator.glb`并按实测边界缩放，所有底座在Godot中参与占位与动态导航。本轮未制作新的专业兵种GLB或蒙皮动画，不宣称已完成新的Blender兵种资产。
