# Badminton Plan

## Done
- [x] Create SwiftUI macOS/iOS project structure with shared UI.
- [x] Configure secrets via xcconfig and keep secrets out of git.
- [x] Integrate TMDB auth (v4) and v3/v4 API client support.
- [x] Home page rails: Trending Movies/TV, Now Playing, Upcoming, On the Air, Airing Today, Popular People.
- [x] Search with `.searchable`, results view, and UserDefaults-backed search history.
- [x] Detail views for Movies, TV Shows, People, and Episodes (with seasons + episodes list).
- [x] TV detail: latest episodes rail, up-next placement, cast/guest stars, and season ordering.
- [x] Poster/profile loading via Kingfisher with consistent sizing.
- [x] Lightbox for detail-view images (full-screen, dismiss on click/keypress).
- [x] Date formatting to human-readable form (e.g., “May 23, 2025”).
- [x] macOS swipe-to-dismiss support on detail pages.
- [x] Trailer links open externally (browser), not embedded.
- [x] Plex OAuth (PIN) with persisted token, settings UI, and server picker.
- [x] Plex account filtering with multi-select of home users.
- [x] Plex rails on home: Now Playing + Recent in side-by-side columns within a shared horizontal scroll.
- [x] Plex rail improvements: dedupe, limit episodes per show, show title formatting, prefetch TMDB mappings, and resolution error handling.
- [x] Plex→TMDB episode resolution using show TMDB ID + season/episode numbers (Tautulli-style).
- [x] CLI/debug harness for Plex history inspection (`scripts/plex_history.swift`).
- [x] Docs checked in: TMDB v3/v4 and Plex OpenAPI references.
- [x] Plex “Now Playing” refreshes on app activation plus manual refresh (pull-to-refresh / Command-R).

## Next
- [ ] Accessibility pass (plan + audit before UI changes).
- [ ] Live Activity integration for Plex playback (likely needs a server component).

## Later / Ideas
- [ ] Validate iOS build and tune layout for compact size classes (deferred).
- [ ] Revisit typography sizing for small text in detail views and rail subtitles (deferred).
- [ ] Add a TMDB-focused CLI/debug harness for response inspection (deferred).
