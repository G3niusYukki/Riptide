# D2 — Override (覆写) schema

Date: 2026-06-02
Status: Accepted
Deciders: @G3niusYukki

## Context

Riptide today has a single profile model: one YAML file = one
configuration. To change anything (add a rule, swap a node, tweak
DNS), users must edit the YAML directly. This blocks the P0 gap
"**Merge Profile**" from `docs/analysis/2026-06-02-riptide-vs-surge-stash.md`
§1.4: the inability to layer user customizations on top of a
subscription without modifying the subscription itself.

Surge and Stash solved this with two different mechanisms:
- **Surge's Module** (`[Module]` section + `.sgmodule` files) — a
  separate YAML/INI file that patches specific sections of the
  active profile at load time
- **Stash's Override** (覆写) — a separate YAML/JSON file that
  overlays on top of the active profile, with first-class UI

Riptide needs a similar capability. This ADR picks the schema that
Riptide's Override will use.

## Considered Options

### Option A: YAML-on-YAML overlay (Stash-style)

- Override is a partial YAML file with the **same schema** as a
  profile. At apply time, deep-merge it onto the active profile.
- Merge rules per field:
  - Scalars: override wins
  - Lists (rules, proxies, proxy-groups): **append** by default
  - Maps (per-proxy options, per-rule options): **deep merge**,
    override wins on conflict
- Stored on disk as `~/Library/Application Support/Riptide/overrides/<name>.yaml`
- **Pros:**
  - Zero new parser code — reuses the existing Clash YAML parser
    in `ConfigMerger.swift`
  - Users can hand-write Override files; copy-paste from community
    (same ecosystem vocabulary as their profile)
  - Trivial to diff in git or in any text editor
- **Cons:**
  - List-append semantics can produce surprising results
    (e.g. adding a rule with the same `DOMAIN,Proxy` as an
    existing rule creates a duplicate rather than replacing it;
    need explicit `replace: true` on the override)
  - No way to express "remove this rule" without a separate
    directive (need `removed: true` or `action: drop`)
  - Subset of the profile schema is exposed; if the profile adds
    a new top-level field, the override parser must be updated

### Option B: New schema (Surge Module-style `.sgmodule`)

- Override is a **new schema** with explicit `override` /
  `remove` / `replace` directives per section
- Schema: `[{section: Proxy, action: override, items: [...]},
  {section: Rule, action: remove, items: [...]}, ...]`
- Stored as `*.sgoverride` (Riptide's own extension, not Stash's
  `.sy` or Surge's `.sgmodule`)
- **Pros:**
  - Explicit semantics: no surprise on list-append
  - Can express "remove rule N" cleanly
  - Easier to round-trip without losing the user's intent
- **Cons:**
  - New parser to write and test
  - New schema to document; community contributions need to learn
    it (smaller community than Stash Override, so learning cost
    is per-user)
  - Schema evolution is our problem (Stash's Override is battle-tested
    over 3 years)

### Option C: Stash Override format compatibility (read Stash `.sy`)

- Override is Stash's exact schema; Riptide reads it as-is
- **Pros:** Community can share Override files between Stash and
  Riptide; zero migration cost for Stash users
- **Cons:**
  - Stash's schema is closed (Stash is proprietary); we'd be
    reverse-engineering from changelog tweets
  - Riptide's profile schema is **Clash-style YAML** (slightly
    different from Stash's); a Stash Override may reference
    sections that don't map cleanly (e.g. Stash's `script` vs
    Riptide's `Scripting/`)
  - Coupling to Stash's release cadence

## Decision

**Option A: YAML-on-YAML overlay (Stash-style)**, with the following
conventions to mitigate its known weak spots:
- Add a `meta: { replace: true }` block at the top of an Override
  file to opt into **replace-by-name** semantics for lists (Riptide
  walks the list, finds items with the same "name" key, and replaces
  them in place; new items are appended)
- Add a `removed: [<selector>]` list for explicit removal
- Default to **append** for any list that doesn't use `meta.replace`

Rationale: 80% of Override use cases are additive (a few extra rules
plus a tweaked DNS list), and append-by-default is the least
surprising behavior for that case. The 20% of cases that need
replace/remove get the explicit opt-in.

## Consequences

**Enables:**
- W2-2: Override data model + storage layer (YAML files in
  `~/Library/Application Support/Riptide/overrides/`)
- Future Override Repository feature (Stash's iCloud-style
  community Override catalog) — but that's SP-2 territory
- Merge Profile (P0 from competitive roadmap Phase 1) reuses
  this same machinery

**Forecloses:**
- We do not get a "remove rule" UX as polished as Stash's
  until/unless we add a visual editor. The `removed:` list
  is functional but text-only.
- Cross-compat with Stash Override is not a goal; users moving
  from Stash to Riptide will need to translate manually.

**Follow-up actions:**
- T+1: Document the `meta.replace` and `removed:` semantics
  in `docs/CONFIG-FORMAT.md` (create this doc if it doesn't
  exist; check first).
- T+2: When W3-1 (visual rule editor) lands, expose
  `meta.replace` and `removed:` in the editor UI.
- T+3: When W2-2 ships, add a `riptide override apply <name>`
  CLI subcommand for power users.

**Risks:**
- Users will be confused by append vs replace semantics.
  Mitigation: the very first Override UI screen will show
  a diff preview ("this override will ADD 3 rules and
  REPLACE 1 rule on the active profile") so the user sees
  the effect before applying.
- Schema evolution: if the profile gains a new top-level
  field, an old Override may not interact with it correctly.
  Mitigation: Override files carry a `min-riptide-version`
  field; Riptide warns if the field is missing.
