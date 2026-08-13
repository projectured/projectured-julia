# Event layer — Interface/Defaults split + EVENT_TYPES internalization

> **Status (2026-08-12): DONE.** `package/kernel/main/event/` holds
> `EventInterface.jl`, `EventDefaults.jl`, `ModifierKeys.jl`, and the other
> split files listed below. `EVENT_TYPES` is internal to `EventPattern.jl`
> as `_concrete_event_types`/`_EVENT_TYPES`. A later, unrelated rename
> changed `get_modifiers`/`is_ctrl` etc. to `get_modifier_keys`/
> `has_ctrl_modifier_key` etc.; that rename is not part of this plan.

Discovered during the seal review of `event/EventModule.jl`, which mixed three
concerns (interface, defaults, aggregator) in one file.

## Changes

- [x] **`EventInterface.jl`** (new) — the abstract `Event`/`DeviceEvent`/`SyntheticEvent`
      types + the bodiless `function get_modifiers end`. Declarations only; added
      to the layering guard's `interface_files` map (event-layer interface purity
      is now machine-checked). Also applied the PAR-NO-CONSUMER-DOCS fix: the
      `DeviceEvent` docstring says "an event source" (not "a backend").
- [x] **`EventDefaults.jl`** (new) — `get_modifiers(::Event) = Modifiers()` fallback
      and the `is_ctrl`/`is_shift`/`is_alt`/`is_meta` predicates derived over it.
- [x] **`EventModule.jl`** slimmed to module docstring + exports + includes
      (`EventInterface` first, `EventDefaults` last).
- [x] **`EVENT_TYPES` internalized** — it was consumed only by `EventPattern.jl`
      (grep-confirmed, no external/test users), so `_concrete_event_types` moved
      there (reflecting `names(EventModule)`) and `EVENT_TYPES` dropped from
      `EventModule`'s exports.
- [x] CLAUDE.md Layer-3 inventory: added `EventInterface.jl` (after EventModule)
      and `EventDefaults.jl` (after EventEnvelope) in load order.

## Modifiers → ModifierKeys rename (follow-up commit)

- [x] Renamed the type `Modifiers` → **`ModifierKeys`** and the file
      `Modifiers.jl` → `ModifierKeys.jl`; kept `get_modifiers`, the `is_*`
      predicates, and the `.modifiers` field name. Whole-word sweep across **77
      `.jl` files** in every package, plus the active guides and the CLAUDE.md
      inventory. `plan/` files left untouched as historical records.
