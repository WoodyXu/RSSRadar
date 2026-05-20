# RSSRadar MVP 技术栈推荐

## 1. 推荐结论

RSSRadar MVP 最适合采用一套“原生 macOS + 本地 SQLite + 本地持久化队列 + 用户自备 AI Provider”的技术栈：

```text
Swift / SwiftUI
+ Swift Concurrency
+ SQLite / GRDB.swift
+ URLSession
+ FeedKit
+ SwiftSoup
+ macOS Keychain
+ OSLog
+ Swift Package Manager
```

这条路线的核心原则是：

1. **尽量原生**：符合产品文档中“原生 macOS App、Swift / SwiftUI、本地运行”的约束。
2. **尽量少依赖**：只引入能明显降低实现风险的库，不堆复杂框架。
3. **本地优先**：所有用户数据、处理进度、缓存、队列状态都落在本地。
4. **可恢复**：RSS 抓取、AI 分析、主题生成、TopicBrief 生成都通过本地任务队列驱动，App 崩溃或退出后可恢复。
5. **不建服务端**：不使用开发者服务器、云数据库、云任务队列或 AI 中转服务。

---

## 2. 技术栈总览

| 层级 | 推荐技术 | 选择理由 |
|---|---|---|
| 桌面客户端 | Swift + SwiftUI | 文档已明确要求原生 macOS App；SwiftUI 足够覆盖 MVP 的侧边栏、列表、详情页、设置页和导出能力。 |
| 少量 macOS 原生能力 | AppKit bridge | SwiftUI 不好处理的窗口、文件导入/导出、菜单、细节交互再局部使用 AppKit。 |
| 并发模型 | Swift Concurrency / async-await / actor | RSS 抓取、网页解析、AI 调用、队列调度都天然适合异步任务。 |
| 本地数据库 | SQLite | 文档已明确要求 SQLite；适合本地优先、单机、可备份、可迁移的结构化数据。 |
| SQLite 访问层 | GRDB.swift | 比直接写 sqlite3 更稳，比 SwiftData/Core Data 更可控；支持迁移、事务、查询封装、并发读写。 |
| API Key 存储 | macOS Keychain | 符合“API Key 只保存在本地并加密存储”的要求。 |
| RSS/Atom/JSON Feed 解析 | FeedKit | 减少 RSS/Atom 边界格式处理成本。 |
| OPML 解析 | Foundation XMLParser | OPML 结构简单，MVP 没必要引入额外库。 |
| 网络请求 | URLSession | 足够支持 RSS 抓取、网页抓取、AI API 请求、超时、重试和取消。 |
| HTML 正文抽取 | SwiftSoup + 自研轻量 Readability 规则 | 符合 MVP“不使用无头浏览器”的约束；失败时降级 RSS 摘要。 |
| AI Provider | 自研 AIProvider 抽象 + URLSession | OpenAI-compatible、Anthropic、Custom Base URL 可共用一套请求调度、重试、JSON 校验。 |
| Markdown 导出 | 自研模板渲染 | MVP 只需要复制/导出 Markdown，不需要复杂 Markdown AST。 |
| 日志 | OSLog + 本地 processing_logs 表 | 系统日志用于开发调试，本地表用于用户可见的 Processing 页面。 |
| 包管理 | Swift Package Manager | Xcode 原生支持；避免 CocoaPods/Carthage 增加维护复杂度。 |
| 测试 | XCTest / Swift Testing + URLProtocol mock | 保证 RSS、AI Provider、数据库迁移、队列恢复等核心逻辑可测。 |
| CI | GitHub Actions macOS runner | 跑单元测试、构建、SwiftLint；发布 notarization 可后置。 |

---

## 3. 推荐项目结构

建议使用一个 Xcode App 工程，加若干内部 Swift Package 或 target。MVP 不需要过度模块化，但需要把 UI、数据、任务队列和 AI 调用分开。

```text
RSSRadar/
├── RSSRadarApp/                 # macOS App target
│   ├── App/
│   ├── Views/
│   ├── ViewModels/
│   └── Resources/
├── Packages/
│   ├── RSSRadarCore/            # Entity、Value Object、领域模型
│   ├── RSSRadarPersistence/     # GRDB、Migration、Repository
│   ├── RSSRadarFeeds/           # Feed 抓取、FeedKit、OPML
│   ├── RSSRadarExtraction/      # HTML 抽取、正文清洗、降级逻辑
│   ├── RSSRadarAI/              # AIProvider、Prompt、JSON 解析
│   ├── RSSRadarProcessing/      # 本地任务队列、扫描流程、重试
│   └── RSSRadarExport/          # Markdown 模板、文件导出
└── Tests/
    ├── PersistenceTests/
    ├── FeedTests/
    ├── AITests/
    └── ProcessingTests/
```

如果早期开发人手很少，也可以先不拆成多个 Swift Package，而是在一个 App target 内按 folder 分层；但至少应保持以下边界：

```text
UI 不直接访问数据库
UI 不直接调用 AI API
AI Provider 不直接改数据库
ProcessingEngine 负责流程编排
Repository 负责数据读写
```

---

## 4. macOS / Swift / SwiftUI 建议

### 4.1 Deployment Target

推荐：

```text
macOS 14.0+
```

原因：

- RSSRadar 是 AI + 信息处理类工具，早期用户大概率使用较新的 macOS。
- macOS 14+ 可以减少 SwiftUI 兼容性分支。
- MVP 阶段更重要的是快速验证核心体验，而不是覆盖最老系统。

部署目标已确认为固定使用 macOS 14.0+。

### 4.2 Swift 版本策略

推荐：

```text
使用当前稳定 Xcode / Swift 工具链
默认开启 async/await
逐步开启 Strict Concurrency 检查
```

不建议一开始就为了“完全 Swift 6 严格并发”牺牲开发速度。更稳妥的做法是：

1. 业务代码尽量用 `actor` 隔离共享状态；
2. 数据库写入统一走 Repository；
3. 网络、AI、RSS 任务用 `async throws`；
4. UI 状态更新限制在 `@MainActor`；
5. 后续逐步收紧 Sendable 和 strict concurrency warning。

---

## 5. UI 技术方案

### 5.1 主框架

使用：

```text
SwiftUI + MVVM-ish
```

建议 UI 结构：

```text
NavigationSplitView
├── Sidebar
│   ├── Today
│   ├── Topics
│   ├── Feeds
│   ├── Processing
│   └── Settings
└── Detail
```

页面 ViewModel 建议：

```text
TodayViewModel
TopicsViewModel
TopicDetailViewModel
FeedsViewModel
ProcessingViewModel
SettingsViewModel
OnboardingViewModel
```

ViewModel 只做：

- 加载页面数据；
- 调用 use case / service；
- 管理页面状态；
- 显示错误和空状态。

不要让 ViewModel 承担 RSS 抓取、AI Prompt 拼接、数据库事务等复杂逻辑。

### 5.2 AppKit 使用边界

SwiftUI 优先。只在以下场景局部使用 AppKit：

- OPML 文件选择；
- Markdown 导出保存路径；
- 菜单栏命令；
- 复制到剪贴板；
- 窗口尺寸和偏好设置；
- 未来可能的 dock/menu bar 细节。

---

## 6. 数据库与持久化方案

### 6.1 推荐选择

使用：

```text
SQLite + GRDB.swift
```

不推荐 MVP 使用 SwiftData / Core Data 作为主存储层，原因是：

1. 产品文档已明确写了 SQLite；
2. RSSRadar 有明确的数据表、关联表和队列状态，关系模型清晰；
3. 需要稳定的迁移机制；
4. 需要可恢复的本地任务队列；
5. 需要可控事务，避免半完成状态污染数据；
6. 后续若要全文搜索，SQLite FTS 更自然。

### 6.2 数据库文件位置

推荐默认路径：

```text
~/Library/Application Support/RSSRadar/rssradar.sqlite
```

同时在 Settings 中显示路径，并允许用户选择自定义数据目录。

### 6.3 SQLite 配置

建议启用：

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
```

原因：

- WAL 更适合本地 App 的读写并发；
- foreign keys 保证 TopicArticle 等关系一致性；
- busy_timeout 可降低短时间并发访问造成的失败。

### 6.4 核心表

除产品文档中的对象外，建议额外增加 `processing_jobs` 和 `operation_logs`。

```text
feeds
articles
article_analyses
topics
topic_articles
topic_briefs
app_settings
processing_jobs
operation_logs
user_corrections
```

#### processing_jobs

用于实现可恢复队列。

```sql
CREATE TABLE processing_jobs (
  id TEXT PRIMARY KEY,
  job_type TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  payload_json TEXT,
  status TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 3,
  last_error_message TEXT,
  scheduled_at TEXT NOT NULL,
  started_at TEXT,
  finished_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

`job_type` 建议包括：

```text
fetch_feed
parse_article
analyze_article
assign_topics
generate_topic_brief
retry_failed_job
```

#### operation_logs

用于 Processing 页面展示用户能理解的处理记录。

```sql
CREATE TABLE operation_logs (
  id TEXT PRIMARY KEY,
  level TEXT NOT NULL,
  message TEXT NOT NULL,
  context_json TEXT,
  created_at TEXT NOT NULL
);
```

#### user_corrections

用于记录用户纠错，但 MVP 不做复杂自动学习。

```sql
CREATE TABLE user_corrections (
  id TEXT PRIMARY KEY,
  correction_type TEXT NOT NULL,
  topic_id TEXT,
  article_id TEXT,
  old_value TEXT,
  new_value TEXT,
  created_at TEXT NOT NULL
);
```

### 6.5 JSON 字段处理

`ArticleAnalysis`、`TopicBrief` 中的数组字段可以先用 JSON TEXT 存储，例如：

```text
key_points_json
entities_json
claims_json
events_json
metrics_json
timeline_json
viewpoints_json
evidence_json
questions_to_watch_json
related_article_ids_json
```

MVP 阶段不必为了每个数组拆子表，避免 schema 过度复杂。只有查询频繁、需要过滤和排序的字段才单独建表。

---

## 7. 本地任务队列设计

### 7.1 为什么必须有本地队列

产品文档要求：

- AI 处理异步执行；
- 大批量扫描时展示进度；
- 失败任务不阻塞整体队列；
- RSS 抓取失败可恢复；
- AI 调用失败可重试；
- 应用异常退出后，处理队列可以恢复。

因此不要只用内存中的 `Task {}` 管理流程。必须把任务状态落库。

### 7.2 推荐实现

使用：

```text
SQLite processing_jobs 表
+ ProcessingEngine actor
+ 有限并发 worker
```

建议组件：

```swift
actor ProcessingEngine {
    func enqueueScanAllFeeds() async throws
    func enqueueFeedScan(feedID: Feed.ID) async throws
    func runPendingJobs() async
    func retry(jobID: Job.ID) async throws
    func cancel(jobID: Job.ID) async throws
}
```

### 7.3 并发策略

MVP 默认：

| 任务类型 | 并发建议 |
|---|---:|
| RSS feed fetch | 4 |
| Web article extraction | 3 |
| AI article analysis | 2 |
| Topic assignment batch | 1 |
| TopicBrief generation | 1 |

AI 任务并发不要太高，因为用户使用自己的 API Key，成本和 rate limit 都不可控。

### 7.4 失败策略

建议：

```text
第 1 次失败：立即记录错误，可重试
第 2 次失败：指数退避 30 秒
第 3 次失败：标记 failed，等待用户手动重试
```

`max_attempts = 3`。App 启动恢复时，将遗留 `running` job 恢复为 `pending`，不额外增加 `attempt_count`。

TopicBrief 重新生成失败时不要覆盖旧缓存。

---

## 8. RSS 与文章抓取方案

### 8.1 Feed 抓取

使用：

```text
URLSession + FeedKit
```

流程：

```text
读取 Feed URL
→ URLSession 请求 XML/JSON
→ FeedKit 解析 RSS / Atom / JSON Feed
→ 标准化为 ArticleCandidate
→ URL + 标题相似度去重
→ 写入 articles 表
→ 生成 parse_article job
```

### 8.2 OPML 导入

使用：

```text
Foundation XMLParser
```

OPML 导入只需要读取 outline 节点中的：

```text
text
title
xmlUrl
htmlUrl
```

不建议为了 OPML 引入第三方库。

### 8.3 正文抽取

使用：

```text
URLSession + SwiftSoup + 自研轻量规则
```

抽取优先级：

```text
RSS full content
→ 网页正文抽取
→ RSS summary
```

轻量正文抽取规则：

1. 移除 `script/style/nav/header/footer/aside`；
2. 优先匹配 `article`、`main`、`[role=main]`；
3. 若无明显正文节点，对 `p` 标签聚合评分；
4. 根据文本长度、链接密度、段落数量评分；
5. 失败则使用 RSS summary。

MVP 不引入 Playwright、Puppeteer、Selenium、WebKit 自动渲染池。

---

## 9. AI Provider 方案

### 9.1 Provider 抽象

按照产品文档中的方向实现：

```swift
protocol AIProvider {
    func complete(request: AICompletionRequest) async throws -> AICompletionResponse
}
```

建议拆成：

```text
OpenAICompatibleProvider
AnthropicProvider
CustomOpenAICompatibleProvider
```

OpenAI-compatible 默认 Base URL 为 `https://api.openai.com/v1`。Anthropic 默认 Base URL 为 `https://api.anthropic.com`。`Custom Base URL` 本质上复用 OpenAI-compatible 的 Chat Completions request/response 结构。

### 9.2 网络层

使用：

```text
URLSession
```

不建议引入 Alamofire。原因：

- AI API 请求结构不复杂；
- 原生 URLSession 支持 async/await；
- 少一个依赖，维护和调试更简单；
- 超时、取消、重试、header、JSON 编解码都够用。

### 9.3 Prompt 管理

内置模板使用资源文件管理：

```text
Prompts/
├── ArticleAnalysisPrompt.md
├── TopicAssignmentPrompt.md
├── TopicBriefPrompt.md
└── CandidateTopicPreviewPrompt.md
```

Prompt 输入输出统一走强类型结构：

```swift
struct ArticleAnalysisOutput: Codable { ... }
struct TopicAssignmentOutput: Codable { ... }
struct TopicBriefOutput: Codable { ... }
```

AI 返回后必须做：

1. JSON parse；
2. 字段完整性校验；
3. enum 值校验；
4. 空数组/空字符串兜底；
5. 失败记录原始错误，不把坏结果写成成功状态。

### 9.4 成本控制

默认配置：

```text
新源最多抓取文章数：20
单次扫描最多 AI 分析文章数：100
单次主题生成批处理文章数：20
AI 请求超时：60 秒
AI 并发：2
```

可进一步增加：

```text
只处理最近 N 天文章
超过 N 字正文自动截断
标题 + 摘要先轻量判断，再决定是否使用全文
```

---

## 10. API Key 与隐私方案

### 10.1 API Key

使用：

```text
macOS Keychain Services
```

只在数据库中保存：

```text
provider
base_url
model_name
keychain_account_identifier
```

不要把 API Key 明文写入：

```text
SQLite
日志
crash report
operation_logs
导出 Markdown
```

### 10.2 隐私边界

MVP 不接入：

```text
Firebase Analytics
Sentry
PostHog
自建遥测服务
云端日志
```

如果后续要做崩溃上报，必须提供明确开关，并默认关闭或在 onboarding 中清晰告知。

---

## 11. Markdown 导出方案

MVP 只需要：

```text
复制当前主题情报为 Markdown
导出当前主题情报为 .md 文件
```

推荐自研模板渲染，不引入 Markdown 库。

```swift
struct TopicBriefMarkdownRenderer {
    func render(topic: Topic, brief: TopicBrief, articles: [Article]) -> String
}
```

只有在后续需要：

- Markdown 预览；
- Markdown AST 编辑；
- 富文本复制；
- HTML 导出；

再考虑引入 `swift-markdown`。

---

## 12. 日志、错误与可观测性

### 12.1 开发日志

使用：

```text
OSLog / Logger
```

按模块划分 category：

```text
feed
extraction
ai
processing
database
ui
export
```

### 12.2 用户可见日志

Processing 页面不要直接读系统日志，而是读 `operation_logs` 和 `processing_jobs`。

用户应该能看到：

```text
正在处理什么
处理到哪一步
失败原因是什么
是否可以重试
最近一次成功时间
```

### 12.3 错误类型

建议定义统一错误：

```swift
enum RSSRadarError: Error {
    case feedFetchFailed(reason: String)
    case feedParseFailed(reason: String)
    case articleExtractionFailed(reason: String)
    case aiRequestFailed(provider: String, reason: String)
    case aiInvalidJSON(reason: String)
    case databaseError(reason: String)
    case keychainError(reason: String)
}
```

UI 层再把技术错误转换成用户能理解的提示。

---

## 13. 测试策略

MVP 最应该测的不是 UI，而是数据和流程。

### 13.1 单元测试优先级

P0：

```text
数据库 migration
Feed 解析
OPML 导入
URL 去重
标题相似度去重
AI JSON 解析与校验
Processing job 状态流转
失败重试
TopicBrief 失败不覆盖旧缓存
Markdown 导出
```

P1：

```text
HTML 正文抽取
主题排序 score
Settings 保存/读取
Keychain wrapper
```

### 13.2 Mock 策略

使用：

```text
URLProtocol mock
临时 SQLite 数据库
FakeAIProvider
固定 RSS fixture
固定 HTML fixture
固定 AI JSON fixture
```

不要在测试中真实调用 AI API。

---

## 14. CI / 工程质量

### 14.1 CI

使用 GitHub Actions macOS runner：

```text
swift test
xcodebuild test
swiftlint
```

发布流程可以后置到 MVP 验证后再完善：

```text
Developer ID signing
Notarization
Sparkle auto update
```

### 14.2 代码风格

推荐：

```text
SwiftLint
SwiftFormat，可选
```

SwiftLint 必须做到本地可执行。SwiftFormat 可选，不作为 MVP 阻塞项。

不要在 MVP 初期引入太多工程治理工具，避免维护成本超过收益。

---

## 16. MVP 依赖清单

建议先只引入这些依赖：

| 依赖 | 用途 | 是否必需 |
|---|---|---|
| GRDB.swift | SQLite 访问、migration、事务 | 必需 |
| FeedKit | RSS / Atom / JSON Feed 解析 | 必需 |
| SwiftSoup | HTML 解析与正文抽取 | 必需 |
| SwiftLint | 代码风格 | 推荐 |

暂缓引入：

| 依赖 | 暂缓原因 |
|---|---|
| Alamofire | URLSession 足够 |
| Realm | SQLite/GRDB 更贴合需求 |
| SwiftData | schema 和队列控制不如 GRDB 直接 |
| Combine-heavy 架构 | async/await 更简单 |
| The Composable Architecture | 对 MVP 偏重，可后续再评估 |
| Markdown AST 库 | 当前只需要模板导出 |
| Sentry / Analytics | 与本地隐私定位冲突，后续需明确用户授权 |
| Playwright / headless browser | 文档明确 MVP 不做复杂浏览器渲染 |

---

## 17. 第一阶段实现顺序

建议按以下顺序开发，避免先做漂亮 UI，后面发现处理流程不可恢复。

### Phase 1：本地数据骨架

```text
GRDB 接入
schema migration
Repository
Settings 存储
Keychain wrapper
```

验收：能创建数据库、保存设置、保存 API Key、跑 migration 测试。

### Phase 2：RSS 与 OPML

```text
手动添加 RSS
OPML 导入
Feed 抓取
Article 入库
URL + 标题去重
Feed 状态更新
```

验收：能导入一批源，并按新源规则抓取最近 20 篇。

### Phase 3：本地任务队列

```text
processing_jobs
ProcessingEngine
任务状态流转
失败重试
Processing 页面
```

验收：App 退出后重新打开，未完成任务可以继续处理。

### Phase 4：AI 单篇分析

```text
AIProvider 抽象
OpenAI-compatible
Anthropic
Custom Base URL
ArticleAnalysis JSON 校验
```

验收：能对文章生成结构化理解，失败时可重试。

### Phase 5：主题生成与匹配

```text
批量主题生成
已有主题匹配
Candidate Topic
Active Topic
用户追踪/忽略/改名
```

验收：用户能从候选主题中选择值得追踪的具体主题。

### Phase 6：TopicBrief 与导出

```text
TopicBrief 预生成
缓存读取
重新生成
Markdown 复制
Markdown 文件导出
```

验收：用户能打开主题情报页，并导出 Markdown。

---

## 18. 最终推荐架构图

```text
┌──────────────────────────────────────────────┐
│                SwiftUI macOS App              │
│  Today / Topics / Feeds / Processing / Settings│
└──────────────────────┬───────────────────────┘
                       │
┌──────────────────────▼───────────────────────┐
│              ViewModels / Use Cases           │
│  ScanFeeds / AnalyzeArticles / GenerateBriefs │
└──────────────────────┬───────────────────────┘
                       │
┌──────────────────────▼───────────────────────┐
│              ProcessingEngine actor           │
│       durable jobs + retry + limited workers  │
└───────┬──────────────┬──────────────┬────────┘
        │              │              │
┌───────▼──────┐ ┌─────▼──────┐ ┌─────▼────────┐
│ Feed Service │ │ AI Service │ │ Brief Export │
│ URLSession   │ │ Providers  │ │ Markdown     │
│ FeedKit      │ │ URLSession │ │ Renderer     │
│ SwiftSoup    │ └────────────┘ └──────────────┘
└───────┬──────┘
        │
┌───────▼──────────────────────────────────────┐
│           Persistence / Repository            │
│        GRDB.swift + SQLite + migrations       │
└───────┬──────────────────────────────────────┘
        │
┌───────▼──────────────────────────────────────┐
│ Local files                                  │
│ ~/Library/Application Support/RSSRadar/       │
│ - rssradar.sqlite                            │
│ - exports/*.md                               │
│                                              │
│ macOS Keychain                               │
│ - API Key                                    │
└──────────────────────────────────────────────┘
```
