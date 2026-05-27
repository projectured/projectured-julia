# Extend Mouse Events

Redesign mouse event structs to support down/up/press semantics, all mouse
buttons, and modifier key state. Also unify modifier handling with `KeyPress`.

---

## Current State

- `MouseClick(button::Symbol, x::Int, y::Int)` — fired on `SDL_MOUSEBUTTONDOWN` only
- `MouseMove(x::Int, y::Int)` — no modifiers, no button state
- `MouseScroll(dx::Int, dy::Int, x::Int, y::Int)` — no modifiers
- `KeyPress(key::Symbol, ctrl::Bool)` — only ctrl, no shift/alt
- SDL backend ignores `SDL_MOUSEBUTTONUP`; `read_from_devices` filters out
  motion events (only button-down and scroll reach projections)

## Target State

Three button events (`MouseDown`, `MouseUp`, `MousePress`) plus `MouseMove`
and `MouseScroll`, all carrying a shared `Modifiers` struct. `KeyPress` gains
the same modifier fields.

---

## Step 1: Add `Modifiers` struct to a shared module

File: `program/src/device/Modifiers.jl` — new `ModifiersModule`

```julia
struct Modifiers
    ctrl::Bool
    shift::Bool
    alt::Bool
end

Modifiers() = Modifiers(false, false, false)
```

- Export `Modifiers`
- Include + using in `Projectured.jl` (before Keyboard and Mouse modules)

A single reusable struct avoids duplicating three Bool fields on every event
type and keeps keyboard/mouse consistent.

---

## Step 2: Redesign mouse event structs

File: `program/src/device/Mouse.jl`

Replace `MouseClick` with three button-event types and add modifiers to all:

```julia
struct MouseDown
    button::Symbol      # :left, :middle, :right
    x::Int
    y::Int
    modifiers::Modifiers
end

struct MouseUp
    button::Symbol
    x::Int
    y::Int
    modifiers::Modifiers
end

struct MousePress
    button::Symbol
    x::Int
    y::Int
    modifiers::Modifiers
end

struct MouseMove
    x::Int
    y::Int
    buttons::Symbol     # :none, :left, :middle, :right (currently held)
    modifiers::Modifiers
end

struct MouseScroll
    dx::Int
    dy::Int
    x::Int
    y::Int
    modifiers::Modifiers
end
```

- Remove `MouseClick` export; add `MouseDown`, `MouseUp`, `MousePress`
- Keep a **deprecation alias** `const MouseClick = MouseDown` if needed for
  incremental migration, or do a clean rename (preferred)

### Semantics

- **`MouseDown`** — raw button-down, fired immediately on `SDL_MOUSEBUTTONDOWN`
- **`MouseUp`** — raw button-up, fired on `SDL_MOUSEBUTTONUP`
- **`MousePress`** — synthesised click: emitted when `MouseUp` occurs at
  (approximately) the same position as the preceding `MouseDown` for the same
  button, within a short time window. Synthesis lives in the backend
  (`sdl_to_mouse`) so projections don't need to track press/release pairs.
- **`MouseMove`** — includes which button (if any) is currently held, enabling
  drag detection upstream.

---

## Step 3: Update `KeyPress` to use `Modifiers`

File: `program/src/device/Keyboard.jl`

```julia
struct KeyPress
    key::Symbol
    modifiers::Modifiers
end
```

Convenience accessor: `KeyPress(key, ctrl::Bool) = KeyPress(key, Modifiers(ctrl, false, false))`
keeps backward compat for existing call sites until they are migrated.

---

## Step 4: Update SDL backend — modifier extraction

File: `program/src/backend/Sdl.jl`

Add a helper to extract `Modifiers` from the SDL modifier bitmask:

```julia
function sdl_modifiers(mod::UInt16)::Modifiers
    ctrl  = (mod & UInt16(0x00C0)) != UInt16(0)  # KMOD_LCTRL | KMOD_RCTRL
    shift = (mod & UInt16(0x0003)) != UInt16(0)  # KMOD_LSHIFT | KMOD_RSHIFT
    alt   = (mod & UInt16(0x0300)) != UInt16(0)  # KMOD_LALT | KMOD_RALT
    Modifiers(ctrl, shift, alt)
end
```

Use `sdl_modifiers` in both `sdl_to_keypress` and `sdl_to_mouse`.

---

## Step 5: Update SDL backend — mouse event translation

File: `program/src/backend/Sdl.jl`

### 5a. `sdl_to_mouse`

- `SDL_MOUSEBUTTONDOWN` (0x00000401) → `MouseDown`
- `SDL_MOUSEBUTTONUP` (0x00000402) → `MouseUp`
- `SDL_MOUSEMOTION` (0x00000400) → `MouseMove`
- `SDL_MOUSEWHEEL` (0x00000403) → `MouseScroll`
- All calls pass `sdl_modifiers(SDL_GetModState())` (or extract mod from the
  event struct where available)

### 5b. `MousePress` synthesis

Track the last `MouseDown` in the backend (button + coords + timestamp).
On `MouseUp`, if same button + distance < 5 px + elapsed < 300 ms, emit
**both** `MouseUp` and `MousePress` (return a vector, or call the reader
twice). If the overhead of returning two events is awkward, emit only
`MousePress` and let consumers that need raw up/down opt in separately.

Simpler alternative: emit `MouseDown` and `MouseUp` only; let a
`ClickRecogniser` projection synthesise `MousePress`. This keeps the backend
thin and gives projections full control. **Decision needed.**

### 5c. `read_from_devices`

- Add `SDL_MOUSEBUTTONUP` (0x00000402) and `SDL_MOUSEMOTION` (0x00000400) to
  the event-type filter so they reach projections.
- Currently only button-down and scroll are forwarded; motion and button-up are
  silently dropped.

---

## Step 6: Update `sdl_to_keypress`

File: `program/src/backend/Sdl.jl`

Replace the inline `ctrl` extraction with `sdl_modifiers(mod)` and construct
`KeyPress(key, modifiers)`.

---

## Step 7: Migrate projection readers — rename `MouseClick` → `MouseDown`

All `projection_read` methods that dispatch on `MouseClick`:

| File | What to change |
|------|---------------|
| `projection/primitive/GraphicsCaching.jl` | `evt isa MouseClick` → `evt isa MouseDown` (or `MousePress`) |
| `projection/primitive/WidgetToGraphics.jl` | `_route_click_to_children` signature + all call sites |
| `projection/primitive/TextToGraphics.jl` | mouse-click selection logic (comments + dispatch) |

### Decision: `MouseDown` vs `MousePress` for selection

Most projections that currently handle `MouseClick` actually want **press**
semantics (select on click). They should dispatch on `MousePress` instead of
`MouseDown`, so that:
- A press-and-drag doesn't immediately select (the drag gesture absorbs the
  down event and no `MousePress` is emitted).
- Selection only fires when the user completes a full click.

If `MousePress` synthesis is deferred to a projection layer, these readers
can keep dispatching on `MouseDown` for now and migrate later.

---

## Step 8: Add modifier-aware routing helpers

File: `projection/primitive/WidgetToGraphics.jl`

Update `_route_click_to_children` and `_route_scroll_to_children` to propagate
modifiers through coordinate translation:

```julia
_route_down_to_children(child_entries, evt::MouseDown) =
    _route_to_children(child_entries, evt.x, evt.y,
        (x, y) -> MouseDown(evt.button, x, y, evt.modifiers))
```

Same pattern for `MouseUp`, `MousePress`, `MouseMove`.

---

## Step 9: Update `Projectured.jl` wiring

File: `program/src/Projectured.jl`

- Add `include("device/Modifiers.jl")` before Keyboard.jl
- Add `using .ModifiersModule: Modifiers`
- Update `using .MouseModule` to import new types
- Update `export` block: remove `MouseClick`, add `MouseDown`, `MouseUp`,
  `MousePress`, `Modifiers`

---

## Step 10: Update dragging plan

File: `plan/dragging.md`

Replace references to `MouseClick` / `MouseRelease` with `MouseDown` /
`MouseUp` to stay consistent with the new event vocabulary.

---

## Step 11: Update tests

Grep for `MouseClick` in `test/` and update constructors + assertions.
Add new tests:
- `Modifiers` construction and field access
- `sdl_modifiers` bitmask decoding
- `MouseDown`, `MouseUp`, `MousePress` round-trip through `sdl_to_mouse`
- Projection readers receive correct modifier state

---

## Step 12: Update guide documentation

Files: `guide/design.md`, `guide/editor/` docs

- Document the new event types and `Modifiers` struct
- Update the `KeyPress` description to show the new `modifiers` field
- Note that `MouseClick` is removed / aliased

---

## Migration Order

1. `Modifiers` struct (Step 1) — no breakage
2. `KeyPress` update (Step 3) + backward-compat constructor — no breakage
3. `sdl_modifiers` helper (Step 4) — no breakage
4. Mouse structs (Step 2) — **breaking**: renames `MouseClick`
5. SDL mouse translation (Step 5) + keypress (Step 6) — depends on 2–4
6. `read_from_devices` filter (Step 5c) — enables motion/button-up forwarding
7. Projection reader migration (Steps 7–8) — must follow 4
8. Wiring (Step 9) — final hookup
9. Plans, tests, docs (Steps 10–12) — parallel with 7–8

Steps 4–6 form the backend batch; steps 7–8 form the projection batch.
Each batch can be done in one commit.

---

## Open Questions

1. **`MousePress` synthesis location** — backend (simpler for consumers) vs
   projection (more flexible, keeps backend thin)? Recommend: backend, with an
   optional projection override later.
2. **Double-click / triple-click** — out of scope for now? If wanted, add
   `clicks::Int` field to `MousePress`.
3. **`MouseMove` in idle state** — projections currently never see motion.
   Forwarding all motion events is noisy. Options: (a) forward all, let
   projections filter; (b) only forward while a button is held; (c) add an
   opt-in flag per projection. Recommend (b) initially.
4. **Backward compat alias** — keep `const MouseClick = MouseDown` or do a
   clean break? Clean break is better since the codebase is small and all call
   sites are known.
