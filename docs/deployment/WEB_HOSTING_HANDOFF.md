# Brushline Rally 网页版可行性与运维部署交接报告

日期：2026-10-31 · 接收方：运维 Agent · 状态：**方案可行，部署交付物待齐备**

仓库：`git@github.com:YicongCao/Brushline-Rally.git`

本次检查的源码基线：`2503ab8d953cacbda4dac4498324615b0a801fb5`。详细代码调研见 [网页版可行性分析](../reviews/2026-10-31-web-port-feasibility.md)。

## 1. 先读：当前能做什么

目标是用 Node.js 托管介绍页及 Godot 网页游戏，玩家通过 HTTPS 链接进入。游戏物理和渲染在浏览器执行，服务器提供文件；首版无需 GPU、Godot 运行进程、数据库或玩家账号服务。

当前仓库已经有完整桌面游戏和调研文档，**尚未提供 Web 导出预设、Web 构建包、Node.js 托管程序、package.json 或部署镜像**。本报告中的目录、环境变量、接口与启动命令是后续交付契约，不是当前仓库已有功能。不要在现有根目录直接执行 npm start，也不要把介绍页上线或 HTTP 200 当作游戏已经可玩。

运维可以先准备站点和发布环境。可玩页面上线必须等待研发交付经浏览器验证的游戏包；只有介绍页时，应标记为“介绍页已上线，试玩待交付”。本报告不代表已进行了部署或浏览器性能验证。

## 2. 可行性结论与首发范围

建议首发桌面浏览器试玩：**松岭 + R200，自由练习，键鼠优先，720p，目标 60 FPS**。这些是研发目标，尚未实测达标。Firefox 与 macOS Safari 应分别记录结果，移动端暂不承诺可玩。

项目使用 Godot 4.7.2、GDScript、自研轮胎／悬架与内置 Jolt。已有源码核查支持保留这套物理实现做 Web 原型。主要适配由研发完成：Compatibility 渲染、着色器与抗锯齿、资源裁剪、场景内存、音频启动、存档和输入。服务器扩容不能解决浏览器 GPU 或车辆物理瓶颈。

Web 需要 WebAssembly 与 WebGL 2，不能原样使用桌面的 Forward+ 渲染器。首包大小、启动时间和内存峰值仍待导出后测量；素材目录 84.57 MiB 的源码统计不能作为部署包或流量报价依据。[Godot Web 官方说明](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)

首版建议单线程构建；多线程作为实测后再采用的配置。实时 75 秒 Demo 会驻留三个赛道世界，研发验收前，介绍页可以使用另行交付的带音频预录视频。

## 3. 责任与交付边界

### 研发交付

1. 与 Godot 4.7.2 匹配的 Web 导出及浏览器适配。
2. 一份完整、文件名未被任意修改的导出目录：入口 HTML、加载 JS、WASM、PCK，以及实际导出的其他依赖；以构建清单为准，不只拷贝这四种文件。
3. 介绍页静态文件、视频及其公开使用所需素材；目录内不包含用户存档或调试数据。
4. 版本清单、逐文件 SHA-256、构建参数及浏览器运行记录。
5. 失败提示、点击启用声音、切后台暂停、恢复、存档和下载操作的游戏内逻辑。

### 运维交付

1. 实现或接入本报告约定的 Node.js 静态服务，锁定依赖和 Node.js 版本。
2. 对接实际域名、HTTPS 入口、进程管理、发布目录、缓存和压缩。
3. 核验文件完整性、HTTP 行为及公网浏览器访问；保存验收证据。
4. 可执行的版本切换、回滚和监控方案。

目标域名、主机、现有反向代理／隧道、CDN 和进程管理方式尚未在此任务中指定。运维 Agent 应先从自己的可信运维上下文确认这些值；缺少时向用户询问，不把本文示例路径或端口误认成已有基础设施。

## 4. 推荐拓扑与目录

```text
浏览器 → HTTPS 入口／可选 CDN → Node.js + Express（内部端口 3000）
                                ├─ /                     介绍页
                                ├─ /play/                当前版本跳转
                                ├─ /play/<build-id>/     完整游戏构建
                                ├─ /healthz              进程存活
                                └─ /readyz               当前构建文件就绪
```

沿用现有 HTTPS 入口；无现有入口时，可采用 Linux 主机反向代理到本机 Node 进程。Node 默认只监听 `127.0.0.1:3000`。如果采用容器，容器内可监听 `0.0.0.0`，宿主端口仍限制到回环或内部网络。

建议服务器目录，实际挂载位置可按既有运维规范调整：

```text
/srv/brushline-rally/
  host/                          Node 服务、package.json、锁文件
  site/                          经批准的介绍页与静态媒体
  game-releases/
    <build-id>/                  单个完整且发布后不修改的游戏包
  state/
    current.json                 当前 build-id，服务端管理
  evidence/
    <build-id>/                  校验、请求头、浏览器及回滚记录
```

静态路由只公开 `site/` 和已发布的 `game-releases/`。`host/`、`state/`、`evidence/`、仓库 `.git`、本机日志和存档均不属于公开根目录。不要直接将整个项目仓库挂载为网站目录。

Express 支持静态目录和路由挂载；建议使用绝对路径，避免服务工作目录变化导致资源失踪。[Express 官方文档](https://expressjs.com/en/starter/static-files/)

## 5. 构建与服务契约

### 构建包必须携带的信息

在包内提供 `build-manifest.json`，至少记录：

- `build_id`：不可变唯一标识，建议为源码短 SHA、构建序号与线程模式组合。不能只使用会重复的 `latest`。
- `source_commit`、`godot_version`、`export_preset`、`renderer`、`threads`、`pwa_enabled`。
- `entry`：相对入口路径，建议 `index.html`。
- `files`：全部交付文件的相对路径、字节数与 SHA-256；清单自身除外。预压缩文件单独记录。
- `save_schema`／物理版本、支持的浏览器范围、研发验证记录的路径或编号。

所有资源路径必须留在构建目录内；发布前核验不存在目录穿越或指向外部文件的链接。入口实际引用的全部资源必须在清单中。按导出器生成的关系保留文件名，不要自行将 WASM／PCK 改名后留下旧 JS 引用。

### Node 服务约定

生产选择受支持的 Node.js LTS，并把精确补丁版本写入镜像或运行时锁定文件。依赖必须有锁文件，安装使用 `npm ci --omit=dev`。[Node.js 官方版本政策](https://nodejs.org/en/about/previous-releases)

待实现的配置变量示例：

```dotenv
NODE_ENV=production
HOST=127.0.0.1
PORT=3000
SITE_ROOT=/srv/brushline-rally/site
GAME_RELEASE_ROOT=/srv/brushline-rally/game-releases
CURRENT_MANIFEST=/srv/brushline-rally/state/current.json
```

服务实现并交付 package.json 后，前台启动约定为：

```sh
cd /srv/brushline-rally/host
npm ci --omit=dev
npm start
```

环境变量由 systemd、容器或现有进程管理器注入；上述命令不负责安装服务。正式运行需有退出重启、开机启动、日志轮转和 SIGTERM 停止行为。`current.json` 用同目录临时文件加原子替换更新；Node 必须按请求读取有效指针，或提供经过验证的重载机制，不能只在启动时读取后永久缓存。

路由约定：

- `/play/`：302 跳转到 `/play/<build-id>/`；使用 `Cache-Control: no-store`。无有效构建时返回明确的 503 待就绪页面。
- `/play/<build-id>/`：提供该版本入口；只能选择已校验发布目录。
- `/healthz`：进程存活返回 200 和简短 JSON，不包含环境变量或内部路径。
- `/readyz`：当前指针有效、清单可读、必需文件齐备时返回 200 和 build-id，否则 503。大文件哈希在发布阶段校验，不在每次探针请求中重算。
- 未知游戏资源：404，不回退到首页；错误和健康响应不缓存。

就绪探针只说明文件服务就绪，不能代替浏览器成功启动和完成驾驶的证据。

## 6. HTTP、缓存与浏览器约束

### 基础响应

- `.wasm`：`Content-Type: application/wasm`。
- `.pck`：`Content-Type: application/octet-stream`。
- HTML、JS、JSON、图片和视频采用正确 MIME；JS/WASM/PCK 不能返回 HTML 错误页并伪装为 200。
- 支持 GET／HEAD。若提供演示视频，支持字节范围请求，检查 206、Content-Range 和拖动播放；其他资源无须为了加载游戏强制实现分片下载协议。

### 缓存与压缩

- 介绍页 HTML、游戏入口 HTML、发布指针：不做长期缓存；HTML 可采用 `no-cache`，指针与跳转采用 `no-store`。
- 不可变版本路径下的 JS／WASM／PCK：可使用 `public, max-age=31536000, immutable`。同一 build-id 下不覆盖旧文件。
- 优先预压缩 WASM／JS／PCK，按 Accept-Encoding 返回 br、gzip 或原始版本；返回正确 Content-Encoding，MIME 仍为原文件类型，并使用 `Vary: Accept-Encoding`。
- 反向代理、CDN、Node 只安排一层负责响应压缩，避免重复压缩。已压缩视频／图片不强制再压缩。
- 新入口发布前先上传完整新目录；旧页面继续请求旧目录。清理旧版本必须有保留策略，不能上线后立即删除。

### 单线程与多线程

首版按构建清单 `threads=false` 部署，不能从文件后缀猜线程模式。以后使用多线程时，由服务按该版本清单发送：

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

使用 HTTPS；localhost 可用于开发，普通局域网 HTTP 地址不是等价例外。多线程页面中核对 `window.isSecureContext`、`window.crossOriginIsolated` 和 SharedArrayBuffer。第三方资源需要相应 CORS／CORP 策略，不能只添加一个通配 CORS 响应头就认为满足隔离要求。首版同域、顶层页面部署最容易验证。[Godot 服务与线程要求](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html#serving-the-files)

首版 PWA 建议关闭。以后启用时必须交付 service worker 缓存版本、更新和回滚方案；只清 CDN 缓存不一定会替换浏览器离线缓存。

### 存档边界

玩家存档在浏览器 IndexedDB，不在 Node 服务器。上线与升级保持稳定 origin；由于游戏使用版本化 URL，研发还需验证跨版本路径是否使用同一存档命名空间。构建回滚不能回滚玩家已经迁移的浏览器存档，需由研发声明保存格式兼容范围。

## 7. 部署与回滚操作顺序

1. **核对环境**：取得实际域名、目标主机、HTTPS 入口、运行方式、内部端口和带宽限制；记录现有站点配置，避免端口或路由冲突。
2. **检查交付物**：游戏包、介绍页、Node 服务、锁文件、版本清单及研发运行记录齐备。缺少 Web 包时只完成站点准备，并明确记录阻塞项。
3. **暂存上传**：将构建上传到不可访问的暂存目录，校验清单、路径、文件数、SHA-256、解压大小和入口依赖。
4. **发布目录**：校验通过后原子移入 `game-releases/<build-id>/`，不覆盖同名已发布版本；此时保留原来的当前版本指针。
5. **验证候选版本**：直接访问候选版本 URL，检查请求头、启动、声音和完整试玩流程；必要时在预发布域名完成验证。
6. **切换入口**：记录原 build-id，原子更新 `current.json`；检查 `/play/` 跳转和 `/readyz` 返回一致，再核验公网入口。
7. **记录交付**：写入版本、域名、验收数据和回滚方式，开始观察错误与带宽。

失败时把指针切回上一个已验收版本；若 Node 服务本身发生变化，也回退其锁定版本和配置。保持旧构建可访问，检查旧版启动与新版浏览器存档的兼容情况。首次发布没有旧游戏版本时，回退到介绍／维护页并让 `/play/` 明确返回未就绪状态。

## 8. 验收与故障定位

以下是运维上线时应执行的检查，本次尚未运行：

```sh
# 在设置为真实候选 URL 后使用；资源文件名取自构建清单。
BRUSHLINE_ORIGIN='https://实际域名'
BRUSHLINE_CANDIDATE_URL='https://实际域名/play/实际build-id'
BRUSHLINE_WASM_URL='https://实际域名/play/实际build-id/实际文件.wasm'
curl -fsS "$BRUSHLINE_ORIGIN/healthz"
curl -fsS "$BRUSHLINE_ORIGIN/readyz"
curl -sS -D - -o /dev/null "$BRUSHLINE_ORIGIN/play/"
curl -fsSI "$BRUSHLINE_CANDIDATE_URL/"
curl -fsSI "$BRUSHLINE_WASM_URL"
curl -fsSI -H 'Accept-Encoding: gzip' "$BRUSHLINE_WASM_URL"
curl -sS -o /dev/null -w '%{http_code}\n' "$BRUSHLINE_CANDIDATE_URL/__missing__.wasm"
```

预期缺失资源为 404。HEAD 只能检查响应头，还需实际 GET 核验压缩后内容可解码、解码后的文件哈希一致，并检查无压缩客户端的回退。视频存在时补充 Range 请求验收。

浏览器验收至少记录：

- Chromium、Firefox、macOS Safari 的具体版本和设备；无法覆盖的项目明确注明。
- 下载完成后能够进入赛道；无缺失资源、WASM 编译或 shader 错误。
- 点击后有音乐、引擎和领航声；暂停、切标签、恢复不会继续带油门。
- 完赛、复位、重新进入、存档重开和显式下载正常；连续切换三次无持续增长的资源占用迹象。
- 同一域名从旧 build-id 到新 build-id，以及回滚后的存档兼容。
- 冷／热启动耗时、实际传输量、指定画质下的帧时间与内存记录。研发暂定 720p 目标 60 FPS，以及 50 Mbps 网络冷启动 15 秒／热启动 5 秒；超出时报告具体瓶颈，不能将这些目标写成实测成绩。
- 回滚后新访问和已打开的旧页面都能继续获取其所属版本资源。

常见定位顺序：白屏先查 404／错误 MIME／控制台；WASM 解码失败查错误 HTML 和重复压缩；多线程启动失败查安全上下文、隔离响应头与第三方资源；加载慢区分网络下载、WASM 初始化与场景构建；帧率低查客户端 CPU／GPU；无声先查用户交互和播放模式；存档丢失查 origin、版本路径、存储限制与格式兼容。

监控至少覆盖进程重启、healthz／readyz、5xx、游戏资源 404、出口带宽、磁盘空间与证书有效期。HTTP 可用率和浏览器启动成功率分别报告；后者需要浏览器巡检或另行实现的客户端事件，不能仅用访问日志推断。

## 9. 运维 Agent 的最终回报格式

```text
状态：站点准备完成／介绍页已上线／试玩已上线／受阻
访问地址：
游戏 build-id 与 source_commit：
Node 服务版本与精确 Node.js 版本：
Godot 版本、渲染器、线程模式、PWA：
部署主机／运行方式／内部端口／HTTPS 入口：
文件校验与 HTTP 验收：
浏览器、声音、驾驶、存档与性能结果：
当前及可回滚版本；回滚操作与实测结果：
证据位置：
尚未验证的内容及阻塞项：
```

交接指令摘要：请先检查真实交付物和既有运维环境，按本报告建设 Node.js 静态托管与不可变版本发布流程。Web 构建未交付时，完成可独立推进的站点准备并列出缺件；构建齐备后完成候选版本浏览器验收、入口切换及回滚演练，再报告“试玩已上线”。
