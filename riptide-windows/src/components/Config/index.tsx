// C13.1 — Config top-level tab.
//
// MVP: re-export the existing `Profiles` implementation under a new
// top-level route. The macOS-aligned 9-tab target is Dashboard / Config
// / Proxy / Traffic / Rules / Connections / Logs / Diagnostics / Settings.
//
// Phase C13.1+ will further split this view into:
//   - ConfigImportPreview  (import by URL / share URI / clipboard / WARP)
//   - ConfigMergeView      (active profile, edit, subscription scheduler)
// and lift the "重写" sub-tab out of Settings (so it lives at
// /settings/rewrite as before, but no longer as a peer of the profile
// CRUD). For this commit, the page body is identical to the previous
// `/profiles` route — the change is purely the URL and the Sidebar
// surfacing.

export { Profiles as Config } from '../Profiles';
