# Device physical properties (backend-populated); retire the display-size global

## Goal

Give the three device markers real physical properties, populated by the backend,
and retire the process-global display-size provider (`DisplayModule`) — an
PAR-PER-EDITOR-STATE smell — in favour of per-editor device state.

Rationale (from the user):
- **Screen** hardware resolution → decides the editor's window resolution/size
  (today's only `get_display_size()` consumer).
- **Mouse** button count & scroll-wheel support → later feeds how events map to
  operations.
- **Keyboard** layout → later matters for the same event→operation mapping.

## Property set

Plain **mutable** structs (devices are per-editor config/state, not documents /
not reactive; mutable so the backend can populate in place). Zero-arg
constructors preserved via field defaults, so every existing
`Screen()`/`Mouse()`/`Keyboard()` call site keeps working.

| device | fields (defaults) |
|---|---|
| `Screen` | `width::Int=1280`, `height::Int=800`, `scale::Float64=1.0` |
| `Mouse` | `button_count::Int=3`, `has_scroll_wheel::Bool=true` |
| `Keyboard` | `layout::Symbol=:qwerty` |

The `(1280, 800)` Screen default is exactly the old SDL-free
`get_display_size` fallback — so a headless/console editor keeps that size.

## Design decisions (the non-obvious forks)

1. **A display query must survive — as a backend method, not a global.** The
   window size is chosen *before* the editor/devices exist (FileEditor/Gallery
   size the `ScreenDocument` scene, then call `run_editor!` which inits the
   backend internally). So the Screen device cannot be the source for
   pre-editor sizing. Resolution: convert `get_display_size()` (global provider
   Ref) into a **backend generic** `get_display_size(backend; display=0)` in
   `BackendInterface.jl`; SDL implements it, the default returns `(1280, 800)`.
   This removes the process-global mutable `_DISPLAY_SIZE_PROVIDER` Ref (the
   actual PAR-PER-EDITOR-STATE smell) while keeping the query.

2. **`DisplayModule` (`backend/Display.jl`) is deleted.** Once `get_display_size`
   is a backend generic and the provider Ref is gone, `DisplayModule` is empty.
   Delete the file, its `include` in `BackendLayer.jl`, and its line in the
   `CLAUDE.md` seal inventory. (Touches the inventory structure — flagged for
   explicit OK, since the file is listed there as `⬜`.)

3. **Backend populates devices via a new no-op-defaulted seam
   `configure_devices!(backend, devices)`** (declared in `BackendInterface.jl`,
   default `= nothing` in `BackendDefaults.jl`, so Headless/Console/Web need no
   method). SDL implements it: fills each `Screen`'s `width`/`height` (its
   display query) and `scale` (from the existing `_DISPLAY_SCALE` detection).
   `run_editor!` calls it right after `initialize_backend!`, before building the
   `Editor`. `initialize_backend!`'s arity is left unchanged (fewer moving
   parts than threading `devices` through it).

4. **SDL's internal `_DISPLAY_SCALE` global stays (33 sites).** Out of scope for
   this pass — retiring it is a deep SDL-rendering refactor. We *read* it to
   populate `Screen.scale`; SDL rendering keeps using its own value (same
   number). Flag as a follow-up.

5. **Mouse/Keyboard are populated with defaults for now.** SDL cannot reliably
   query button count / keyboard layout in SDL2, so `configure_devices!` leaves
   them at their struct defaults. The fields exist for the future event-mapping
   consumers the user named; honest-doc the "not yet discovered" status.

## Steps (each its own commit)

> **Note:** steps 2–5 could not be separate commits — `get_display_size` cannot
> exist in two modules at once (the no-duplicate-export rule), so moving it out
> of `DisplayModule` into `BackendModule` and migrating every consumer had to be
> one atomic change. Landed together; SDL verified populating a real display
> `(2560×1440 @ 2.0)`.

- [x] **1. Device structs.** Make `Screen`/`Mouse`/`Keyboard` mutable with the
  fields + defaults + keyword/zero-arg ctors. Update their docstrings (physical
  properties, honestly noting which the backend fills). Kernel-only; verify load
  + `test_kernel_layering()` (Device.jl still declares only `abstract type
  Device`; the fragments gain fields — Device.jl interface purity unaffected).
  **Done** — smoke (defaults, keyword ctors, in-place mutation) + guard 10/10.
- [x] **2. Backend seam.** Add `get_display_size(backend; display=0)` and
  `configure_devices!(backend, devices)` to `BackendInterface.jl`; export both
  from `BackendModule`; add the `configure_devices!` no-op + the
  `get_display_size` `(1280,800)` default to `BackendDefaults.jl`. Delete
  `backend/Display.jl` + its `BackendLayer.jl` include + `CLAUDE.md` line.
- [x] **3. Editor.** `run_editor!` calls `configure_devices!(backend, devices)`
  after `initialize_backend!`. Verify with HeadlessBackend (no-op path: defaults
  survive).
- [x] **4. SDL.** Implement `get_display_size(backend::SdlBackend; display)` and
  `configure_devices!(backend::SdlBackend, devices)`; drop the `__init__`
  `set_display_size_provider!` registration. Load SDL, confirm methods attach.
- [x] **5. Consumers.** FileEditor/Gallery: `get_display_size()` →
  `get_display_size(backend)` (thread the resolved backend into the sizing).
- [x] **6. Docs.** `naming.md`, `editor.md`, `devices-and-backends.md`,
  `architecture.md` (both kernel + top-level), `visual/doc/architecture.md`,
  `PAR-BACKEND-SEAM`, `BackendInterface.jl` header (done in step 2), device
  fragment docstrings (done in step 1). Retired-global + new device fields noted;
  the deleted `### DisplayModule` section removed.
- [x] **7. Tests.** `HeadlessBackendTest`: device defaults + keyword ctors,
  `get_display_size` fallback `(1280,800)`, `configure_devices!` no-op leaves
  defaults (→ 21/21). New `sdl/test/backend/DeviceConfigTest.jl`
  (`test_device_config`): `get_display_size(SdlBackend())` is a positive Int
  tuple, `configure_devices!` populates the Screen to match + a Float64 scale,
  Mouse/Keyboard untouched (→ SDL 37/37). PAR-NEW-CODE-SHIPS-TESTS.

## Status: DONE

All seven steps landed. Commits: `18fa5b76` (device structs), `11713291`
(backend seam + retire the display-size global), `f642b7fe` (docs), and the
test commit. Follow-ups recorded above (SDL `_DISPLAY_SCALE` global; actually
consuming Mouse/Keyboard properties in event→operation mapping) remain open.

## Out of scope / follow-ups
- Retiring SDL's internal `_DISPLAY_SCALE` global (33 sites).
- Actually *consuming* Mouse/Keyboard properties in event→operation mapping.

## Verification
- `test_kernel_layering()` 10/10; kernel load; HeadlessBackend round-trip.
- `test_console_backend()` (editor loop) green.
- SDL + Web load; SDL populates a real Screen resolution; examples still size
  windows.
