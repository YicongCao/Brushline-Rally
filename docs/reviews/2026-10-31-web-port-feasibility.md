# Brushline Rally 网页版与 Node.js 托管可行性

调研日期：2026-10-31。项目基线：`3ab1c4ab1b70abed5bb739c844d2a0f337e520bf`，Godot 4.7.2。

## 决策摘要

**建议推进桌面浏览器试玩原型。** 架构上可以保留 Godot、GDScript、自研车辆模型和 Jolt，把游戏导出为 WebAssembly/WebGL 2，再由 Node.js 提供网页和资源。托管工作较小；主要工作是 Compatibility 渲染适配、首包与场景内存控制，以及浏览器输入、声音、保存体验。

- 单赛道／单车、键鼠优先的桌面浏览器试玩：值得实施，性能需原型确认。
- 全部四赛道、八车、改装车库与实时 Demo：有移植路径，不能承诺原画质、原加载速度和原帧率。
- 手机浏览器：暂不作为首发验收目标，需要额外触屏操作、画质与内存方案。
- 本次完成源码检查、资源统计和官方资料核对；没有安装 Web 模板、导出游戏、启动托管服务或进行浏览器实测。以下性能指标是拟定门槛，不是已达到的结果。

## 一、运行架构

```text
Godot 4.7.2 构建阶段
  项目代码与资源 → Web 导出 → HTML / JS / WASM / PCK

访问链路
  玩家浏览器 ← HTTPS → Node.js / Express
                         ├─ 首页、说明、下载入口
                         └─ /play/<build-id>/ 游戏导出文件

浏览器内部
  Godot WebAssembly：执行 GDScript、车辆物理、赛道与菜单
  WebGL 2：渲染画面
  Web Audio：播放声音
  IndexedDB：本机浏览器存档
```

Node.js 负责文件与页面服务，游戏运算在玩家设备进行。此方案不需要把游戏改写为 JavaScript，也不需要在服务器运行一份游戏实例。多人联机、账号同步和可信排行榜属于后续独立功能；仅提供网页版时无需数据库。

Godot 的 Web 导出使用 WebAssembly 与 Compatibility/WebGL 2；Forward+ 和 Mobile 渲染器不能直接用于 Web。[官方 Web 导出说明](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)

## 二、当前项目的有利条件

- [项目配置](../../project.godot)为 GDScript、Jolt、120 Hz 物理。仓库扫描未发现 C# 或 `.gdextension`，运行时代码未发现显式 Thread／WorkerThreadPool 依赖。
- [车辆积分](../../scripts/vehicle/rally_vehicle.gd)、[轮胎模型](../../scripts/vehicle/tire_model.gd)是项目代码，具备复用基础。
- Godot **4.7.2** 的 Jolt 构建条件不排除 Web，并包含针对 WebAssembly SIMD 的分支。这支持“保留 Jolt 做原型”的判断，但不等于本项目已通过 Web 运行验收。[构建条件](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/modules/jolt_physics/config.py)、[Web 构建分支](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/modules/jolt_physics/SCsub)
- [赛道生成](../../scripts/stage/stage_generator.gd)已有分帧构建；[输入控制](../../scripts/input/input_controller.gd)已有失焦清空输入和安全暂停；[存档](../../scripts/game/profile_store.gd)已有临时文件、备份与回滚逻辑，可以继续利用。
- 当前 [导出配置](../../export_presets.cfg)只有 macOS／Windows，没有 Web 预设。本机 4.7.2 模板目录也只安装了桌面模板。Node.js 已有 `v26.1.0`，后续部署应锁定受支持 LTS 分支的维护版本，而不是直接沿用这一个旧补丁版本。[Node.js 版本政策](https://nodejs.org/en/about/previous-releases)

## 三、需要适配的地方

### 1. 渲染与画质：主要工作项

为 Web 增加独立画质配置，桌面继续沿用 Forward+。需要逐项检查车辆描边、路面、植被、水面、光柱、车灯与 UI 玻璃，避免用一次全局切换代替验收。

具体依据：

- [赛道表现](../../scripts/presentation/stage_presentation.gd)和 [Demo 场景](../../scripts/showcase/showcase_world.gd)硬设 FXAA，Compatibility 不支持该项，应比较无 AA 和低倍 MSAA 的清晰度与耗时。
- [眩光 shader](../../assets/shaders/sample_flare.gdshader)按 Forward+/Metal 深度约定判定天空；需要检查 Web 的实际深度与全屏覆盖行为，不能仅凭代码注释认定一定失败。官方说明不同渲染器的 NDC 深度范围存在差异。[深度处理说明](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html)
- [车轮特效](../../scripts/presentation/vehicle_feedback.gd)使用 GPUParticles3D、透明尘土和近距离淡出；应验证实际用到的功能，优先限制粒子数量和透明覆盖。不能把“使用 GPU 粒子”直接列为必然不支持，也不能假设全换 CPU 粒子就更快。
- [原生分辨率工具](../../scripts/ui/native_resolution.gd)会按实际像素放大离屏视口。Web 应给 3D 内部分辨率设置上限，初始目标 1280×720，UI 保持清晰，避免 Retina 屏无意增加数倍像素工作量。

官方 4.7 渲染功能表列出 FXAA 在 Compatibility 中不可用，同时列出普通雾、屏幕／深度纹理等可用功能；不要照搬更老版本的限制列表。[渲染功能表](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)

### 2. 物理性能：保留模型，先测量

当前为 120 Hz 物理，每轮胎有 4 次内部求解子步，接触查询会在 5／9／17 点之间切换。WebAssembly 的运行成本、地面查询和 GDScript 热路径都需要测量。Node.js 服务器升级不会改善玩家设备的这一部分帧率。

第一轮保持原物理频率与参数，先降低绘制成本和非必要场景更新。只有确实测出物理预算不足，才评估降低频率或优化热路径；改变频率后必须重新检查制动、混合路面和反打恢复，并管理物理版本与成绩比较。不能默认浏览器和原生版逐位确定性一致。

建议先建立单线程构建基线，再比较多线程构建的收益。多线程并不会自动并行所有 GDScript 逻辑；它还需要 HTTPS／localhost 安全上下文及跨源隔离。[官方线程说明](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html#thread-and-extension-support)

### 3. 首包、加载与 Demo 内存

本次本地文件统计：`assets/` 共 531 个文件，逻辑大小 **84.57 MiB**，含导入描述文件；其中中文字体 `NotoSansSC-Variable.ttf` 为 **16.95 MiB**。`resources/showcase/` 为 **3.42 MiB**。

这些不是 Web 下载量，也不是运行内存：导入后的纹理、WASM、导出筛选、压缩、解码与运行时创建的几何都会改变结果。目前没有真实 `.pck`／`.wasm` 可供测量。

建议：

- 第一包只提供一条赛道与一辆车。当前桌面预设是 `all_resources`；Web 要独立梳理导出依赖，并保留动态路径加载的车型、音频和 JSON，不能简单改为“只导出选中场景”。
- 首先减少大幅画册／宣传图片的游戏内分辨率，长背景音乐评估压缩音频。当前音乐接口类型固定为 AudioStreamWAV，换格式需要一起调整。
- 中文字体可以研究裁剪，但必须保留车牌输入等用户文本的合理字符范围与回退方式，不能只按菜单文字裁剪。
- 先交付一个经过裁剪的 PCK；分赛道下载作为第二阶段，需要增加内容清单、下载、挂载和依赖管理，Node 静态服务本身不会自动把资源变成按需加载。
- [Demo 导演](../../scripts/showcase/showcase_director.gd)会提前准备三个独立世界，只停止非活动场景的更新／渲染，仍保留其内存。首版网页建议提供带音频的预录 Demo 视频和可驾驶试玩；完整实时 75 秒 Demo 待峰值内存合格后加入。若其无加载转场要求保留，应在场景驻留、预热与资源精简之间实测取舍。
- 分帧加载已有基础，但赛道生成仍含一次性工作；加载进度必须覆盖下载、WASM 初始化、资源读取、道路／景观构建和首次绘制。

### 4. 声音：大部分可复用，必须检查循环和交互

[音乐与领航](../../scripts/game/audio_director.gd)主要播放 WAV；[合成音效](../../scripts/presentation/synth_audio.gd)一次生成短 PCM 并缓存为 AudioStreamWAV，并非 AudioStreamGenerator 持续供给音频。因此不应仅凭“程序化生成声音”判断音频无法移植。

网页应由“点击开始”启动游戏声音。先尝试默认 Sample 播放，听验发动机动态变调、多层混音、领航压低背景音乐、暂停与恢复，以及运行时创建 WAV 的兼容性；有问题的播放器再评估 Stream 模式的延迟与成本。[官方 Web 音频说明](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html#audio-playback)

### 5. 保存、导出与操作

- `user://` 在网页中对应浏览器本地存储，不会自动同步到 Node.js 或桌面存档。同域浏览器重开可保留的行为需要实测；清理站点数据、配额限制和存储回收都要处理。[浏览器存储政策](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria)
- 保留当前 JSON、备份和幽灵格式，检查连续保存、快速刷新、关闭页面后重开及保存失败恢复。FileAccess 写入已有引擎同步机制，不应每帧手动强制同步文件系统。
- [相册](../../scripts/game/photo_album.gd)与 [遥测导出](../../scripts/vehicle/telemetry_recorder.gd)目前写到本地路径；Web 应增加显式下载按钮，使用 `JavaScriptBridge.download_buffer()`。浏览器下载与游戏内保存是两件事。[JavaScriptBridge](https://docs.godotengine.org/en/4.7/classes/class_javascriptbridge.html)
- 页面隐藏、窗口失焦时暂停驾驶与声音，清空油门／转向；恢复时由玩家确认继续。现有输入通知可复用，但 Demo 当前会断开普通场景暂停信号，需单独接入浏览器可见性处理。
- 全屏使用用户点击触发；退出按钮返回网页。检查方向键／空格导致页面滚动、手柄首次激活与映射、全屏退出和窗口尺寸变化。手机触控另做设计。

## 四、Node.js 托管方案

建议 Node.js LTS + Express 提供整站，使用同域路径承载游戏。Express 本身支持静态文件和路径挂载；生产环境可在前方接 HTTPS 反向代理／CDN。[Express 官方说明](https://expressjs.com/en/starter/static-files/)

目录约定建议：

```text
web-host/                 Node 服务、依赖锁文件、启动说明
web-shell/                自定义启动页源文件
builds/web/<build-id>/    Godot 导出产物，加入忽略规则
```

站点路由建议：`/` 为介绍页，`/play/<build-id>/` 为游戏，`/healthz` 为服务健康检查。托管根目录仅包含公开构建产物，不直接公开整个仓库。Godot 启动页通过 Custom HTML Shell 维护，避免每次导出覆盖手改内容。

必须落实的服务行为：

- `.wasm` 返回 `application/wasm`，`.pck` 返回二进制 MIME；缺失游戏资源返回 404，不能被首页回退规则变成 HTML。
- 使用 Brotli／gzip 预压缩或正确协商的压缩服务，包含对应 Content-Encoding 和 Vary。防止重复压缩。
- HTML 和版本清单重新验证缓存；包含版本号的整套构建目录可长期缓存。原子切换入口，保留旧构建一段时间，避免 JS、WASM、PCK 混用。
- 公网使用 HTTPS，本地开发可用 localhost。局域网 HTTP 地址不等同于 localhost 安全上下文例外。
- 多线程构建启用 `Cross-Origin-Opener-Policy: same-origin` 和 `Cross-Origin-Embedder-Policy: require-corp`，并在浏览器检查 `crossOriginIsolated`。第三方字体、图片、CDN 或嵌入页面需满足相应 CORS／CORP 条件；首版同域部署最简单。[COEP 规则](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Embedder-Policy)
- 只有拿到实测收益才增加双构建自动选择；单线程版本不必强制依赖跨源隔离。PWA／离线缓存可随后加入，先处理好构建更新与存档兼容。

纯静态试玩的服务器负担主要是资源分发。带宽估算使用“每次冷加载实际传输量 × 冷加载人数”，实际费用取决于部署商和缓存命中率。本次没有测得首包大小，不能据源码大小报价。

## 五、建议实施顺序与验收

### 阶段 A：证明能够正确运行

获取与 4.7.2 匹配的官方 Web 导出模板；增加独立 Web 预设和画质分支；选择松岭 + R200 自由练习；用本地 Node 服务运行。先完成标题、进赛道、驾驶、声音、暂停、复位、结束和存档重开。此阶段先用桌面 Chromium，随后覆盖 Firefox 和 macOS Safari。

### 阶段 B：证明适合发给别人

测冷／热启动下载量、进入可驾驶状态耗时、着色器首次使用卡顿、帧时间 P95／P99、物理耗时和内存峰值。至少跑完整赛段，并连续重进赛道三次观察资源释放。用指定机器、浏览器版本和画质记录结果；现有原生 Metal 的性能报告不能替代 Web 数据。

拟定门槛：桌面 720p 以 60 FPS 为目标；若需 30 FPS 档位，必须有明确切换与稳定物理表现。代表性驾驶片段不能持续低于 30 FPS；P95 帧时间按所选 60／30 FPS 档分别以约 16.7／33.3 ms 为目标。先保留 120 Hz 物理，验证后驱反打、制动、软沙和改装边界；不能通过慢放仿真达成帧率。

启动预算可暂定为：在明确记录的 50 Mbps 网络条件下，首次进入试玩不超过 15 秒、缓存后不超过 5 秒。这是待协商的体验目标；必须用实际 HTTP 传输、WASM 初始化和场景构建总时间验收，超预算时先优化首包与加载过程。

### 阶段 C：扩展内容

原型合格后加入其余车辆、赛道、车库、相册下载和实时 Demo。上线前完成 HTTPS、压缩缓存、旧构建更新、断网重试、站点存储失败、键鼠／实体手柄与浏览器差异检查。若增加云存档或排行榜，再设计账号、数据隔离与服务端校验。

## 最终判断

目前没有发现必须重写游戏或替换物理引擎的硬障碍；也没有足够证据承诺全内容网页版达到原生体验。**建议下一步实施一个独立 Web 试玩预设和 Node.js 托管原型，以一车一图验证性能，再决定扩展范围。** 本次交付仅为调研报告，未修改运行时或部署服务。
