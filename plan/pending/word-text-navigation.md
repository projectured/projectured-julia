# Word-wise text navigation: Ctrl+Left / Ctrl+Right

> **✅ DONE (verified 2026-06-23):** Word-wise Ctrl+Left/Right caret motion is
> fully implemented and wired, plus the BFS test keys. **Note on location:** the
> codebase was restructured since this plan was written. All character-cursor
> motion moved out of `TextToGraphics.projection_read` into the Text *domain*
> `document_read` in `package/visual/example/document/Text.jl` (TextToGraphics now
> delegates to it via `document_read(iomap.input, evt)` at
> `package/visual/main/text/TextToGraphics.jl:133`). All the
> helpers and key bindings this plan proposed live in `Text.jl`. See per-step
> annotations below. The only un-done item is the *optional* focused unit test
> (Testing step 3), which the plan itself marked optional.

## Goal

Add **word-granular caret motion** to flat text editing: `Ctrl+Left` jumps the
character cursor backward to the start of the current/previous word, `Ctrl+Right`
jumps forward to the start of the next word. Today only single-character
(`Left`/`Right`), line (`Home`/`End`, `Up`/`Down`), and document
(`Ctrl+Home`/`Ctrl+End`) motion exist.

Scope is **Left/Right only**. `Ctrl+Up`/`Ctrl+Down` have no natural word
semantics and are left unbound by this task (see *Open decisions*).

## Where this lives

All character-cursor motion is owned by `TextToGraphics.projection_read`
([program/src/projection/primitive/TextToGraphics.jl:206](../../program/src/projection/primitive/TextToGraphics.jl#L206)).
The single-char cases are the `KeyDown(:left)` / `KeyDown(:right)` rules at
[:254](../../program/src/projection/primitive/TextToGraphics.jl#L254) and
[:268](../../program/src/projection/primitive/TextToGraphics.jl#L268). The
document-jump rules `Ctrl+Home`/`Ctrl+End` already demonstrate the modifier-keyed
pattern at [:244-248](../../program/src/projection/primitive/TextToGraphics.jl#L244).

The model this layer works in: an ordered list of `TextString` spans, each with
0-based character offsets; a caret is `(span, char)` projected from a selection
path `elements[span].content{char}` (see `_cursor_position`,
[:700](../../program/src/projection/primitive/TextToGraphics.jl#L700), and
`_build_selection_path`, [:713](../../program/src/projection/primitive/TextToGraphics.jl#L713)).
`span_infos` ([:239](../../program/src/projection/primitive/TextToGraphics.jl#L239))
is the ordered `(elem_idx, length)` list the existing left/right logic walks.

## Critical gotcha — `@event_case` modifier matching

Per [program/src/device/EventCase.jl:40](../../program/src/device/EventCase.jl#L40),
modifier flags are matched **exactly only when a `;` block is present**; omitting
the block leaves modifiers **unconstrained**. So the current `KeyDown(:left)` /
`KeyDown(:right)` rules match Left/Right with *any* modifiers — **Ctrl+Left/Right
already fire single-char motion today.**

Consequences for this task:

1. The new `KeyDown(:left; ctrl)` / `KeyDown(:right; ctrl)` rules **must precede**
   the bare `KeyDown(:left)` / `KeyDown(:right)` rules in the same `@event_case`
   block (first-match-wins, top to bottom).
2. Nothing upstream swallows Ctrl+Left/Right first: `Ctrl+.` ([:214](../../program/src/projection/primitive/TextToGraphics.jl#L214)),
   the alt-decline ([:220](../../program/src/projection/primitive/TextToGraphics.jl#L220)),
   the structural-decline ([:225](../../program/src/projection/primitive/TextToGraphics.jl#L225)),
   and `Ctrl+Home`/`Ctrl+End` ([:245-246](../../program/src/projection/primitive/TextToGraphics.jl#L245))
   are all disjoint. Good.
3. In **structural mode** there is no character cursor: `_cursor_position` returns
   `nothing` and the body bails at [:251](../../program/src/projection/primitive/TextToGraphics.jl#L251)
   (`current === nothing && return nothing`). Placing the new cases *after* that
   guard means Ctrl+Left/Right correctly fall through to `SyntaxNodeToText` in
   structural mode, matching plain-arrow behavior. Place them inside the main
   `@event_case evt` block at [:253](../../program/src/projection/primitive/TextToGraphics.jl#L253).

## Design — word motion as *iterated* single-char motion

The subtle correctness hazard is **caret-path canonicalization at span
boundaries**. A flat offset sitting on a span join maps to two equivalent
`(span, char)` representations; the existing per-char logic deliberately skips
"boundary duplicates" (see comments at
[:264](../../program/src/projection/primitive/TextToGraphics.jl#L264) and
[:280](../../program/src/projection/primitive/TextToGraphics.jl#L280)) so that
each visual caret has one canonical path. If word motion built its own
independent flat-string index map, it could land on the *non-canonical* twin,
producing selection paths that per-char navigation never yields — which would
desync the navigation BFS and the `check_reaches_all` coverage check.

**Avoid this entirely by reusing the existing per-char transition.** Word motion
= repeatedly take a single canonical char step in the chosen direction until a
word boundary is crossed. Every intermediate and final caret is, by construction,
a caret the per-char path already produces, so canonicalization is free and
consistent.

### Step 1 — Extract pure step helpers

**✅ DONE (verified):** `_step_left` / `_step_right` exist as pure helpers,
returning `nothing` for clamp, with the boundary-duplicate skip (`prev[2]-1`,
`next[2] > 0 ? 1 : 0`). See `package/visual/example/document/Text.jl:388` and
`:400`. The bare `:left` / `:right` cases now call them
(`package/visual/example/document/Text.jl:365-374`). (In the current code they live
in `Text.jl`, not `TextToGraphics.jl`, due to the restructure.)

Refactor the inline bodies of the `:left` / `:right` cases into pure helpers
(near the other reader helpers around
[:737](../../program/src/projection/primitive/TextToGraphics.jl#L737)):

```julia
# Next caret one character left of (span_idx, char_idx), or nothing if already
# clamped at document start. Mirrors the current :left body verbatim, including
# the boundary-duplicate skip (prev[2]-1).
_step_left(span_infos, span_idx, char_idx) -> (span, char) | nothing

# Symmetric; mirrors the current :right body (next[2] > 0 ? 1 : 0 boundary skip).
_step_right(span_infos, span_idx, char_idx) -> (span, char) | nothing
```

Return `nothing` to mean "no movement possible" (current code clamps in place;
the helper distinguishes clamp from progress so the word loop can stop). The
existing `:left` / `:right` cases then become one call each — a behavior-
preserving refactor verifiable on its own before any new keys are added.

### Step 2 — Character lookup for class testing

**✅ DONE (verified):** `span_text` lookup is built at
`package/visual/example/document/Text.jl:341`. `_char_left` / `_char_right` exist at
`:430` / `:422` (Unicode-safe via `nextind`, returning `nothing` at span ends).
`_is_word_char(c) = isletter(c) || isdigit(c) || c == '_'` at `:416`.

Build a span-content lookup alongside `span_infos` so the word loop can read the
character it is crossing:

```julia
span_text = Dict(elem_idx => String(span.content)
                 for (elem_idx, span) in enumerate(styled) if span isa TextString)
```

Helper to fetch the character immediately left/right of a caret (the char that a
step would cross), returning `nothing` at the ends:

```julia
_char_left(span_text, span_idx, char_idx)   # span_text[span_idx][char_idx]   (1-based char_idx)
_char_right(span_text, span_idx, char_idx)  # span_text[span_idx][char_idx+1]
```

Word-char predicate (Unicode-aware, standard editor convention):

```julia
_is_word_char(c) = isletter(c) || isdigit(c) || c == '_'
```

### Step 3 — Word loop

**✅ DONE (verified):** `_word_step_right` at
`package/visual/example/document/Text.jl:438` and `_word_step_left` (the mirror) at
`:450`, matching the proposed two-phase loop verbatim.

```julia
# Ctrl+Right: skip the current word run, then the separator run → next word start.
function _word_step_right(span_infos, span_text, span_idx, char_idx)
    s, c = span_idx, char_idx
    # over word chars
    while (ch = _char_right(span_text, s, c)) !== nothing && _is_word_char(ch)
        nxt = _step_right(span_infos, s, c); nxt === nothing && return (s, c); (s, c) = nxt
    end
    # over separators
    while (ch = _char_right(span_text, s, c)) !== nothing && !_is_word_char(ch)
        nxt = _step_right(span_infos, s, c); nxt === nothing && return (s, c); (s, c) = nxt
    end
    (s, c)
end
```

`_word_step_left` is the mirror: step left while the char *being crossed*
(`_char_left`) is a separator, then while it is a word char — landing at the
start of the current/previous word.

### Step 4 — Wire the keys

**✅ DONE (verified):** `KeyDown(:left; ctrl)` / `KeyDown(:right; ctrl)` rules
are placed *before* the bare `:left` / `:right` rules in the main `@event_case`
block at `package/visual/example/document/Text.jl:357-364`, calling the word-step
helpers and returning `ReplaceSelectionOperation(_build_selection_path(...))`.

Inside the main `@event_case evt` block, *before* the bare `:left` / `:right`
rules:

```julia
KeyDown(:left; ctrl) => begin
    s, c = _word_step_left(span_infos, span_text, current.span, current.char)
    return ReplaceSelectionOperation(_build_selection_path(s, c))
end
KeyDown(:right; ctrl) => begin
    s, c = _word_step_right(span_infos, span_text, current.span, current.char)
    return ReplaceSelectionOperation(_build_selection_path(s, c))
end
```

## Behavior summary

- **Ctrl+Right** lands at the start of the next word (skips remainder of current
  word, then intervening separators). At document end it clamps in place.
- **Ctrl+Left** lands at the start of the current word, or the previous word if
  already at a word start / in separators. At document start it clamps in place.
- Stops at `TextString` span boundaries (the stop-condition helpers
  `_char_left`/`_char_right` read only the current span). This is intentional:
  `WordWrapping` runs before `TextToGraphics` and *consumes* the space at soft-wrap
  points, so it lives in no span. Peeking across the boundary would see the next
  line's first letter as the crossed character and wrongly merge two words
  (`…dolor` + `sit…`) into one. Since each visual line is its own span, this means
  word motion stops at line ends — a defensible, common editor behavior. (The
  earlier "crosses boundaries transparently" intent was unsafe given the consumed
  wrap-space; revisit only if span boundaries that are *not* line/wrap boundaries
  with intra-line styled word runs appear.) In structural mode it declines and
  falls through to the tree layer.

## Testing

**✅ DONE (verified):** The two Ctrl+Left/Right nav keys are present in
`nav_keys` of `explore_text_selections` at
`package/test/src/editor/TextNavigationTest.jl:35-36`. (Test file moved to
`package/test/src/editor/`.) Items 1 and 2 below are satisfied; item 3 (the
optional focused unit test) was **not** added — no `_word_step` / word-nav test
exists anywhere under `package/test/` — and the plan itself flagged it optional.

1. **Extend the BFS nav set.** Add the two keys to `nav_keys` in
   `explore_text_selections`
   ([test/src/editor/TextNavigationTest.jl:26-35](../../test/src/editor/TextNavigationTest.jl#L26)):
   ```julia
   KeyDown(:left,  Modifiers(ctrl=true)),
   KeyDown(:right, Modifiers(ctrl=true)),
   ```
   Word jumps land only on carets per-char motion already reaches, so this only
   *adds reachability*. `check_reaches_all` is a subset assertion (reachable ⊇
   enumerated carets, [:104-129](../../test/src/editor/TextNavigationTest.jl#L108)),
   so it cannot regress; the per-state reprint walk validates every new state.

2. **Targeted runs** (smallest scope first, per CLAUDE.md):
   - `test_text_navigation("text", ...; check_reaches_all=true)` — multi-word,
     multi-line flat text.
   - The curated complete-coverage examples `["text", "json", "ini"]`
     ([:181](../../test/src/editor/TextNavigationTest.jl#L181)).
   - `test_printer`/`test_reader` on `text` to confirm the Step-1 refactor is
     behavior-preserving before adding keys.

3. **Optional focused unit test** asserting concrete targets on a known string
   (e.g. caret in the middle of a word: Ctrl+Right → next word start; Ctrl+Left →
   this word start), to pin the boundary convention against future drift.

## Open decisions

- **Ctrl+Up / Ctrl+Down**: no word meaning. Recommend leaving unbound (this layer
  returns `evt` and they propagate). A future task could map them to
  paragraph/blank-line jumps if desired — out of scope here.
- **Word-char class**: plan uses `isletter || isdigit || '_'`. If punctuation
  should form its own class (emacs-style three-way stepping), it is a one-line
  change in `_is_word_char` plus an extra loop phase; not proposed for v1.
- **Shift+Ctrl+Left/Right (word selection ranges)**: depends on range-selection
  support, which the character cursor model does not yet have. Out of scope.
