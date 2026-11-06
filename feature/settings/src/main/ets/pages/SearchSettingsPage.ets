import { HdsNavDestination } from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import {
  AppStrings,
  ConciseListRow,
  GroupedListSection,
  SecondaryListScaffold,
  SearchFilterSettings,
  SearchFilterState,
  SearchHistorySettings,
  SearchHistoryState,
  GlobalSearchFilterState,
  ThemeConstants,
  ListRowDivider,
  connectNavStack,
  NavStackHolder,
  connectSearchFilter,
  connectSearchHistory,
  connectGlobalSearchFilter,
  immersiveTitleBar,
} from 'shared'

/**
 * Search settings page grounded in eros_fe SearchSettingPage's Settings-tree placement, but scoped to
 * NextE's existing search data: persisted history and advanced filter profile management.
 */
@ComponentV2
export struct SearchSettingsPage {
  @Local history: SearchHistoryState = connectSearchHistory();
  @Local filter: SearchFilterState = connectSearchFilter();
  @Local globalFilter: GlobalSearchFilterState = connectGlobalSearchFilter();
  @Local navStackHolder: NavStackHolder = connectNavStack();
  @Local isFirstSecondaryDestination: boolean = false;
  private stack: NavPathStack = connectNavStack().stack;
  private scroller: Scroller = new Scroller();

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private historyCountText(): string {
    return `${this.history.items.length}`
  }

  private filterStateText(): Resource {
    return this.filter.isActive()
      ? $r('app.string.search_settings_filter_active')
      : $r('app.string.search_settings_filter_clean')
  }

  // D11 derivation: empty query counts as unconfigured regardless of the switch; otherwise the
  // switch decides enabled/disabled. Derived live from enabled + query, never persisted.
  private globalFilterStatusText(): Resource {
    if (this.globalFilter.tagCount() === 0) {
      return $r('app.string.global_filter_status_unconfigured')
    }
    return this.globalFilter.enabled
      ? $r('app.string.global_filter_status_enabled')
      : $r('app.string.global_filter_status_disabled')
  }

  private globalFilterCountText(): string {
    return `${this.globalFilter.tagCount()}`
  }

  private async clearHistory(): Promise<void> {
    await SearchHistorySettings.clear(this.ctx())
  }

  private confirmClearHistory(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.search_history_clear_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.search_history_clear'),
        fontColor: Color.Red,
        action: () => {
          this.clearHistory()
        },
      },
    })
  }

  private async resetFilters(): Promise<void> {
    await SearchFilterSettings.reset(this.ctx())
  }

  private confirmResetFilters(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.search_settings_filter_reset_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {},
      },
      secondaryButton: {
        value: $r('app.string.search_settings_filter_reset'),
        fontColor: Color.Red,
        action: () => {
          this.resetFilters()
        },
      },
    })
  }

  private refreshFirstSecondaryDestination(pathStack: NavPathStack): void {
    const pathNames: string[] = pathStack.getAllPathName()
    this.isFirstSecondaryDestination = pathNames.length === 1 && pathNames[0] === 'SearchSettings'
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
              title: $r('app.string.search_settings_history_count'),
              subtitle: $r('app.string.search_settings_history_hint'),
              leadingIcon: $r('sys.symbol.clock'),
              trailingText: this.historyCountText(),
              showChevron: false,
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.search_history_clear'),
              leadingIcon: $r('sys.symbol.trash'),
              destructive: true,
              showChevron: false,
              action: () => {
                this.confirmClearHistory()
              },
            })
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.search_settings_filter_profile'),
              subtitle: $r('app.string.search_settings_filter_hint'),
              leadingIcon: $r('sys.symbol.funnel'),
              trailingText: this.filterStateText(),
              showChevron: false,
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.search_settings_filter_reset'),
              leadingIcon: $r('sys.symbol.arrow_counterclockwise'),
              destructive: true,
              showChevron: false,
              action: () => {
                this.confirmResetFilters()
              },
            })
          }
        }
        ListItem() {
          GroupedListSection() {
            ConciseListRow({
              title: $r('app.string.global_filter_title'),
              subtitle: this.globalFilterStatusText(),
              leadingIcon: $r('sys.symbol.funnel'),
              trailingText: this.globalFilterCountText(),
              showChevron: false,
            })
            ListRowDivider()
            ConciseListRow({
              title: $r('app.string.global_filter_hint'),
              leadingIcon: $r('sys.symbol.slider_horizontal_2'),
              action: () => {
                this.stack.pushPathByName('GlobalSearchFilter', null)
              },
            })
          }
        }
      }
    }
    .titleBar(immersiveTitleBar(AppStrings.get('settings_search')))
    .hideBackButton(this.navStackHolder.isSplitMode && this.isFirstSecondaryDestination)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      this.refreshFirstSecondaryDestination(context.pathStack)
    })
    .onWillShow(() => {
      this.refreshFirstSecondaryDestination(this.stack)
    })
  }
}
