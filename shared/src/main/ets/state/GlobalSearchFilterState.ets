import { AppStorageV2 } from '@kit.ArkUI'
import { TagQuery } from '../components/TagQueryComposer'
import { CustomProfile, PROFILE_TYPE_GALLERY } from '../model/CustomProfile'

/**
 * Quote-aware token split with the EXACT boundary rules of TagQuery.parse (double quotes toggle
 * in-quote mode, spaces split only outside quotes) but without the parse → serialize round-trip:
 * tokens keep their raw bytes, so unconventional user input ($ suffixes, unusual quoting) reaches
 * EH exactly as typed. Empty tokens are dropped, same as TagQuery.parse.
 */
function splitQueryTokens(query: string): string[] {
  const tokens: string[] = []
  let cur: string = ''
  let inQuote: boolean = false
  for (let i = 0; i < query.length; i++) {
    const ch: string = query.charAt(i)
    if (ch === '"') {
      inQuote = !inQuote
      cur = cur + ch
    } else if (ch === ' ' && !inQuote) {
      if (cur.length > 0) {
        tokens.push(cur)
        cur = ''
      }
    } else {
      cur = cur + ch
    }
  }
  if (cur.length > 0) {
    tokens.push(cur)
  }
  return tokens
}

/**
 * Persisted global advanced-search filter: one AND/OR/NOT tag combination (TagQuery.serialize form,
 * same syntax as CustomProfile.searchText) plus a master switch, merged into gallery search and
 * gallery-list requests at build time. User-facing semantics:
 * - Empty query counts as unconfigured: isActive() is false and no request changes.
 * - The switch only gates merging; the configured tags are always kept (FR-009).
 * - `applySeq` bumps on every configuration change so mounted host pages can @Monitor and refresh
 *   (search page persists + re-runs, gallery tabs reload) — mirrors SearchFilterState.applySeq.
 */
@ObservedV2
export class GlobalSearchFilterState {
  @Trace enabled: boolean = false
  @Trace query: string = ''
  @Trace applySeq: number = 0

  /** True only when the switch is on AND at least one tag is configured (empty filter = unconfigured). */
  isActive(): boolean {
    return this.enabled && TagQuery.parse(this.query).length > 0
  }

  /**
   * Merge this filter into `userQuery` for gallery requests. Inactive → the user query verbatim.
   * Active → user tokens byte-for-byte first (never re-serialized, never written back to the input
   * field or history), then filter tokens whose raw string is not already present among the user
   * tokens (exact-string dedup only — semantic conflicts are intentionally NOT resolved, both are
   * sent and EH's server behavior wins). An empty user query returns just the filter combination,
   * which is how keyword-less gallery browsing stays filtered.
   */
  mergedQuery(userQuery: string): string {
    if (!this.isActive()) {
      return userQuery
    }
    const userTokens: string[] = splitQueryTokens(userQuery)
    const filterTokens: string[] = splitQueryTokens(this.query)
    const out: string[] = []
    userTokens.forEach((t: string) => {
      out.push(t)
    })
    filterTokens.forEach((t: string) => {
      let duplicate: boolean = false
      for (let i = 0; i < userTokens.length; i++) {
        if (userTokens[i] === t) {
          duplicate = true
          break
        }
      }
      if (!duplicate) {
        out.push(t)
      }
    })
    return out.join(' ')
  }

  /** Number of configured tags (derived, never persisted — single source of truth is enabled + query). */
  tagCount(): number {
    return TagQuery.parse(this.query).length
  }
}

const GLOBAL_SEARCH_FILTER_KEY: string = 'v2_globalSearchFilter'

export function connectGlobalSearchFilter(): GlobalSearchFilterState {
  return AppStorageV2.connect(GlobalSearchFilterState, GLOBAL_SEARCH_FILTER_KEY, () => new GlobalSearchFilterState())!
}

/**
 * Cache identity for a home profile's first-page cache entry, extended by the global filter so
 * entries from different filter states never collide (FR-008). Non-gallery profiles and an inactive
 * filter return the plain content revision — identical to the pre-feature key, so disabling the
 * switch reuses exactly the "never configured" cache. An active filter appends ':gf:' plus the
 * length-prefixed query (same `length:content` encoding as CustomProfile.revisionPart) because the
 * content-based revision is stable across restarts, keeping warm-up and read keys identical.
 */
export function globalSearchFilterCacheRevision(profile: CustomProfile): string {
  const base: string = profile.contentRevision()
  if (profile.listType !== PROFILE_TYPE_GALLERY) {
    return base
  }
  const gf: GlobalSearchFilterState = connectGlobalSearchFilter()
  if (!gf.isActive()) {
    return base
  }
  return `${base}:gf:${gf.query.length}:${gf.query}`
}
