# RSSRadar 数据库文档

数据库路径：`~/Library/Application Support/RSSRadar/rssradar.sqlite`

基于 SQLite (GRDB)，使用 WAL 模式，所有表均通过外键关联维护引用完整性。

---

## 表总览

| 表名 | 主题 | 行数 | 说明 |
|------|------|------|------|
| `grdb_migrations` | 迁移记录 | - | GRDB 内部表，记录已执行的 schema 迁移版本 |
| `feeds` | RSS 源 | 1 | 用户添加的 RSS/Atom/JSON Feed 订阅源 |
| `articles` | 文章 | 20 | RSS 源抓取并解析后的文章内容 |
| `article_analyses` | AI 分析 | 1 | 文章经 AI 分析后提取的结构化信息 |
| `topics` | 主题 | 14 | 从文章中自动提取的待处理主题候选 |
| `topic_articles` | 主题-文章关联 | 0 | 文章与主题的多对多关系及关联置信度 |
| `topic_briefs` | 主题简报 | 0 | 主题的 AI 生成摘要和全景视图 |
| `app_settings` | 应用配置 | 1 | 用户配置的 AI Provider、扫描参数等设置 |
| `processing_jobs` | 处理任务队列 | 0 | 待执行的异步处理任务（抓取/解析/分析/分配） |
| `operation_logs` | 操作日志 | 0 | 应用运行时的事件和错误日志 |
| `user_corrections` | 用户纠正 | 0 | 用户对 AI 主题分配结果的修正记录 |

---

## feeds — RSS 源

存储用户订阅的 RSS/Atom/JSON Feed 信息，是整个数据流的入口。

### 字段

| 字段 | 类型 | 说明 | 产生方式 |
|------|------|------|----------|
| `id` | TEXT PRIMARY KEY | 全局唯一标识符 (UUID) | 自动生成 |
| `title` | TEXT NOT NULL | Feed 显示名称 | 解析 RSS `<title>` 或用户手动输入 |
| `url` | TEXT NOT NULL | Feed 订阅地址 | 用户添加时提供 |
| `site_url` | TEXT | 源网站首页地址 | 解析 RSS `<link>` 或用户手动输入 |
| `status` | TEXT NOT NULL | 源状态 | `active` / `error` / `paused` / `no_articles`，由扫描服务更新 |
| `last_checked_at` | TEXT | 最近一次扫描时间 | 每次 scan 后由 FeedScanService 更新 |
| `last_success_at` | TEXT | 最近一次成功扫描时间 | scan 成功完成时更新 |
| `last_processed_article_published_at` | TEXT | 已处理的最新的文章发布时间 | 用于增量扫描——只抓取该时间之后的新文章 |
| `error_message` | TEXT | 最近一次错误信息 | scan 失败时记录具体错误 |
| `created_at` | TEXT NOT NULL | 创建时间 (ISO8601) | 创建记录时的时间戳 |
| `updated_at` | TEXT NOT NULL | 更新时间 (ISO8601) | 每次更新 feed 记录时刷新 |

### 状态说明

- `active`：正常，正在接受扫描
- `error`：最近一次扫描失败（网络错误、解析失败等）
- `paused`：用户手动暂停
- `no_articles`：扫描成功但没有解析到任何文章

---

## articles — 文章

存储 RSS 源抓取到的文章原始内容，是整个系统的核心数据实体。

### 字段

| 字段 | 类型 | 说明 | 产生方式 |
|------|------|------|----------|
| `id` | TEXT PRIMARY KEY | 全局唯一标识符 (UUID) | FeedScanService 扫描时自动生成 |
| `feed_id` | TEXT NOT NULL, FK | 所属 Feed 的 id | 由 FeedScanService 在解析时注入 |
| `title` | TEXT NOT NULL | 文章标题 | 解析 RSS `<title>` |
| `url` | TEXT NOT NULL | 文章原文链接 | 解析 RSS `<link>` 或 `<guid>` |
| `author` | TEXT | 文章作者 | 解析 RSS `<author>` 或 Dublin Core `dc:creator`，可能为空 |
| `published_at` | TEXT | 文章原始发布时间 | 解析 RSS `<pubDate>`，时区为 UTC |
| `rss_summary` | TEXT | RSS 中的 description/summary 字段原文 | 解析 RSS `<description>`，包含原始 HTML 或 CDATA |
| `content` | TEXT | 文章全文内容 | 优先取 RSS `<content:encoded>`（CDATA 格式）；若无则抓取网页正文；再无则用 rss_summary |
| `content_source` | TEXT | content 字段的内容来源 | `rss_full_content`（来自 RSS content:encoded）/ `web_extracted`（抓取网页）/ `rss_summary`（降级为 description）/ NULL |
| `status` | TEXT NOT NULL | 当前处理状态 | `fetched` → `parsed` → `analyzed` → `assigned` → `ignored` / `failed`，由各处理阶段更新 |
| `importance_score` | REAL | AI 评估的重要性分数 (0~1) | 由 ArticleAnalysisService 分析后写入，完成分析前为 NULL |
| `error_message` | TEXT | 最近一次处理错误信息 | 处理失败时记录，通常是 JSON 解码错误 |
| `created_at` | TEXT NOT NULL | 首次抓取时间 | 创建记录时的时间戳 |
| `updated_at` | TEXT NOT NULL | 最近一次更新时间 | 每次更新 article 记录时刷新 |

### 处理状态流转

```
fetched  →  parsed  →  analyzed  →  assigned
    ↓         ↓          ↓           ↓
  (跳过)   (跳过)    (失败重试)  (失败重试)
              ↓
            failed  (内容截断/解析失败)
```

### 已知数据问题

`content:encoded` 中使用 CDATA 的 RSS 源（如雪球），FeedKit 解析时可能发生 CDATA 边界丢失，导致 content 被截断（结尾的 `]]>` 丢失），进而导致后续 AI 分析时 LLM 输出不完整 JSON 而解析失败。

根本原因是 maxTokens 设置得太小，为 1200，导致 LLM 输出被截断。           

---

## article_analyses — AI 分析结果

存储 AI 对文章进行结构化分析后的输出结果，一个文章只有一条分析记录。

**Prompt 文件：** `Packages/RSSRadarAI/Sources/RSSRadarAI/Prompts/ArticleAnalysisPrompt.md`

### 字段

| 字段 | 类型 | 说明 | 产生方式 |
|------|------|------|----------|
| `id` | TEXT PRIMARY KEY | 分析记录 id (UUID) | ArticleAnalysisService 生成 |
| `article_id` | TEXT NOT NULL, UNIQUE, FK | 关联的文章 id | ArticleAnalysisService 写入时关联 |
| `summary` | TEXT NOT NULL | 文章一段式摘要 | AI 根据 `content` 生成 |
| `key_points_json` | TEXT NOT NULL | 关键论点列表 (JSON 数组) | AI 从 `content` 中提取 |
| `entities_json` | TEXT NOT NULL | 提到的实体列表 (JSON 数组) | AI 识别 `content` 中的公司/人/产品/技术/政策/市场实体 |
| `claims_json` | TEXT NOT NULL | 事实性声明列表 (JSON 数组) | AI 从 `content` 中提取论断 |
| `events_json` | TEXT NOT NULL | 提到的事件列表 (JSON 数组) | AI 识别文章描述的具体事件 |
| `metrics_json` | TEXT NOT NULL | 数据指标列表 (JSON 数组) | AI 提取 `content` 中的数字/百分比/规模等量化数据 |
| `content_type` | TEXT NOT NULL | 文章内容类型 | AI 判断，`news` / `analysis` / `opinion` / `tutorial` / `announcement` |
| `possible_topics_json` | TEXT NOT NULL | 关联主题候选列表 (JSON 数组) | AI 从 `content` 中提取可追踪的具体主题 |
| `importance_score` | REAL NOT NULL | AI 评估的重要性分数 (0~1) | AI 给出，存储到 article.importance_score |
| `model_name` | TEXT NOT NULL | 执行分析的模型名称 | 从配置读取（如 `deepseek-v4-pro`） |
| `generated_at` | TEXT NOT NULL | 分析完成时间 | AI 分析完成时的时间戳 |

---

## topics — 主题

从文章中自动提取的主题候选，每条代表一个潜在的投资/新闻议题。

**Prompt 文件：** `Packages/RSSRadarAI/Sources/RSSRadarAI/Prompts/TopicAssignmentPrompt.md`

主题由 `TopicAssignmentService` 根据多个文章的 AI 分析结果批量生成。AI 综合文章的 `summary`、`key_points`、`entities` 等字段，推理出新的主题候选名称、描述和相关实体。

### 字段

| 字段 | 类型 | 说明 | 产生方式 |
|------|------|------|----------|
| `id` | TEXT PRIMARY KEY | 主题 id (UUID) | TopicAssignmentService 生成 |
| `name` | TEXT NOT NULL | 主题显示名称 | AI 推理生成，对应 `new_topic_name` |
| `normalized_name` | TEXT NOT NULL | 小写规范化名称 | 由 name 字段小写化并去除标点符号后计算得出，非 AI 生成 |
| `description` | TEXT NOT NULL | 主题描述 | AI 推理生成，对应 `new_topic_description` |
| `original_ai_name` | TEXT | AI 原始名称 | 与 name 相同，保留 AI 生成时的原始版本 |
| `original_ai_description` | TEXT | AI 原始描述 | 与 description 相同，保留 AI 生成时的原始版本 |
| `entities_json` | TEXT NOT NULL | 主题相关实体列表 (JSON 数组) | AI 从关联文章中提取，对应 `new_topic_entities` |
| `status` | TEXT NOT NULL | 主题状态 | 系统默认 `candidate`（待确认），用户确认后改为 `active` |
| `importance_score` | REAL | 主题重要性分数 (0~1) | AI 推理给出，对应 `new_topic_importance_score` |
| `created_at` | TEXT NOT NULL | 创建时间 | 创建记录时的时间戳 |
| `updated_at` | TEXT NOT NULL | 更新时间 | 每次更新时刷新 |

---

## topic_articles — 主题与文章的关联

表示文章与主题之间的多对多关系，记录每篇文章对主题的贡献程度。

**AI 生成说明：** `confidence`、`reason`、`contribution_type` 三个字段由 `TopicAssignmentService` 的 LLM 推理输出生成。

### 字段

| 字段 | 类型 | 说明 | 产生方式 |
|------|------|------|----------|
| `topic_id` | TEXT NOT NULL, FK, PK | 关联的主题 id | 系统根据 AI 分配结果写入 |
| `article_id` | TEXT NOT NULL, FK, PK | 关联的文章 id | 系统根据 AI 分配结果写入 |
| `confidence` | REAL NOT NULL | 置信度 (0~1) | AI 推理给出，对应 LLM 输出的 `confidence` |
| `reason` | TEXT NOT NULL | 关联原因说明 | AI 推理给出，对应 LLM 输出的 `reason` |
| `contribution_type` | TEXT NOT NULL | 贡献类型 | AI 推理给出，`new_event` / `new_opinion` / `new_data` / `background` |
| `created_at` | TEXT NOT NULL | 创建时间 | 分配时的时间戳 |

---

## topic_briefs — 主题简报

为主题生成的全景简报，包含主题当前要点、动态变化、时间线、观点对比等结构化信息。

**Prompt 文件：** `brief_type = full` 时为 `TopicBriefPrompt.md`；`brief_type = preview` 时为 `CandidateTopicPreviewPrompt.md`。文件位于 `Packages/RSSRadarAI/Sources/RSSRadarAI/Prompts/`。

### 字段

| 字段 | 类型 | 说明 | 产生方式 |
|------|------|------|----------|
| `id` | TEXT PRIMARY KEY | 简报 id (UUID) | TopicBriefGenerationService 生成 |
| `topic_id` | TEXT NOT NULL, FK | 所属主题 id | 调用方指定，系统写入 |
| `brief_type` | TEXT NOT NULL | 简报类型 | 调用方指定，`full` / `preview` |
| `current_takeaway` | TEXT NOT NULL | 主题当前核心要点 | AI 推理生成 |
| `latest_changes_json` | TEXT NOT NULL | 最近动态变化 (JSON) | AI 从最新关联文章中提取 |
| `timeline_json` | TEXT NOT NULL | 主题时间线 (JSON) | AI 综合整理 |
| `viewpoints_json` | TEXT NOT NULL | 不同观点对比 (JSON) | AI 从文章中梳理不同立场 |
| `evidence_json` | TEXT NOT NULL | 支持证据列表 (JSON) | AI 从文章中提取 |
| `questions_to_watch_json` | TEXT NOT NULL | 值得关注的开放问题 (JSON) | AI 提出 |
| `related_article_ids_json` | TEXT NOT NULL | 相关文章 id 列表 (JSON) | AI 从关联文章中提取 |
| `model_name` | TEXT NOT NULL | 生成简报的模型名称 | 从 LLM 响应读取 |
| `generated_at` | TEXT NOT NULL | 生成时间 | 生成时的时间戳 |

每个主题每种 `brief_type` 只允许一条记录（通过 UNIQUE 约束）。

---

## app_settings — 应用配置

存储用户配置的应用级参数，整个应用只有一条记录（id = 'default'）。

### 字段

| 字段 | 类型 | 说明 | 产生方式 |
|------|------|------|----------|
| `id` | TEXT PRIMARY KEY | 固定为 'default' | 初始化时固定写入 |
| `ai_provider` | TEXT NOT NULL | AI Provider 类型 | `openai_compatible` / `anthropic` / `custom`，用户配置 |
| `base_url` | TEXT NOT NULL | AI API Base URL | 用户配置 |
| `model_name` | TEXT NOT NULL | 使用的模型名称 | 用户配置 |
| `database_path` | TEXT | 数据库文件路径 | 初始化时写入 |
| `keychain_account_identifier` | TEXT | Keychain 中存储 API Key 的账户标识符 | 用户配置 API Key 后由系统写入 |
| `scan_mode` | TEXT NOT NULL | 扫描触发模式 | `manual`（手动）/ `on_launch`（启动时）/ `interval`（定时），用户配置 |
| `scan_interval_hours` | INTEGER NOT NULL | 定时扫描间隔（小时） | 用户配置，仅 interval 模式生效 |
| `max_articles_per_scan` | INTEGER NOT NULL | 每次扫描最多处理文章数 | 用户配置 |
| `max_articles_for_new_feed` | INTEGER NOT NULL | 新 Feed 首次扫描最多导入文章数 | 用户配置 |
| `max_articles_per_topic_batch` | INTEGER NOT NULL | 每次主题简报生成最多使用的文章数 | 用户配置 |
| `ai_request_timeout_seconds` | INTEGER NOT NULL | AI 请求超时时间（秒） | 用户配置 |
| `updated_at` | TEXT NOT NULL | 更新时间 | 每次保存设置时刷新 |

---

## processing_jobs — 处理任务队列

管理所有异步处理任务（RSS 扫描、文章解析、AI 分析、主题分配等），实现任务调度和重试机制。

### 字段

| 字段 | 类型 | 说明 | 产生方式 |
|------|------|------|----------|
| `id` | TEXT PRIMARY KEY | 任务 id (UUID) | 创建任务时自动生成 |
| `job_type` | TEXT NOT NULL | 任务类型 | `fetch_feed` / `parse_article` / `analyze_article` / `assign_topics` / `generate_topic_brief` / `retry_failed_job` |
| `entity_type` | TEXT NOT NULL | 任务关联的实体类型 | `feed` / `article` / `topic` / `topic_brief` / `job` |
| `entity_id` | TEXT | 任务关联的实体 id | 根据 entity_type 指向具体实体的 id |
| `payload_json` | TEXT NOT NULL | 任务参数 (JSON) | 调度任务时将参数序列化后存储 |
| `status` | TEXT NOT NULL | 任务状态 | `pending`（等待执行）/ `running`（执行中）/ `completed`（成功）/ `failed`（失败） |
| `priority` | INTEGER NOT NULL DEFAULT 0 | 优先级，数值越大越先执行 | 创建任务时指定 |
| `attempt_count` | INTEGER NOT NULL DEFAULT 0 | 已尝试次数 | 每次执行后递增 |
| `max_attempts` | INTEGER NOT NULL DEFAULT 3 | 最大重试次数 | 创建任务时指定 |
| `last_error_message` | TEXT | 最近一次失败错误信息 | 任务失败时记录 |
| `scheduled_at` | TEXT NOT NULL | 计划执行时间 | 创建任务时设定 |
| `started_at` | TEXT | 实际开始执行时间 | 任务被 worker 取出执行时写入 |
| `finished_at` | TEXT | 执行完成时间 | 任务完成（成功或失败）时写入 |
| `created_at` | TEXT NOT NULL | 任务创建时间 | 创建时的时间戳 |
| `updated_at` | TEXT NOT NULL | 任务更新时间 | 每次更新状态时刷新 |

---

## operation_logs — 操作日志

记录应用运行期间的重要事件和错误，用于问题排查和审计。

### 字段

| 字段 | 类型 | 说明 | 产生方式 |
|------|------|------|----------|
| `id` | TEXT PRIMARY KEY | 日志记录 id (UUID) | 记录日志时自动生成 |
| `level` | TEXT NOT NULL | 日志级别 | `info`（正常事件）/ `warning`（警告）/ `error`（错误） |
| `message` | TEXT NOT NULL | 日志消息 | 记录时提供的描述文本 |
| `context_json` | TEXT NOT NULL | 上下文附加数据 (JSON) | 记录时附加的上下文信息（如 stack trace、相关 id 等） |
| `created_at` | TEXT NOT NULL | 日志产生时间 | 记录时的时间戳 |

---

## user_corrections — 用户纠正记录

记录用户对 AI 自动分配结果的修正，用于持续优化主题分配质量。

### 字段

| 字段 | 类型 | 说明 | 产生方式 |
|------|------|------|----------|
| `id` | TEXT PRIMARY KEY | 纠正记录 id (UUID) | 用户操作时自动生成 |
| `correction_type` | TEXT NOT NULL | 纠正类型 | `remove_article_from_topic`（从主题移除文章）/ `add_article_to_topic`（添加文章到主题）/ `create_topic_from_article`（从文章创建新主题） |
| `topic_id` | TEXT (FK, nullable) | 关联的主题 id | 根据 correction_type 填写 |
| `article_id` | TEXT (FK, nullable) | 关联的文章 id | 根据 correction_type 填写 |
| `old_value` | TEXT | 旧值（被替换/删除的内容） | 根据 correction_type 填写 |
| `new_value` | TEXT | 新值（替换/新增的内容） | 根据 correction_type 填写 |
| `created_at` | TEXT NOT NULL | 纠正操作时间 | 操作时的时间戳 |

---

## 索引

| 索引名 | 作用于 | 用途 |
|--------|--------|------|
| `idx_articles_feed_id` | `articles(feed_id)` | 按 Feed 快速查询文章 |
| `idx_articles_published_at` | `articles(published_at)` | 按发布时间排序和筛选 |
| `idx_article_analyses_article_id` | `article_analyses(article_id)` | 按文章查找分析结果 |
| `idx_topics_status` | `topics(status)` | 按状态筛选主题候选 |
| `idx_topic_articles_article_id` | `topic_articles(article_id)` | 按文章查找关联主题 |
| `idx_topic_briefs_topic_id` | `topic_briefs(topic_id)` | 按主题查找简报 |
| `idx_processing_jobs_status_schedule` | `processing_jobs(status, scheduled_at)` | 任务队列调度查询 |
| `idx_processing_jobs_entity` | `processing_jobs(entity_type, entity_id)` | 按实体查找关联任务 |
| `idx_operation_logs_created_at` | `operation_logs(created_at)` | 按时间查询日志 |
| `idx_user_corrections_topic_id` | `user_corrections(topic_id)` | 按主题查找纠正记录 |
| `idx_user_corrections_article_id` | `user_corrections(article_id)` | 按文章查找纠正记录 |