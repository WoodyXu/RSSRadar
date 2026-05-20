# RSSRadar MVP 实施计划

本计划面向 AI 开发者。每一步都应独立提交、保持变更范围小，并在通过对应测试后再进入下一步。严禁跳过本地优先、Keychain、可恢复队列和失败不阻塞等核心约束。

## 阶段 1：工程与基础架构

### 步骤 1：创建 macOS SwiftUI 工程骨架
指令：创建原生 macOS App 工程，部署目标使用 macOS 14.0+。工程形态使用纯 Swift Package + macOS app target，并从一开始建立 app target 和 internal packages。建立 App、Views、ViewModels、Resources、Packages、Tests 的基础目录，并保持 UI、数据、AI、抓取、处理、导出边界清晰。
验证测试：确认工程可在本机编译；确认测试 target 可运行一个空测试；确认目录结构与技术文档推荐结构一致。

### 步骤 2：接入基础工程质量工具
指令：配置 Swift Package Manager 依赖管理，并准备本地可执行的 SwiftLint。暂不引入技术文档明确暂缓的依赖。
验证测试：运行 lint 与测试套件；确认没有无关依赖；确认构建日志中只包含 MVP 必需依赖。

### 步骤 3：建立核心领域模型
指令：定义 Feed、Article、ArticleAnalysis、Topic、TopicArticle、TopicBrief、AppSettings 的领域模型，字段应覆盖产品文档的数据设计。所有领域对象 ID 统一使用 UUID string。
验证测试：为每个模型添加编码、解码、默认值和状态枚举测试；确认无效状态不能被静默当作有效数据。

## 阶段 2：本地数据与安全存储

### 步骤 4：接入 SQLite 与迁移机制
指令：使用 SQLite 和 GRDB 建立数据库层，启用 WAL、foreign keys 和 busy timeout。创建版本化 migration。SQLite 时间字段统一使用 ISO8601 text。
验证测试：在临时数据库上运行迁移测试；确认所有表创建成功；确认外键约束生效；确认重复执行迁移不会破坏数据。

### 步骤 5：创建 Repository 层
指令：为核心对象建立 Repository，UI 和 ViewModel 不得直接访问数据库。
验证测试：使用临时 SQLite 数据库测试增删改查；确认事务失败会回滚；确认 Repository 不依赖真实 UI。

### 步骤 6：实现设置持久化
指令：保存 AI Provider、Base URL、模型名、数据库路径、扫描模式、扫描间隔和处理上限。API Key 不得写入 SQLite。用户修改数据库路径时使用新路径新库，不迁移旧库。
验证测试：保存并重新读取设置；确认默认值符合文档；检查数据库内容不包含 API Key 明文。

### 步骤 7：实现 Keychain API Key 存储
指令：将 API Key 写入 macOS Keychain，并只在设置中保存 Keychain 标识。
验证测试：保存、读取、替换、删除 API Key；确认日志、数据库和用户可见错误中不出现 Key 明文。

## 阶段 3：RSS 与文章抓取

### 步骤 8：实现手动添加 RSS 源
指令：支持用户输入 RSS URL，抓取并解析 feed 元信息，保存 Feed 状态。
验证测试：使用固定 RSS fixture 验证标题、站点 URL、状态和错误信息；无效 URL 应记录错误且不崩溃。

### 步骤 9：实现 OPML 导入
指令：解析 OPML outline 中的 text、title、xmlUrl、htmlUrl，并批量创建 Feed。
验证测试：使用包含分组、缺失字段和重复源的 OPML fixture；确认有效源被导入、重复源被跳过、错误被记录。

### 步骤 10：实现 Feed 抓取与文章入库
指令：用 URLSession 和 FeedKit 抓取 RSS、Atom、JSON Feed，标准化为 Article，并按新源最多 20 篇规则入库。新源按发布时间倒序选取，缺少发布时间的文章排在后面；缺少 `published_at` 的文章不得用于更新 `last_processed_article_published_at`；Feed 处理进度按已成功入库文章中的最新 `published_at` 更新。
验证测试：使用固定 feed fixture；确认新源最多写入 20 篇；确认老源只抓取 last_processed_article_published_at 之后的文章；确认缺少发布时间的文章不会推进处理进度。

### 步骤 11：实现文章去重
指令：按 URL 和同一 feed 内标题相似度去重，避免重复文章进入后续 AI 队列。URL 去重需要做基础 canonicalization：host lowercase、移除 fragment、移除常见 tracking params。
验证测试：构造 URL 相同、标题近似、标题不同三类样本；确认重复样本只保存一次，非重复样本保留；确认不同 feed 的相似标题不会被误去重。

### 步骤 12：实现正文抽取与降级
指令：正文来源优先级为 RSS full content、网页正文抽取、RSS summary。网页抽取失败时必须降级为摘要。
验证测试：使用 full content、可抽取 HTML、不可抽取 HTML 三类 fixture；确认 content_source 正确，失败不阻塞处理。

## 阶段 4：可恢复本地任务队列

### 步骤 13：建立 processing_jobs 与 operation_logs
指令：增加可恢复任务表和用户可见日志表，任务类型覆盖抓源、解析文章、分析文章、主题归类、生成情报页和重试。
验证测试：验证任务创建、状态变更、日志写入；确认 operation_logs 不包含敏感信息。

### 步骤 14：实现 ProcessingEngine
指令：实现 actor 驱动的有限并发处理引擎，任务状态必须落库，不能只存在内存。
验证测试：创建多类待处理任务；确认并发上限符合技术文档；确认任务成功后进入完成状态。

### 步骤 15：实现失败重试策略
指令：任务失败时记录错误、增加 attempt_count、按策略延后重试。`max_attempts = 3`，第 3 次失败后标记 failed，等待用户手动重试。
验证测试：使用可控失败任务验证三次失败流转；确认 failed 任务可由用户手动重试；确认失败任务不阻塞其他任务。

### 步骤 16：验证异常退出恢复
指令：启动任务后模拟 App 退出，再重新启动处理引擎，恢复未完成任务。启动恢复时，将遗留 running job 恢复为 pending，不额外增加 attempt_count。
验证测试：确认 running 或 pending 任务能回到可处理状态；确认已完成任务不会重复执行；确认恢复 running job 不增加 attempt_count。

## 阶段 5：AI Provider 与结构化分析

### 步骤 17：实现 AI Provider 抽象
指令：支持 OpenAI-compatible、Anthropic、Custom Base URL 三类 Provider，统一请求超时、取消和错误映射。OpenAI-compatible 默认 Base URL 为 `https://api.openai.com/v1`；Anthropic 默认 Base URL 为 `https://api.anthropic.com`；OpenAI-compatible 与 Custom Base URL 均按 Chat Completions 兼容格式实现。
验证测试：使用 FakeAIProvider 和 URLProtocol mock；确认每类 Provider 生成正确请求；确认默认 Base URL 正确；确认超时和错误被转为用户可理解错误。

### 步骤 18：实现 Prompt 管理
指令：为单篇文章分析、主题归类、情报页生成、候选主题预览建立内置 Prompt 模板，模板放在 `Prompts/*.md` 资源文件中，不开放复杂 Prompt 编辑。
验证测试：确认每个任务类型能加载对应模板；确认模板缺失时返回明确错误；确认模板输入不包含 API Key。

### 步骤 19：实现单篇文章分析
指令：对文章标题、来源、发布时间、摘要、正文和 URL 进行 AI 结构化理解，并保存 ArticleAnalysis。
验证测试：用固定 AI JSON fixture 验证 summary、key_points、entities、claims、events、metrics、content_type、possible_topics、importance_score 均被校验和保存。

### 步骤 20：实现 AI JSON 校验失败处理
指令：AI 返回无效 JSON、缺字段、非法枚举或空关键字段时，不得写入成功分析结果。AI JSON 校验失败时，job 进入 retry 或 failed；article 保持上一稳定状态，最终不可恢复时标记 failed 并记录错误。
验证测试：使用无效 JSON fixture；确认文章进入 failed 或可重试状态；确认原始错误被记录但不泄露敏感信息。

## 阶段 6：主题生成、匹配与纠错

### 步骤 21：实现批量主题生成与匹配
指令：基于一批 ArticleAnalysis 和已有 Topic，按每批 20 篇生成具体候选主题或匹配已有主题，并支持一篇文章归入多个主题。宽泛主题名通过 Prompt 约束加本地最小规则校验处理，校验失败进入重试。
验证测试：使用固定 AI 输出验证 Topic、TopicArticle、confidence、reason、contribution_type；确认宽泛主题名会被拒绝或要求重试。

### 步骤 22：实现候选主题管理
指令：支持查看候选主题、简版预览、追踪、忽略、改名、改描述。同状态下按 normalized name 对 candidate topic 做简单去重。
验证测试：验证 candidate 到 active、candidate 到 ignored 的状态流转；确认改名和改描述会持久化；确认重复候选主题不会重复创建。

### 步骤 23：实现 Active Topic 持续更新
指令：后续扫描必须使用用户修改后的主题名和描述参与归类，active topic 扫描后预生成完整情报页。
验证测试：改名后执行一次模拟扫描；确认 AI 输入使用新名称和新描述；确认 TopicArticle 关系更新。

### 步骤 24：实现用户纠错记录
指令：支持从主题移除文章、将文章加入已有主题、基于文章创建新主题，并记录 user_corrections。
验证测试：分别执行三类纠错；确认关系表和纠错表一致；确认系统提示用户可重新生成 TopicBrief。

## 阶段 7：TopicBrief、Today 与导出

### 步骤 25：实现 TopicBrief 生成与缓存
指令：为 active topic 生成完整 TopicBrief，为 candidate topic 生成简版预览。打开主题时优先展示缓存。TopicBrief 默认使用中文生成。
验证测试：确认 generated_at 被保存；确认缓存存在时不重复调用 AI；确认 candidate 只生成 preview。

### 步骤 26：实现 TopicBrief 失败保护
指令：用户手动重新生成失败时，必须保留旧版本并展示错误。
验证测试：先保存旧 brief，再模拟 AI 失败；确认旧 brief 未被覆盖；确认 operation_logs 记录失败。

### 步骤 27：实现 Today 页面数据源
指令：聚合扫描状态、今日重要主题、新候选主题、追踪主题更新，并按 recency、importance、新增文章数、active bonus 排序。
验证测试：构造多主题样本；确认只展示 active 的今日重要主题，只展示 candidate 的新候选主题；确认排序稳定。

### 步骤 28：实现 Topic Detail 数据源
指令：展示主题标题、状态、当前结论、最近变化、时间线、观点分歧、关键证据、观察点和相关文章。
验证测试：使用完整 TopicBrief fixture；确认关键证据关联来源文章；确认相关文章包含标题、来源、发布时间、摘要、贡献类型和链接。

### 步骤 29：实现 Markdown 复制与文件导出
指令：将当前主题情报渲染为 Markdown，支持复制和导出当前主题为单个 Markdown 文件。不实现 PDF、Notion 或 Obsidian 同步。
验证测试：用固定 TopicBrief 和 Article 数据生成 Markdown；确认包含主题名、生成时间、当前结论、时间线、观点分歧、关键证据、观察点和相关文章链接。

## 阶段 8：界面、空状态与总体验收

写任何 UI 前必须读取仓库中的 `DESIGN.md`，并按其中视觉和交互规范实现。

### 步骤 30：实现 Onboarding 流程
指令：串联欢迎说明、OPML 或手动添加 RSS、AI Provider 配置、处理上限设置、首次扫描和候选主题展示。
验证测试：执行完整首次使用路径；确认用户能导入源、保存 Keychain API Key、启动扫描并看到候选主题。

### 步骤 31：实现 Feeds、Processing、Settings 页面
指令：Feeds 展示源状态和手动刷新；Processing 展示任务进度、失败原因和重试；Settings 展示 AI、扫描、成本和数据路径设置。清空本地数据必须提供保守确认，默认不删除 Keychain API Key，除非用户明确勾选。
验证测试：分别验证添加源、刷新源、失败任务重试、设置保存读取、清空本地数据入口的行为；确认未勾选时 API Key 保留。

### 步骤 32：实现错误与空状态
指令：覆盖无 RSS 源、未配置 API Key、AI 调用失败、正文抓取失败、没有新文章五类状态。
验证测试：为每类状态构造场景；确认用户看到明确下一步操作；确认 UI 不崩溃、不阻塞可继续流程。

### 步骤 33：执行隐私与安全验收
指令：检查应用不接入开发者服务器、云同步、遥测、云端日志或 AI 中转；AI 请求只从用户本机发往用户配置 Provider。
验证测试：扫描数据库、日志、导出文件和测试 fixture；确认不存在 API Key 明文；确认没有第三方遥测依赖。

### 步骤 34：执行性能与稳定性验收
指令：使用多 RSS 源和较大文章集合验证启动、列表查询、后台处理、失败恢复和 UI 响应。
验证测试：确认启动后 2 秒内显示主界面；确认大批量扫描时 UI 可操作；确认失败任务不阻塞队列；确认异常退出后可恢复。

### 步骤 35：执行 MVP 端到端验收
指令：从空数据库开始，完成导入 RSS、配置 Provider、首次扫描、文章分析、主题生成、追踪主题、生成情报页、导出 Markdown 的完整闭环。
验证测试：按产品文档第 21 节逐项验收；所有验收项通过后，才允许标记 MVP 实施完成。
