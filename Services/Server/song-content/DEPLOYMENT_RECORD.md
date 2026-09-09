# 生产部署记录

- 服务：现有 PM2 `token-admin`
- 运行文件：`/www/wwwroot/token-admin/server.js`
- 本地监听：`127.0.0.1:3388`
- 外部入口：`https://ncm.zijiu522.cn/_admin/agents`
- 公共 API：`https://ncm.zijiu522.cn/api/public/song-content*`
- 数据库：`/www/wwwroot/token-admin/song-content/song-content.sqlite`
- 反向代理：Nginx 仅将歌曲内容公共路径和后台路径转发至现有 token-admin
- 部署前备份：`/www/backup/token-admin-before-song-content-20260726T064914Z`
- App Agent 配置部署前备份：`/www/backup/token-admin-before-app-agent-prompts-20260726T080718Z`
- App Agent 配置部署后数据库备份：`/www/backup/token-admin-after-app-agent-prompts-20260726T080718Z`
- 最终歌曲 Agent 部署前备份：`/www/backup/token-admin-before-final-song-agent-20260726T091913Z`
- 叙事内容 v2 代码部署前备份：`/www/backup/token-admin-before-song-content-narrative-20260726T120744Z`
- 叙事内容 v2 配置发布前数据库备份：`/www/backup/token-admin-song-content-config-v2-20260726T121313Z`
- 跨平台“音乐幕后”部署前备份：`/www/backup/token-admin-before-cross-platform-content-20260726T130614070Z`
- 回滚：恢复备份中的 `server.js`、公共资源和 Nginx 配置，重启现有 PM2 进程

部署原则：不创建新 PM2 服务，不新增公网端口，不覆盖原有混淆 AI 配置运行文件。

2026-07-26 已发布公开配置 schema 2 / 版本 4，包含五类 App Agent 的独立启停、App 内置系统提示词、提示词版本、用户模板、温度、输出 Token 和最低超时。歌曲内容通过真实性与来源覆盖检查后自动发布。原 `ai-remote-config.js` 部署后 SHA-256 保持为 `f7bbcf29c06920a5843464221bd9785759716116d1639509c9c2c4f18c86cf6c`。

2026-07-26 已发布公开配置版本 6：歌曲内容提示词升级为 `song-editor-v2`，默认输出上限 4000 tokens，单任务上限 12000 tokens。生产冒烟 QCM `000NQDjk4BA0W3` 四模块全部生成并自动发布，校验通过，重复请求未新建生成任务。

生产冒烟歌曲：QCM `000NQDjk4BA0W3`（《暗号》/ 周杰伦 / 《八度空间》），统一歌曲 ID `3e91d466-c27e-4fc2-b12e-30bec256f901`，已发布内容版本 `94b4a82c-b008-451f-b138-f80b5712cb1d`。四个正文模块均有来源，自动校验通过；第二次 ensure 返回同一版本且生成任务数不增加。

2026-07-26 已将歌曲内容资料采集扩展到 KCM、QSM 和 AM：非 NCM/QCM 歌曲按标题、歌手、专辑与时长严格映射到可验证的 QCM/NCM 官方资料；仅在专辑完全一致且时长误差不超过 5 秒时，允许去除 Live 等版本后缀后匹配。公开内容对缺少独立歌曲简介的歌曲使用已有“音乐幕后/专辑介绍”回退，并继承原来源引用，不新增无来源文案。

生产冒烟歌曲：KCM `0011705422C00D4FEFA7E22F343F886A`（《你的 (Live)》/ 汪苏泷 / 《有歌2024 第7期》），统一歌曲 ID `6adf1f6a-fc42-4195-9a29-f9dcc9404622`，已发布 `zh-Hans` 内容版本 `cf87a235-e9b6-4e00-9356-7aaaa6fd5a9a`。连续两次公共 API 请求均返回 200、四个正文模块、QQ 音乐来源，且 `generation` 均为 null。QSM 与 AM 使用《暗号》元数据的跨平台采集冒烟均取得 2 个官方来源。

2026-07-27 已部署联网检索版“音乐幕后”。部署前文件与数据库备份位于 `/www/backup/token-admin-before-web-retrieval-20260727T020410584Z`。服务端先按歌曲、歌手和专辑严格检索网页，再提取可访问页面正文；来源按 `songSummary`、`creationStory`、`background`（乐评）、`albumSummary` 标记内容角色。Agent 只能引用允许对应字段的 B 级及以上来源，多余的跨字段引用会被剔除，没有评论类来源时不生成乐评。

已发布 Agent 配置版本 15，提示词 `song-editor-web-v4`、内容 schema 3。生产冒烟 QCM `000NQDjk4BA0W3`（《暗号》）检索到 QQ 音乐与搜狐共 3 个来源，发布内容版本 `0bb3ced5-dfe7-4577-9a3e-305ba41ef47b`：歌曲介绍 207 字、乐评 469 字、创作故事 319 字、专辑介绍 319 字。连续两次公共 API 请求均返回 200、同一持久化版本且 `generation` 为 null。

2026-07-27 已将联网检索策略接入 Agent 管理前端和生成管线。管理页可设置联网检索开关与单任务网页来源上限，并在来源列表区分“平台资料 / 联网检索”、显示中文内容字段。配置草稿保存后，生成任务会读取已发布策略执行；默认开启，网页来源上限为 6，服务端限制范围为 1–10。部署前文件与数据库备份位于 `/www/backup/token-admin-before-web-retrieval-admin-ui-20260727T022700Z`，继续复用原 PM2 `token-admin` 与本地端口 3388。

2026-07-27 联网检索由单一 360 扩展为 360、Bing、搜狗三路并行，任一路失败不阻断其余来源；管理页可逐项启停，来源记录保存实际命中的检索服务。生产网络以《暗号》冒烟，360 命中搜狐、Bing 命中网易云音乐，搜狗候选未通过正文与可信度筛选而被正常丢弃。部署前文件与数据库备份位于 `/www/backup/token-admin-before-multi-search-20260727T023948Z`。

2026-07-27 新增豆瓣与小红书重点来源。两者通过已启用搜索服务做站内定向检索，只用于乐评和专辑相关证据；目标网页正文自身必须同时匹配歌曲与歌手，登录墙、空壳页和仅搜索摘要匹配的结果不入库。生产冒烟中豆瓣《暗号》页面通过校验，小红书返回的无关公开笔记被正确过滤。部署前文件与数据库备份位于 `/www/backup/token-admin-before-douban-xhs-20260727T024935Z`。

2026-07-27 修复 Agent 管理的字段差异、角色权限和内容空状态溢出：长文双列按容器换行，权限逐项折行，权限面板增加内边距并调整列宽。已发布配置版本 16，提示词 `song-editor-web-v5`；正文禁止“现有评论认为”“报道提到”“资料显示”以及平台名称转述，歌曲介绍和专辑介绍不得用平台标签定义作品。服务端校验发现来源转述腔会拒绝结果并自动重试。部署前文件与数据库备份位于 `/www/backup/token-admin-before-layout-prompt-v5-20260727T025858Z`。

多来源证据使《凄美地》首次 v5 重写超过原 12,000 Token 单任务上限，配置版本 17 将单任务总上限调整为 20,000，最大输出仍为 4,000。重试后已发布内容版本 `c70edead-5bb7-445e-b507-9f9542dffae0`，提示词 `song-editor-web-v5`，四个字段来源覆盖率 100%，校验无错误和警告，正文不含平台名或来源转述句式。配置调整前备份位于 `/www/backup/token-admin-before-config-v17-20260727T030336Z`。

2026-07-27 启用全自动内容审核并发布配置版本 18：生成结果有校验错误或警告时自动重试，不再创建待审核内容；高风险事实只有通过多来源覆盖校验才自动发布，证据不足时自动重试，耗尽次数后标记失败。人工发布或驳回会同步关联生成任务状态。历史 3 个 `review` 任务已按最终内容状态清理为 2 个完成、1 个失败。部署前备份位于 `/www/backup/token-admin-before-auto-review-20260727T040124Z`。

2026-07-27 已部署通用公告与 AI 熔断恢复更新。公告支持通知、活动、维护、重要提醒、协议政策和版本更新，管理端可配置优先级、展示版本、时间窗口、客户端版本、平台、地区、确认要求及跳转；App 公共接口采用轻量清单 ETag/304，并仅按未读展示版本读取详情。AI 熔断期间 Worker 不再领取新任务，恢复窗口到期后只允许一个半开探测；后台任务错误只返回中文展示信息，并可配置 15–900 秒恢复窗口。继续复用 PM2 `token-admin`、本地端口 3388 和 `/_admin/` 入口。数据库、运行文件、管理页与 Nginx 部署前备份位于 `/www/backup/token-admin-before-announcements-circuit-20260727T123718Z`；HTTPS 公告页面、清单接口、轻量字段约束、数据库 `quick_check`、后台错误中文化和熔断关闭状态均已冒烟通过。

2026-07-27 修复“音乐幕后”批量生成失败与来源操作列溢出。根因是内容 Worker 未遵守 App AI 的每日、每小时和最小请求间隔，连续请求触发上游 429；现已合并 App AI 用量限制、按 `Retry-After` 退避、限流不消耗任务重试次数，并将受限 Provider 串行调度。重试复用已保存的有效证据，旧来源缺少内容角色时重新采集并刷新元数据；模型返回空字段或抄错来源 ID 时，丢弃未知引用并使用同一证据包中的平台正式歌曲/专辑介绍兜底。来源表改为受控列宽，长标题省略显示，状态与“标记失效”操作始终保留在容器内。部署前备份位于 `/www/backup/token-admin-before-agent-rate-limit-layout-20260727T133143Z`；45 个可恢复任务已重新排队，生产验证《偏爱》《暗号》均生成发布成功，恢复后 12 条任务完成且无新增 `AI_RATE_LIMITED` 失败。

2026-07-27 已部署 Agent 上下文预算优化。单次输入与单任务总 Token 预算拆分管理，证据正文按字段角色和来源等级保留后自适应压缩，平台映射及来源元数据不再把无关原始字段送入模型；遗漏字段补全只携带对应角色的来源和精简后的已有内容，不再重复提交整份证据。首轮有效结果即使超过总任务预算也会保留，只停止额外补全，避免已生成内容被错误丢弃；上游上下文容量错误会单独显示中文原因。管理页将“生成中”拆为“排队中”和“处理中”，并将歌曲总数标为“已收录歌曲”。部署前文件与数据库备份位于 `/www/backup/token-admin-before-context-budget-20260727T153439Z`；原 3 个 `AI_TOKEN_LIMIT_EXCEEDED` 任务已重试并全部完成，实际输入分别为 10,455、10,774 和 16,768 Token，继续复用 PM2 `token-admin`、本地端口 3388 和原域名入口。

2026-07-28 已部署公告发布版本选择与客户端 Build 匹配。公告管理页直接读取 IPA 管理中已发布的版本，可按 `CFBundleShortVersionString + CFBundleVersion` 选择最低和最高发布版本；服务端新增 Build 范围持久化、清单过滤及无效范围校验。App 公告请求同步携带 Version 与 Build，并在欢迎页结束后的首次检查强制刷新轻量清单，后续前后台切换仍按服务端建议间隔懒检查，公告正文继续仅在存在未读公告时读取；未上报 Build 的旧客户端按 Version 兼容匹配。生产已有测试公告未展示的原因是把 Build `69` 填入了 Version 字段，且当前状态为已下线。部署前文件与数据库备份位于 `/www/backup/token-admin-before-announcement-release-target-20260727T162515Z`，继续复用 PM2 `token-admin`、本地端口 3388 和原域名入口。

2026-07-28 已升级 Agent 生成任务为完整队列界面。服务端任务列表关联歌曲、平台映射与封面，返回歌名、歌手、专辑、平台、队列位置、任务总数及分状态统计；管理页显示任务阶段、触发原因、排队位置、处理时间、尝试次数、Token、费用和结果，支持状态筛选、25/50/100 条分页及活动任务自动刷新。TokenAdmin 同时新增全局深浅色切换，登录页、管理页和公开账号页面共享并持久化主题偏好，保留原有深色终端视觉。生产任务接口验证共 155 个任务，歌曲元数据和队列位置返回正常；浏览器实测浅色模式、队列 4 页及 1280px 页面无横向溢出。部署前文件与数据库备份位于 `/www/backup/token-admin-before-queue-light-20260728-022718`，继续复用 PM2 `token-admin`、本地端口 3388 和原域名入口。

2026-07-28 修复 Agent 队列长期停留在排队状态。根因是服务端 Worker 复用了 App 客户端的每日 100 次、每小时 20 次请求额度，额度耗尽后不会领取任何任务；现服务端继续遵守 15 秒请求间隔、每分钟限制、上游退避和熔断保护，但不再套用客户端日/小时额度。部署后完成任务由 103 增至 104，并自动继续处理下一首，排队任务由 83 降至 82，确认队列持续消费。歌曲管理同时新增总数、搜索结果总数、25/50/100 条分页及上一页/下一页控制；生产浏览器实测共 176 首、4 页，第 1 页与第 2 页歌曲不同，1280px 页面无横向溢出。部署前备份位于 `/www/backup/token-admin-before-worker-song-pagination-20260728-033228`，继续复用原 PM2 `token-admin`、本地端口 3388 和域名入口。

2026-07-28 修正生成任务处理时间口径。`started_at` 现在表示当前或最终一次连续 Worker 尝试的开始时间；任务重新排队、限流延迟和人工重试会清空旧计时，过期租约被其他 Worker 接管时重新开始计时，不再把队列等待或服务中断累计为处理时间。数据库迁移已隐藏无法可靠还原的历史异常时长，生产查询中超过 1 小时的错误记录现为 0；浏览器实测正在生成任务显示本轮 5 秒，排队任务只显示队列位置和加入时间。部署前备份位于 `/www/backup/token-admin-before-qcm-login-job-timing-20260728-042930`，继续复用原 PM2 `token-admin`、本地端口 3388 和域名入口。

2026-07-28 已部署“音乐幕后”平台内部数据清洗与英文资料检索增强。网易云音乐百科采集不再把 `songTag`、`songBizTag`、`melody_style`、`orpheus://` 及内部路由参数作为正文或兜底内容；历史已发布版本若含此类内部载荷会自动下线并创建升级任务。联网检索新增 Apple Music、SoundCloud、Spotify 与 Qobuz 定向查询，补充英文歌曲资料、制作信息、艺人说明和专辑资料识别；只有匹配歌曲艺人的 SoundCloud 官方主页可提升为 B 级来源。生产以 NCM `1379918404`（《time machine (feat. aren park)》）验证：原始百科数据命中内部字段，清洗结果不再输出任何内部载荷，旧污染版本已下线并进入重新生成队列。服务端 29 项测试、远端模块加载、公开配置、域名入口和 SQLite `quick_check` 均通过；部署前备份位于 `/www/backup/token-admin-before-ncm-wiki-sanitizer-20260728T021339Z`，继续复用原 PM2 `token-admin`、本地端口 3388 和域名入口。

2026-08-03 已完成全量 Agent 升级部署。歌曲内容 Agent 升级为 `song-editor-web-v7`，会对有证据支持但为空或明显过短的歌曲介绍、创作故事、乐评和专辑介绍执行一次定向补全；App 下发仅保留均衡器、听歌洞察和特别问候三个 Agent，版本分别升级为 `mono-audio-agent-v28`、`mono-listening-insight-v3` 和 `special-greeting-v2`，并下发独立的最大尝试次数。歌词舞台与壁纸搜索翻译 Agent 已从公开配置及管理页移除。发布配置为版本 19，ID `66c480e1-bf3d-478b-b780-da97028f9acb`；公共配置经真实有效 Token 与现有设备绑定请求验证返回 200，只包含三个目标 Agent。部署前 SQLite 一致性备份和 17 个代码/UI 文件快照位于 `/www/backup/token-admin-before-agent-upgrade-20260803T024412Z`，数据库 SHA-256 为 `ab8f08d18dabab6272a235c3ddd65230bb9e08068c12164cb113241dc00b3aa8`，`PRAGMA integrity_check` 返回 `ok`；部署后数据库恢复点位于 `/www/backup/token-admin-after-agent-upgrade-20260803T025223Z`，SHA-256 为 `5a73985f7e1e7934a132d399830dbb59371bc28762c6a665cc29498353bf0106`，完整性检查同样为 `ok`。部署后原 PM2 `token-admin` 保持 `online`，继续监听 `127.0.0.1:3388`；`https://ncm.zijiu522.cn/_admin/agents` 返回 HTTP 200，JS/CSS 公网哈希与本地文件一致。管理页静态资源版本更新为 `2026080301`，避免旧缓存继续显示已删除的 Agent。原混淆 AI 配置文件未覆盖，SHA-256 仍为 `f7bbcf29c06920a5843464221bd9785759716116d1639509c9c2c4f18c86cf6c`。部署前本地服务端测试共 34 项通过，远端所有运行 JavaScript 均通过 `node --check`。

2026-08-19 已部署调音 Agent v30 与 Mono 调音知识契约。均衡器 Agent 发布为 `mono-audio-agent-v30-dsp`，配置版本 20，ID `1148205e-69f0-4329-a1d5-c40bd59c5e46`；原 10 段和 32 段定制提示词完整保留，并追加 `mono-tuning-knowledge-v1` 的证据优先级、OPRA/设备基线隔离、DSP 阶段职责、动态处理互斥、组合余量、相位与单声道安全规则。管理页资源版本更新为 `2026081901`。部署前文件与一致性数据库备份位于 `/www/backup/token-admin-before-audio-agent-v30-20260819T013510Z`，部署后恢复点位于 `/www/backup/token-admin-after-audio-agent-v30-20260819T015300Z`，数据库 SHA-256 为 `b201347742bd190845fcde7f1602403504e9edeb1dd4ddf874ae9b378cb72942`，前后 `PRAGMA integrity_check` 均为 `ok`。生产公共配置经有效 Token 与现有设备绑定请求验证返回 HTTP 200、版本 20 和 `mono-audio-agent-v30-dsp`；管理页与静态资源公网入口均返回 HTTP 200，公网 JS SHA-256 为 `eb9a0d63cc051aa61665347d8ef05ac8839da4e0c632b6d16c7525d183c39c32`。原 PM2 `token-admin` 保持 `online` 并继续监听 `127.0.0.1:3388`，不稳定重启为 0；原混淆 `ai-remote-config.js` 未覆盖，SHA-256 仍为 `f7bbcf29c06920a5843464221bd9785759716116d1639509c9c2c4f18c86cf6c`。本地服务端测试 27 项通过，Swift 提示词文件通过解析，远端发布脚本在生产数据库副本上完成发布与幂等复跑验证。

2026-09-02 已部署云端调音小模型训练服务与云快照 v5 兼容层。训练服务扫描全部用户云端方案，生产扫描共 5,725 条可训练历史方案先验，其中 10 段 5,372 条、32 段 353 条、无效 0 条；历史方案不伪造缺失的测量输入，而以受控权重参与群体输出先验，新版完整样本继续训练测量特征到方案参数的映射。所有训练设置、任务、下载与发布接口均要求 `training.manage`，权限仅授予 `content-admin`。运行服务当前由 systemd `recovered-token-admin.service` 托管，继续监听 `127.0.0.1:3388`；部署后服务为 `active`、不稳定重启为 0，App 使用的 `https://mono.zijiu522.cn/_admin/api/audio-training` 未授权请求返回 401，现有站点返回 200，SQLite 检查均为 `ok`。部署前恢复点位于 `/www/backup/token-admin-before-audio-training-20260902T114119Z`，部署后恢复点位于 `/www/backup/token-admin-after-audio-training-20260902T114608Z`。本地相关服务端测试 21 项、远端训练测试 5 项全部通过；按需求未运行 Xcode 构建，也未自动启动训练任务。

2026-09-02 已把调音训练产物升级为可在 iPhone 执行的完整 Core ML 制品链路。服务端保留可审计的 JSON 权重快照，同时使用固定版本 `coremltools 8.0` 生成带 84 项输入、60 项输出及完整 schema 元数据的 `.mlmodel`，持久化文件 SHA-256、大小和版本；发布与下载前均确保制品存在，已有模型无需重训即可按需补生成，下载接口继续要求 `training.manage`。生产现有 `mono-audio-base-20260902140532-2d9052c4`（训练样本 5,734）已成功生成 24,006 字节 Core ML 文件，服务端复算哈希一致；部署后云端可训练方案已增至 5,781 条、49 个贡献账号、无效 0 条。完整训练样本的新目标 schema 会剥离设备基线，避免端侧安全编译再次叠加耳机校准。服务由 `recovered-token-admin.service` 托管，切换后为 `active`、不稳定重启为 0；站点返回 200，训练状态与 Core ML 下载入口未授权均返回 401，两份 SQLite `quick_check` 及模型文件校验均为 `ok`。部署前恢复点位于 `/www/backup/token-admin-before-coreml-20260902T122800Z`，部署后恢复点位于 `/www/backup/token-admin-after-coreml-20260902T145500Z`。本地相关服务端测试 45 项、远端训练测试 5 项全部通过，Core ML 数值等价验证最大绝对误差为 0；按需求未运行 Xcode 构建，仅执行 Swift 语法解析和 Core ML API 类型检查。

2026-09-02 已修正历史方案训练的零梯度路径。目标归一化现在保留绝对零点，群体先验从零输出偏置开始按历史方案逐样本执行 SGD；完整测量样本继续优化 84→隐藏层→60 的特征回归权重。每个模型记录初始/最终训练损失、初始/最终验证损失、损失改善量和实际优化步数，测试分别验证完整样本权重发生更新、历史方案偏置发生更新且两类损失下降。App 全权限开发者页同步增加端侧模型启停、CPU/GPU/Neural Engine 计算策略、群体先验强度、高级 DSP 阶段样本门槛、真实 Core ML 多输入自检及当前歌曲“模型推理→本地调音编译→DSP 应用”测试；没有完整测量输入的旧方案仍不伪造音频特征。生产训练器 SHA-256 为 `7fc4597c7f8cb5ef726b6103ad5bb5ccd0431961362fca149f06f5b218bacffd`，远端训练测试 5 项通过；另以线上 5,785 条方案在隔离临时库完成 12 轮真实训练和 Core ML 导出：执行 50,688 个优化步，训练损失从 `0.825174` 降至 `0.273878`，验证损失从 `0.768406` 降至 `0.200026`，60 个输出中 53 个偏置完成非零学习，生成 12,414 字节 `.mlmodel`。临时库已删除，正式模型库与发布指针未修改。服务为 `active`、不稳定重启为 0，站点返回 200，受保护训练接口未授权返回 401，两份 SQLite `quick_check` 均为 `ok`。部署前恢复点位于 `/www/backup/token-admin-before-real-audio-training-20260902T153624Z`，部署后恢复点位于 `/www/backup/token-admin-after-real-audio-training-20260902T153909Z`。本地相关服务端测试 63 项通过，6 个关键 Swift 文件在全项目上下文中类型检查通过；按需求未运行 Xcode 构建，现有线上模型未自动重训或发布。

2026-09-03 已修复 iPhone 编译 Core ML 制品时报 `Scale` 层 rank-1 输入不合法的问题。根因是 `NeuralNetworkBuilder` 对公开形状 `[84]` 和 `[60]` 插入了要求至少 rank-3 的 `Scale` 层；新导出器使用 84×84 对角 `InnerProduct` 完成输入归一化并保留裁剪层，同时把输出反归一化严格折叠进最终全连接层，公开输入输出仍为 `[84]`/`[60]`。制品格式升级为 `coreml-neuralnetwork-v2`，旧格式会被判定为过期并按需重新生成。截图对应且已发布的 `mono-audio-base-20260902164527-1659e996` 已用原训练权重重新导出为 51,344 字节模型，SHA-256 为 `5b23ec1ba8bf79aef85028613a9ac6fe682647d7009376193ade4852dbf41750`；Apple `coremlcompiler` 按 iOS 16 成功编译，Core ML 运行时完成 60 项有限值推理，与 JSON 权重计算的最大绝对误差为 `0.000036821`。本地服务端测试 63 项、远端训练测试 5 项通过；服务为 `active`、不稳定重启为 0，公网首页返回 200、受保护训练接口未授权返回 401，两份 SQLite `quick_check` 均为 `ok`。部署前恢复点位于 `/www/backup/token-admin-before-coreml-rank-fix-20260902T165449Z`，部署后恢复点位于 `/www/backup/token-admin-after-coreml-rank-fix-20260902T165700Z`；按需求未运行 Xcode 构建。

2026-09-03 已修复真机手动云同步后完整调音样本不进入训练集、开发者页仍显示旧数量的问题。线上只读取证确认北京时间 01:00:00 生成的新方案已在 01:00:01 写入云快照，云端唯一方案共 5,789 条；实际缺陷是播放列表快照归一化只保留 `cachedProposals`、`savedProposals` 和元数据，静默丢弃 v5 `trainingSamples`，因此完整样本一直为 0。服务端现由统一兼容模块保存完整特征与目标对象、返回完整样本计数，并使用请求客户端版本保护 v4 及更旧客户端不能通过嵌套字段缺失清空 v5 样本；App 上传后校验服务端接收数量，完整数据不足会明确报错，全权限开发者会自动刷新云端训练统计，普通用户不会调用管理扫描接口。实时数据集与既有模型的冻结样本数分别标为“云端当前可训练样本”和“本模型训练样本”，后者只在重新训练生成模型时变化。生产备份位于 `/www/backup/token-admin-before-cloud-training-sync-20260903T014200Z`；部署后 `recovered-token-admin.service` 为 `active/running`、不稳定重启为 0，公网首页 200，训练与云快照接口未授权均为 401，两份 SQLite `quick_check` 均为 `ok`，重启后无 warning。本地相关服务端测试 16 项、Swift 语法解析、两份本地化文件校验及差异检查均通过；按需求未运行 Xcode 构建，也未启动训练或修改已发布模型。

2026-09-03 已部署调音训练 schema 4，将原有调音 Agent 的个性化学习状态作为真实模型条件输入。模型输入由 158 项扩展为 177 项，新增学习启用状态、置信度、证据数、10 段频带修正及低音、高音、环绕、混响、立体声宽度和处理强度修正；有学习上下文的样本训练不含设备修正的个性化目标，同时保留不含学习和设备修正的群体目标，设备/OPRA 基线继续只在端侧安全编译阶段叠加。端侧仅在模型至少含 8 条学习条件样本后让模型接管学习修正，旧模型及数据不足时继续使用原 Agent 本地学习路径，避免未训练的新维度影响声音。App 模型安装目录已迁移到用户可见的 `Documents/MonoAudioTrainingModels`，下载的原始 `.mlmodel` 不再在编译后删除，清单会校验文件名、字节数和 SHA-256；该 App 修复需安装本地新版后才会生效。生产部署前恢复点位于 `/www/backup/token-admin-before-audio-training-schema4-20260902T224814Z`，训练器、测试和 Core ML 导出器 SHA-256 分别为 `96726320138af4980f89031ff4ceea879b90629ce1320cd4c5d642754ca51743`、`c13cc351ffff3cc84933bede7439b1195fd3832dde56cb98017d28f6821f1756` 和 `e137efd95cf15c5cf889f0df12bd80be4f892594a5a8e92ba3e267bda539b13d`。本地相关服务端测试 26 项、远端训练测试 15 项全部通过；隔离临时库读取线上云数据完成 1 轮真实训练与 Core ML 导出，扫描 5,795 条可训练样本、8 条完整样本、0 条学习条件样本，生成 136,556 字节、177 输入/60 输出的 `.mlmodel`，未修改正式训练库或发布指针。部署后服务为 `active`、不稳定重启为 0，公网首页返回 200，训练与模型下载接口未授权均返回 401，三份 SQLite `quick_check` 均为 `ok`，部署后服务日志无 error。当前正式发布模型仍为 schema 1 的 `mono-audio-base-20260902201947-2fdb2c39`，本次未启动正式训练或发布；按需求未运行 Xcode 构建，仅执行 Swift 语法解析、本地化校验和差异检查。

2026-09-03 已部署单模型双频段训练 schema 6。一次训练仍只生成并发布一个 Core ML 模型，但模型内部以掩码监督分别学习原生 10 段和原生 32 段输入/输出分支，共 636 项输入、92 项输出（10 段增益 10 项、32 段增益 32 项、共享调音参数 50 项）；两种频段不再互相重采样或被拆成两个模型。歌曲风格、同风格歌曲的时序指纹、Agent 个性化学习状态与详细设备参数继续作为条件输入，设备/OPRA 修正不进入模型目标。生产恢复点位于 `/www/backup/token-admin-before-audio-training-dualband-20260903T001850Z`，包含部署前训练器、测试、Core ML 导出器和一致性训练数据库备份；训练器、测试和导出器 SHA-256 分别为 `e2d22a8bad1c995016fd23820b54da12b06f45a71e7767deb7dc868096acdf7d`、`dfaeda1af26c2722cf3dfdb7e85eee3daee947147c15602249dfe3d809baa9e1` 和 `9fdad46b4635adeb48b69aa9cc87a1887590e93a06e08f57d4ecbb0777736038`。远端训练测试 18 项全部通过，三份 SQLite `quick_check` 均为 `ok`；`recovered-token-admin.service` 为 `active`、不稳定重启为 0，站点返回 200，受保护训练入口未授权返回 401，部署后仅有 Node SQLite 实验特性提示、无服务错误。当前正式发布模型仍为 schema 1 的 `mono-audio-base-20260902201947-2fdb2c39`，本次未启动训练、未生成或发布 schema 6 模型；按需求未运行 Xcode 构建。

2026-09-03 已部署单模型四分支训练增强。训练器现在把 `10 段/标准`、`10 段/空间增强`、`32 段/标准`、`32 段/空间增强` 作为一个模型内的独立条件分支，训练开始前要求四个分支均有样本；验证拆分保留曲目隔离的同时保证每个已观测分支留在训练集。历史方案继续作为真实群体先验参与完整 MLP 优化，并保留频段与空间模式条件，不伪造历史上不存在的音频测量输入。部署时云端共有 5,852 条可训练方案，其中完整样本 8 条、历史方案 5,844 条；四分支数量依次为 4,949、550、250、103。生产恢复点位于 `/www/backup/token-admin-before-audio-training-profile-20260903T025007Z`，包含部署前训练器、测试及三份一致性 SQLite 备份，备份数据库 `quick_check` 均为 `ok`；新训练器和测试 SHA-256 分别为 `504f91dd1d8a5823a917fe62219dc88195aea7eaa04d6f0fd5be4109459e2c6a` 和 `b7b04275ff5ebd13f83f809b444b0f0b84037eb8e359d6c5707de83444fa0b92`。本地与安装目录远端训练测试均为 22 项全部通过；部署后 `recovered-token-admin.service` 为 `active/running`、不稳定重启为 0，公网首页和管理页返回 200，受保护训练入口未授权返回 401，三份生产 SQLite `quick_check` 均为 `ok`，服务日志无 warning/error。当前无活跃训练任务，正式发布模型仍为 schema 1 的 `mono-audio-base-20260902201947-2fdb2c39`，本次未启动训练、未生成或发布新模型；按需求未运行 Xcode 构建。

2026-09-03 已部署训练器优化并重训、发布新模型。审计发现已发布的 `874351d7` 训练集里 40% 完整样本是端侧模型自己生成的方案、目标为单一账号的个性化目标、32 段先验因输出归一化只用完整样本统计而被裁成平线、544/636 项输入 σ<0.2。训练器改为：排除 `trainedCoreMLModel`/`appleIntelligenceLocalCompiler`/`appleIntelligence` 来源的样本与方案；默认 `population` 目标模式（学习上下文置零，个人偏好留给端侧 Agent），可切回 `personalized`；`manualEqualizer` 反馈改为“用户最终曲线 − 听到的曲线”增量叠加到群体目标；输出尺度按全部训练目标统计；输入归一化 one-hot 透传、条件特征只缩放不居中、其余居中并给 σ 下限；监督/历史两组分层 minibatch 按 `priorWeight` 混合，账号 `1/√n` 衰减、每曲目一票、历史方案按分支等分并带入方案强度；Momentum SGD + weight decay + 梯度裁剪 + 早停保留最优轮；8 维意图瓶颈训练后折叠回输出层，Core ML 契约不变；训练移入 `worker_threads`。设置表自动新增 `prior_weight`、`weight_decay`、`early_stopping_patience`、`intent_units`、`target_mode`。导出器新增 `mono.input_mean`、`mono.complete_account_count`、`mono.target_mode`、`mono.quality_warnings` 元数据，端侧据此按分支覆盖度在群体先验与歌曲修正之间混合。恢复点 `/www/backup/token-admin-before-audio-training-optimize-20260903T155043Z`（训练器、测试、导出器、训练库一致性备份，`quick_check` 为 `ok`）；新训练器与导出器 SHA-256 为 `b5f367dc860b76801ffc700faa244cb5c41f308766015ba1882d5608793072fb`、`7f94e24fd84a361aafe744b92ec62e6506d38b11522ceac398193d769bf3b6a8`。服务器 Node 22 上训练测试 29 项通过，本地 song-content 59 项通过，Xcode `Mono` iOS 构建成功。部署后云端扫描 5,996 条可训练（完整 49 条、历史 5,947 条，排除自生成样本 33 条、方案 9 条，完整样本账号 2 个）；训练 11 轮早停（最佳第 3 轮）、2,046 步、训练损失 0.8335→0.2374、18 条留出完整样本验证损失 0.7802→0.0618，生成并发布 `mono-resonance-s1-schema6-20260903155241-add880c9`（Core ML 1,741,285 字节，SHA-256 `59099c17e60b701bfc44a75449ef2ba5122b7a454c71d027c7d91edbd68ccdaa`），10 段/标准先验 preamp -6.10、增益与 5,947 条历史方案均值一致，32 段先验有完整曲线，质量提示为三个分支缺少留出完整样本。服务为 `active`、不稳定重启 0，公网训练入口未授权 401、首页与管理页 200，两份 SQLite `quick_check` 为 `ok`。开源仓库 `Lincb522/mono-resonance` 同步了新训练算法、导出器元数据与文档，撤回旧预览权重并发布 `add880c9`（MIT 身份重导出，Core ML 与 JSON 最大误差 4.2e-4），提交 `4b08ad1`，CI 通过。App 侧改动（跳过自生成样本、手动 EQ 曲线回写、端侧先验混合与回退计数、开发者页新设置）需安装新版后生效。

2026-09-09 10:56（北京时间）已部署共鸣 S2 模型选择与用户分发接口。服务器继续使用 `new-server` 上的 `recovered-token-admin.service`、原目录 `/www/wwwroot/token-admin` 与监听端口 `127.0.0.1:3388`。更新 `song-content-integration.js`、`song-content/audio-tuning-training.js`；本地 `token-admin/ai-remote-config.js` 部署为新文件 `ai-remote-config-s2.js`，仅将现有 `server.js` 的配置模块引用切换至该文件。原混淆 `ai-remote-config.js` 保留且 SHA-256 仍为 `f7bbcf29c06920a5843464221bd9785759716116d1639509c9c2c4f18c86cf6c`；没有更改 Nginx、证书、端口或站点静态资源。

新增 `audio_training_published_models` 发布历史表，首次启动将原发布指针迁入可选目录。当前已发布的 `mono-resonance-s2-schema7-20260908120520-93813299`（feature schema 7 / target schema 4，Core ML 157,376 字节）已进入目录；先在一致性数据库副本上验证了迁移与生产模型制品的大小/SHA-256。管理模型列表要求完整训练权限，普通用户下载要求有效 App Token、设备标识及当前启用的分发模型；部署代码不会自动修改原 AI 服务配置或选定新的分发模型。

部署前恢复点：`/www/backup/token-admin-before-s2-distribution-20260909T025101Z`，包含原入口、原配置模块、集成模块、训练模块及一致性训练数据库备份。暂存、校验与回滚脚本在 `/www/backup/mono-s2-staging-20260909T025101Z`；需要回滚代码时执行 `python3 /www/backup/mono-s2-staging-20260909T025101Z/deploy.py --rollback`。回滚保留新增的兼容表与线上后续数据，不恢复数据库快照覆盖新数据。

验证：本地 Node 26 与服务器 Node 22 的相关测试均为 45 项通过；17 组模拟旧接口场景与线上混淆模块及新模块一致。公网首页和后台入口为 200，新模型列表及 Core ML 下载入口由部署前的 404 变为未认证 401，既有公开 AI 配置入口仍为 401。服务切换后 PID 为 `1540180`；10:57:46 检查仍为 `active/running`、自动重启 0，四份生产 SQLite `quick_check` 均为 `ok`，没有活动训练任务；启动日志只有一条 Node SQLite 实验特性提示，没有匹配到服务错误。三个部署模块与入口文件哈希均匹配，原混淆模块哈希不变。

本次没有运行 Xcode 构建、上传 App 或启动训练；新增手机端服务选择界面需包含该改动的 App 版本。真实用户登录后的线上配置发布、获准下载和端侧 Core ML 推理链路尚未验证。


## 2026-09-09 共鸣置信度校准服务端部署

2026-09-09 12:26:13（北京时间）已将置信度校准训练模块和 Core ML 导出脚本部署到 `new-server:/www/wwwroot/token-admin`，并重启现有 `recovered-token-admin.service`。仅更新 `song-content/audio-tuning-training.js`、`song-content/scripts/export-audio-training-coreml.py`；入口、AI 配置模块、站点资源和依赖保持原哈希。

新训练流程按歌曲隔离选模与校准数据，为 10/32 段、标准/空间四个分支生成独立校准记录，随 Core ML 元数据分发。新模型发布要求有效校准；数据不足或歌曲身份不明确时返回明确的 `MODEL_CONFIDENCE_NOT_CALIBRATED`，保留当前发布状态。现有已发布模型继续可用，不因部署代码自动改变置信度。

服务器 Node 22 环境的 57 项回归全部通过。用服务器现有 `audio-training-runtime` Python 环境验证了四个分支的合成训练与 Core ML 导出，导出校准元数据与训练结果一致。在生产训练数据库副本上验证现有两个发布模型可读取、完整制品校验通过，以及未校准模型重新发布被拒绝且发布状态不变。生产数据未用于新训练，生产发布操作未被调用。

切换后进程为 `1547352`，服务为 `active/running`，自动重启为 0。公网首页与后台入口为 200，AI 配置、模型列表与下载入口未认证响应为 401。四份生产 SQLite `quick_check` 均为 `ok`，16 个既有模型制品的大小及 SHA-256 保持一致，现有两个发布目录项及当前模型 `mono-resonance-s2-schema7-20260909033347-ea0b31ed` 未变。启动检查没有错误标记，只有一条 Node SQLite 实验特性提示。

备份：`/www/backup/token-admin-before-confidence-20260909T042119Z`，包含两个旧代码文件及一致性训练数据库副本。暂存与回滚脚本：`/www/backup/mono-confidence-staging-20260909T042119Z`；需要回滚代码时执行 `python3 /www/backup/mono-confidence-staging-20260909T042119Z/deploy.py --rollback`，不会用旧数据库覆盖线上新数据。

完整部署证据保存在本机 `/tmp/mono-confidence-deploy-20260909T042119Z/` 与远端暂存目录。本次没有重新训练或发布真实模型、修改 AI 分发配置、运行 Xcode 构建或上传 App；手机端置信度展示和 Agent 记录修复需随新 App 安装。真实账号鉴权后的生产下载与新模型端侧推理尚未验证。


## 2026-09-09 共鸣模型自动说明、更新日志与发布规则部署

2026-09-09 13:43:04（北京时间）已将三个服务端文件部署到 `new-server:/www/wwwroot/token-admin`：`song-content/audio-tuning-training.js`、新增的 `song-content/audio-training-release-notes.js`、`ai-remote-config-s2.js`。原混淆 `ai-remote-config.js`、服务入口、站点资源、样本模块与 Core ML 导出脚本保留原哈希。

本次按最终需求允许未校准模型发布，取代同日 12:26 部署的校准发布门槛；继续校验权限、确认操作及模型制品完整性。训练以 10 段分支为必要条件，32 段为可选分支，各分支校准状态独立，不补写虚假校准。发布时按模型真实样本、训练指标、分支状态及上一发布模型自动生成说明和详细更新日志，不接受客户端手填内容；重试发布保留已自动生成的内容。列表和 AI 配置下发发布时间、摘要及简版日志，配置 ETag 随模型发布元数据更新，模型下载使用可读文件名。

服务器 Node 22.23.1 上 61 项回归全部通过。使用生产训练数据库与模型文件的独立副本，验证未校准 `3e890c07-b459-42c0-8bb9-48a12e74e707` 发布成功、自动说明与发布预览一致、旧客户端手填内容被忽略，以及关闭重开服务后重复发布日志稳定。实际 0c07 数据生成摘要为“方案样本 7,511 条，较上一发布版增加 7 条。当前各分支尚未校准。”，未篡改既有校准结果。制品为 158,551 字节，下载名 `Mono-Resonance-S2_2026-09-09_04-43-09.908UTC.mlmodel`。

部署后进程 `1554735` 为 `active/running`，自动重启为 0；公网首页与后台入口返回 200，配置、模型目录及下载入口未认证返回 401。四份 SQLite `quick_check` 均为 `ok`，发布表新增字段已就绪，18 个既有制品大小及 SHA-256 不变，19 个模型及两个发布目录项不变，启动日志未发现错误标记。当前实际发布仍为 `ea0b31ed-5772-4f98-b86f-b8fe86ef9a41`；本次没有调用生产模型发布或修改用户分发选择。

备份位于 `/www/backup/token-admin-before-auto-release-20260909T053926Z`，包含旧代码、缺省文件清单和一致性训练数据库副本。部署及回滚脚本位于 `/www/backup/mono-auto-release-staging-20260909T053926Z`；回滚命令为 `python3 /www/backup/mono-auto-release-staging-20260909T053926Z/deploy.py --rollback`，仅恢复代码（含移除本次新增模块），不会恢复旧数据库。

完整证据位于本机 `/tmp/mono-auto-release-deploy-20260909T053926Z/` 及远端暂存目录。本次未运行 Xcode 构建、安装或上传 App；客户端选择框、说明展示及发布界面需包含相应改动的 App。真实账号鉴权后的生产发布、下载及手机端自动下载/推理仍未验证。


## 2026-09-09 14:31:23 共鸣模型能力说明与旧发布日志转换

已部署 `song-content/audio-training-release-notes.js` 和 `song-content/audio-tuning-training.js` 到 `new-server:/www/wwwroot/token-admin`。自动更新日志现根据模型具备的 10/32 段分支、个性化听感、设备适配及独立置信度证据生成面向用户的能力说明，不再输出样本数量或训练损失报告。能力变化只按可核实的前后状态描述；缺少比较依据时描述当前支持的能力，不推断听感提升。32 段仍为可选分支，未校准模型仍可发布。

服务启动时已将三条既有发布记录转换为第 2 版能力日志，保留全部原发布时间、模型记录和制品。当前发布模型为 `3e890c07-b459-42c0-8bb9-48a12e74e707`，发布于北京时间 2026-09-09 13:53:15；该发布在此次部署前已完成。模型下载名继续为 `Mono-Resonance-S2_2026-09-09_04-43-09.908UTC.mlmodel`。

服务器 Node 22.23.1 的 66 项回归全部通过。生产数据库与实际模型文件的服务器内独立副本验证通过：三条旧日志转换、重复启动幂等、未校准 0c07 重复发布、手填日志忽略、说明预览一致，以及校准数据和原制品不变。上线后服务 PID `1560317` 为 `active/running`，自动重启为 0；四份 SQLite `quick_check` 为 `ok`，19 个模型记录和 18 个模型制品哈希未变，启动日志错误标记为 0。公网首页、后台入口返回 200；未认证的 AI 配置、模型目录和下载入口返回 401。

部署前备份：`/www/backup/token-admin-before-capability-notes-20260909T062902Z`，包含两个旧模块和一致性训练库备份。回滚命令：`python3 /www/backup/mono-capability-notes-staging-20260909T062902Z/deploy.py --rollback`，仅恢复代码，不用旧数据库覆盖后续数据。入口、AI 配置模块（含原混淆文件）、样本模块、导出脚本、站点资源及分发选择未修改。

完整证据：本机 `/tmp/mono-capability-notes-deploy-20260909T062902Z/`、服务器 `/www/backup/mono-capability-notes-staging-20260909T062902Z/`。本次只更新服务代码及既有发布说明，没有重新训练或发布真实模型。App 代码中的版本与 Beta 名称、简写时间、声音中心小字号版本行、更新日志标签、实际置信度展示修复与上一轮通过局部回归的版本哈希一致，需新版 App 生效；按用户要求未运行 Xcode 构建或上传 App。真实账号鉴权后的生产下载和手机界面、端侧推理本次未验证。


## 2026-09-09 15:22:01 完整下发面向用户的模型更新日志

已部署 `song-content/audio-tuning-training.js` 与 `ai-remote-config-s2.js` 到 `new-server:/www/wwwroot/token-admin`。日志继续使用现有简短、面向用户的能力说明；移除前三行和 420 字符截断，模型目录与普通用户 AI 配置均完整返回所有条目，兼容字段 `changelog` 同样包含完整内容。配置保留 `notes`，已有 ETag 逻辑会使旧的截断响应缓存失效。自动说明生成器和已保存的日志没有改写，不需要重新发布模型。

服务器 Node 22.23.1 上相关回归 67 项全部通过；本地针对分发和完整文本的 12 项回归及中英文 Swift 解码回归通过。在生产数据库和实际模型文件的服务器内独立副本上，四个已发布模型均完整下发日志；合成认证的公开配置路径验证了旧 ETag 返回更新内容、新 ETag 返回 304、重复启动稳定，以及发布时间、模型记录和制品不变。该隔离验证没有使用真实用户凭据或读取生产 AI 服务配置。

上线后服务 PID `1564935` 为 `active/running`，自动重启为 0；四份生产 SQLite `quick_check` 均为 `ok`，20 个模型记录、19 个既有模型制品、四条发布目录的时间及日志保持不变。部署模块哈希匹配，入口、原混淆配置模块、集成模块、样本模块、导出器及日志生成器哈希未变。公网首页和后台入口返回 200，受保护的 AI 配置、模型目录与下载入口未认证返回 401；启动检查未发现错误标记，仅有一条 Node SQLite 实验特性提示。

部署前备份：`/www/backup/token-admin-before-full-changelog-20260909T071900Z`。回滚命令：`python3 /www/backup/mono-full-changelog-staging-20260909T071900Z/deploy.py --rollback`，仅恢复两个代码文件，不恢复旧数据库。完整证据位于本机 `/tmp/mono-full-model-changelog-20260909-151637/` 与远端暂存目录。本次没有启动训练、发布模型或修改分发选择；按要求未运行 Xcode 构建。真实用户认证后的线上完整响应及手机界面本次未验证。


## 2026-09-09 16:23:14 共鸣模型自动更新分发部署

已将 `song-content/audio-tuning-training.js` 与 `ai-remote-config-s2.js` 部署到 `new-server:/www/wwwroot/token-admin`。已启用共鸣分发的配置会跟进下一次发布的新模型，下载接口使用同一分发结果验证模型 ID 和 SHA。显式选择保留至下一次模型发布；关闭的服务或分发不会被自动启用。现有完整更新日志与 ETag 缓存失效逻辑继续生效。本次未修改生产 AI 配置或发布模型。

服务器 Node 22.23.1 上 68 项回归全部通过。使用生产训练库及模型文件的服务器内独立副本，验证了自动跟进、最近手动选择保留、关闭分发保持、完整日志和 304 响应，以及持久配置与模型数据不变；未使用真实用户凭据。

上线后服务 `recovered-token-admin.service` 的 PID 为 `1570549`，状态为 `active/running`，自动重启为 0。部署文件哈希匹配，原混淆 `ai-remote-config.js`、服务入口及其他依赖保持原哈希；四份 SQLite `quick_check` 为 `ok`，20 个模型记录、19 个模型制品及四条发布记录保持一致。启动日志检查没有错误标记，仅有一条 Node SQLite 实验特性提示。公网首页和后台入口返回 200，未认证的配置、目录与模型下载返回 401。真实账号鉴权后的生产响应和手机端更新流程仍未验证。

备份：`/www/backup/token-admin-before-resonance-auto-update-20260909T082012Z`。回滚命令：`python3 /www/backup/mono-resonance-auto-update-staging-20260909T082012Z/deploy.py --rollback`，仅恢复两个代码模块，不恢复旧数据库。完整证据位于本机 `/tmp/mono-resonance-auto-update-deploy-20260909T082012Z/` 和远端 `/www/backup/mono-resonance-auto-update-staging-20260909T082012Z/`。

本次为服务端部署，未运行 App 构建、安装或上传；模型内置、启用弹窗、更新日志弹窗和界面文案需随包含这些修改的 App 生效。
