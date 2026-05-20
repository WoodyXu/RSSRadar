# RSSRadar 架构决策

本文记录跨阶段、长期有效的实现决策。具体开发顺序见 `implementation-plan.md`，产品体验见 `design-document.md`，技术选型细节见 `tech-stack.md`。

## 工程结构

- 工程形态使用纯 Swift Package + macOS app target。
- 从一开始建立 macOS app target 和 internal packages，保持 UI、持久化、RSS 抓取、AI、处理队列、导出边界清晰。
- 部署目标固定为 macOS 14.0+。
- 写 UI 前必须读取仓库中的 `DESIGN.md`。
- MVP 初期不把 app icon、完整菜单等 macOS 打磨项作为核心阻塞项。

## 数据与持久化

- 所有领域对象 ID 统一使用 UUID string。
- SQLite 时间字段统一使用 ISO8601 text。
- 用户修改数据库路径时使用新路径新库，不迁移旧库。
- 删除 RSS Feed 使用硬删除，并级联删除该 feed 的文章、分析结果和主题关联。
- 清空本地数据默认清业务数据，不默认删除 Keychain API Key，除非用户明确勾选。

## RSS 与去重

- Article URL 去重需要做基础 canonicalization：host lowercase、移除 fragment、移除常见 tracking params。
- 标题相似度去重只在同一 feed 内执行。
- 新源最多 20 篇按发布时间倒序选取，缺少发布时间的文章排在后面。
- 如果 feed 中文章缺少 `published_at`，不得用它更新 `last_processed_article_published_at`。
- Feed 处理进度按已成功入库文章中的最新 `published_at` 更新，不等待 AI 分析完成。

## 本地处理队列

- App 启动恢复时，将遗留 `running` job 恢复为 `pending`，不额外增加 `attempt_count`。
- `max_attempts = 3`；第 3 次失败后标记 `failed`，等待用户手动重试。
- AI JSON 校验失败时，job 进入 retry 或 failed；article 保持上一稳定状态，最终不可恢复时标记 `failed` 并记录错误。

## AI 与主题

- TopicBrief 默认使用中文生成。
- OpenAI-compatible 默认 Base URL 为 `https://api.openai.com/v1`。
- Anthropic 默认 Base URL 为 `https://api.anthropic.com`。
- OpenAI-compatible 与 Custom Base URL 均按 Chat Completions 兼容格式实现。
- Prompt 模板放在 `Prompts/*.md` 资源文件中。
- Topic assignment 在单篇分析完成后按每批 20 篇生成或匹配主题。
- 宽泛主题名通过 Prompt 约束加本地最小规则校验处理，校验失败进入重试。
- Candidate topic 在同状态下按 normalized name 做简单去重。

## MVP 范围

- MVP 初期不做独立完整 Article Detail，相关操作先放在 Processing 和 Topic Detail。
- Onboarding 在阶段 8 实现；前面阶段允许通过功能页完成闭环。
