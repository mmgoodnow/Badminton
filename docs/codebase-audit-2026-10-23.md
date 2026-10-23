# Badminton reliability audit — October 23, 2026

## Scope and evidence

Reviewed the SwiftUI home/search/detail/settings flows, Plex and Seerr clients/authentication/account resolution, availability storage, TMDB client/loading, Live Activity integration, build configuration, and existing tests. This is a source audit with targeted live API checks and mocked networking regression tests. It is not proof of successful authenticated playback/history or media requests against the user's services.

Read-only live checks with the Mac app's saved credentials reproduced:

- Seerr `/api/v1/auth/me`: **403**, `You do not have permission to access this endpoint`.
- Seerr `/api/v1/settings/public`: **200**.
- Plex `/api/v2/resources`, including required client headers: **401**.

The existing Seerr session is invalid. Plex's saved token is also unauthorized; the user must reconnect Plex before live server access or Plex-based Seerr session renewal can succeed. No live media requests were submitted. No other Plex server was queried. Credentials were kept out of diagnostics.

The rebuilt Mac app was inspected through accessibility: the top rail visibly reports `Reconnect Plex in Settings; its saved connection is no longer authorized.` and exposes Retry, while TMDB content remains visible.

## Fixed in this pass

| Problem | Resulting behavior | Main source |
| --- | --- | --- |
| Seerr interpreted one exact 403 message as expired authentication even though Seerr also uses it for permission denials. Other 401/403 responses surfaced as generic errors. | On protected-endpoint 403, checks `/auth/me`; valid sessions retain the actual permission error. Invalid sessions renew once using the existing Plex identity and retry once. Concurrent calls share renewal. 401 works without a JSON body. | `Overseerr/OverseerrAPIClient.swift`, `OverseerrAuthManager.swift` |
| Saved Seerr cookie competed with URLSession's ambient cookie jar. | Requests use the explicitly selected Seerr session and disable automatic cookie handling. Sign-out/server changes invalidate pending session results. | `Overseerr/OverseerrAPIClient.swift`, `OverseerrAuthManager.swift` |
| Every Plex history, session, and prefetched metadata request repeated cloud discovery. A single chosen remote address could fail without fallback. | Shares discovery for five minutes within the client, races actual reads across advertised addresses of the selected server, and reuses the working address. Connection reads have a six-second timeout. | `Plex/PlexAPIClient.swift` |
| Missing preferred server silently selected a different server. | An absent, unselected, or unreachable server produces an error. All history, sessions, and metadata reads require the Preferences server identifier. Alternative addresses always belong to that identifier. | `Plex/PlexAPIClient.swift` |
| Three startup tasks could load the Plex rail concurrently; history preceded playback, and manual refresh waited for TMDB first. | One combined Plex task identity; concurrent history/playback and manual-refresh sources; generation checks prevent stale rail results overwriting new preferences. | `Home/HomeView.swift` |
| History failure hid playback; refresh failure erased the rail and only printed diagnostics. | History and playback can succeed independently. Failed refreshes preserve previous items and expose an error with Retry. Plex 401/403 discovery errors explain that reconnection is needed. | `Home/HomeView.swift` |
| An expired Plex token required disconnecting before sign-in, which cleared the server selection. | Settings now offers Reconnect Plex while signed in, preserving the server and account filters. | `Settings/SettingsView.swift` |
| Plex navigation/artwork caches were keyed by ratingKey without server identity. | Clears resolution caches and cancels background work when token/server/account scope changes or Plex disconnects. | `Home/HomeView.swift` |
| Seerr availability used bare numeric TMDB IDs, mixing movie and TV namespaces; the cache survived server changes and disconnects. | Uses `(mediaType, tmdbID)` keys and scopes persisted snapshots to a hash of server/session. Disconnect clears published availability; stale responses cannot publish into a new scope. Library reads use the same session recovery. | `Overseerr/OverseerrLibraryIndex.swift` and badge callers |
| Optional public-settings failure hid successfully fetched Seerr status. | Loads and applies request status independently; optional settings retain their default if unavailable. Pending/processing movies cannot be requested again through the UI. | `Overseerr/OverseerrRequestViewModel.swift` |
| Older failed searches could clear newer results; overlapping tasks could clear the loading indicator prematurely. | Cancels superseded search tasks and guards result/error/loading publication with query and generation checks. | `Search/SearchView.swift` |

## Remaining improvements, in priority order

### 1. Validate with a renewed Plex login

Use **Reconnect Plex** in Settings to renew the token while preserving the selected server and account filters. Then verify cold start, refresh, an unavailable server address, switching account filters, opening a rail item, and Seerr movie/TV status. Seerr renewal requires a Plex token accepted by Seerr. A genuine account permission restriction will correctly remain an error and requires a Seerr account configuration change.

There is no defensible live latency comparison while discovery returns 401. Mocked tests demonstrate one discovery across history, sessions, and metadata and fallback to a reachable address; they do not establish real network speed. A cached address can still cost up to six seconds before rediscovery of a working address, and cloud discovery is still required at initial load and every cache expiry. A manually configured direct server URL could remove that cloud dependency, but would need identity verification against the selected server and an explicit Settings control.

### 2. Decouple optional TMDB sections from core content

`HomeViewModel.load` awaits eight results as one tuple before publishing any section. Movie/TV/episode detail loaders similarly couple core details to credits, videos, image configuration, or parent-show data. One optional endpoint failure can hide otherwise valid content. Publish each section independently, use fallback image configuration, and show section-specific retries. Start with home and movie/TV details; avoid a wholesale UI rewrite.

### 3. Finish concurrency cleanup

The Mac compiler reports existing Swift 6 migration warnings concerning actor-isolated model decoding, client default arguments, and detached TV/TMDB tasks. The project currently compiles in Swift 5 mode with MainActor default isolation. Give immutable network DTOs explicit nonisolated/Sendable boundaries and use structured task cancellation before enabling Swift 6 enforcement.

Plex account/server Settings view models still lack generation checks. Account matching also waits for Plex Home and name lookups before publishing the rail. Cache successful user-directory lookups with a bounded lifetime and timeout; do not remove matching logic without validating managed-user IDs against real responses. Avoid guessing that Plex Home IDs and server account IDs are interchangeable.

### 4. Improve metadata prefetch and matching

`startPlexPrefetch` marks every candidate before completion; cancelled/failed candidates can stay marked until the scope resets, and episodes from one show can repeat show-metadata reads. Track successful and in-flight work separately and deduplicate by show ratingKey. All cache writers should recheck scope after network awaits.

TMDB title-search fallback currently takes the first result. Prefer external IDs, match title/year/type before accepting a fallback, and surface ambiguity. These affect navigation correctness rather than initial rail transport.

### 5. Reduce credential exposure in storage and artwork URLs

Plex, Seerr, and TMDB credentials are still persisted through UserDefaults in their token stores. Move secrets to Keychain with a migration that preserves current logins. Plex artwork URLs still carry server tokens in query parameters and go through Kingfisher. Supply the token through request headers and use an explicit server-scoped cache key. Plex JSON reads in the revised client now use token headers.

### 6. Add broader acceptance coverage and split large files

The prior unit test was an empty example; the prior UI suite only launches the app and measures launch time. The added network tests cover the failures fixed here. Next add controlled UI fixtures for expired-login recovery and per-section failures, plus iOS/Live Activity acceptance checks. The roughly 1,800-line Home file combines presentation, data fetching, account filtering, artwork, navigation resolution, and disk writes; extract those responsibilities after behavior is pinned by tests. Remove unused template `Item.swift` only after confirming project references.

## Validation

- The complete Mac acceptance command passed: nine networking regression tests and four UI test runs. Mac app builds and typechecks through Xcode's normal test build, using existing signing and deployment settings.
- Regression tests cover session renewal/retry, simultaneous renewal, genuine permission denial, non-JSON 401, selected-server isolation, connection fallback, discovery reuse, missing selected server, independent playback/history, stale-rail preservation, and movie/TV availability separation plus disconnect cleanup.
- Mac app restarted after builds; the visible invalid-Plex-token state was checked. The final built app was copied to `/Applications/Badminton.app` and relaunched.
- Existing compiler concurrency warnings remain; authenticated live Plex timing, live Seerr request submission, and iOS/device behavior remain unverified.
