import { common } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { connectGlobalSearchFilter } from '../state/GlobalSearchFilterState'
import { StorageKeys } from '../constants/StorageKeys'
import { DiagnosticLogger } from '../diagnostics/DiagnosticLogger'
import { SearchFilterPersistScheduler } from './SearchFilterSettings'

/** Serialized global advanced-search filter (the persistable subset of GlobalSearchFilterState; not applySeq). */
export class GlobalFilterSnapshot {
  en: boolean = false // enabled master switch
  q: string = '' // query (TagQuery.serialize form; empty = unconfigured)
}

/**
 * Persists the global advanced-search filter (master switch + AND/OR/NOT tag query) as one JSON
 * object in the shared settings store. Mirrors SearchFilterSettings end to end: restore runs once
 * at startup (SettingsBootstrap) and deliberately does NOT bump applySeq (no host page is mounted
 * yet, so a bump would only cause persist/reload churn), live edits go through a debounced
 * scheduler so rapid composer typing coalesces into one durable write, and flush forces the newest
 * snapshot durable before an editing surface is left. The backup adapter is denylist-based, so the
 * new preference key joins the plaintext settings backup automatically.
 */
export class GlobalSearchFilterSettings {
  // Independent instance: the advanced-filter scheduler must never flush this class's pending
  // writes (and vice versa) — each snapshot type owns its own debounce window.
  private static readonly persistScheduler: SearchFilterPersistScheduler = new SearchFilterPersistScheduler()

  static async restore(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const raw: string = store.getSync(StorageKeys.GLOBAL_SEARCH_FILTER, '') as string
      if (raw.length === 0) {
        return
      }
      const snap: GlobalFilterSnapshot | null = GlobalSearchFilterSettings.parse(raw)
      if (snap === null) {
        return
      }
      const gf = connectGlobalSearchFilter()
      gf.enabled = snap.en
      gf.query = snap.q
    } catch (error) {
      DiagnosticLogger.warn('settings', 'globalsearchfilter_restore_failed', (error as Error).message)
    }
  }

  /** Queue the newest filter snapshot; live composer edits share one durable write instead of one per keystroke. */
  static persist(context: common.UIAbilityContext): void {
    const serialized: string = GlobalSearchFilterSettings.serializedCurrent()
    GlobalSearchFilterSettings.persistScheduler.schedule(
      (): Promise<void> => GlobalSearchFilterSettings.writeSerialized(context, serialized),
    )
  }

  /** Force the latest known snapshot durable before leaving an editing surface. */
  static async flush(context: common.UIAbilityContext): Promise<void> {
    GlobalSearchFilterSettings.persist(context)
    await GlobalSearchFilterSettings.persistScheduler.flush()
  }

  private static serializedCurrent(): string {
    const gf = connectGlobalSearchFilter()
    const snap: GlobalFilterSnapshot = new GlobalFilterSnapshot()
    snap.en = gf.enabled
    snap.q = gf.query
    return JSON.stringify(snap)
  }

  private static async writeSerialized(context: common.UIAbilityContext, serialized: string): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(
        context,
        StorageKeys.STORE_SETTINGS,
      )
      const existing: string = store.getSync(StorageKeys.GLOBAL_SEARCH_FILTER, '') as string
      if (existing === serialized) {
        return
      }
      store.putSync(StorageKeys.GLOBAL_SEARCH_FILTER, serialized)
      store.flushSync()
    } catch (error) {
      DiagnosticLogger.warn('settings', 'globalsearchfilter_save_failed', (error as Error).message)
    }
  }

  /** Defensive parse: bad JSON / shape → null; bad fields → safe defaults (false / ''). */
  private static parse(raw: string): GlobalFilterSnapshot | null {
    try {
      const parsed: Object = JSON.parse(raw) as Object
      // Reject a non-object blob (null / primitive / array) outright rather than silently coercing
      // it to an all-defaults snapshot that would overwrite live state.
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return null
      }
      const o = parsed as GlobalFilterSnapshot
      const s: GlobalFilterSnapshot = new GlobalFilterSnapshot()
      s.en = o.en === true
      s.q = typeof o.q === 'string' ? o.q : ''
      return s
    } catch (error) {
      DiagnosticLogger.warn('settings', 'globalsearchfilter_parse_failed', (error as Error).message)
      return null
    }
  }
}
