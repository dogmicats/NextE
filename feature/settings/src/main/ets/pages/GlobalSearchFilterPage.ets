import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  ConciseListRow,
  GlobalSearchFilterSettings,
  GlobalSearchFilterState,
  GroupedListSection,
  GroupedListItemSection,
  ListRowDivider,
  QueryTag,
  SecondaryListScaffold,
  SwipeDeleteAction,
  TagQuery,
  TagQueryComposer,
  TagQueryRowNameCache,
  TagRow,
  TagRowItem,
  ThemeConstants,
  connectGlobalSearchFilter,
  immersiveTitleBar,
} from 'shared'

/**
 * Settings-side editor for the global advanced-search filter (设置→搜索→全局搜索过滤). Mirrors the
 * search filter sheet's global-filter section exactly: master switch card, composer-in-header tag
 * group, swipe-deletable TagRow list with relation switching via the parse/serialize round-trip.
 * Unlike the sheet (whose host page persists through its applySeq monitor), this standalone page
 * persists every edit itself and flushes on leave; the applySeq bump still notifies mounted
 * search/gallery pages so live results refresh (FR-007).
 */
@ComponentV2
export struct GlobalSearchFilterPage {
  @Local gf: GlobalSearchFilterState = connectGlobalSearchFilter();
  @Local private nameCache: TagQueryRowNameCache = new TagQueryRowNameCache();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // Restored tags may already exist on disk; resolve their display names up front.
    this.nameCache.ensure(this.ctx(), this.gf.query)
  }

  aboutToDisappear(): void {
    // Force the newest snapshot durable before the page goes away (edits are debounced).
    GlobalSearchFilterSettings.flush(this.ctx())
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  // Every edit bumps gf.applySeq (mounted search/gallery pages refresh) and persists immediately.
  private bumpApplySeq(): void {
    this.gf.applySeq = this.gf.applySeq + 1
  }

  private setEnabled(value: boolean): void {
    this.gf.enabled = value
    this.bumpApplySeq()
    GlobalSearchFilterSettings.persist(this.ctx())
  }

  private setQuery(value: string): void {
    this.gf.query = value
    this.bumpApplySeq()
    GlobalSearchFilterSettings.persist(this.ctx())
    this.nameCache.ensure(this.ctx(), this.gf.query)
  }

  private tagRowItems(): TagRowItem[] {
    const out: TagRowItem[] = []
    TagQuery.parse(this.gf.query).forEach((t: QueryTag, i: number) => {
      out.push(new TagRowItem(t, i, this.nameCache.nameOf(t)))
    })
    return out
  }

  private setTagRelation(index: number, relation: number): void {
    const tags: QueryTag[] = TagQuery.parse(this.gf.query)
    if (index >= 0 && index < tags.length) {
      tags[index].relation = relation
      this.setQuery(TagQuery.serialize(tags))
    }
  }

  private removeTag(index: number): void {
    const tags: QueryTag[] = TagQuery.parse(this.gf.query)
    if (index >= 0 && index < tags.length) {
      tags.splice(index, 1)
      this.setQuery(TagQuery.serialize(tags))
    }
  }

  @Builder
  private FilterHeader() {
    Column() {
      Text($r('app.string.global_filter_hint'))
        .fontSize(ThemeConstants.FONT_SIZE_BODY)
        .fontColor($r('sys.color.font_secondary'))
      TagQueryComposer({
        query: this.gf.query,
        onQueryChange: (q: string) => {
          this.setQuery(q)
        },
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private FilterItems() {
    ForEach(
      this.tagRowItems(),
      (it: TagRowItem) => {
        ListItem() {
          Column() {
            ListRowDivider()
            TagRow({
              tag: it.tag,
              index: it.index,
              displayName: it.displayName,
              onSetRelation: (index: number, rel: number) => {
                this.setTagRelation(index, rel)
              },
            })
          }
          .width('100%')
        }
        .swipeAction({
          end: () => {
            this.DeleteSwipe(it.index)
          },
        })
      },
      (it: TagRowItem, index: number) =>
        `gf_tag_${index}_${it.tag.relation}_${it.tag.namespace}_${it.tag.text}_${it.displayName}`.replace(/[^A-Za-z0-9_]/g, '_'),
    )
  }

  @Builder
  private DeleteSwipe(index: number) {
    SwipeDeleteAction({
      action: () => {
        this.removeTag(index)
      },
    })
  }

  build() {
    HdsNavDestination() {
      SecondaryListScaffold({
        scroller: this.scroller,
        bottomPadding: ThemeConstants.SPACE_XL,
        alwaysEnableEdgeSpring: true,
      }) {
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.global_filter_master_switch'),
              hasSwitch: true,
              checked: this.gf.enabled,
              showChevron: false,
              switchAction: (value: boolean) => {
                this.setEnabled(value)
              },
            })
          }
        }
        GroupedListItemSection({
          showHeader: true,
          headerBuilder: () => {
            this.FilterHeader()
          },
          content: () => {
            this.FilterItems()
          },
        })
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('global_filter_title')))
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
