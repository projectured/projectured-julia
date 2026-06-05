# JSON navigation and mouse clicks — bottom-up through Text → Syntax → JSON

End-to-end goal: arrow-key navigation and mouse-click selection must work
reliably on a JSON document edited through the standard
`JsonToSyntax → SyntaxToText → TextToGraphics` pipeline. The pre-condition is
that each layer below it works the same way on its own example
(`text`, `syntax`, `json`).

The user-visible symptom: clicking on a character in the rendered JSON should
move the cursor to that character; arrow keys should walk it. Today
`test_selections()` passes for the keyboard half on `text`, `syntax`, and
`json`, but `test_mouse_clicks()` is disabled in `ProjecturedTest.jl`
([test/src/ProjecturedTest.jl#L83](../../test/src/ProjecturedTest.jl#L83)) and
the run-time editor does not actually deliver `MousePress` to the navigation
chain at all.

This plan is a layered audit. Each layer becomes correct, has tests, and
*stays* correct before the next layer is touched.

---

## 0. Mental model — what the projection chain must do

Selections live as `ReferencePath`s stored in `Document.selection` cells.
Every projection must satisfy two contracts:

1. **Print**: produce a reactive `selection::Cell` on the output document that
   reflects the input document's selection translated into the output domain.
2. **Read**: when an event or downstream `ReplaceSelectionOperation` arrives
   on the output domain, translate it back into a
   `ReplaceSelectionOperation` whose path is in the input domain.

The chain we are validating, in printer order:

```
JsonObject/JsonArray/JsonString/…    (JSON domain, .entries/.elements/.value)
    │ JsonToSyntax
    ▼
SyntaxNode / SyntaxLeaf              (Syntax domain, .children/.open/.value/.close)
    │ SyntaxToText
    ▼
TextText (sequence of TextString)    (Text domain, .elements[i].content{k})
    │ TextToGraphics
    ▼
GraphicsCanvas (Vector{GraphicsText, GraphicsRect})  — element index + pixel offset
    │ GraphicsCaching (GraphicsCanvasToGraphicsImage)
    ▼
GraphicsImage (rasterised tile)      — what the screen actually shows
```

Mouse events enter from the bottom; key events enter from the bottom as well
(they reach `TextToGraphics` because every earlier step's
`projection_read(_, _, evt::KeyDown)` returns `nothing`, so the
`SequentialProjection` chain tries the last step first per
[Sequential.jl#L78](../../program/src/projection/higherorder/Sequential.jl#L78)).

What changes per layer:

| Layer | Path-step format the layer owns |
|---|---|
| Text → Graphics | `ElementReference(i) + PointReference(x, y)` → `.elements[i].content{k}` |
| Syntax → Text | `.elements[i].content{k}` → `.open{k}` / `.value{k}` / `.close{k}` / `.children[i]+rest` / `proj(p, {k})` |
| JSON → Syntax | `.open/.value/.close + …` → `.value{k}` (primitives), `.entries[i].key/.value` (objects), `.elements[i]` (arrays), or `proj(p, …)` for delimiters/whitespace |

---

## 1. Current state — what works, what's missing

Verified by reading the code, not by running:

### Works today

- `TextToGraphics.projection_read` ([TextToGraphics.jl#L86](../../program/src/projection/primitive/TextToGraphics.jl#L86))
  handles all eight nav keys (`left`, `right`, `up`, `down`, `home`, `end`,
  `Ctrl+Home`, `Ctrl+End`) and `_translate_click` translates
  `RangeReference(i)+PointReference(x,y)` paths to `.elements[i].content{k}`.
- `SyntaxLeafToText` / `SyntaxNodeToText` invert text-domain paths via
  `map_reference_backward` + `_pos_to_selection`
  ([SyntaxToText.jl#L110](../../program/src/projection/primitive/SyntaxToText.jl#L110)).
- `Json{Bool,Number,String}ToSyntaxLeaf` accept `value{k}` paths and pass
  through; delimiter paths become `ProjectionReference`. `JsonArrayToSyntaxNode`
  and `JsonObjectToSyntaxNode` invert `.children[i]+rest` recursively
  ([JsonToSyntax.jl#L240](../../program/src/projection/primitive/JsonToSyntax.jl#L240),
   [JsonToSyntax.jl#L329](../../program/src/projection/primitive/JsonToSyntax.jl#L329)).
- `test_selections()` exercises every `(example, key)` pair via BFS and
  passes for `text`, `syntax`, `json`, `json_sorted`, `json_null`,
  `json_string` ([SelectionTest.jl](../../test/src/editor/SelectionTest.jl)).

### Missing or broken

1. **`MousePress` never reaches `TextToGraphics` in the runtime editor.**
   `_multi_window_projection` ([example/src/Examples.jl#L169](../../example/src/Examples.jl#L169))
   does not include `GraphicsCaching`, so there is no
   `GraphicsCanvasToGraphicsImage.projection_read` step to turn a raw
   `MousePress` into a `ReplaceSelectionOperation` of
   `RangeReference(i)+PointReference(x,y)`. The chain tries each step from
   the bottom; none of `TextToGraphics`, `SyntaxToText`, or `JsonToSyntax`
   has a `MousePress` method, so the event is dropped. The widget/workbench
   examples avoid this only because `WidgetToGraphics` *does* implement
   `MousePress` routing.

2. **`test_mouse_clicks()` is commented out** in
   [`ProjecturedTest.jl`](../../test/src/ProjecturedTest.jl#L83). The
   per-example coverage in `MouseClickTest.jl` is shallow: it requires only
   that a cursor exists after a click, not that it landed near the click.

3. **`TextToGraphics` `_print_listnode` path emits an empty
   `char_to_coord`** ([TextToGraphics.jl#L310](../../program/src/projection/primitive/TextToGraphics.jl#L310)).
   Examples that pass a `ListNode`-backed `TextText` (`book`, `conversation`,
   `assistant`) get no `home`/`end`/`up`/`down` line navigation and no click
   translation at all. Not in scope for this plan but flag it — a fix here
   will fall out of step 3.

4. **`SyntaxListToText.map_reference_forward/backward` return
   `nothing`** ([SyntaxToText.jl#L159](../../program/src/projection/primitive/SyntaxToText.jl#L159)).
   Selection cannot be mapped through this projection at all. Same scope
   note as above.

5. **`JsonObject` selection cell does not share child IO maps**
   ([JsonToSyntax.jl#L285](../../program/src/projection/primitive/JsonToSyntax.jl#L285)).
   The cell building entry pair nodes runs every time the `CellVector` is
   read. The selection cell does not consult those entries; it relies on
   `set_selection!` propagating through `getfield(e, :selection)`. This is
   subtle — covered by the recursion contract from
   [selection-deep-dive.md §8](../../guide/selection-deep-dive.md#8-selection-projection-under-recursion).
   Need to verify the existing implementation still satisfies that contract
   under mouse-click round-trip; if not, refactor to the shared-cell
   pattern that `JsonArrayToSyntaxNode` already uses.

6. **No "fuzz" tests for mouse-click round-trip.** Step 2 will add a strict
   round-trip property: for every text-character position `c` in the
   rendered output, clicking on the centre of `c`'s glyph produces a
   selection whose printer-side cursor lands within the same glyph's
   bounding box.

---

## 2. The plan, in three slices

Each slice ends in a green test target before the next begins.

### Slice A — Text domain (foundations)

**Goal.** `text` example: full keyboard navigation + mouse-click selection,
both verified by a strict round-trip test.

#### A1. Add `MousePress` handler to `TextToGraphics.projection_read`

The current implementation requires a downstream
`GraphicsCanvasToGraphicsImage` step. We need `TextToGraphics` itself to
accept a raw `MousePress` event whose coordinates are in canvas-local space,
so the chain doesn't depend on a caching layer above it.

In [`TextToGraphics.jl`](../../program/src/projection/primitive/TextToGraphics.jl):

```julia
function projection_read(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt::MousePress)
    evt.button === :left || return nothing
    coord_map = iomap.char_to_coord[]
    isempty(coord_map) && return nothing
    # Pick the segment whose y-band contains evt.y; tie-break by x.
    sc = _hit_segment(coord_map, evt.x, evt.y, p.measure)
    sc === nothing && return nothing
    char_pos = _char_position_at_x(sc, evt.x, p.measure)
    return ReplaceSelectionOperation(_build_selection_path(sc.span_idx, char_pos))
end
```

`_hit_segment` should:
- prefer a segment whose y-band strictly contains `evt.y`;
- if none, fall back to the nearest line (so clicks below the last line snap
  to end of text, and clicks above to start);
- among segments on the matched line, pick the one whose x-range covers
  `evt.x`, else the closest in x.

This subsumes `_translate_click` for the
`GraphicsCanvasToGraphicsImage`-relayed case (the relay is just a precise
point that lands in some segment's band).

Import `MousePress` from `..MouseModule` at the top of the file.

#### A2. Add `_hit_segment`, refactor `_translate_click`

Move the segment-picking logic into a shared `_hit_segment` so the
`MousePress` and `ReplaceSelectionOperation` (relayed click) paths share
exactly one implementation.

#### A3. Strict round-trip test — Text only

Add `test/src/editor/MouseClickTest.jl` extension (or new
`MouseClickRoundtripTest.jl`):

```julia
function test_click_roundtrip_text(example)
    iomap = projection_print(example.projection, example.document)
    canvas = _find_canvas(iomap)
    coord_map = _find_text_iomap(iomap).char_to_coord[]
    for sc in coord_map
        # one click per character cell; expect cursor in this glyph's band
        for k in sc.char_start:sc.char_end
            cx = _seg_cursor_x(sc, k, measure) + 1
            cy = sc.y + 1
            op = projection_read(example.projection, iomap,
                                  MousePress(:left, cx, cy, Modifiers()))
            @test op isa ReplaceSelectionOperation
            set_selection!(example.document, op.path)
            new_iomap = projection_print(example.projection, example.document)
            cursor = _find_cursor_rect(new_iomap)
            @test cursor !== nothing
            @test sc.y <= cursor.y < sc.y + line_h
            @test sc.x <= cursor.x <= sc.x + sc_width(sc)
        end
    end
end
```

Run this against the `text` example only in this slice. Re-enable the
existing weak `test_mouse_clicks()` only for `text` to start.

#### A4. Add navigation keys not currently tested per character

The BFS in `SelectionTest.jl` covers reachable states but doesn't assert that
walking right N times from position 0 ends at position N. Add a thin
`test_text_nav_invariants` that:

- starts at `Ctrl+Home`, walks `:right` to end, counts states, expects
  `total_chars + 1`;
- walks `:left` back, expects the same count;
- `home`/`end` on each line land on segment-`char_start`/`char_end`;
- `up` from line `i` (`i>1`) lands on line `i-1`, same target column rule
  as the code.

Drop this into `test/src/editor/TextNavigationTest.jl`.

#### A5. Exit criteria for Slice A

- `test_selections()` still green for `text`.
- `test_text_nav_invariants` green.
- `test_click_roundtrip_text` green (every character cell round-trips).
- Smoke test by hand: `run_example("text")`, click around, arrow-key around.

### Slice B — Syntax domain

**Goal.** `syntax` example: same guarantees as Text, plus correct mapping of
clicks/positions on delimiter characters (`{`, `}`, `[`, `]`, `, `, `\n`,
indent whitespace).

#### B1. Verify the Text→Syntax backward map covers every Text position

`SyntaxNodeToText.map_reference_backward` already calls `_pos_to_selection`,
which handles `.open`, child-recurse, sep, indent/newline, and `.close`
([SyntaxToText.jl#L527](../../program/src/projection/primitive/SyntaxToText.jl#L527)).
The case to double-check is the `proj(p, {k})` fallback for whitespace and
separators — make sure `set_selection!` then `print` makes the cursor
reappear at that same flat position, so a click on whitespace lands on the
correct visible spot.

Add a unit-level test (no example needed) that walks every flat character
offset of a hand-built `SyntaxNode` and asserts
`_syntax_to_flat(_, _pos_to_selection(_, k), _, 0) == k`. Place under
`test/src/projection/SyntaxToTextRoundtripTest.jl`.

#### B2. Confirm Syntax-leaf selection paths survive forward through `SyntaxNodeToText`

Selection set by clicking child `c`'s `.value{k}` round-trips up through:

1. JSON reader (not in this slice) → not applicable;
2. `Syntax → Text` printer: the parent `SyntaxNode`'s `_collect_spans` reads
   each child's leaf cursor via `_collect_child_spans` and prefers it over the
   structural cursor at the parent
   ([SyntaxToText.jl#L477](../../program/src/projection/primitive/SyntaxToText.jl#L477)).

The test: hand-build a `SyntaxNode` containing two `SyntaxLeaf`s,
`set_selection!(node, @reference children[2].value{3})`, print, assert the
output cursor lands at the flat offset corresponding to the second leaf's
value at offset 3.

#### B3. Extend the click round-trip test to the `syntax` example

Reuse `test_click_roundtrip_text` machinery but parametrise on
`example.projection`. The `SyntaxToText` example uses
`RecursiveProjection(SyntaxToText())` + `TextToGraphics`; a click should
round-trip through both layers and end up in the same text-band as the
click. This is the same test code with a different example fixture.

#### B4. Exit criteria for Slice B

- `test_selections()` still green for `syntax` and `text`.
- `SyntaxToTextRoundtripTest` green for every offset.
- `test_click_roundtrip` green for both `text` and `syntax` examples.
- Smoke test: `run_example("syntax")`, click on a quote, click on the comma
  separator, click between elements — cursor lands on the expected glyph.

### Slice C — JSON domain

**Goal.** `json` example (and `json_null`, `json_string`): full keyboard
navigation + mouse-click selection working through the full
`JsonToSyntax → SyntaxToText → TextToGraphics` chain.

#### C1. Audit `JsonObjectToSyntaxNode` against the recursion contract

The selection cell built in `projection_print`
([JsonToSyntax.jl#L292](../../program/src/projection/primitive/JsonToSyntax.jl#L292))
strips `.entries` and prepends `.children`. The children `CellVector`
rebuilds pair nodes on each read. Per
[selection-deep-dive.md §8](../../guide/selection-deep-dive.md#8-selection-projection-under-recursion)
the selection cell and the children cell must share the same projected
children — otherwise the selection cell can read a stale `selection` from a
discarded pair node.

Refactor `projection_print` to follow the same shape as
`JsonArrayToSyntaxNode`:

```julia
pair_iomaps = Cell(() -> [project_pair(p, e, recursion, ctx) for e in projected_entries])
sel = Cell(() -> begin
    path = j.selection
    path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
    @reference_case path begin
        entries{s:e}.rest... => begin
            i = s + 1
            iomaps = pair_iomaps[]
            i > length(iomaps) && return nothing
            child_sel = iomaps[i].output.selection
            child_sel === nothing && return nothing
            @reference children[i].^(child_sel)
        end
    end
end)
children = CellVector(() -> SyntaxDocument[im.output for im in pair_iomaps[]])
```

`project_pair` builds the per-entry pair `SyntaxNode` (`children = [key_leaf,
value_subtree]`) the way the inline `for` loop currently does, but as a
named helper for clarity.

#### C2. Verify the reader covers every Text position

`JsonArrayToSyntaxNode.projection_read` already falls back to
`_syntax_to_flat` + `ProjectionReference` for clicks on `[`, `]`, `, `, the
trailing `\n indent` etc.
([JsonToSyntax.jl#L240](../../program/src/projection/primitive/JsonToSyntax.jl#L240)).
`JsonObjectToSyntaxNode` has the same fallback. The contract: every flat
position `k` produces *some* `ReplaceSelectionOperation`, even if the path is
purely a `ProjectionReference` (meaning "click on a projection-introduced
character"). After `set_selection!` the cursor must reappear at flat
position `k`.

Add a test (`test/src/projection/JsonToTextRoundtripTest.jl`):

```julia
for example in (json_example, json_string_example, json_null_example)
    iomap = projection_print(example.projection, example.document)
    coord_map = _find_text_iomap(iomap).char_to_coord[]
    for sc in coord_map, k in sc.char_start:sc.char_end
        cx = _seg_cursor_x(sc, k, measure) + 1
        cy = sc.y + 1
        op = projection_read(example.projection, iomap,
                              MousePress(:left, cx, cy, Modifiers()))
        @test op isa ReplaceSelectionOperation
        clear_selection!(example.document)
        set_selection!(example.document, op.path)
        new_iomap = projection_print(example.projection, example.document)
        cursor = _find_cursor_rect(new_iomap)
        @test cursor !== nothing
        # cursor must land on the same character cell
        @test abs(cursor.x - (sc.x + (cx - sc.x))) < CHAR_WIDTH_TOLERANCE
        @test cursor.y == sc.y
    end
end
```

#### C3. Verify keyboard nav reachability

`test_selections()` already passes for `json` and friends. After Slice C's
refactor of `JsonObjectToSyntaxNode`, re-run and confirm the state count is
unchanged (or larger — never smaller). Capture the baseline before
refactoring:

```julia
result = explore_selections(make_json_document_example(), make_json_projection_example())
@show result.state_count  # baseline
```

Refactor; re-run; assert `>= baseline`.

#### C4. Re-enable `test_mouse_clicks()` for `text`, `syntax`, `json`

In [test/src/ProjecturedTest.jl#L83](../../test/src/ProjecturedTest.jl#L83)
uncomment the call. Update `MouseClickTest.jl`'s skip list to *only* skip
examples that have no text rendering yet:

```julia
example.name in ("widget", "widget_tabbed_pane", "workbench", "filesystem",
                  "xml", "line_numbering", "word_wrapping", "book",
                  "conversation", "assistant") && continue
```

These remaining skips are tracked in the followups below.

#### C5. Exit criteria for Slice C

- `test_selections()` still green for `json`, `json_sorted`, `json_null`,
  `json_string` (and earlier slices).
- `test_click_roundtrip` green for `text`, `syntax`, `json`, `json_string`,
  `json_null`.
- `test_mouse_clicks()` re-enabled and green for the reduced skip list.
- Manual: `run_example("json")`, click on `"name"`, `:`, `"Alice"`, inside
  the array `[95, 87, 100]` — each click puts the cursor on the clicked
  glyph; arrow keys then walk the cursor as expected.

---

## 3. Out of scope (followups, not this plan)

Capture but don't address here:

- **`TextToGraphics._print_listnode` produces an empty `char_to_coord`.**
  This breaks navigation/clicks for `book`, `conversation`, `assistant`. A
  separate plan should propagate the same `SegCoord`-tracking from the
  monolithic path into the paragraph builder.
- **`SyntaxListToText` has no `map_reference_*`.** Mouse-click selection
  through this projection is impossible. Out of scope; tracked.
- **Widget pipeline mouse routing.** Widgets already route `MousePress`
  through `_route_click_to_children`; not part of this plan.
- **Selection range and whole-element selection.** Covered by
  [plan/pending/syntax-tree-selection.md](syntax-tree-selection.md).
- **Editing (insert / delete / paste).** Not selection; separate.

---

## 4. Implementation order, in commits

| # | Slice | Commit |
|---|---|---|
| 1 | A1 + A2 | Add `MousePress` handler + `_hit_segment` in `TextToGraphics` |
| 2 | A3 + A4 | Add Text nav-invariant + click-roundtrip tests |
| 3 | B1 + B2 | Syntax round-trip unit tests; small fixes if any |
| 4 | B3 | Extend click-roundtrip test to `syntax` |
| 5 | C1 | Refactor `JsonObjectToSyntaxNode` to share `pair_iomaps` |
| 6 | C2 + C3 | Add JSON round-trip and reachability tests |
| 7 | C4 | Re-enable `test_mouse_clicks()` for the supported examples |

Each commit ships green tests. If a commit reveals a deeper bug, stop and
add a unit-level regression test before fixing — that keeps the bug from
silently coming back when the next slice lands.

---

## 5. Risks and decision points

- **Clicks on a `ProjectionReference` (structural char) — keep them or
  ignore them?** Today `JsonArrayToSyntaxNode` falls back to
  `ProjectionReference(p, {flat})` so clicking on `[` puts the cursor
  *somewhere*. That cursor reappears via `_pos_to_selection`'s `proj(_)`
  case. Keep this behaviour; flagging it here only because if the round-trip
  test fails for these positions we'll be tempted to drop them — don't,
  because the user can still walk a cursor onto them with arrow keys, and
  they need to round-trip.
- **`MousePress` synthesis.** SDL backend already synthesises `MousePress`
  from a matched `MouseDown`/`MouseUp` pair
  ([backend/Sdl.jl#L890](../../program/src/backend/Sdl.jl#L890)). No change
  needed on the backend side for this plan.
- **`SequentialProjection`'s reader visits steps last-to-first.** Means a
  `MousePress` reaching `TextToGraphics` directly (no caching layer above)
  is the *normal* path for the example pipelines after this plan. The
  widget/workbench pipelines that include `GraphicsCaching` will still work
  because `GraphicsCanvasToGraphicsImage` produces a
  `ReplaceSelectionOperation` whose path is `RangeReference(i) +
  PointReference(x, y)` — `TextToGraphics._translate_click` continues to
  handle that case unchanged.

---

## 6. Acceptance check — what "done" means for this plan

A single command at the repo root passes:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy julia --project=. \
  -e 'using Projectured, ProjecturedExample, ProjecturedTest; \
      test_selections(); \
      test_mouse_clicks(); \
      test_text_nav_invariants(); \
      test_click_roundtrip()'
```

Zero `@warn`s, zero failures. Manual smoke on `run_example("json")` confirms
the cursor follows the mouse and arrow keys behave as expected.

---

## 7. What actually landed (post-implementation notes)

The plan as written assumed `JsonObjectToSyntaxNode` already produced
clean back-translated paths. While implementing the slices we uncovered
three additional bugs that had to be fixed for the JSON example to work
end-to-end. The `test_click_roundtrip` test (Slice C2) accepted them
because it only checks that the cursor *renders near* the click — it
doesn't check that the produced path is semantically clean. A stricter
`test_json_content_clicks_clean` test was added to guard against
regression.

### 7.1 `_translate_json_path(JsonObject, ...)` pattern mismatch

[program/src/projection/primitive/JsonToSyntax.jl#L416](../../program/src/projection/primitive/JsonToSyntax.jl#L416)
matched `children{s:e}.field(_).children{s2:e2}.leaf_path...` but the
pair-node structure built by `JsonObjectToSyntaxNode.projection_print`
puts the key leaf and the value subtree directly under
`pair.children = [key_leaf, value_subtree]` — no `field(_)` step. Every
click on a value inside a nested object (e.g. `"Wonderland"`) fell
through to `_syntax_to_flat` and got wrapped in `proj(JsonObjectToSyntaxNode, {flat})`.
Fix: `children{s:e}.children{s2:e2}.leaf_path...`.

### 7.2 `NestingProjection.map_reference_*` returned `nothing`

[program/src/projection/higherorder/Nesting.jl#L69](../../program/src/projection/higherorder/Nesting.jl#L69)
had stub `map_reference_*` returning `nothing`. `json_sorted` wraps the
top-level JSON pipeline in `SortingAtProjection`, which expands to
`RecursiveProjection(ReferenceDispatchingProjection(… entries =>
NestingProjection(SortingProjection, recursion=PreservingProjection)))`.
At the screen level, `CopyingProjection._map_ref` walks struct fields
via `map_reference_backward`. When it reached the `entries` field's
child iomap (a `NestingProjectionIoMap`), it called
`map_reference_backward(NestingProjection, …)` and got `nothing`,
killing the chain. Without this fix the JSON pattern fix above broke
`json_sorted`. Fix: `map_reference_forward/backward` delegate to inner.

### 7.3 Initial selection not lifted to the screen

[example/src/Examples.jl `run_example`](../../example/src/Examples.jl)
wrapped each example's `document` (with its pre-set deep selection) in a
`ScreenDocument`/`WindowDocument`, but never lifted the inner selection
to a screen-rooted path. `screen.selection` stayed `nothing`. The
editor's loop runs `clear_selection!(screen); set_selection!(screen, op.path)`
on every click, and `clear_selection!` only walks the chain reachable
from `screen.selection` — so the inner stale selection (e.g. on Alice)
was never cleared. The next click took a different branch via
`set_selection!`, leaving *two* leaves with non-`nothing` selections.
`_collect_spans` iterates children left-to-right and picks the first
cursor it finds, so the cursor appeared stuck on the original branch.

Fix: after building the `ScreenDocument`, lift the first window's
content selection by calling
`set_selection!(screen, @reference windows[i].content.^(inner_sel))`
(`.windows[i].content.child.^(inner_sel)` for the tooltip variant).
This populates `screen.selection` so subsequent `clear_selection!`
walks the full chain.

### 7.4 Pre-existing bug found in `BookToSyntax._backward_book_path`

Slice B's stricter offset accounting in `_subtree_len` /
`_pos_to_selection` (always emit the trailing `\n + indent` before
close, not just for empty children) made more positions reachable.
That exposed a pre-existing path-shape bug: `_backward_book_path`
emitted `elements{N}` (PositionReference, 0-based cursor semantics)
where it should have emitted `elements[N]` (ElementReference, 1-based
index semantics). `set_selection!` interprets RangeReference as
`idx = h.start + 1`, so a "position 1" cursor was navigating to
element 2, then a backward translation from a BookParagraph's
`.value{k}` was applied to a BookList sibling. Fix: three `{elem_i}` →
`[elem_i]` edits in `BookToSyntax.jl`.

### 7.5 `_flat_to_text_elem_path` would anchor on empty spans

For `JsonNull`, the rendered SyntaxLeaf has `open=""`, `value="null"`,
`close=""`. A cursor at flat offset 4 (end of "null") was mapped to
`.elements[3].content{0}` (the empty close span). `_collect_spans`'s
cursor renderer only emits SegCoords for non-empty spans, so the
cursor disappeared. Fix: when `flat_pos` lands at the boundary, anchor
on the last non-empty span instead of advancing into an empty next
span.

### Tests added beyond the original slice plan

- `test_json_content_clicks_clean_all()` — walks each JSON example's
  rendered segments, picks the ones whose text matches a known content
  string (a `JsonString`/`JsonNumber`/`JsonBool` value or an object
  key), and asserts the resulting click path contains no
  `ProjectionReference`. Catches §7.1 by construction.
- `SyntaxToText flat-position round-trip` (unit-level): walks every
  flat offset of three hand-built syntax trees and asserts
  `_syntax_to_flat ∘ _pos_to_selection == identity`. Caught §7.4 and
  the trailing-newline accounting bug.

### Out-of-scope items still tracked

- `TextToGraphics._print_listnode` ignores `char_to_coord` — `book`,
  `conversation`, `assistant` examples skip click round-trip.
- `SyntaxListToText` has no `map_reference_*`.
- `object`, `math`, `julia` domain projections don't yet propagate
  selection forward to the cursor cell.
- `collection`, `reversing`, `filtering`, `sorting`: tracked in
  [plan/pending/fix-selection-tests.md](../pending/fix-selection-tests.md).
