import {
  AppModalScaffold,
  AppStrings,
  ThemeConstants,
  ListRowDivider,
  SearchFilterState,
  connectSearchFilter,
  ConciseListRow,
  EhConstants,
  Favcat,
  FavSelectionState,
  GroupedListSection,
  GroupedListItemSection,
  connectFavSelection,
  CategorySelector,
  AdvancedSearchControls,
  SearchFilterSettings,
  SwipeDeleteAction,
  TagQueryComposer,
  TagRow,
  TagQuery,
  QueryTag,
  TagRowItem,
  TagQueryRowNameCache,
  GlobalSearchFilterState,
  connectGlobalSearchFilter,
  SEARCH_SCOPE_FAVORITE,
  SEARCH_SCOPE_GALLERY,
  SEARCH_SCOPE_WATCHED,
  SegmentButtonTheme,
  ThemeDisplayState,
  connectThemeDisplay,
} from 'shared'
import { common } from '@kit.AbilityKit'
import { LengthMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI'
import { SearchSessionState } from '../state/SearchSessionState'

const SEGMENT_HEIGHT: number = 44
const SEGMENT_PADDING_V: number = 8
const FORM_FONT_SIZE: number = ThemeConstants.FONT_SIZE_TITLE

/**
 * Search filter sheet content (hosted via the search page's bindSheet). Scope and favorite folder are
 * page-session state; persisted category/advanced values remain in SearchFilterState. Every change
 * re-runs the current query through the page monitor. Favorite rows reuse the existing selector-page
 * information hierarchy, with the trailing count replaced by the native Radio control.
 */
@ComponentV2
export struct SearchFilterSheet {
  @Local filter: SearchFilterState = connectSearchFilter();
  @Local gf: GlobalSearchFilterState = connectGlobalSearchFilter();
  @Local private nameCache: TagQueryRowNameCache = new TagQueryRowNameCache();
  @Local fav: FavSelectionState = connectFavSelection();
  @Local private themeDisplay: ThemeDisplayState = connectThemeDisplay();
  @Param session: SearchSessionState = new SearchSessionState();
  @Local private scopeItems: SegmentButtonV2Items = new SegmentButtonV2Items([{ text: '' }, { text: '' }, { text: '' }]);
  @Event onClose: () => void = () => {};

  aboutToAppear(): void {
    this.scopeItems[0].text = AppStrings.get('search_scope_gallery')
    this.scopeItems[1].text = AppStrings.get('search_scope_watched')
    this.scopeItems[2].text = AppStrings.get('search_scope_favorite')
    // The global filter may already hold tags restored from disk; resolve their display names up front.
    this.nameCache.ensure(this.ctx(), this.gf.query)
  }

  private bumpApplySeq(): void {
    this.filter.applySeq = this.filter.applySeq + 1
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private close(): void {
    SearchFilterSettings.flush(this.ctx())
    this.onClose()
  }

  private setScope(scope: string): void {
    this.session.setScope(scope)
  }

  private scopeIndex(): number {
    if (this.session.scope === SEARCH_SCOPE_WATCHED) {
      return 1
    }
    if (this.session.scope === SEARCH_SCOPE_FAVORITE) {
      return 2
    }
    return 0
  }

  private scopeForIndex(index: number): string {
    if (index === 1) {
      return SEARCH_SCOPE_WATCHED
    }
    if (index === 2) {
      return SEARCH_SCOPE_FAVORITE
    }
    return SEARCH_SCOPE_GALLERY
  }

  private resetFilter(): void {
    this.session.reset()
    this.filter.selectedCats = 0
    this.filter.advancedEnabled = false
    this.filter.minRating = 0
    this.filter.pagesFrom = 0
    this.filter.pagesTo = 0
    this.filter.requireTorrent = false
    this.filter.showExpunged = false
    this.filter.disableLanguageFilter = false
    this.filter.disableUploaderFilter = false
    this.filter.disableTagFilter = false
    this.bumpApplySeq()
    // Reset stays scoped to the per-search advanced filters: the global filter is an independent
    // persisted configuration with its own master switch and must survive Reset untouched.
  }

  // ── global filter (gallery scope only) ─────────────────────────────────────
  // Every edit bumps gf.applySeq; the hosting page (GallerySearchPage) monitors it to persist and
  // re-run the current query. The sheet itself never persists the global filter.

  private bumpGlobalApplySeq(): void {
    this.gf.applySeq = this.gf.applySeq + 1
  }

  private setGlobalEnabled(value: boolean): void {
    this.gf.enabled = value
    this.bumpGlobalApplySeq()
  }

  private setGlobalQuery(value: string): void {
    this.gf.query = value
    this.bumpGlobalApplySeq()
    this.nameCache.ensure(this.ctx(), this.gf.query)
  }

  private globalTagRowItems(): TagRowItem[] {
    const out: TagRowItem[] = []
    TagQuery.parse(this.gf.query).forEach((t: QueryTag, i: number) => {
      out.push(new TagRowItem(t, i, this.nameCache.nameOf(t)))
    })
    return out
  }

  private setGlobalTagRelation(index: number, relation: number): void {
    const tags: QueryTag[] = TagQuery.parse(this.gf.query)
    if (index >= 0 && index < tags.length) {
      tags[index].relation = relation
      this.setGlobalQuery(TagQuery.serialize(tags))
    }
  }

  private removeGlobalTag(index: number): void {
    const tags: QueryTag[] = TagQuery.parse(this.gf.query)
    if (index >= 0 && index < tags.length) {
      tags.splice(index, 1)
      this.setGlobalQuery(TagQuery.serialize(tags))
    }
  }

  private favoriteRows(): Favcat[] {
    const rows: Favcat[] = [new Favcat('a', AppStrings.get('favorites_all'), this.fav.remoteTotalCount())]
    this.fav.favList.forEach((fc: Favcat) => {
      if (FavSelectionState.isRemoteSlot(fc.favId)) {
        rows.push(fc)
      }
    })
    return rows
  }

  private favoriteColor(favId: string): ResourceColor {
    const color: string = EhConstants.favCatColor(favId)
    return color.length > 0 ? color : ThemeConstants.FAV_HEART_DEFAULT
  }

  @Builder
  private FavoritePrefix(favId: string) {
    SymbolGlyph($r('sys.symbol.heart_fill'))
      .fontSize(ThemeConstants.SYMBOL_SIZE_STANDARD)
      .fontColor([this.favoriteColor(favId)])
      .padding({ left: ThemeConstants.SPACE_SM, right: ThemeConstants.SPACE_SM })
  }

  @Builder
  private FavoriteRadio(fc: Favcat) {
    Radio({ value: fc.favId, group: 'nexte_search_favorite_scope' })
      .checked(this.session.favoriteFavcat === fc.favId)
      .radioStyle({ checkedBackgroundColor: ThemeConstants.BRAND_PRIMARY })
      .hitTestBehavior(HitTestMode.None)
      .margin({ right: ThemeConstants.SPACE_MD })
  }

  @Builder
  private FavoriteFolderSelector() {
    Text($r('app.string.filter_favorite_folder'))
      .fontSize(ThemeConstants.FONT_SIZE_BODY)
      .fontColor($r('sys.color.font_secondary'))
    GroupedListSection() {
      ForEach(
        this.favoriteRows(),
        (fc: Favcat, index: number) => {
          ConciseListRow({
            title: fc.favTitle,
            trailingText: '',
            showChevron: false,
            prefixBuilderParam: () => {
              this.FavoritePrefix(fc.favId)
            },
            suffixBuilderParam: () => {
              this.FavoriteRadio(fc)
            },
            action: () => {
              this.session.setFavoriteFavcat(fc.favId)
            },
          })
          if (index < this.favoriteRows().length - 1) {
            ListRowDivider()
          }
        },
        (fc: Favcat, index: number) =>
          `search_favcat_${index}_${fc.favId}_${fc.favTitle}`.replace(/[^A-Za-z0-9_]/g, '_'),
      )
    }
  }

  // Global-filter tag rows need ListItem semantics (swipe-to-delete), so they render as a
  // GroupedListItemSection inside the scaffold List — the same composer-in-header wiring the
  // custom-tab editor (TabEditPage) uses, which keeps the composer stable while rows change.
  @Builder
  private GlobalFilterHeader() {
    Column() {
      Text($r('app.string.global_filter_title'))
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
      TagQueryComposer({
        query: this.gf.query,
        onQueryChange: (q: string) => {
          this.setGlobalQuery(q)
        },
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private GlobalFilterItems() {
    ForEach(
      this.globalTagRowItems(),
      (it: TagRowItem) => {
        ListItem() {
          Column() {
            ListRowDivider()
            TagRow({
              tag: it.tag,
              index: it.index,
              displayName: it.displayName,
              onSetRelation: (index: number, rel: number) => {
                this.setGlobalTagRelation(index, rel)
              },
            })
          }
          .width('100%')
        }
        .swipeAction({
          end: () => {
            this.GlobalDeleteSwipe(it.index)
          },
        })
      },
      (it: TagRowItem, index: number) =>
        `gf_tag_${index}_${it.tag.relation}_${it.tag.namespace}_${it.tag.text}_${it.displayName}`.replace(/[^A-Za-z0-9_]/g, '_'),
    )
  }

  @Builder
  private GlobalDeleteSwipe(index: number) {
    SwipeDeleteAction({
      action: () => {
        this.removeGlobalTag(index)
      },
    })
  }

  build() {
    AppModalScaffold({
      title: $r('app.string.filter'),
      confirmIcon: $r('sys.symbol.arrow_counterclockwise'),
      confirmText: $r('app.string.filter_reset'),
      closeAction: () => {
        this.close()
      },
      confirmAction: () => {
        this.resetFilter()
      },
    }) {
      ListItem() {
        Column({ space: ThemeConstants.SPACE_MD }) {
          TabSegmentButtonV2({
            items: this.scopeItems,
            selectedIndex: this.scopeIndex(),
            enableStateAnimation: true,
            itemFontSize: LengthMetrics.vp(FORM_FONT_SIZE),
            itemSelectedFontSize: LengthMetrics.vp(FORM_FONT_SIZE),
            itemFontWeight: FontWeight.Medium,
            itemSelectedFontWeight: FontWeight.Bold,
            buttonBackgroundColor: SegmentButtonTheme.tabButtonBackground(this.themeDisplay.effectiveDark),
            itemSelectedBackgroundColor:
              SegmentButtonTheme.tabSelectedItemBackground(this.themeDisplay.effectiveDark),
            itemFontColor: SegmentButtonTheme.itemFont(this.themeDisplay.effectiveDark),
            itemSelectedFontColor: SegmentButtonTheme.tabSelectedItemFont(this.themeDisplay.effectiveDark),
            onItemClicked: (index: number) => {
              this.setScope(this.scopeForIndex(index))
            },
            itemPadding: {
              top: LengthMetrics.vp(SEGMENT_PADDING_V),
              bottom: LengthMetrics.vp(SEGMENT_PADDING_V),
              start: LengthMetrics.vp(8),
              end: LengthMetrics.vp(8),
            },
          })
            .width('100%')
            .constraintSize({ minHeight: SEGMENT_HEIGHT })
          if (this.session.scope === SEARCH_SCOPE_FAVORITE) {
            Text($r('app.string.filter_favorite_scope_hint'))
              .fontSize(ThemeConstants.FONT_SIZE_CAPTION)
              .fontColor($r('sys.color.font_secondary'))
              .lineHeight(18)
            this.FavoriteFolderSelector()
          }
          if (this.session.scope !== SEARCH_SCOPE_FAVORITE) {
            CategorySelector({
              filter: this.filter,
              onChanged: () => {
                this.bumpApplySeq()
              },
            })
            AdvancedSearchControls({
              filter: this.filter,
              onChanged: () => {
                this.bumpApplySeq()
              },
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: ThemeConstants.SPACE_SM,
          right: ThemeConstants.SPACE_SM,
          top: ThemeConstants.SPACE_SM,
          bottom: ThemeConstants.SPACE_SM,
        })
      }
      if (this.session.scope === SEARCH_SCOPE_GALLERY) {
        // Global filter (gallery scope only). Both the switch card and the tag group sit at the
        // scaffold List's padding edge — the same ListItem/ListItemGroup card convention as
        // TabEditPage and MyTagsPage — so the two new cards stay mutually aligned.
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.global_filter_master_switch'),
              hasSwitch: true,
              checked: this.gf.enabled,
              showChevron: false,
              switchAction: (value: boolean) => {
                this.setGlobalEnabled(value)
              },
            })
          }
        }
        GroupedListItemSection({
          showHeader: true,
          headerBuilder: () => {
            this.GlobalFilterHeader()
          },
          content: () => {
            this.GlobalFilterItems()
          },
        })
      }
    }
  }
}
