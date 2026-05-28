针对目前的产品 UI，需要做如下优化：
1. 使用目录下的icon.png，作为应用图标；
2. 去掉 Today 这个 tab；
3. 界面上全部使用中文，对照翻译如下：
- Topics：主题聚合
- Feeds：内容源配置
- Processing：处理日志
- Settings：通用配置
- Topics status：All：全部，Candidate：待确认主题，Active：跟踪主题，Ignored：忽略主题
- Track：跟踪，Ignore：忽略
4. 在 Topic 的 tab 里，最上方请给出一段文字说明如下：
待确认主题：AI发现的潜在主题，你可以点击「跟踪」或「忽略」。
跟踪主题：AI持续观察跟踪。
忽略主题：你不感兴趣的主题。
5. Feeds的 tab里，请显性划分两个区域，上部区域是添加源，下部区域是对当前源进行管理，refresh：手动刷新，delete：删除，去掉 pause 这个按钮
6. Topic 的 tab 里，去除掉 achived 这个状态
7. setting 的 tab 里，AI 板块分为两部分，上半部分用来填写新配置，下半部分限制当前的配置，注明url 和 model