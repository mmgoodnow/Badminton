# Agent Guidelines

- Commit early and often.
- Build the Mac version of the app after changes.
- After building, kill and restart the Mac app.
- When debugging or expanding API usage (TMDB/Plex), prefer validating responses first with curl or a quick script before changing client code.
- Local API docs are available in `docs/` (TMDB OpenAPI JSON + Plex OpenAPI JSON); use them for endpoint/field lookup.
- Prefer `rg` for search; avoid adding duplicate `navigationDestination` declarations or nested `NavigationStack` instances.
- Keep Plex/TMDB resolution flows observable via logs before changing UI error states.
