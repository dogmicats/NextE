# Implementation Plan: 全局高级搜索过滤（Global Search Filter）

**Input**: Feature specification from `spec/global-search-filter/spec.md`

## Summary

新增一组持久化的全局搜索过滤标签（与/或/非，EH 原生操作符语义）：用户配置一次并在总开关启用后，应用在**请求构建期**把该标签组合自动合并进画廊搜索与首页画廊类列表的 `f_search`；不污染搜索输入框、不写入搜索历史；提供总开关；配置入口两处（搜索页过滤面板内嵌编辑区 + 设置→搜索 的状态行与管理编辑页）。配置走现有 preferences 设置存储（自动随备份/恢复），页面缓存按过滤状态隔离，修改即时刷新已加载列表。

## Technical Context

**Language/Version**: ArkTS（项目现有 HarmonyOS 工程配置，`entry/` + `feature/*` + `shared/` 多模块）
**Primary Dependencies**: State Management V2（AppStorageV2 / @ObservedV2 / @Trace / @Monitor / @ComponentV2）、ArkData Preferences、现有 `TagQueryComposer`/`TagRow`/`TagQuery`（shared/components/TagQueryComposer.ets）、`EhApiService.getGalleryList` 的 `GalleryListQuery.search` → `f_search` 通路、`EhPageCacheService.homeProfileKey`
**State Management**: 仅 V2（项目硬性约束：`node scripts/test_v1_decorator_inventory_contract.mjs` 必须 `0 file(s)`，禁止任何 V1 装饰器）
**Storage**: preferences `STORE_SETTINGS`（`'nexte_settings'`）下新键 `search.globalFilter`（JSON snapshot）；备份适配器为 denylist 制，新键自动随 `preferences` 明文分区备份/恢复，无需新备份通道
**Testing**: `bash scripts/run_ci_preflight.sh` 全部契约脚本 + `devecocli build`；UI 验收由用户手动执行（设备操作不在自动范围）
**Target Platform**: HarmonyOS NEXT（手机）
**Performance Goals**: 面板实时编辑持久化防抖（250ms，复用现有 `SearchFilterPersistScheduler` 模式）；查询合并为纯字符串分词/拼接（微秒级，无 IO）
**Constraints**: 未经用户明确允许禁止更改样式（新 UI 全部复用现有标准行组件 `ConciseListRow`/`GroupedListSection`/`GroupedListItemSection`/`TagRow`）；`TabEditPage` 不改动（narrow change）；所有契约脚本必须全绿
**Scale/Scope**: 新增 3 个 ArkTS 文件 + 修改约 15 个文件（含 4 个语言资源文件与 1 份持久化清单文档）

## Project Structure

### Documentation (this feature)

```text
spec/global-search-filter/
├── spec.md              # Phase 1 需求规范（已完成）
├── plan.md              # 本文件（/spec-plan 输出）
└── tasks.md             # /spec-tasks 输出（下一阶段生成）
```

### Source Code (repository root)

```text
# ── 新增文件 ──────────────────────────────────────────────────────────────
shared/src/main/ets/state/GlobalSearchFilterState.ets
    # @ObservedV2 全局过滤状态 + connectGlobalSearchFilter() + 纯合并逻辑
    # mergedQuery() + globalSearchFilterCacheRevision(profile) 辅助函数
shared/src/main/ets/settings/GlobalSearchFilterSettings.ets
    # Snapshot + 防抖持久化（restore/persist/flush），镜像 SearchFilterSettings 模式
feature/settings/src/main/ets/pages/GlobalSearchFilterPage.ets
    # 设置侧"全局搜索过滤"编辑页（P3 管理入口的目的地，NavDestination）

# ── 修改文件（shared）──────────────────────────────────────────────────────
shared/src/main/ets/constants/StorageKeys.ets
    # 新增 static readonly GLOBAL_SEARCH_FILTER: string = 'search.globalFilter'
shared/src/main/ets/settings/SettingsBootstrap.ets
    # loadForFirstContent 第二个 Promise.all 组注册 GlobalSearchFilterSettings.restore
    # preloadPageCaches 的 homeProfileKey revision 改用 globalSearchFilterCacheRevision
shared/src/main/ets/components/TagQueryComposer.ets
    # 新增导出 TagQueryRowNameCache：解析标签→翻译名（供两个新编辑表面共用）
shared/src/main/ets/Index.ets
    # 导出新符号：GlobalSearchFilterState、connectGlobalSearchFilter、
    # globalSearchFilterCacheRevision、GlobalSearchFilterSettings、TagQueryRowNameCache

# ── 修改文件（feature/search，P1）─────────────────────────────────────────
feature/search/src/main/ets/viewmodel/SearchViewModel.ets
    # buildQuery()：scope===SEARCH_SCOPE_GALLERY 时 search 字段经 mergedQuery() 合并
feature/search/src/main/ets/pages/GallerySearchPage.ets
    # 新增 @Local globalFilter + @Monitor('globalFilter.applySeq')：
    # persist + （有关键词时）vm.reapplyFilters()
feature/search/src/main/ets/components/SearchFilterSheet.ets
    # session.scope===SEARCH_SCOPE_GALLERY 时在 AppModalScaffold 的 List 内容中
    # 追加"全局过滤"区：总开关行（ConciseListRow hasSwitch）+ GroupedListItemSection
    # （header=TagQueryComposer）+ ForEach TagRow 滑动删除行（TabEditPage 同款接线）

# ── 修改文件（feature/home，P2）───────────────────────────────────────────
feature/home/src/main/ets/viewmodel/GalleryListViewModel.ets
    # buildQuery()：gallery 类型 profile 的 search 字段经 mergedQuery() 合并
    # cacheKey()：profile 分支的 revision 改用 globalSearchFilterCacheRevision(this.profile)
feature/home/src/main/ets/components/GallerySourcePage.ets
    # 新增 @Local globalFilter + @Monitor('globalFilter.applySeq')：
    # 当前 profile 为 gallery 类型且已加载时 vm.reload(true)

# ── 修改文件（feature/settings + entry，P3）──────────────────────────────
feature/settings/src/main/ets/pages/SearchSettingsPage.ets
    # 新增"全局搜索过滤"分组行：状态行（未配置/已启用/已停用 + 标签数）+ 管理入口
    # pushPathByName('GlobalSearchFilter')
feature/settings/src/main/ets/Index.ets
    # export { GlobalSearchFilterPage } from './pages/GlobalSearchFilterPage'
entry/src/main/ets/model/IndexRouteCoordinator.ets
    # 路由名联合类型加 'globalSearchFilter'；映射表加 'GlobalSearchFilter': 'globalSearchFilter'
entry/src/main/ets/pages/Index.ets
    # import GlobalSearchFilterPage + builder 函数 IndexGlobalSearchFilterRoute()
    # 手写 routerMap 加 'globalSearchFilter': wrapBuilder(IndexGlobalSearchFilterRoute)

# ── 修改文件（资源与文档）─────────────────────────────────────────────────
entry/src/main/resources/base/element/string.json
entry/src/main/resources/zh_CN/element/string.json
entry/src/main/resources/en_US/element/string.json
entry/src/main/resources/ja_JP/element/string.json
    # 新增全局过滤相关字符串（4 locale 同步，复用既有 tag_compose_* 与 filter_* 键）
docs/plans/active/persistence-dataset-inventory.md
    # 新增行 | StorageKeys.GLOBAL_SEARCH_FILTER | setting | plaintext | excluded | …
```

**Structure Decision**: 本计划**遵循项目现有架构**（entry + feature/* + shared 多模块、MVVM 式 viewmodel/components 分层、设置类 Settings + State 成对模式），不引入新目录层级、不做 MVVM 迁移。新增文件仅 3 个：状态与合并逻辑（shared/state，与 SearchFilterState 同位）、持久化（shared/settings，与 SearchFilterSettings 同位）、设置编辑页（feature/settings/pages，与 SearchSettingsPage 同位）——每处放置均与被镜像的现有文件同目录，文件数已是最小充分集合。

## Complexity Tracking

（无 Constitution Check 违规——完全沿既有架构与目录约定。）

## Research & Decisions

### D1. 合并点：请求构建期（`buildQuery().search` 字段）
- **Decision**: 在 `SearchViewModel.buildQuery()`（搜索页）与 `GalleryListViewModel.buildQuery()`（首页画廊类列表）生成 `GalleryListQuery.search` 时调用 `GlobalSearchFilterState.mergedQuery(userQuery)` 合并；`EhApiService` 组装 `f_search` 的通路零改动。
- **Rationale**: 这是唯一同时满足 FR-002/SC-005（不回写输入框、不写历史——VM 的 `query` 与页面 `fieldState.keyword` 始终保持原始词）与 FR-003/FR-004（按调用方精确裁剪生效范围）的位置；分页/刷新/日期跳转全部经同一 `buildQuery`/`fetchPage` 通路，天然全覆盖（SC-001）。
- **Alternatives considered**: 在 `EhApiService.getGalleryList` 组装层合并（无法区分 watched/favorites 等不生效范围，丢失调用上下文）；在搜索输入层合并（直接污染输入框与搜索历史，违反 FR-002/SC-005）。

### D2. 状态与持久化：完全镜像 SearchFilterState / SearchFilterSettings 模式
- **Decision**: `GlobalSearchFilterState`（@ObservedV2，字段 `enabled`/`query`/`applySeq`）经 `AppStorageV2.connect(GlobalSearchFilterState, 'v2_globalSearchFilter', …)` 连接；`GlobalSearchFilterSettings` 用 `GlobalFilterSnapshot {en, q}` JSON 存 `StorageKeys.GLOBAL_SEARCH_FILTER`（preferences `nexte_settings` store），防抖复用现有 `SearchFilterPersistScheduler` 的**独立实例**；`SettingsBootstrap.loadForFirstContent` 注册 restore，restore 时**不 bump applySeq**（镜像 SearchFilterSettings.restore，避免启动期无谓刷新）。
- **Rationale**: 与项目既有全局过滤状态（高级搜索分类/评分）同一套心智与生命周期；备份走 denylist 制 preferences 整体分区，新键自动纳入备份/恢复（spec Assumption）；`applySeq` 模式让各宿主页面用 `@Monitor` 精确响应变更（FR-007）。
- **Alternatives considered**: 存入每个 CustomProfile（重复配置、无法一次配置全局生效）；存 RDB/LocalDataStore（过重，且脱离现有设置备份分区）。

### D3. 生效范围裁剪：仅 gallery
- **Decision**: 搜索页仅 `scope === SEARCH_SCOPE_GALLERY` 合并；首页仅 `profile.listType === PROFILE_TYPE_GALLERY` 的 profile 合并（含内置"首页" `BUILTIN_DEFAULT_UUID` 与自定义画廊标签页；无搜索词时 `mergedQuery('')` 直接返回过滤词，满足 FR-003 纯浏览）。watched / favorite / popular / toplist 一律不合并、不进缓存键（FR-004）。`GalleryListViewModel` 的 null-profile 退化路径（profile 缺失的 syncSource 兜底）保持不合并——该路径无对应缓存键隔离手段且实际不可达（每个首页 tab 都以 profile uuid 为 key）。
- **Rationale**: spec 明确的生效范围；非 gallery 源的请求语义（favorites.php / toplist.php / popular 快照）不含用户搜索词合并的语义。
- **Alternatives considered**: watched 也合并（用户明确排除）；所有列表源统一合并（违反 FR-004）。

### D4. 缓存隔离：`globalSearchFilterCacheRevision(profile)` 统一组合 revision
- **Decision**: 新增共享辅助函数 `globalSearchFilterCacheRevision(profile: CustomProfile): string`：非 gallery 类型或过滤未激活（`!isActive()`）时恒等 `profile.contentRevision()`；gallery 且激活时返回 `contentRevision() + ':gf:' + 长度前缀(query)`（沿用 `CustomProfile.ets` 中 `revisionPart` 的 `长度:内容` 拼接风格）。仅两处调用：`GalleryListViewModel.cacheKey()` 的 profile 分支与 `SettingsBootstrap.preloadPageCaches()` 的全部 `homeProfileKey(...)` 调用点（含 selectedProfile 与遍历 profiles）。
- **Rationale**: 内容基 revision 跨重启稳定（同一配置命中同一缓存键，重启后预热与读取一致）；停用/未配置时键与现状完全相同（SC-004：关闭开关后行为与"从未配置"一致，含缓存复用）；单一 helper 消除 VM 与预热两处键漂移风险（FR-008）。搜索页结果无页面缓存（`SearchViewModel` 不使用 `EhPageCacheService`），无需处理搜索侧缓存。`GalleryFirstPageRun` 的 run 身份比较保持 profile 纯 revision 不变，缓存键比较天然拦截过滤变更后的旧请求写入（其末位 `cacheKey()` 一致性检查）。
- **Alternatives considered**: 给 `homeProfileKey` 加第四参数（两处调用仍需手工同步，且改公共签名波及面大）；运行期计数器 revision（重启归零导致缓存键漂移、预热失效）。

### D5. 合并语义：字符串 token 级完全去重，不重新序列化
- **Decision**: `mergedQuery(userQuery)`：未激活时原样返回；激活时对两串做**引号感知分词**（与 `TagQuery.parse` 相同的引号/空格规则，但保留 token 原文），输出 = 用户 token 原文 + 过滤 token 中未被用户 token **完全相同字符串**包含的部分，空格连接。用户 token 逐字节保留（不经过 parse→serialize 往返）。
- **Rationale**: spec Edge Cases："完全相同 token 去重，同一 token 只发送一次"且"语义冲突不消解"（两个都发送）；保留原文避免非常规输入（`$`、特殊引号）被 `EhConstants.exactTagSearchQuery` 规范化漂移；过滤 token 本身来自 `TagQuery.serialize`，已是规范形态。
- **Alternatives considered**: parse→serialize 往返后按 (namespace,text,relation) 去重（会改写用户原始 token 的字节形态，违反"合并结果不回显"精神且引入规范化风险）；语义级冲突消解（spec 明确不做）。

### D6. 两个编辑表面：复用共享原语，各自薄接线；新增共享 `TagQueryRowNameCache`
- **Decision**: 过滤面板"全局过滤"区（`SearchFilterSheet`，AppModalScaffold 的 List 内容中追加）与设置编辑页（`GlobalSearchFilterPage`）都用 `GroupedListItemSection`（header = `TagQueryComposer`）+ `ForEach` `TagQuery.parse(gf.query)` → `ListItem(TagRow).swipeAction(删除)` 接线（`TabEditPage` 同款）；总开关行用 `ConciseListRow({hasSwitch: true, …})`。行翻译名由新增共享类 `TagQueryRowNameCache`（放 `TagQueryComposer.ets`，与 `TagRowItem` 同文件）提供，两个新表面共用；**`TabEditPage` 保持零改动**。
- **Rationale**: ArkUI 约束 `swipeAction` 挂在 `ListItem` 上、`ListItem` 必须是宿主 `List` 直接子节点——无法把整段抽成共享 struct；强行用共享 @Builder 跨文件发 ListItem 有状态重渲染隐患。薄接线每处约 50 行（parse/serialize 往返 + relation 切换 + splice 删除 + swipe），逻辑核心（联想、关系菜单、行渲染）全部复用现有共享组件，满足 FR-010 的"交互与解析体系复用"。翻译名解析（`ensureTranslations` 模式）抽出共享避免两份拷贝。
- **Alternatives considered**: 共享 @Builder 发射 ListItems（重渲染语义风险）；重构 TabEditPage 复用新 helper（触碰无关页面，违反 narrow-change 约束）；不做翻译名解析（行显示退化为原始 token，与标签页编辑器体验不一致，削弱 FR-010）。

### D7. 面板可见性与 reset 边界
- **Decision**: 过滤面板的"全局过滤"区仅在 `session.scope === SEARCH_SCOPE_GALLERY` 时显示（favorite 与 **watched** 都隐藏——watched 请求不合并，显示编辑区会误导）；面板右上 reset（`resetFilter()`）**不**重置全局过滤（保持只作用于分类/高级过滤，避免意外清空持久配置）。
- **Rationale**: spec Edge Case 明确收藏范围隐藏、切回画廊恢复；watched 同属"不合并范围"，同理隐藏。reset 语义沿用现状（只清 SearchFilterState），全局过滤是独立持久配置、有自己的开关。
- **Alternatives considered**: watched 也显示编辑区（编辑不生效，误导）；reset 一并清全局过滤（意外丢失配置，违反"总开关关闭仍保留配置"的产品直觉）。

### D8. 设置入口与路由注册
- **Decision**: `SearchSettingsPage` 新增分组：状态行（`ConciseListRow`，trailingText = 标签数，subtitle/状态 = 未配置/已启用/已停用）+ 管理入口行（push `'GlobalSearchFilter'`）；新编辑页 `GlobalSearchFilterPage` 放 `feature/settings/pages/`，注册链完整沿用 `SearchSettings` 先例：`IndexRouteCoordinator`（类型联合 + `'GlobalSearchFilter': 'globalSearchFilter'` 映射）→ `Index.ets` builder + 手写 routerMap 条目 → `feature/settings/Index.ets` 导出。
- **Rationale**: 与全部既有设置子页注册点一一对应，无新机制；`Stack` push 用 coordinator 键（PascalCase），与 `SearchSettingsPage` 现有 `'SearchSettings'` push 方式一致。
- **Alternatives considered**: 编辑页放 feature/search（设置域的页面在 feature/settings，放置错误）；复用 sheet 全屏化（bindSheet 大窗非页面栈成员，无法从设置直达且返回行为不一致）。

### D9. 存储契约合规
- **Decision**: `StorageKeys.GLOBAL_SEARCH_FILTER = 'search.globalFilter'` 加入 `persistence-dataset-inventory.md`（`| setting | plaintext | excluded |`，与 `SEARCH_FILTER` 行同分类）；AppStorageV2 键 `'v2_globalSearchFilter'` 以字符串常量形式定义（满足 `test_app_storage_v2_key_contract`：常量暴露、字符集、全库唯一）；不触碰 `BackupPreferencesAdapter`（denylist 制，新键自动随 preferences 明文分区备份/恢复）。
- **Rationale**: `test_persistence_inventory_contract` 要求每个 `StorageKeys.*` 静态成员都有清单行且分类合法；键值与既有 `search.filter` 命名对齐。
- **Alternatives considered**: 复用 `search.filter` 键（会与高级过滤 snapshot 冲突/耦合两类配置）。

### D10. 刷新接线：各宿主 `@Monitor('globalFilter.applySeq')`
- **Decision**: `GallerySearchPage`：monitor → `GlobalSearchFilterSettings.persist(ctx)` +（关键词非空时）`vm.reapplyFilters()`（镜像 `onFilterApply`，US1 场景 1/3/4 的立即重跑）；`GallerySourcePage`：monitor → 当前 profile 为 gallery 类型且 `loadedOnce` 时 `vm.reload(true)`（US2 场景 3，含内置首页与自定义画廊 tab）；设置编辑页自身在每次变更时持久化 + `aboutToDisappear` flush。任何表面的修改都 bump `applySeq`，所有已挂载的监听页面统一响应（FR-007）。
- **Rationale**: 与既有 `filter.applySeq` / `profilesState.profiles` 监听模式完全一致；`reload(true)` 强制重跑可打断在途请求（epoch 机制已内建）。
- **Alternatives considered**: 事件总线（项目内无此模式）；在每个 VM 内轮询 revision（浪费且延迟）。

### D11. 文案与状态派生
- **Decision**: 状态行文本实时派生：`tagCount = TagQuery.parse(gf.query).length`；状态 = `!enabled && count===0` → 未配置；`enabled && count>0` → 已启用；`!enabled && count>0` → 已停用（`enabled && count===0` 视同未配置——spec Edge Case"过滤词为空视为未配置"）。新字符串 4 个 locale 同步加入 entry 资源，复用既有 `tag_compose_*`、`filter_*`、`settings_search` 系列键；受 `check_i18n_duplicates` 约束（如检出重复值则调整措辞或复用既有键）。
- **Rationale**: 派生值不落库，单一事实来源是 `enabled + query`。
- **Alternatives considered**: 持久化 tagCount（会与 query 漂移）。

## Data Model

### GlobalSearchFilterState（shared/src/main/ets/state/GlobalSearchFilterState.ets）

@ObservedV2 类，经 `AppStorageV2.connect` 单例连接（键常量 `GLOBAL_SEARCH_FILTER_KEY = 'v2_globalSearchFilter'`，工厂 `connectGlobalSearchFilter()`）：

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `enabled` | `@Trace boolean` | 总开关；关闭后所有请求与缓存行为与未配置一致（FR-009） |
| `query` | `string`（@Trace） | 标签组合序列化串（`TagQuery.serialize` 形态：空格=与、`~`=或、`-`=非），与 `CustomProfile.searchText` 同一语法 |
| `applySeq` | `number`（@Trace） | 每次配置变更 +1；各宿主页面 `@Monitor` 的刷新信号（镜像 `SearchFilterState.applySeq`） |

方法：
- `isActive(): boolean` — `enabled && TagQuery.parse(query).length > 0`（空过滤词视为未激活）。
- `mergedQuery(userQuery: string): string` — D5 语义；未激活原样返回。
- `tagCount(): number` — `TagQuery.parse(query).length`（状态行/编辑页计数）。

文件级导出函数：
- `globalSearchFilterCacheRevision(profile: CustomProfile): string` — D4 语义（非 gallery / 未激活 → `profile.contentRevision()`；否则追加 `':gf:' + 长度前缀(query)`）。

### GlobalFilterSnapshot（shared/src/main/ets/settings/GlobalSearchFilterSettings.ets）

可持久化子集（不含 applySeq）：`en: boolean`（= enabled）、`q: string`（= query）。JSON 单对象存 preferences `nexte_settings` store 的 `search.globalFilter` 键；防御式 parse（坏 JSON/坏形状 → 安全默认/忽略，镜像 `SearchFilterSettings.parse`）。

### GlobalSearchFilterSettings（同文件）

静态类，API 面与 `SearchFilterSettings` 对齐：
- `restore(context)`：读快照 → 写 state 字段（不 bump applySeq）。
- `persist(context)`：快照当前 state → `SearchFilterPersistScheduler` 独立实例防抖（250ms）落盘；写入前字符串相等则跳过。
- `flush(context)`：persist + 等待调度器排空（离开编辑表面前强制落盘）。

### TagQueryRowNameCache（shared/src/main/ets/components/TagQueryComposer.ets 内新增导出）

`@ObservedV2` 类：持有 `@Trace names: Map<string, string>`（键 = `TagQuery.keyOf(tag)`，值 = 翻译名）；`ensure(context, query)` 按需逐 tag 经 `TagTranslationService.translateFullTagAsync` 补全（best-effort，失败保留原始 token 显示）；`nameOf(tag)` 查询。供过滤面板区与设置编辑页共用（`TabEditPage` 不改）。

### 合并后查询（Merged Query）

请求期派生值 = `mergedQuery(userQuery)`，仅存在于 `buildQuery` 调用栈，不落库、不回显、不进任何 UI 状态（对应 spec Key Entities）。

## Contracts & Interfaces

### 请求合并契约

- `SearchViewModel.buildQuery()`：`search: this.scope === SEARCH_SCOPE_GALLERY ? connectGlobalSearchFilter().mergedQuery(this.query) : this.query`（watched/favorite 路径不变，FR-004）。
- `GalleryListViewModel.buildQuery()`：当 `useProfile && profile.listType === PROFILE_TYPE_GALLERY` 时 `search` 经 `mergedQuery(p.searchText)`；其余分支（popular/toplist/favorite/watched/null-profile）字节级不变。
- `EhApiService`、`f_search` 组装通路：**零改动**。

### 缓存键契约

- `GalleryListViewModel.cacheKey()` profile 分支：`EhPageCacheService.homeProfileKey(isEx, safeModeCacheScope(uuid), globalSearchFilterCacheRevision(this.profile))`；`homeListKey`（toplist 等）分支不变。
- `SettingsBootstrap.preloadPageCaches()`：selectedProfile 与 profiles 遍历的 `homeProfileKey` revision 均改用 `globalSearchFilterCacheRevision(p)`。
- 恢复时序：`GlobalSearchFilterSettings.restore` 在 `loadForFirstContent` 内完成，早于 `loadDeferred` 的 `preloadPageCaches` 与任何首页/搜索加载 → 预热键与消费键一致。

### UI 表面契约

- **SearchFilterSheet**（P1）：`session.scope === SEARCH_SCOPE_GALLERY` 时，在既有 ListItem 之后追加：总开关行（`ConciseListRow` `hasSwitch`，`checked = gf.enabled`，切换 → `gf.enabled=v` + `applySeq++`）+ `GroupedListItemSection`（header = 区标题 + `TagQueryComposer({query: gf.query, onQueryChange → gf.query=v + applySeq++})`；内容 = `ForEach(TagQuery.parse(gf.query))` → `ListItem(TagRow).swipeAction(删除 → parse/splice/serialize 回写 + applySeq++)`；relation 切换 → `parse/改 relation/serialize` 回写 + applySeq++）。行翻译名经 `TagQueryRowNameCache`。每次变更后由 `GallerySearchPage` 的 monitor 负责持久化与重跑；面板自身不直接 persist。reset 按钮不触碰 `gf`（D7）。
- **GallerySearchPage**（P1）：`@Local globalFilter = connectGlobalSearchFilter()`；`@Monitor('globalFilter.applySeq') onGlobalFilterApply()` → `GlobalSearchFilterSettings.persist(ctx)`；`fieldState.keyword.trim().length > 0` 时 `vm.reapplyFilters()`（`vm.query` 保持原始词，重跑时 buildQuery 按最新过滤合并）。
- **GallerySourcePage**（P2）：`@Local globalFilter = connectGlobalSearchFilter()`；`@Monitor('globalFilter.applySeq') onGlobalFilterChange()` → 当前 profile `listType === PROFILE_TYPE_GALLERY` 且 `loadedOnce` 时 `vm.reload(true)`；其余类型 tab 无动作。
- **SearchSettingsPage**（P3）：新增分组行 1 = 状态行（`ConciseListRow`，title = 全局搜索过滤，subtitle = 状态文本（D11），trailingText = `${tagCount()}`，不可点或点击同入口）；行 2 = 管理入口（`ConciseListRow` chevron，action → `stack.pushPathByName('GlobalSearchFilter')`）。
- **GlobalSearchFilterPage**（P3，新 NavDestination）：`HdsNavDestination` + `SecondaryListScaffold`（同 `SearchSettingsPage` 骨架）：总开关行 + `GroupedListItemSection`（composer + TagRow 滑动行），每次变更 `applySeq++` + `GlobalSearchFilterSettings.persist(ctx)`，`aboutToDisappear` 时 `flush(ctx)`。

### 路由注册契约（沿用 searchSettings 全部注册点）

1. `entry/src/main/ets/model/IndexRouteCoordinator.ets`：路由名类型联合加 `'globalSearchFilter'`；`ROUTE` 映射加 `'GlobalSearchFilter': 'globalSearchFilter'`。
2. `entry/src/main/ets/pages/Index.ets`：`import { GlobalSearchFilterPage } from 'settings'`（经 feature/settings 的 Index 导出）；`function IndexGlobalSearchFilterRoute() { GlobalSearchFilterPage() }`；routerMap 加 `'globalSearchFilter': wrapBuilder<[]>(IndexGlobalSearchFilterRoute)`。
3. `feature/settings/src/main/ets/Index.ets`：`export { GlobalSearchFilterPage } from './pages/GlobalSearchFilterPage'`。

### 字符串资源契约（entry 4 locale 同步新增）

| 键 | 用途 | zh_CN 参考 |
| --- | --- | --- |
| `global_filter_title` | 面板区标题 / 设置行 title / 编辑页标题 | 全局过滤（设置行用"全局搜索过滤"措辞则拆两键，实现时按 i18n 查重结果定） |
| `global_filter_master_switch` | 总开关行 title | 启用全局过滤 |
| `global_filter_status_unconfigured` | 状态：未配置 | 未配置 |
| `global_filter_status_enabled` | 状态：已启用 | 已启用 |
| `global_filter_status_disabled` | 状态：已停用 | 已停用 |
| `global_filter_hint` | 设置入口行 / 编辑页说明 | 配置 |

复用既有键：`tag_compose_placeholder`、`tag_compose_rel_and/or/not`、`filter_*`、`settings_search`、`common_cancel` 等。受 `scripts/check_i18n_duplicates.py` 约束。

### 持久化清单契约

`docs/plans/active/persistence-dataset-inventory.md` 新增行：
`| StorageKeys.GLOBAL_SEARCH_FILTER | setting | plaintext | excluded | Global advanced-search filter (master switch + AND/OR/NOT tag query) |`
（与 `StorageKeys.SEARCH_FILTER` 行同分类；满足 `test_persistence_inventory_contract` 对新 StorageKeys 成员的覆盖检查。）

### 契约脚本合规清单（验证阶段逐项跑）

- `node scripts/test_v1_decorator_inventory_contract.mjs` → `0 file(s)`（全程仅 V2 装饰器）
- `node scripts/test_app_storage_v2_key_contract.mjs` → 新键 `v2_globalSearchFilter` 以常量定义、合法、全库唯一
- `node scripts/test_persistence_inventory_contract.mjs` → 新 StorageKeys 成员有清单行
- `python3 scripts/check_i18n_duplicates.py` → 新字符串无重复
- `bash scripts/run_ci_preflight.sh`（all）全绿
- `devecocli build` 成功

### 需求追踪（spec → 本计划）

| spec 条目 | 落点 |
| --- | --- |
| US1 / FR-001 / FR-005 / FR-007(搜索) / FR-009 | D2 状态与持久化、SearchFilterSheet 区、GallerySearchPage monitor、GlobalSearchFilterSettings |
| US1 验收 2 / FR-002 / SC-005 | D1 + D5（请求期合并、原始词不回显） |
| US2 / FR-003 / FR-008 / SC-002 / SC-004 | GalleryListViewModel 合并 + D4 缓存 revision + GallerySourcePage monitor |
| US3 / FR-006 | SearchSettingsPage 状态行 + GlobalSearchFilterPage + D8 路由 |
| FR-004 / Edge(不生效范围) | D3 范围裁剪 |
| FR-010 / Edge(去重/冲突/空过滤/历史/重启) | D5 合并语义 + D2 restore + 复用 TagQuery 体系（D6） |
| SC-001 / SC-003 | D1 全通路合并 + D2 持久化与启动恢复 |
