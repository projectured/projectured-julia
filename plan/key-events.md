# Key Events — Extend with KeyDown, KeyUp, KeyPress + Modifiers + Decoded Character

Replace the single `KeyPress` struct with a proper three-event keyboard model
that distinguishes physical key actions from logical character input, carries
all modifier flags, and delivers a decoded Unicode character where applicable.

---

## Current State

### `Keyboard.jl`

```julia
struct KeyPress
    key::Symbol   # :left, :right, :up, :down, :home, :end, :return, :comma, :period
    ctrl::Bool
end
```

- Single event type conflating physical key-down with logical character input.
- Only `ctrl` modifier tracked; `shift`, `alt`, `meta` are lost.
- No decoded character — printable keys are either ignored or mapped to
  `:comma`, `:period` etc. by symbol name.
- `sdl_to_keypress` in `Sdl.jl` only fires on `SDL_KEYDOWN`; `SDL_KEYUP` and
  `SDL_TEXTINPUT` are discarded.

### Consumers (files that `import KeyPress` or `isa KeyPress`)

| File | Usage |
|---|---|
| `projection/primitive/TextToGraphics.jl` | Navigation (arrows, home/end, up/down) |
| `projection/generic/Focusing.jl` | `Ctrl+,` / `Ctrl+.` focus zoom |
| `projection/primitive/WidgetToGraphics.jl` | Currently stubs (`return nothing`) |
| `backend/Sdl.jl` | Translates SDL keysym → `KeyPress` |
| `editor/Editor.jl` | Routes events to `projection_read` |

---

## Design

### Three Event Types

| Struct | SDL Source | Semantics |
|---|---|---|
| `KeyDown` | `SDL_KEYDOWN` | A physical key was pressed. Carries the key symbol and all modifiers. Used for navigation, shortcuts, non-character actions. Fires with repeat when held. |
| `KeyUp` | `SDL_KEYUP` | A physical key was released. Same fields as `KeyDown`. Needed for future features (drag-end, modifier tracking, key-repeat suppression). |
| `KeyPress` | `SDL_TEXTINPUT` | A logical character was produced by the OS input method. Carries the decoded `Char` (full Unicode). This is the event for text insertion. |

Rationale: SDL's own model separates `SDL_KEYDOWN`/`SDL_KEYUP` (physical
scancodes + modifiers) from `SDL_TEXTINPUT` (composed Unicode text). Mapping
this 1:1 avoids reimplementing dead-key composition, IME, and keyboard-layout
translation.

### Modifier Flags

All three event types carry a `Modifiers` struct (or inline fields):

```julia
struct Modifiers
    ctrl::Bool    # either Ctrl key
    shift::Bool   # either Shift key
    alt::Bool     # either Alt key (Option on macOS)
    meta::Bool    # Super/Windows/Command key
end
```

`KeyDown` and `KeyUp` always populate all four fields from the SDL mod
bitmask. `KeyPress` populates them as well (SDL_TEXTINPUT does not carry
modifiers directly, but we can snapshot `SDL_GetModState()` at event time).

### Key Symbol

`KeyDown` and `KeyUp` carry a `key::Symbol` field, same vocabulary as today
plus additional symbols to cover the full useful keyboard:

**Navigation:** `:left`, `:right`, `:up`, `:down`, `:home`, `:end`,
`:page_up`, `:page_down`

**Editing:** `:backspace`, `:delete`, `:return`, `:tab`, `:insert`

**Function keys:** `:f1` .. `:f12`

**Modifier-only:** `:lctrl`, `:rctrl`, `:lshift`, `:rshift`, `:lalt`,
`:ralt`, `:lmeta`, `:rmeta`

**Misc:** `:escape`, `:space`, `:caps_lock`

**Printable fallback:** `:char` (for `KeyDown`/`KeyUp` of printable keys
where the specific physical key identity is not important; the actual
character comes via `KeyPress`)

### Decoded Character in `KeyPress`

```julia
struct KeyPress
    char::Char        # the Unicode character produced
    text::String      # the full UTF-8 text from SDL_TEXTINPUT (usually 1 char)
    modifiers::Modifiers
end
```

The `char` field is the first `Char` of the text input event. The `text`
field preserves the full string for multi-codepoint inputs (e.g. IME
composition results). Most consumers will use `char`.

---

## Step-by-Step Plan

### Step 1: Define `Modifiers` struct in `Keyboard.jl`

File: `program/src/device/Keyboard.jl`

```julia
struct Modifiers
    ctrl::Bool
    shift::Bool
    alt::Bool
    meta::Bool
end

Modifiers() = Modifiers(false, false, false, false)
Modifiers(; ctrl=false, shift=false, alt=false, meta=false) =
    Modifiers(ctrl, shift, alt, meta)
```

Export `Modifiers`.

---

### Step 2: Define `KeyDown` and `KeyUp` in `Keyboard.jl`

```julia
struct KeyDown
    key::Symbol
    modifiers::Modifiers
    repeat::Bool        # true if this is an auto-repeat event
end

struct KeyUp
    key::Symbol
    modifiers::Modifiers
end
```

Export `KeyDown`, `KeyUp`.

---

### Step 3: Redefine `KeyPress` in `Keyboard.jl`

Replace the old `KeyPress(key::Symbol, ctrl::Bool)` with:

```julia
struct KeyPress
    char::Char
    text::String
    modifiers::Modifiers
end

KeyPress(char::Char) = KeyPress(char, string(char), Modifiers())
KeyPress(char::Char, mods::Modifiers) = KeyPress(char, string(char), mods)
```

Export `KeyPress` (already exported).

---

### Step 4: Add backward-compatible helpers

To ease migration, add helpers that let existing code work with minimal
changes:

```julia
# Convenience accessors on all three types
is_ctrl(e::Union{KeyDown, KeyUp, KeyPress})  = e.modifiers.ctrl
is_shift(e::Union{KeyDown, KeyUp, KeyPress}) = e.modifiers.shift
is_alt(e::Union{KeyDown, KeyUp, KeyPress})   = e.modifiers.alt
is_meta(e::Union{KeyDown, KeyUp, KeyPress})  = e.modifiers.meta
```

---

### Step 5: Update `sdl_to_keypress` → split into `sdl_to_keydown`, `sdl_to_keyup`

File: `program/src/backend/Sdl.jl`

Replace `sdl_to_keypress(keysym, mod)` with:

```julia
function sdl_mod_to_modifiers(mod::UInt16)
    Modifiers(
        ctrl  = (mod & UInt16(0x00C0)) != 0,  # KMOD_LCTRL | KMOD_RCTRL
        shift = (mod & UInt16(0x0003)) != 0,  # KMOD_LSHIFT | KMOD_RSHIFT
        alt   = (mod & UInt16(0x0300)) != 0,  # KMOD_LALT | KMOD_RALT
        meta  = (mod & UInt16(0x0C00)) != 0,  # KMOD_LGUI | KMOD_RGUI
    )
end

function sdl_keysym_to_symbol(keysym::Int32)
    # Navigation
    keysym == Int32(1073741904) && return :left       # SDLK_LEFT
    keysym == Int32(1073741903) && return :right      # SDLK_RIGHT
    keysym == Int32(1073741906) && return :up         # SDLK_UP
    keysym == Int32(1073741905) && return :down       # SDLK_DOWN
    keysym == Int32(1073741898) && return :home       # SDLK_HOME
    keysym == Int32(1073741901) && return :end        # SDLK_END
    keysym == Int32(1073741899) && return :page_up    # SDLK_PAGEUP
    keysym == Int32(1073741902) && return :page_down  # SDLK_PAGEDOWN
    # Editing
    keysym == Int32(8)          && return :backspace   # SDLK_BACKSPACE
    keysym == Int32(127)        && return :delete      # SDLK_DELETE
    keysym == Int32(13)         && return :return      # SDLK_RETURN
    keysym == Int32(9)          && return :tab         # SDLK_TAB
    keysym == Int32(1073741897) && return :insert      # SDLK_INSERT
    # Function keys
    keysym == Int32(1073741882) && return :f1
    keysym == Int32(1073741883) && return :f2
    keysym == Int32(1073741884) && return :f3
    keysym == Int32(1073741885) && return :f4
    keysym == Int32(1073741886) && return :f5
    keysym == Int32(1073741887) && return :f6
    keysym == Int32(1073741888) && return :f7
    keysym == Int32(1073741889) && return :f8
    keysym == Int32(1073741890) && return :f9
    keysym == Int32(1073741891) && return :f10
    keysym == Int32(1073741892) && return :f11
    keysym == Int32(1073741893) && return :f12
    # Misc
    keysym == Int32(27)         && return :escape      # SDLK_ESCAPE
    keysym == Int32(32)         && return :space        # SDLK_SPACE
    keysym == Int32(1073741881) && return :caps_lock   # SDLK_CAPSLOCK
    # Modifier-only keys
    keysym == Int32(1073742048) && return :lctrl
    keysym == Int32(1073742052) && return :rctrl
    keysym == Int32(1073742049) && return :lshift
    keysym == Int32(1073742053) && return :rshift
    keysym == Int32(1073742050) && return :lalt
    keysym == Int32(1073742054) && return :ralt
    keysym == Int32(1073742051) && return :lmeta
    keysym == Int32(1073742055) && return :rmeta
    # Printable fallback
    return :char
end

function sdl_to_keydown(keysym::Int32, mod::UInt16, is_repeat::Bool)
    sym = sdl_keysym_to_symbol(keysym)
    KeyDown(sym, sdl_mod_to_modifiers(mod), is_repeat)
end

function sdl_to_keyup(keysym::Int32, mod::UInt16)
    sym = sdl_keysym_to_symbol(keysym)
    KeyUp(sym, sdl_mod_to_modifiers(mod))
end

function sdl_to_keypress(text_bytes::NTuple{32,UInt8})
    # SDL_TEXTINPUT provides a null-terminated UTF-8 string in .text[32]
    len = something(findfirst(==(0x00), collect(text_bytes)), 33) - 1
    len == 0 && return nothing
    text = String(UInt8[text_bytes[i] for i in 1:len])
    ch = first(text)
    mod = SDL_GetModState()
    KeyPress(ch, text, sdl_mod_to_modifiers(UInt16(mod)))
end
```

---

### Step 6: Update `read_from_devices` in `Sdl.jl`

Handle `SDL_KEYDOWN`, `SDL_KEYUP`, and `SDL_TEXTINPUT`:

```julia
function read_from_devices(::SdlBackend, devices)
    event_ref = Ref{SDL_Event}()
    while Bool(SDL_PollEvent(event_ref))
        evt = event_ref[]
        if evt.type == SDL_QUIT
            return QuitEvent()
        elseif evt.type == SDL_KEYDOWN
            keysym = evt.key.keysym.sym
            if keysym == Int32(27)  # Escape
                return QuitEvent()
            end
            is_repeat = evt.key.repeat != 0
            return sdl_to_keydown(keysym, evt.key.keysym.mod, is_repeat)
        elseif evt.type == SDL_KEYUP
            return sdl_to_keyup(evt.key.keysym.sym, evt.key.keysym.mod)
        elseif evt.type == SDL_TEXTINPUT       # 0x00000303
            kp = sdl_to_keypress(evt.text.text)
            kp !== nothing && return kp
        elseif evt.type == 0x00000401 || evt.type == 0x00000403
            mouse = sdl_to_mouse(evt)
            mouse !== nothing && return mouse
        end
    end
    return nothing
end
```

Note: `SDL_StartTextInput()` must be called once during init (it is the
default on most platforms, but being explicit avoids surprises).

---

### Step 7: Update `Projectured.jl` exports

File: `program/src/Projectured.jl`

- Add `using .KeyboardModule: KeyDown, KeyUp, Modifiers` alongside the
  existing `KeyPress` import.
- Add `export KeyDown, KeyUp, Modifiers`.

---

### Step 8: Migrate `TextToGraphics.jl` reader — navigation

File: `program/src/projection/primitive/TextToGraphics.jl`

Change:

```julia
evt isa KeyPress || return nothing
```

to:

```julia
evt isa KeyDown || return nothing
```

Replace `evt.ctrl` with `is_ctrl(evt)` (or `evt.modifiers.ctrl`).

Replace `evt.key == :left` etc. — these stay the same since `KeyDown.key` is
still a `Symbol`.

The existing `:comma` / `:period` checks can remain on `KeyDown` since those
are keyboard shortcuts, not text insertion.

---

### Step 9: Migrate `Focusing.jl` reader — shortcuts

File: `program/src/projection/generic/Focusing.jl`

Change:

```julia
elseif event isa KeyPress && event.ctrl
    if event.key == :comma
```

to:

```julia
elseif event isa KeyDown && is_ctrl(event)
    if event.key == :comma
```

---

### Step 10: Migrate `WidgetToGraphics.jl` reader stubs

File: `program/src/projection/primitive/WidgetToGraphics.jl`

These are currently all `return nothing`. Update the `evt` type annotations
where present to accept `Union{KeyDown, KeyUp, KeyPress}` or leave
untyped — no functional change needed.

---

### Step 11: Update `Editor.jl` — accept all three event types

File: `program/src/editor/Editor.jl`

The `read!` function already passes events generically:

```julia
editor.operation = projection_read(editor.projection, editor.iomap, event)
```

No structural change needed. The new event types will flow through naturally.
However, add `KeyDown` and `KeyUp` to the doc comment for `read!`.

---

### Step 12: Add `SDL_StartTextInput` call

File: `program/src/backend/Sdl.jl`

In `init!`:

```julia
function init!(::SdlBackend)
    @assert SDL_Init(SDL_INIT_VIDEO) == 0
    @assert TTF_Init() == 0
    SDL_StartTextInput()
end
```

And in `quit!`, optionally call `SDL_StopTextInput()`.

---

### Step 13: Update tests

- Any test that constructs `KeyPress(:left, false)` must be changed to
  `KeyDown(:left, Modifiers())`.
- Any test that constructs `KeyPress(:comma, true)` must be changed to
  `KeyDown(:comma, Modifiers(ctrl=true))`.
- Add new tests for `KeyPress('a')`, `KeyDown(:backspace, Modifiers())`, etc.
- Add `sdl_mod_to_modifiers` unit tests for each modifier bit.

---

### Step 14: Update guide documentation

Files: `guide/design.md`, `CLAUDE.md`

- Section 6.9 "KeyPress Abstraction" — rewrite to describe the three-event
  model.
- Section "Keyboard.jl — KeyPress" — replace with the new struct definitions.
- All code examples showing `KeyPress(:left, false)` → `KeyDown(:left, Modifiers())`.
- Add description of `Modifiers` struct.
- Document `KeyPress.char` / `KeyPress.text` for text insertion.

---

## Detailed SDL Modifier Bitmask Reference

```
KMOD_LSHIFT = 0x0001     KMOD_RSHIFT = 0x0002
KMOD_LCTRL  = 0x0040     KMOD_RCTRL  = 0x0080
KMOD_LALT   = 0x0100     KMOD_RALT   = 0x0200
KMOD_LGUI   = 0x0400     KMOD_RGUI   = 0x0800
KMOD_NUM    = 0x1000     KMOD_CAPS   = 0x2000
```

---

## Migration Summary

| Old | New | Notes |
|---|---|---|
| `KeyPress(:left, false)` | `KeyDown(:left, Modifiers())` | Navigation events are `KeyDown` |
| `KeyPress(:comma, true)` | `KeyDown(:comma, Modifiers(ctrl=true))` | Shortcuts are `KeyDown` |
| `evt isa KeyPress` | `evt isa KeyDown` | For navigation/shortcut handlers |
| `evt.ctrl` | `evt.modifiers.ctrl` or `is_ctrl(evt)` | Modifier access |
| (not possible before) | `KeyPress('a')` | Character insertion from `SDL_TEXTINPUT` |
| (not possible before) | `KeyUp(:shift, Modifiers(shift=false))` | Key release tracking |

---

## Future Considerations

- **Key repeat filtering** — `KeyDown.repeat` allows consumers to ignore
  auto-repeat if desired (e.g. for single-shot shortcuts).
- **IME composition** — `SDL_TEXTEDITING` events can be added later as a
  `KeyComposing` event for showing inline IME candidates.
- **Clipboard shortcuts** — With `Ctrl+C`/`Ctrl+V` now distinguishable via
  `KeyDown` (they won't generate `SDL_TEXTINPUT`), clipboard operations can
  be implemented cleanly.
- **Terminal backend** — Terminal escape sequences map naturally to
  `KeyDown`/`KeyPress` with modifiers.
- **Web backend** — Browser `keydown`/`keyup`/`input` events map 1:1 to
  this three-event model.

---

## Validation

After all changes, verify:

1. `grep -r "KeyPress(:.*," program/src/` — should only appear in
   backward-compat helpers or new `KeyPress(char)` constructors.
2. `grep -rn "evt.ctrl" program/src/` — should be zero (replaced by
   `evt.modifiers.ctrl` or `is_ctrl`).
3. Arrow keys, Home/End, Ctrl+Home/Ctrl+End still navigate correctly.
4. Ctrl+comma/Ctrl+period still zoom focus in `Focusing.jl`.
5. Typing printable characters produces `KeyPress` events with correct `char`.
6. Holding a key produces `KeyDown` events with `repeat=true`.
7. Releasing a key produces `KeyUp` events.
