# Optimize rendering: dirty-rectangle partial repaint

## Goal

Today every editor frame repaints the entire window: [`_render_window!`](../../program/src/backend/Sdl.jl)
does `SDL_RenderClear` → full `_render_canvas!` walk → `SDL_RenderPresent`, regardless of
whether anything changed (driven unconditionally by `print!` in
`program/src/editor/Editor.jl`).

Nothing needs to be repainted that has not been **invalidated**. The reactive engine
already tracks invalidation per `Cell` (`isuptodate(cell)` returns `c.valid` without
forcing a recompute). So we can:

1. Walk the window's canvas tree and find the **smallest axis-aligned rectangle** that
   covers every invalidated graphic.
2. Set that rectangle as an SDL clip rect and repaint **only** that region, copying the
   full retained frame to the window.
3. Optionally paint a red outline of that rectangle so the dirty region is visible while
   developing.

This realizes the intent already stated in `GraphicsModule`'s docstring:
*"All fields are reactive Cells … for automatic dependency tracking and incremental redraws."*

## Key facts discovered while studying the code

- **Validity is observable without side effects.** `ReactiveModule.isuptodate(c)` →
  `c.valid`. Raw cells are reachable as `getfield(obj, :field)` (the `@document` macro's
  `getproperty` reads through the cell with `getfield(obj, :field)[]`, which *would*
  recompute). So we can test dirtiness first, then read the value.
- **Invalidation granularity is the computed/collection cell, not leaf fields.**
  `TextToGraphics` rebuilds an entire `Vector{GraphicsText}` inside one computed `both`
  thunk; the per-element field cells (`Cell(text)`, `Cell(Int32(x))`, …) are primitive and
  always "valid". When a line of text changes, the canvas's `elements` cell (a
  `CellVector(() -> both[][1])`) becomes invalid and regenerates the whole vector — the old
  element objects are discarded. The multi-line document is a `ListNode` chain whose
  `.next` / `.prev` are computed (`setfn!`), so editing one line invalidates that line's
  node/content while sibling nodes stay valid.
  ⇒ **The dirty unit is a (sub)canvas / collection whose backing cell is invalid**, and the
  dirty region for it is the bounding box of the elements it produces.
- **The SSAA path already keeps a persistent render target** (`res.target`, an
  `SDL_TEXTUREACCESS_TARGET` texture) that retains pixels across frames; it is only
  destroyed on resize. Currently `_render_window!` clears and fully repaints it each frame.
  This texture is the perfect surface for partial repaint — render only the dirty region
  into it (the rest is retained), then copy the whole texture to the window.
- **`SDL_RenderClear` ignores the clip rect** (clears the entire target). Partial clearing
  must therefore use `SDL_RenderSetClipRect` + a background `SDL_RenderFillRect`, not
  `RenderClear`.
- **The window backbuffer is undefined after `SDL_RenderPresent`** (vsync double buffer).
  So the window itself can never be partially updated directly; we must always copy the
  *entire* persistent target to the window every present. Only the work of *re-rendering the
  target* is reduced.
- Bounding-box machinery already exists: `_bounds_elem!` / `_accumulate_bounds!` /
  `_canvas_content_bounds` compute element bboxes with the same offset accumulation as
  `_dispatch_render_elem!`.
- Offscreen paths (`write_image`, `record_video`) are unaffected — only the live-window
  `_render_window!` path changes.

## Design

### Per-window state additions (`SdlWindowResources`)

- Generalize the persistent target so the **non-SSAA path also renders through a retained
  target** (target sized to device pixels, `ss == 1`). This gives every window a stable
  frame buffer to do partial repaint into and to copy from. (Alternative: only optimize when
  `ss > 1`; rejected — default `ss` is 2 but we want correctness at `ss == 1` too.)
- `dirty_bounds::Dict{UInt, NTuple{4,Int}}` — last-rendered absolute bounds (logical px)
  keyed by `objectid` of each dirty-unit canvas. Used to union **old ∪ new** extents so a
  unit that *moved* or whose contents *shrank/were removed* still clears its vacated pixels.
- `first_paint::Bool` (or detect `target == C_NULL`) — forces a full repaint on the first
  frame, after a resize, or after the target is recreated.

### Phase 1 — compute the dirty rect (`_compute_dirty_rect`)

Walk the canvas tree mirroring `_render_canvas!`'s offset accumulation (`ox`, `oy`, nested
canvas / viewport / ListNode traversal). At each structural cell, **test `isuptodate`
before reading it**:

- For a `GraphicsCanvas`: test `getfield(canvas, :elements)` (the collection cell) and the
  geometry cells (`:x`, `:y`). For `ListNode`-backed elements, walk the spine testing each
  node's `.next` / `.prev` and `.value` cells.
- For a `GraphicsViewport`: if anything inside is dirty, treat the **entire viewport
  rectangle** as the dirty unit (it clips its content anyway — a clean, conservative clamp
  that also covers scroll offset changes).
- A subtree is a **dirty unit** when its backing cell is invalid. For each dirty unit:
  - Compute its **new** bounds via the existing `_bounds_elem!` accumulation.
  - Union with its **cached previous** bounds from `dirty_bounds` (old extent).
  - Refresh `dirty_bounds[objectid]` to the new bounds.

Return `nothing` (nothing invalid ⇒ skip paint entirely) or `(x0, y0, x1, y1)` in logical
px, clamped to the window and padded by a few px (e.g. `±2` logical) so anti-aliased glyph
edges straddling the clip boundary are not clipped.

Force full-window dirty (`(0, 0, w, h)`) when: `first_paint`, the window-content canvas
object itself changed identity, or the top-level `elements`/structure cell is invalid in a
way that can't be localized.

Note on ordering: Phase 1 must read validity *before* Phase 2 recomputes. Reading a
structural cell to descend recomputes it; we capture `isuptodate` immediately before each
such read, exactly as the subsequent render would read it.

### Phase 2 — clipped repaint (`_render_window!` rewrite)

```
dirty = _compute_dirty_rect(res, canvas)
dirty === nothing && return            # nothing changed; skip clear/paint/present
_ensure_target!(res)                   # generalized (works for ss == 1 too)
SDL_SetRenderTarget(renderer, res.target)
SDL_RenderSetScale(renderer, ss*scale, ss*scale)
SDL_RenderSetClipRect(renderer, dirty)            # in logical coords; scale maps to device
SDL_SetRenderDrawColor(renderer, bg...)
SDL_RenderFillRect(renderer, dirty)               # NOT RenderClear (which ignores clip)
_render_canvas!(renderer, canvas, 0, 0, w, h)     # SDL clips draws to `dirty`
SDL_RenderSetClipRect(renderer, C_NULL)
SDL_RenderSetScale(renderer, 1, 1)
SDL_SetRenderTarget(renderer, C_NULL)
SDL_RenderCopy(renderer, res.target, C_NULL, C_NULL)   # whole frame → window
# optional debug overlay:
if _DEBUG_DIRTY[]
    SDL_SetRenderDrawColor(renderer, 0xff,0,0,0xff)
    SDL_RenderDrawRect(renderer, dirty_in_window_coords)   # unfilled outline, on window
end
SDL_RenderPresent(renderer)
```

The debug rectangle is drawn on the **window** (after the full target copy, before present),
so it does not accumulate into the retained target and is naturally erased by next frame's
copy.

**Optional CPU culling refinement:** during `_render_canvas!`, skip drawing
elements/subtrees whose bbox does not intersect `dirty`. SDL already pixel-clips them, but
skipping the draw calls and cell reads saves CPU. Safe because any *invalid* element is, by
construction, inside `dirty` (the dirty rect was built from invalid units), so culling only
ever skips already-valid elements whose pixels are retained in the target. This is a
follow-up; the first cut can rely on SDL's clip and still walk the whole tree.

### Controls (env vars, consistent with `PROJECTURED_SUPERSAMPLE` / `PROJECTURED_DISPLAY_SCALE`)

- `PROJECTURED_DEBUG_DIRTY=1` → draw the red dirty-rect outline.
- `PROJECTURED_PARTIAL_RENDER=0` → disable the optimization (always full repaint) as an
  escape hatch / A-B comparison.

## Correctness caveats (and how they're handled)

1. **Undefined backbuffer after present** → always copy the full retained target to the
   window each present. ✓ (only target re-render is reduced)
2. **Moved / removed / shrunk content** leaving stale pixels → union old (cached
   `dirty_bounds`) ∪ new bounds per dirty unit. ✓
3. **Anti-aliasing at clip edges** → pad the dirty rect by a few logical px. ✓
4. **Viewport scroll** → whole-viewport dirty clamp. ✓
5. **First frame / resize / target recreation / canvas identity change** → full repaint. ✓
6. **Nothing changed** → skip paint+present entirely (saves the most). Cursor blink, if
   present, is itself a cell write ⇒ shows up as dirty. ✓

## Testing

- **Pure logic tests for `_compute_dirty_rect`** (no live window needed): build a
  `GraphicsCanvas`, force a full read so all cells are valid, write one leaf cell (e.g. a
  `GraphicsText.x` or the `both` upstream), then assert the returned rect tightly covers
  exactly the changed element(s), and that an untouched canvas returns `nothing`. Add to the
  backend's test surface alongside the existing SDL helpers.
- **No-regression sweep on the projection/printer tests** (`test_printers`, etc.) — these
  don't touch `_render_window!`, so they should be untouched; run a couple
  (`test_printer(json_example)`, `test_repl(json_example)`) to confirm.
- **Visual sanity in the live app**: run an example with `PROJECTURED_DEBUG_DIRTY=1`, type a
  character, and confirm the red rectangle hugs only the edited line/region and that the rest
  of the screen stays correct (no stale pixels, no flicker) while scrolling and resizing.
- **`write_image` / `record_video` unaffected** — confirm an offscreen render still matches
  (those paths are not modified).

## Implementation steps

1. [x] Generalize the persistent render target to all windows (`ss == 1` too); add
       `dirty_bounds` + `first_paint` to `SdlWindowResources`. `_ensure_ss_target!` now
       sets `first_paint=true` and clears `dirty_bounds` whenever it (re)creates the target
       (first frame / resize).
2. [x] Implement `_compute_dirty_rect(res, canvas)` reusing `_bounds_elem!` /
       `_accumulate_bounds!`, with viewport clamp, old∪new union via `dirty_bounds`,
       padding, and full-repaint fallbacks.
3. [x] Rewrite `_render_window!` for the clip + `FillRect` + full-copy + skip-when-clean
       flow; added the `PROJECTURED_DEBUG_DIRTY` red overlay and `PROJECTURED_PARTIAL_RENDER`
       escape hatch (read once in `init!` via `_init_render_flags!`).
4. [ ] (Optional, deferred) Intersection culling in `_render_canvas!` —
       SDL already pixel-clips draws to the clip rect, so this is a pure-CPU refinement; not
       needed for correctness.
5. [x] Added `test_dirty_rect` (`test/src/backend/DirtyRectTest.jl`, wired into
       `test_projections` + exports): covers single-element detection + padding, the clean
       (`nothing`) case, old∪new on move/shrink, window clamping, the empty canvas, and the
       `ListNode` per-line-edit vs. spine-change (extend-to-viewport-bottom) paths. Ran
       `test_dirty_rect` (14/14), `test_text_to_graphics`, `test_write_image`,
       `test_printer(json_example)`, `test_repl(json_example)` — all green.
6. [ ] Live visual check in the real app with `PROJECTURED_DEBUG_DIRTY=1` — **pending the
       user** (requires an interactive window; cannot be done headlessly here).

## Implementation notes / decisions made

- **The dirty walk mirrors `_render_canvas!` exactly** (prev-links, next-links, the
  layout early-stop, nested-canvas `vw-cx/vh-cy` and viewport `vx+vw/vy+vh` extents). This
  was essential: the renderer leaves off-screen `ListNode.next` cells *lazily invalid*, so a
  naive full-spine walk reported "dirty" every frame and defeated skip-when-clean. By
  visiting only the nodes the renderer draws, those tail cells are never misread.
- **Spine changes extend to the viewport bottom** instead of relying on a whole-list bounds
  cache. A line insert/delete reflows everything below it, and widening the dirty region down
  to the viewport edge both covers the reflow and clears a removed *last* line's vacated
  pixels — without paying `measure_text` for every visible line on clean frames.
- **`_render_window!` always runs the dirty walk** (even on the forced-full first paint) so
  `dirty_bounds` is seeded with each unit's current extent; otherwise the first edit after
  open could ghost moved content. Full-window clear is still forced on `first_paint` because
  the target is undefined and empty margins have no element to mark them dirty.
- **`CellVector` had to be imported** into `SdlBackendModule` (it was not already).
- Dirty detection keys on **computed container cells** (a canvas's `CellVector`-backed
  `elements`, a `ListNode`'s `.value`/spine), plus any leaf whose own field cell is stale
  (in-place mutation). This matches the reactive reality that writing a primitive cell marks
  it *valid* and only invalidates dependents — so leaf primitives regenerated wholesale are
  caught at their owning container.

## Open decisions (defaults chosen; revisit if needed)

- Skip present entirely when clean (chosen) vs. always present the retained target. Skipping
  saves the most; if it ever causes a compositor stall, switch to "copy+present retained".
- Per-unit `dirty_bounds` keyed by `objectid` (chosen) vs. snapshotting full previous frame
  bounds. `objectid` keying is O(dirty units) memory and handles the move/remove cases.
