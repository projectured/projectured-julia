# Device layer restructure — event / device / gesture / binding

Split kernel layer 6 (`device/`) into the four concepts it actually holds, and put each at
its true dependency height. Backward compatibility is explicitly **not** a concern: the
compatibility aliases and the phantom module names go away with it.

## The problem

Today `device/` (layer 6) holds three topics at two dependency heights:

| File | Actually depends on | True height |
| --- | --- | --- |
| `Device.jl`, `Modifiers.jl`, `Keyboard.jl`, `Mouse.jl`, `ScreenDevice.jl` | nothing | 0 |
| `EventCase.jl` (`@event_case` + its parser) | the event structs | 0 |
| `GestureRecognizer.jl` | events + `EventEnvelope` | 0 |
| `GestureBinding.jl` (`@gestures`, `read_gesture`, the registry) | **`Document`** (layer 2) + **`Operation`** (layer 5) | above 5 |

One file — `GestureBinding.jl` — needs documents and operations, and it drags the whole
zero-dependency event vocabulary up to layer 6 with it. That in turn pushes `backend/` to
layer 7, so a backend (whose defining property under AR-42 is that it knows nothing about
documents) sits *above* documents, references, selections and operations in the layer
diagram. One roommate, a four-layer cascade.

Consequences visible in the code today:

- **The event/gesture distinction exists only in prose.** There is no `abstract type Event`.
  `MousePress` (synthesised by the recogniser) sits next to `MouseDown` (emitted by a
  backend) in `Mouse.jl`, distinguished by a docstring. `EventEnvelope.event` and
  `Intent.gesture` are `Any`.
- **The pattern language is stranded at the wrong height.** `EventPattern`-style matching
  needs only event types, but lives beside the bindings, so `GestureBinding.jl` must reach
  into `EventCase.jl`'s private parser via the same-namespace fragment trick.
- **Phantom modules.** `EventCaseModule` and `GestureBindingModule` do not exist — they are
  `const … = ProjecturedKernel.GestureModule` aliases in `ProjecturedVisual.jl` and
  `ProjecturedDomain.jl`, keeping ~20 stale import headers alive. Both fragment files still
  open with a docstring naming the module they are not (AR-66).
- **Drift the structure permits.** `_EVENT_TYPES` (a hand-written copy of every event's field
  list) covers `MouseEnter`/`MouseLeave`, but `_pattern_expr` has no arm for them and none for
  `KeyChord` — so no reified binding can be written for hover or for a chord.

## Target structure

Thirteen layers. `cell` stays at index 1 (it is independent of the four new layers, and
keeping it first avoids touching the sealed `cell/CellLayer.jl`).

```
 1 cell
 2 event      — Modifiers, Event/DeviceEvent/SyntheticEvent, all event structs,
                EventEnvelope, the pattern language (EventPattern, matches, describe)
 3 device     — Device, Keyboard, Mouse, Screen, read_from_devices, write_to_devices   → event
 4 gesture    — GestureRecognizer (events → gestures)                                  → event
 5 backend    — Backend seam, Display, HeadlessBackend                                 → device
 6 document
 7 reference
 8 selection
 9 operation
10 binding    — GestureBinding, the registry, @gestures/@gesture_set, read_gesture
                                                              → event, document, operation
11 projection — keeps its Projection-typed gesture-seam methods (the seam pattern, AR-49)
12 agent
13 editor
```

**Accepted permissiveness.** `device` and `gesture` are at the same height — both import
`event`, neither imports the other. The layer order tolerates this (layer N imports ≤ N; it
need not import N−1), so the guard will *permit* a `gesture → device` edge that we never
want. Making them two slices of one layer would forbid it. **Decision: take the layer order
and accept the permissiveness** — the kernel deliberately keeps by-concept layers rather than
slices (architecture-rules.md), and the naming benefit is worth more than the unused edge.

**Why `binding` and not `gesture` for layer 10.** A gesture is a recognised combination of
events (it carries no intent) and belongs to the input vocabulary; a *binding* is where a
gesture acquires meaning. Calling layer 10 `gesture/` would put one word at two heights —
exactly the muddle this plan removes.

## File map

### `event/` (new, layer 2)

| New file | Module | From |
| --- | --- | --- |
| `EventLayer.jl` | — (fragment) | new |
| `EventModule.jl` | `EventModule` (aggregator) | new |
| `Modifiers.jl` | fragment | `device/Modifiers.jl` |
| `KeyboardEvent.jl` | fragment | `device/Keyboard.jl` (events only) |
| `MouseEvent.jl` | fragment | `device/Mouse.jl` (events only) |
| `WindowEvent.jl` | fragment | `device/ScreenDevice.jl` (`WindowQuit`) + visual's `WindowClose`/`WindowResize`/`WindowDefocus` |
| `EventEnvelope.jl` | fragment | `device/GestureModule.jl` |
| `EventPattern.jl` | `EventPatternModule` | `device/GestureBinding.jl` (patterns) + `device/EventCase.jl` |

`EventModule` merges four modules that every consumer imports together anyway
(`import ..KeyboardModule: KeyDown` + `..MouseModule: MousePress` + `..ModifiersModule: Modifiers`
is the current ritual) — AR-46's module criterion: merge modules only ever imported together.

### `device/` (layer 3)

| New file | Module | From |
| --- | --- | --- |
| `DeviceLayer.jl` | — (fragment) | rewritten |
| `Device.jl` | `DeviceModule` | `device/Device.jl` + the `Keyboard`/`Mouse`/`Screen` singletons lifted out of `Keyboard.jl`/`Mouse.jl`/`ScreenDevice.jl` |

### `gesture/` (new, layer 4)

| New file | Module | From |
| --- | --- | --- |
| `GestureLayer.jl` | — (fragment) | new |
| `GestureRecognizer.jl` | `GestureRecognizerModule` | unchanged content |

### `binding/` (new, layer 10)

| New file | Module | From |
| --- | --- | --- |
| `BindingLayer.jl` | — (fragment) | new |
| `GestureBinding.jl` | `GestureBindingModule` (aggregator) | `device/GestureBinding.jl` minus the patterns |
| `Gestures.jl` | fragment | the `@gestures` / `@gesture_set` macros |

`GestureBindingModule` becomes a **real** module — the phantom alias becomes the truth.

### Deleted

- `device/GestureModule.jl` (the aggregator; its `EventEnvelope` goes to `event/`)
- `device/EventCase.jl` as a separate concept (folds into `EventPattern.jl`; see Phase 5 for
  whether `@event_case` survives at all)
- `const EventCaseModule` / `GestureBindingModule` / `GestureApiModule` / `DeviceApiModule`
  aliases in `ProjecturedVisual.jl` and `ProjecturedDomain.jl`

## The layer index is deleted, not renumbered

**Decision (2026-07-14, user):** the hard-coded layer index comes *out* of the files. It is a
duplicate of the include order in `ProjecturedKernel.jl` — the single source of truth — and this
restructure is precisely the way it rots. `ProjecturedKernel.jl`'s own include list keeps its
`# layer N —` comments, because there the number *is* the reading order it documents.

Every other mention is either deleted or reworded to a dependency statement, which is the fact
worth keeping ("imports only the cell and event layers" survives a renumbering; "layer 6" does
not). The 19 sites:

| File | Seal | Mention |
| --- | --- | --- |
| `cell/CellLayer.jl` | 🔒 | `(layer 1)` |
| `document/DocumentLayer.jl` | 🔒 | `(layer 2)` |
| `document/DocumentModule.jl` | 🔒 | `Layer 2 of the kernel — …` |
| `reference/ReferenceLayer.jl` | 🔒 | `(layer 3)` |
| `reference/ReferenceModule.jl` | ⬜ | `Layer 3 of the kernel — …` |
| `selection/SelectionLayer.jl` | ⬜ | `(layer 4)` |
| `selection/SelectionModule.jl` | ⬜ | `Layer 4 …`, and `(layer 3)` / `(layer 2)` / "one layer above" in the body |
| `operation/OperationLayer.jl` | ⬜ | `(layer 5)` |
| `operation/OperationModule.jl` | ⬜ | `Layer 5 of the kernel — …` |
| `device/DeviceLayer.jl`, `device/Device.jl`, `device/GestureModule.jl` | ⬜ | `layer 6` (files being replaced anyway) |
| `backend/BackendLayer.jl`, `backend/Backend.jl`, `backend/HeadlessBackend.jl` | ⬜ | `layer 7` |
| `projection/ProjectionLayer.jl` | ⬜ | `(layer 8 — interface & infrastructure)` |
| `agent/AgentLayer.jl`, `agent/Agent.jl` | ⬜ | `layer 9` |
| `editor/EditorLayer.jl` | ⬜ | `(layer 10 — the read-eval-print loop)` |

The parenthetical *descriptions* stay (`— the read-eval-print loop`); only the number goes.

### 🔒 Sealed-file permission gate

- [x] **Permission granted 2026-07-14** ("yep, delete, I allow unsealing").
- [x] On the tree as it actually stands, only **one** of the layer-index files is still sealed:
      `reference/ReferenceLayer.jl`. `cell/CellLayer.jl`, `document/DocumentLayer.jl` and
      `document/DocumentModule.jl` had been unsealed upstream by the cell-kinds work, so the
      scrub touches exactly one sealed file, for one header line. No sealed *code* changed.

## Phases

Work in a dedicated git worktree. One commit per phase; each phase leaves the tree green.

### Phase 0 — preparation

- [ ] Read this plan against the current tree; re-run the import inventory
      (`grep -rn "DeviceModule\|ModifiersModule\|KeyboardModule\|MouseModule\|ScreenDeviceModule\|GestureModule\|GestureRecognizerModule\|EventCaseModule\|GestureBindingModule" --include=*.jl package/`)
      — ~60 sites across kernel/base/visual/domain/sdl/web plus test and example packages.
- [ ] Confirm nothing in `cell/`…`operation/` imports a device-layer module (verified 2026-07-14: nothing does).

### Phase 1 — the layer move ✅ done

A relocation, so a regression here is a load error or a guard failure, never a behaviour change.

- [x] Created `event/`, `device/`, `gesture/`, `binding/` per the file map.
- [x] Rewrote `ProjecturedKernel.jl`'s include list to the 13-layer order (this file keeps its
      `# layer N —` comments; it is the source of truth).
- [x] Deleted the layer index from the other 19 sites; the new layer fragments state their
      dependencies, never an index.
- [x] Updated the guard's layer list in `package/kernel/test/ProjecturedKernelTest.jl`.
- [x] Rewrote every import header (48 files across kernel/base/visual/domain/sdl/web + test and
      example packages), scripted from a symbol → module table rather than by hand.
- [x] Updated the `const …Module = …` alias blocks in `ProjecturedBase.jl`,
      `ProjecturedVisual.jl`, `ProjecturedDomain.jl`; **deleted** the phantom aliases
      (`EventCaseModule`, `GestureBindingModule`, `GestureApiModule`, `DeviceApiModule`).
- [x] Updated the CLAUDE.md seal inventory to the 13 layers.
- [x] Moved the kernel tests: `test/device/*` → `test/event/`, `test/gesture/`, `test/binding/`;
      `GestureModuleTest` became `event/EventModuleTest.jl` (all three of its testsets — the
      envelope, `@event_case`, pattern match/describe — are event-layer concerns now).

**Decisions taken during the move** (they go beyond pure relocation, and are forced by it):

- **The pattern parser is now exported, not a private fragment reach-in.** Splitting patterns
  (`event/`) from bindings (`binding/`) puts a module boundary between `@gestures` and the parser
  it rides on, and AR-48's answer to that is "export it, don't re-implement it". `EventPatternModule`
  therefore exports a macro-authoring API — `EventRule`, `parse_event_rule`, `event_pattern_expr`,
  `event_field_bindings` — and `@gestures` calls it. The old `_parse_rule`/`EvPat`/`_pattern_expr`
  internals and the same-namespace fragment trick that shared them are gone. The field-pattern node
  types stay private: a caller sees an opaque `EventRule`.
- **`GesturePattern` → `EventPattern`.** A pattern matches an event, and it now lives in the event
  layer; the concrete `KeyDownPattern`/`MousePressPattern`/… names are unchanged.
- **`MouseEnterPattern` / `MouseLeavePattern` now exist** (they were in the parser's event table but
  had no reified pattern, so `@gestures` could not bind hover). `KeyChordPattern` still does not —
  Phase 3.
- **`_keypress_label` is gone**: the label is computed by `KeyPressPattern`'s own constructor, so the
  emitted pattern expression names nothing private.

Verified: `test_kernel_layering()` (8/8), `test_kernel()` (407/407), `test_base()` (96/96),
`test_visual()` (51856 pass, 1 broken), `test_domain()` — compared against a clean-`main` baseline.

### Phase 2 — the `Event` type

- [ ] `abstract type Event end`; `abstract type DeviceEvent <: Event end` (what a backend may
      emit) and `abstract type SyntheticEvent <: Event end` (what a recogniser or tracker may
      emit). `MousePress`, `KeyChord`, `MouseEnter`, `MouseLeave` are the synthetic ones.
- [ ] `get_modifiers(::Event)::Modifiers`, and define `is_ctrl`/`is_shift`/`is_alt`/`is_meta`
      **once for all events** — today they exist only for the three keyboard types even though
      every mouse event carries a `Modifiers`.
- [ ] Type `EventEnvelope.event::Event`; state `read_from_devices`'s return type
      (`Union{EventEnvelope,Nothing}` over `DeviceEvent`s). This makes AR-42's "convert platform
      events in the backend" a type-level fact rather than a comment.
- [ ] Sink `WindowClose` / `WindowResize` / `WindowDefocus` from visual's `screen/ScreenDocument.jl`
      into `event/WindowEvent.jl` (AR-47: they reference nothing visual; `WindowQuit` is already in
      the kernel, so the window-event vocabulary is currently split across two packages). The window
      *document* and its operations stay in visual.

Verify: `test_kernel()`, `test_visual()`, `run_example` on an SDL and a console example (event
construction happens in the backends).

### Phase 3 — the pattern language

- [ ] Derive the event-field table from the types (`fieldnames` minus `:modifiers`) instead of
      hand-maintaining `_EVENT_TYPES`, so pattern support cannot drift from the event structs again.
- [ ] Collapse the eight near-identical `GesturePattern` structs (plus the `@eval` loop generating
      three of them) into one generic `EventPattern{E<:Event}` holding a field-constraint
      `NamedTuple` — one `matches`, one `describe`. Keep `KeyDownPattern(...)`, `KeyPressPattern(...)`,
      … as convenience constructors returning `EventPattern{KeyDown}` etc., so the ~10 hand-written
      construction sites in base/visual/domain are unaffected.
- [ ] This closes the gap: `MouseEnter`/`MouseLeave`/`KeyChord` patterns now exist.
- [ ] The pattern language lives in `event/EventPattern.jl`, so `binding/` imports it as an
      exported name — the private-parser fragment hack disappears (AR-48).

Verify: `test_kernel()`, `test_domain()` (the `@gestures` domains), `test_gesture_map` /
GestureMapTest.

### Phase 4 — binding-layer cleanup (the AR defects)

- [ ] Export one `fire_gesture_bindings(bindings, target, selection, event)`. Today the loop is
      written three times: `_fire_gestures`, and again inline in `read_projection_gesture`
      (`projection/GestureBindings.jl`) because the helper is private across a module boundary —
      AR-48 says export it, don't re-implement it.
- [ ] Fold `read_document_gesture` and `read_node_gesture` into one function with an explicit
      selection argument; they differ *only* in where the selection comes from.
- [ ] Delete `_GESTURE_CACHE` (the module-level `IdDict`). It is the letter of AR-6/AR-45 and it is
      not thread-safe. It memoises a supertype walk of a few `append!`s — recomputing per event is
      free. If profiling ever disagrees, the replacement is a per-editor memo, not a global.
- [ ] Move `is_help_gesture` out of the kernel. "F1 means help" is an *intent* hard-coded in the
      input stack, contradicting the principle the surrounding comment itself states, and its
      docstring names `GestureHelpProjection` and `OpenWindowOperation` (AR-70). It becomes an
      ordinary reified binding owned by the help projection in `domain/gesturemap/`.

Verify: `test_kernel()`, `test_domain()`, `test_repl` on a `@gestures` domain (json), and a live
`run_example("workbench")` — gesture-binding reuse bugs can pass direct-read tests yet fail live.

### Phase 5 — documentation and the docstring scrub

- [ ] AR-70/AR-71 scrub of every moved file: `Mouse.jl` names `WidgetHoverTrackingProjection`;
      `ScreenDevice.jl` names `ScreenDocument` with a stale path; `GestureBinding.jl` says "this is
      the kernel half (Stage 1 + Stage 2) … ported onto it in `document/Json.jl`"; `pop_gesture!`
      explains it matches "the backend's *old* behaviour"; `is_help_gesture` cites
      "event-to-gesture.md Phase 2 B"; `Keyboard.jl`/`Modifiers.jl` document themselves in SDL
      constants (`SDL_KEYDOWN`, `KMOD_LCTRL`). Every one of these points up the dependency chain or
      records history that belongs in a done plan.
- [ ] Fix the two fragment docstrings that name modules which do not exist.
- [ ] Update `documentation/architecture.md` (the layer inventory),
      `package/kernel/doc/devices-and-backends.md` (the device/event tables), and the layer diagram
      in `ProjecturedKernel.jl`'s docstring (AR-60).

### Phase 6 — decision gate: does `@event_case` survive? (optional; may become its own plan)

`@event_case` and `@gestures` parse the same grammar with the same parser; one compiles to `isa`
chains (fast, **invisible**), the other reifies to data (inspectable). Once patterns are generic
reified data, `@event_case` is redundant: its remaining use sites are the geometry arms in the
visual/domain projections, which express fine as `get_projection_gesture_bindings` tables fired by
`read_projection_gesture` (the pattern never matches x/y; the operation closure gets the event and
reads them).

The payoff is bigger than deleting a macro: **every mouse and geometry gesture becomes
inspectable.** Today they are compiled into `@event_case` bodies, so the gesture-help projection
cannot see them at all — the "what fires is what is shown" property `@gestures` exists for is
silently broken for exactly the gestures a new user most needs help with. The cost is a table walk
instead of an `isa` chain per event, which is nothing.

- [ ] Audit the 8 `@event_case` sites. The SDL one is doing platform *translation*, not binding, and
      stays a plain dispatch. Some arms may return non-`Operation` values (an `Intent`, a
      pass-through gesture) — check each before committing to the collapse.
- [ ] Decide: collapse, or keep `@event_case` as a documented fast path with a stated reason.

## Non-goals

- No change to what any gesture *does*. Every phase is structure; behaviour is held constant and
  the existing tests are the oracle.
- No change to the `Projection`-typed gesture-seam methods' home. They dispatch on `Projection` and
  correctly live in the projection layer; the split across two layers is the seam pattern working.
- `HeadlessBackend`'s scripted event queue (AR-68 "no test doubles in main") is a pre-existing
  question this plan does not open.

## Verification summary

| Phase | Narrowest sufficient test |
| --- | --- |
| 1 | `test_kernel_layering()` → `test_kernel()` → full-stack load → `test_visual()` / `test_domain()` |
| 2 | `test_kernel()`, `test_visual()`, `run_example` (SDL + console) |
| 3 | `test_kernel()`, `test_domain()`, GestureMapTest |
| 4 | `test_kernel()`, `test_domain()`, `test_repl(json_example)`, live `run_example("workbench")` |
| 5 | docs only |

A broad `test_all()` sweep is worth it once, after Phase 4, to confirm the baseline
(~13 known failures) is unchanged.
