# RSSRadar MVP 产品设计文档

## 1. 文档目的

RSSRadar 是一款本地优先的 Mac RSS 主题情报工具。它不是传统 RSS Reader，也不是单篇文章摘要工具，而是帮助用户把大量 RSS 文章自动整理成可持续追踪的具体主题情报页。

MVP 的核心目标是验证：

> 用户是否愿意从“逐篇阅读 RSS 文章”切换到“按具体主题消费情报”。

---

## 2. 产品形态与总体约束

## 2.1 产品形态

RSSRadar MVP 是一款原生 Mac 桌面应用。

技术形态：

- 原生 macOS App；
- 使用 Swift / SwiftUI 开发；
- 本地运行；
- 不依赖开发者服务器；
- 不提供 Web 端、移动端或浏览器插件。

## 2.2 MVP 明确不做

MVP 不提供：

- 用户登录；
- 用户账号；
- 云端同步；
- 云端数据库；
- 团队协作；
- 多设备同步；
- 服务端 AI 中转；
- 服务端任务队列；
- 云端备份；
- RSS 源市场；
- 推荐系统；
- 通知系统；
- 付费系统；
- 移动端；
- 浏览器插件；
- Notion / Obsidian 自动同步；
- PDF 导出；
- AI 问答；
- 知识图谱；
- 主题自动合并 / 拆分。

## 2.3 本地优先原则

所有用户数据默认保存在本地，包括：

- RSS 源配置；
- RSS 抓取进度；
- 文章元数据；
- 文章正文或摘要；
- AI 分析结果；
- 候选主题；
- 追踪主题；
- 文章与主题的关联关系；
- 主题情报页缓存；
- 用户设置；
- 导出记录。

应用不上传用户数据到开发者服务器。

---

## 3. 目标用户

## 3.1 投资 / 行业研究用户

订阅大量行业媒体、公司公告、研究博客，希望快速知道某个公司、行业、政策或市场主题最近发生了什么变化。

典型需求：

- 跟踪公司基本面变化；
- 跟踪行业竞争格局；
- 跟踪政策变化；
- 汇总不同来源观点；
- 提取关键证据和后续观察点。

## 3.2 内容创作者

从大量信息源中发现选题、观点冲突和可写素材。

典型需求：

- 发现新选题；
- 汇总不同观点；
- 找到争议点；
- 提炼可写角度；
- 导出 Markdown 作为写作素材。

## 3.3 技术学习 / 技术研究用户

订阅技术博客、产品更新、开源项目动态，希望自动沉淀技术主题和学习笔记。

典型需求：

- 追踪技术趋势；
- 汇总产品更新；
- 跟踪开源项目动态；
- 梳理技术讨论脉络。

---

## 4. MVP 核心体验

## 4.1 用户核心闭环

```text
导入 RSS 源
→ 配置 AI API Key
→ 扫描 RSS 文章
→ 抓取并解析文章
→ AI 单篇文章理解
→ AI 批量生成 / 匹配具体主题
→ 用户确认、忽略或修改候选主题
→ 生成主题情报页
→ 用户阅读或导出 Markdown
```

## 4.2 产品核心对象

MVP 围绕五个核心对象设计：


| 对象              | 说明              |
| --------------- | --------------- |
| Feed            | 用户添加或导入的 RSS 源  |
| Article         | 从 RSS 源抓取到的文章   |
| ArticleAnalysis | AI 对单篇文章的结构化理解  |
| Topic           | AI 生成或用户确认的具体主题 |
| TopicBrief      | 围绕某个主题生成的情报页缓存  |


## 4.3 MVP 成功标准

MVP 需要让用户完成以下行为：

1. 成功导入 RSS 源；
2. 成功配置自己的 AI API Key；
3. 成功抓取一批文章；
4. 成功生成候选主题；
5. 用户能判断候选主题是否值得追踪；
6. 用户能打开主题情报页并获得价值；
7. 用户能把主题情报导出为 Markdown。

---

## 5. 信息架构

## 5.1 主导航

建议使用 macOS 常见侧边栏结构：

```text
RSSRadar
├── Today
├── Topics
│   ├── Active Topics
│   ├── Candidate Topics
│   └── Archived / Ignored Topics
├── Feeds
├── Processing
└── Settings
```

## 5.2 页面说明


| 页面           | 作用                                   |
| ------------ | ------------------------------------ |
| Today        | 展示今日重要主题、新候选主题、追踪主题更新和扫描状态           |
| Topics       | 管理所有主题，包括追踪中、候选、忽略、归档                |
| Topic Detail | 查看主题情报页和相关文章                         |
| Feeds        | 管理 RSS 源、查看抓取状态、手动刷新                 |
| Processing   | 查看文章处理状态、失败任务、重试入口                   |
| Settings     | 配置 AI Provider、API Key、模型、扫描频率、数据目录等 |


---

## 6. Onboarding 设计

## 6.1 目标

首次使用时让用户完成三件事：

1. 导入或添加 RSS 源；
2. 配置 AI API Key；
3. 启动首次扫描。

## 6.2 Onboarding 流程

```text
欢迎页
→ 说明产品定位
→ 导入 OPML 或手动添加 RSS 源
→ 配置 AI Provider / API Key / Model
→ 设置单次处理文章上限
→ 启动首次扫描
→ 展示扫描与 AI 处理进度
→ 展示第一批候选主题
```

## 6.3 欢迎页文案重点

需要明确告诉用户：

- RSSRadar 不是普通 RSS Reader；
- 它按具体主题组织信息；
- AI 调用使用用户自己的 API Key；
- API Key 只保存在本地并加密存储；
- 所有数据默认保存在本地；
- MVP 不提供云端同步。

---

## 7. RSS 源管理设计

## 7.1 支持能力

MVP 支持：


| 功能         | 优先级 | 说明                                       |
| ---------- | --- | ---------------------------------------- |
| 手动添加 RSS 源 | P0  | 用户输入 RSS URL，应用解析 Feed 信息                |
| OPML 导入    | P0  | 支持从其他 RSS Reader 批量迁移                    |
| 删除 RSS 源   | P0  | 删除源后不再抓取新文章                              |
| 查看源状态      | P0  | 显示 active / error / paused / no_articles |
| 手动刷新源      | P0  | 用户可单独刷新某个源                               |
| 全局手动扫描     | P0  | 用户可触发所有源扫描                               |
| 扫描频率设置     | P0  | 支持手动、启动时、每 N 小时                          |


## 7.2 RSS 源状态

Feed 状态建议包括：

```text
active       正常
error        最近抓取失败
paused       用户暂停
no_articles  暂无文章
```

## 7.3 RSS 抓取进度

每个 RSS 源需要维护：

- `last_processed_article_published_at`
- `last_checked_at`
- `last_success_at`
- `last_error_message`

单次扫描规则：

1. 如果该源已有 `last_processed_article_published_at`：
  - 从该时间戳之后的新文章开始处理；
  - 一直处理到当前源的最新文章。
2. 如果该源没有处理记录：
  - 视为新源；
  - 最多抓取最近 20 篇文章。
3. 同一文章通过 URL 与标题相似度进行基础去重。
4. 抓取完成后更新该源的处理进度。

## 7.4 MVP 不做

- RSS 源分组；
- RSS 源评分；
- OPML 导出；
- RSS 源市场；
- 复杂源健康检测；
- 推荐 RSS 源；
- 高级源过滤规则。

---

## 8. 文章抓取与解析设计

## 8.1 抓取策略

文章内容获取优先级：

1. 优先使用 RSS Feed 中提供的完整内容；
2. 如果 RSS 只有摘要，则尝试抓取网页正文；
3. 如果网页正文抓取失败，则降级使用 RSS 摘要；
4. 遇到 paywall、反爬、JS 渲染失败时，不做复杂浏览器渲染；
5. 不使用无头浏览器作为 MVP 默认能力。

## 8.2 文章字段

文章需要保存：

- 标题；
- URL；
- 来源 Feed；
- 作者；
- 发布时间；
- RSS 摘要；
- 正文内容；
- 正文获取方式；
- 处理状态；
- AI 摘要；
- 重要性分数；
- 创建时间；
- 更新时间。

## 8.3 文章状态

```text
fetched    已从 RSS 获取元数据
parsed     已解析正文或摘要
analyzed   已完成 AI 单篇理解
assigned   已完成主题归类
ignored    被用户或系统忽略
failed     处理失败
```

## 8.4 失败处理

当文章处理失败时：

- 保留失败状态；
- 记录错误信息；
- 允许用户手动重试；
- 不阻塞其他文章处理；
- 不影响已生成的主题情报页。

---

## 9. AI Provider 设计

## 9.1 支持范围

MVP UI 支持三类 AI Provider：


| Provider          | 说明                    |
| ----------------- | --------------------- |
| OpenAI-compatible | 支持 OpenAI API 格式的模型服务 |
| Anthropic         | 支持 Anthropic API      |
| Custom Base URL   | 用户自定义兼容服务地址           |


内部统一抽象为：

```swift
protocol AIProvider {
    func complete(request: AICompletionRequest) async throws -> AICompletionResponse
}
```

## 9.2 用户配置项

设置页需要支持：

- Provider；
- API Key；
- Base URL；
- Model Name；
- 单次处理文章上限；
- 请求超时时间；
- 是否启用启动时扫描；
- 每 N 小时扫描频率。

## 9.3 API Key 存储

API Key 要求：

- 只保存在用户本地；
- 优先使用 macOS Keychain；
- 不进入 SQLite 明文存储；
- 不上传开发者服务器；
- 用户可随时删除或替换。

## 9.4 Prompt 策略

MVP 不开放复杂 Prompt 编辑。

设计原则：

- Prompt 由产品内置；
- 按任务类型维护模板；
- 输出要求结构化 JSON；
- 失败时允许重试；
- 后续版本再考虑高级 Prompt 配置。

---

## 10. AI 处理流程设计

## 10.1 整体流程

```text
新文章进入处理队列
→ 提取标题 / 摘要 / 正文 / 来源 / 时间
→ 单篇文章 AI 理解
→ 保存 ArticleAnalysis
→ 批量基于新文章分析主题
→ 匹配已有主题或生成候选主题
→ 建立 ArticleTopic 关联
→ 为 active topic 预生成 TopicBrief
→ 为 candidate topic 生成简版预览
```

## 10.2 单篇文章理解

输入：

- title；
- source；
- published_at；
- rss_summary；
- content；
- url。

输出：

```json
{
  "summary": "文章核心摘要",
  "key_points": ["关键点 1", "关键点 2"],
  "entities": ["公司", "产品", "人物", "技术", "政策"],
  "claims": ["文章中的核心判断"],
  "events": ["文章提到的关键事件"],
  "metrics": ["文章提到的重要数据"],
  "content_type": "news / analysis / opinion / tutorial / announcement",
  "possible_topics": ["候选主题 1", "候选主题 2"],
  "importance_score": 0.8
}
```

## 10.3 主题生成 / 匹配

主题处理采用两阶段：

### 阶段一：单篇文章理解

每篇文章先被结构化理解，提取实体、事件、观点、指标和候选主题。实体提取应优先覆盖公司、人物、产品、行业、资产、技术、政策和事件等维度；候选主题应作为后续聚合的少量实体或维度锚点，不应简单复制全部实体。

### 阶段二：批量主题生成 / 匹配

基于一批新文章与已有主题，AI 判断：

1. 文章是否属于已有主题；
2. 是否应该生成新候选主题；
3. 一篇文章可归入一个或多个主题；
4. 每个归类结果需要给出置信度和理由；
5. 新主题必须能作为后续文章复用的聚合锚点。

## 10.4 主题命名规则

主题生成应优先围绕可复用的实体或维度锚点，而不是单篇文章的细颗粒角度。公司、人物、产品、行业、资产、技术、政策和事件等维度平等对待，哪个维度最能承载后续文章聚合，就使用哪个维度命名。

AI 可以生成公司、人物、产品、行业、资产、技术、政策或事件主题，例如：

- 腾讯；
- ChatGPT；
- 半导体；
- AI 监管；
- 比特币；
- Claude Code；
- 美加墨世界杯。

AI 不应优先生成只服务单篇文章的细主题，例如：

- OpenAI 数据中心开支与盈利压力；
- 茅台批价下跌对渠道利润的影响；
- Claude Code 与 Codex 的开发者采用竞争；
- AI 服务跨境数据合规压力。

主题命名建议优先遵循：

```text
公司 / 人物 / 产品 / 行业 / 资产 / 技术 / 政策 / 事件
```

只有当文章确实围绕一个可持续追踪的具体事件，且没有更合适的公司、人物、产品、行业、资产、技术或政策锚点时，才使用事件型主题。

## 10.5 文章归类输出

```json
{
  "article_id": "article_id",
  "topic_id": "topic_id",
  "confidence": 0.87,
  "reason": "文章讨论 Claude Code 在大型代码库中的多文件编辑表现，符合该主题范围。",
  "contribution_type": "new_event / new_opinion / new_data / background"
}
```

## 10.6 用户纠错能力

MVP 支持：

- 从主题中移除文章；
- 将文章加入已有主题；
- 基于文章创建新主题；
- 修改主题名称；
- 修改主题描述；
- 忽略候选主题；
- 追踪候选主题；
- 重新分析文章；
- 重新生成主题情报页。

MVP 暂不支持：

- 自动学习所有用户纠错偏好；
- 复杂 include / exclude rules；
- 主题自动合并；
- 主题自动拆分；
- 复杂实体关系图。

---

## 11. 主题设计

## 11.1 主题状态

```text
candidate  候选主题
active     用户追踪中的主题
ignored    用户忽略的主题
archived   用户归档的主题
```

## 11.2 候选主题

候选主题由 AI 生成。

用户可以：

- 查看候选主题；
- 预览简版情报；
- 追踪主题；
- 忽略主题；
- 修改主题名称；
- 修改主题描述；
- 查看相关文章。

候选主题只提供简版预览，不进行持续更新。

## 11.3 Active Topic

用户点击“追踪”后，candidate topic 变为 active topic。

Active topic 会：

- 在后续扫描中参与文章匹配；
- 持续更新相关文章；
- 在扫描处理完成后预生成完整 TopicBrief；
- 出现在 Today 的“今日重要主题”与“追踪主题更新”中。

## 11.4 用户改名后的影响

用户修改主题名称或描述后：

- 保存用户修改后的版本；
- 后续 AI 归类使用修改后的主题名和描述；
- 原始 AI 生成名称可选保存为内部字段，便于调试；
- UI 默认只显示用户修改后的版本。

---

## 12. 主题情报页设计

## 12.1 生成策略

TopicBrief 采用预生成并缓存的方式。

规则：

1. 扫描处理完成后，为 active topic 预生成完整 TopicBrief；
2. 为 candidate topic 生成简版预览；
3. 用户打开主题时优先展示缓存内容；
4. 用户可以点击“重新生成”；
5. 重新生成失败时保留旧版本；
6. 每次生成记录 `generated_at`；
7. TopicBrief 默认使用中文生成。

## 12.2 页面结构

```markdown
# 主题名称

## 当前结论
一句话说明这个主题当前最重要的判断。

## 最近发生了什么
总结最近新增文章带来的关键变化。

## 时间线
按时间顺序整理主题演变。

## 主要观点分歧
聚类不同来源的观点，而不是简单罗列文章。

## 关键证据
列出重要数据、事实、案例。每条关键证据需要关联来源文章。

## 接下来值得观察
列出后续需要继续跟踪的问题。

## 相关文章
展示标题、来源、发布时间、AI 摘要、贡献类型、原文链接。
```

## 12.3 关键证据设计

每条关键证据需要包含：

- 证据内容；
- 来源文章 ID；
- 来源文章标题；
- 来源名称；
- 原文链接；
- 发布时间。

MVP 不做：

- 句子级引用；
- 复杂 footnote；
- 自动事实核查；
- 多来源证据可信度评分。

## 12.4 相关文章列表

相关文章列表只显示：

- 标题；
- 来源；
- 发布时间；
- AI 摘要；
- 贡献类型；
- 原文链接。

不做完整文章阅读器体验。

---

## 13. Today 首页设计

## 13.1 页面目标

用户打开 App 后，优先看到值得关注的主题，而不是未读文章列表。

## 13.2 页面模块


| 模块     | 说明                 |
| ------ | ------------------ |
| 今日重要主题 | 展示 active topic    |
| 新候选主题  | 展示 candidate topic |
| 追踪主题更新 | 展示用户已追踪主题的最新变化     |
| 扫描状态   | 展示最近扫描时间、处理文章数、失败数 |


## 13.3 排序规则

首页排序依据：

1. 最近更新时间；
2. 主题重要度；
3. 新增文章数；
4. 是否为用户追踪主题。

建议实现一个简单排序分数：

```text
score =
  recency_score * 0.35
+ importance_score * 0.30
+ new_article_count_score * 0.20
+ active_topic_bonus * 0.15
```

MVP 阶段该分数只作为排序辅助，不需要向用户解释复杂算法。

## 13.4 今日重要主题

只展示 active topic。

每个卡片展示：

- 主题名称；
- 当前结论；
- 最近变化摘要；
- 新增文章数；
- 最近更新时间；
- 打开详情按钮。

## 13.5 新候选主题

只展示 candidate topic。

每个卡片展示：

- 主题名称；
- 简短描述；
- 相关文章数量；
- 主要来源；
- 追踪；
- 忽略；
- 改名。

---

## 14. Markdown 导出设计

## 14.1 导出范围

MVP 只支持：

- 复制当前主题情报为 Markdown；
- 导出当前主题情报为 Markdown 文件。

不支持：

- 自动同步到文件夹；
- Notion 同步；
- Obsidian 自动同步；
- PDF 导出；
- 富文本复制；
- 每日简报导出。

## 14.2 导出内容

导出的 Markdown 包含：

- 主题名；
- 生成时间；
- 当前结论；
- 最近发生了什么；
- 时间线；
- 主要观点分歧；
- 关键证据；
- 接下来值得观察；
- 相关文章链接。

## 14.3 Markdown 模板

```markdown
# {{topic_name}}

生成时间：{{generated_at}}

## 当前结论

{{current_takeaway}}

## 最近发生了什么

{{latest_changes}}

## 时间线

{{timeline}}

## 主要观点分歧

{{viewpoints}}

## 关键证据

{{evidence}}

## 接下来值得观察

{{questions_to_watch}}

## 相关文章

{{related_articles}}
```

---

## 15. 设置页设计

## 15.1 设置项


| 设置项          | 说明                                     |
| ------------ | -------------------------------------- |
| API Provider | OpenAI-compatible / Anthropic / Custom |
| API Key      | 用户自备，保存在 Keychain                      |
| Base URL     | 支持自定义模型服务地址                            |
| Model Name   | 用户填写或选择模型名称                            |
| 数据存储位置       | SQLite 数据库路径                           |
| 扫描频率         | 手动 / 启动时 / 每 N 小时                      |
| 单次处理文章上限     | 控制 AI 调用成本                             |
| 请求超时时间       | 控制 AI 请求等待时间                           |
| 清空本地数据       | 删除本地文章、主题和分析结果                         |


清空本地数据必须提供保守确认。默认只清除本地业务数据，不默认删除 Keychain 中的 API Key；只有用户明确勾选时才删除 API Key。

## 15.2 成本控制设置

用户可配置：

- 单次扫描最多处理文章数；
- 单次 AI 批处理文章数；
- 是否只处理最近 N 天文章；
- AI 请求超时时间。

MVP 默认建议：


| 设置              | 默认值   |
| --------------- | ----- |
| 新源最多抓取文章数       | 20    |
| 单次扫描最多 AI 分析文章数 | 100   |
| 单次主题生成批处理文章数    | 20    |
| AI 请求超时         | 120 秒 |


---

## 16. 本地数据设计

## 16.1 存储方案

MVP 使用：

- SQLite 存结构化数据；
- macOS Keychain 存 API Key；
- Markdown 文件仅用于用户主动导出；
- 不直接把内部知识库维护成 Markdown 文件。

## 16.2 Feed

```json
{
  "id": "feed_id",
  "title": "Feed title",
  "url": "https://example.com/rss.xml",
  "site_url": "https://example.com",
  "status": "active / error / paused / no_articles",
  "last_checked_at": "...",
  "last_success_at": "...",
  "last_processed_article_published_at": "...",
  "error_message": null,
  "created_at": "...",
  "updated_at": "..."
}
```

## 16.3 Article

```json
{
  "id": "article_id",
  "feed_id": "feed_id",
  "title": "文章标题",
  "url": "https://example.com/article",
  "author": "作者",
  "published_at": "...",
  "rss_summary": "RSS 摘要",
  "content": "正文或摘要",
  "content_source": "rss_full_content / web_extracted / rss_summary",
  "status": "fetched / parsed / analyzed / assigned / ignored / failed",
  "importance_score": 0.8,
  "error_message": null,
  "created_at": "...",
  "updated_at": "..."
}
```

## 16.4 ArticleAnalysis

```json
{
  "id": "analysis_id",
  "article_id": "article_id",
  "summary": "文章核心摘要",
  "key_points": ["关键点 1", "关键点 2"],
  "entities": ["实体 1", "实体 2"],
  "claims": ["核心判断 1"],
  "events": ["关键事件 1"],
  "metrics": ["关键数据 1"],
  "content_type": "news / analysis / opinion / tutorial / announcement",
  "possible_topics": ["候选主题 1"],
  "importance_score": 0.8,
  "model_name": "model",
  "generated_at": "..."
}
```

## 16.5 Topic

```json
{
  "id": "topic_id",
  "name": "主题名称",
  "description": "主题描述",
  "original_ai_name": "AI 原始主题名",
  "original_ai_description": "AI 原始主题描述",
  "entities": ["实体 1", "实体 2"],
  "status": "candidate / active / ignored / archived",
  "importance_score": 0.8,
  "created_at": "...",
  "updated_at": "..."
}
```

## 16.6 TopicArticle

```json
{
  "topic_id": "topic_id",
  "article_id": "article_id",
  "confidence": 0.87,
  "reason": "归类理由",
  "contribution_type": "new_event / new_opinion / new_data / background",
  "created_at": "..."
}
```

## 16.7 TopicBrief

```json
{
  "id": "brief_id",
  "topic_id": "topic_id",
  "brief_type": "full / preview",
  "current_takeaway": "当前结论",
  "latest_changes": [],
  "timeline": [],
  "viewpoints": [],
  "evidence": [],
  "questions_to_watch": [],
  "related_article_ids": [],
  "model_name": "model",
  "generated_at": "..."
}
```

## 16.8 AppSettings

```json
{
  "ai_provider": "openai_compatible / anthropic / custom",
  "base_url": "https://api.example.com",
  "model_name": "model-name",
  "database_path": "...",
  "scan_mode": "manual / on_launch / interval",
  "scan_interval_hours": 6,
  "max_articles_per_scan": 100,
  "max_articles_for_new_feed": 20,
  "ai_request_timeout_seconds": 120
}
```

---

## 17. 核心流程详细设计

## 17.1 首次使用流程

```text
用户打开 App
→ 欢迎页说明产品定位
→ 用户导入 OPML 或添加 RSS 源
→ 应用解析 Feed 信息
→ 用户配置 AI Provider / API Key / Model
→ 用户设置处理上限
→ 用户点击首次扫描
→ 应用按新源规则抓取每个源最近最多 20 篇
→ 解析文章正文或摘要
→ 对文章做 AI 单篇理解
→ 批量生成 / 匹配候选主题
→ 展示候选主题
→ 用户追踪、忽略或改名
→ 为追踪主题生成完整 TopicBrief
→ 用户进入 Today 或 Topic Detail
```

## 17.2 日常扫描流程

```text
用户打开 App 或达到扫描间隔
→ 应用读取每个 Feed 的 last_processed_article_published_at
→ 抓取该时间戳之后的新文章
→ 去重
→ 解析文章内容
→ 进入 AI 分析队列
→ 单篇文章理解
→ 批量主题匹配 / 新候选主题生成
→ 更新 ArticleTopic 关系
→ 为 active topic 预生成 TopicBrief
→ 为 candidate topic 生成简版预览
→ 更新 Today
```

## 17.3 用户纠错流程

### 从主题移除文章

```text
用户打开 Topic Detail
→ 在相关文章中选择移除
→ 删除 TopicArticle 关系
→ 标记该操作记录
→ 提示用户是否重新生成 TopicBrief
```

### 将文章加入已有主题

```text
用户在文章列表中选择加入主题
→ 选择目标 Topic
→ 创建 TopicArticle 关系
→ 提示用户是否重新生成 TopicBrief
```

### 基于文章创建新主题

```text
用户选择文章
→ 点击创建新主题
→ 应用基于文章分析结果生成主题草稿
→ 用户确认名称和描述
→ 创建 active 或 candidate topic
→ 生成 TopicBrief
```

## 17.4 重新生成流程

### 重试文章分析

```text
用户在 Processing 或 Topic Detail 点击重试
→ 清除失败状态
→ 重新执行正文解析或 AI 分析
→ 保存新结果
→ 更新关联主题
```

### 重新生成主题情报页

```text
用户在 Topic Detail 点击重新生成
→ 应用读取该主题相关文章和分析结果
→ 调用 AI 生成新的 TopicBrief
→ 成功后替换缓存
→ 失败时保留旧版本并提示错误
```

---

## 18. 错误与空状态设计

## 18.1 无 RSS 源

提示用户：

- 导入 OPML；
- 手动添加 RSS URL；
- 说明需要 RSS 源才能开始。

## 18.2 未配置 API Key

提示用户：

- RSS 抓取可以进行；
- AI 分析、主题生成和情报页生成需要 API Key；
- 引导进入 Settings 配置。

## 18.3 AI 调用失败

展示：

- 失败原因；
- 模型名称；
- 失败时间；
- 重试按钮；
- 检查 API Key / Base URL / Model Name 的入口。

## 18.4 文章正文抓取失败

降级策略：

- 使用 RSS 摘要；
- 标记 `content_source = rss_summary`；
- 不阻塞 AI 分析；
- 在必要时提示“该文章仅基于 RSS 摘要分析”。

## 18.5 没有新文章

展示：

- 最近扫描时间；
- 所有源已是最新；
- 手动刷新按钮。

---

## 19. MVP UI 关键界面

## 19.1 Today

主要元素：

- 扫描状态卡片；
- 今日重要主题；
- 新候选主题；
- 追踪主题更新；
- 手动扫描按钮。

## 19.2 Topic Detail

主要元素：

- 主题标题；
- 状态标签；
- 重新生成按钮；
- 导出 Markdown；
- 当前结论；
- 最近变化；
- 时间线；
- 观点分歧；
- 关键证据；
- 后续观察点；
- 相关文章。

## 19.3 Candidate Topic Detail

主要元素：

- 候选主题名称；
- 简版情报预览；
- 相关文章；
- 追踪按钮；
- 忽略按钮；
- 改名入口。

## 19.4 Feeds

主要元素：

- RSS 源列表；
- 源状态；
- 最近扫描时间；
- 最近错误；
- 添加 RSS；
- OPML 导入；
- 删除源；
- 手动刷新。

## 19.5 Processing

主要元素：

- 待处理文章数；
- 分析中；
- 失败任务；
- 重试按钮；
- 单篇文章状态。

## 19.6 Settings

主要元素：

- AI Provider；
- API Key；
- Base URL；
- Model Name；
- 扫描频率；
- 处理上限；
- 数据库路径；
- 清空本地数据。

---

## 20. 非功能需求

## 20.1 性能

MVP 目标：

- App 启动后 2 秒内展示主界面；
- RSS 源列表和 Topic 列表本地查询应快速响应；
- AI 处理异步执行，不阻塞 UI；
- 大批量扫描时展示进度；
- 失败任务不阻塞整体队列。

## 20.2 隐私

要求：

- 不上传 RSS 源列表到开发者服务器；
- 不上传文章内容到开发者服务器；
- AI 调用直接从用户本机发起到用户配置的 Provider；
- API Key 存储在 Keychain；
- 用户可清空全部本地数据。

## 20.3 稳定性

要求：

- RSS 抓取失败可恢复；
- AI 调用失败可重试；
- TopicBrief 重新生成失败不覆盖旧版本；
- SQLite 数据库需要基础迁移机制；
- 应用异常退出后，处理队列可以恢复。

## 20.4 成本控制

要求：

- 支持单次处理文章上限；
- 新源默认最多抓取最近 20 篇；
- 重复文章不重复分析；
- 同一主题批量生成 TopicBrief；
- 尽量先用标题和摘要做轻量判断，再决定是否使用全文。

---

## 21. MVP 验收标准

## 21.1 Onboarding

- 用户可以完成 OPML 导入；
- 用户可以手动添加 RSS 源；
- 用户可以配置 OpenAI-compatible Provider；
- 用户可以配置 Anthropic Provider；
- 用户可以配置 Custom Base URL；
- API Key 成功保存到 Keychain；
- 用户可以启动首次扫描。

## 21.2 RSS 抓取

- 新源最多抓取最近 20 篇文章；
- 老源从 `last_processed_article_published_at` 之后抓取；
- 支持手动扫描；
- 支持启动时扫描；
- 支持每 N 小时扫描；
- 抓取失败会记录错误；
- 正文失败时可降级 RSS 摘要。

## 21.3 AI 分析

- 能完成单篇文章结构化理解；
- 能生成具体候选主题；
- 能将文章归入已有主题；
- 支持一篇文章归入多个主题；
- AI 失败后可重试；
- 用户可设置单次处理上限。

## 21.4 主题管理

- 用户可追踪候选主题；
- 用户可忽略候选主题；
- 用户可修改主题名称；
- 用户可修改主题描述；
- 用户改名后的主题名和描述会用于后续 AI 归类；
- 候选主题可预览简版情报；
- Active topic 可持续更新。

## 21.5 主题情报页

- Active topic 扫描后会预生成完整 TopicBrief；
- Candidate topic 可生成简版预览；
- 用户打开主题时优先展示缓存；
- 用户可手动重新生成；
- 关键证据能关联来源文章；
- 相关文章列表包含标题、来源、发布时间、AI 摘要、贡献类型、原文链接。

## 21.6 Markdown 导出

- 用户可复制主题情报为 Markdown；
- 用户可导出主题情报为 Markdown 文件；
- Markdown 包含主题名、生成时间、当前结论、时间线、观点分歧、关键证据、观察点和相关文章链接；
- 不做自动同步。

