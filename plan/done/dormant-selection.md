# Dormant selections: a document can keep the selection it loses

> **Status (2026-08-12): DONE.** The code is in the tree: `SelectionDocument` in
> `package/kernel/main/document/SelectionDocument.jl`, `keeps_dormant_selection`
> in `package/kernel/main/selection/SelectionDefaults.jl`, and the five keepers in
> `package/pane/main/Pane.jl` and `package/widget/main/Widget.jl`. All six steps
> below are done, and the four sealed files got explicit permission, were edited,
> and are sealed again. See **Sealed files**.

Today a selection change erases the old path. This plan lets a document say
"keep mine". What it keeps stays exactly where it is, and its state changes from
live to **dormant**: still stored, still drawable, but not the one the editor acts
on. When the focus comes back, it becomes live again.

Nothing changes for a document that does not ask. The default is still to clear.

## Goal

1. Two states for a stored selection: **live** and **dormant**. One selection is
   live at a time, and the keyboard is bound to it.
2. Any projection can ask whether the selection of its input document is live,
   by reading that document alone.
3. When the selection moves, the abandoned branch is either cleared, as today, or
   kept and marked dormant.
4. A tab group keeps its selection, so it still shows the tab it showed. A
   dormant selection draws pale.
5. When the focus returns, the dormant selection becomes live again.

## Vocabulary

The words below are the only words the code uses for these things.

| Word | Meaning |
| --- | --- |
| `SelectionDocument` | The value a `selection` cell holds: a reference in its `primary` field, plus a `live` flag. |
| live selection | A selection whose `live` field is `true`. The editor acts on this one. |
| dormant selection | A selection whose `live` field is `false`. Drawn pale, acted on never. |
| keeper | A document that answers "keep" when it is asked at a divergence. |
| divergence | The node where the old path and the new path route into different children. |
| restore | To make a dormant selection live again, when the focus returns to it. |

The keepers are `PaneGroup`, `PaneTab`, `PaneSplit`, `WidgetTabbedPane` and
`WidgetSplitPane`.

## What this fixes

Two symptoms, both measured on the real documents.

**A group forgets its tab.** Two groups, three tabs in the first. Focus tab 3 of
group 1, then focus a tab of group 2:

```
focus g1 tab 3:        g1.selection = ::PaneGroup.tabs::CellVector[3]::PaneTab
                       shown(g1) = 3
then focus g2 tab 2:   g1.selection = nothing
                       shown(g1) = 1
```

The pane holds no active-tab field on purpose — the tab a group shows is the tab
its own selection names, and `pane_shown_tab_index` falls back to tab 1 when that
selection is gone ([PaneSurgery.jl:238](../../package/pane/main/PaneSurgery.jl#L238)).
The selection layer erases the state the rule reads.

**A pane forgets its caret.** Same cause, one level deeper.

## How the selection is stored today

`set_selection!` writes the whole remaining path into every node along it, so the
root holds the complete path and each child holds the tail
([SelectionDefaults.jl:83](../../package/kernel/main/selection/SelectionDefaults.jl#L83)).
The chain is shared by identity: `child.selection[] === parent.selection[].tail`.

A node's cell therefore holds the **entire** suffix below it, not one step.
Measured on a caret inside a tab:

```
root   : …elements[1]::PaneGroup.tabs[3]::PaneTab.content::PrimitiveString.value{4}
g1     : ::PaneGroup.tabs[3]::PaneTab.content::PrimitiveString.value{4}
tab3   : ::PaneTab.content::PrimitiveString.value{4}
content: ::PrimitiveString.value{4}
```

`replace_selection!` runs `_sync_selection!`, which walks both paths together.
Where they diverge it installs the new suffix and **clears the old branch**
([SelectionDefaults.jl:196](../../package/kernel/main/selection/SelectionDefaults.jl#L196)):

```julia
if old isa ConcreteReference
    oc = _selection_child(document, old)
    oc === nothing || clear_selection!(oc)      # ← the line this plan replaces
end
```

## Design

### Rule 1 — the selection cell holds a document

```julia
@document struct SelectionDocument
    primary::Any                       # the reference, or nothing
    live::Bool = true                  # false ⇒ dormant
    selection::ImmutableCell{Nothing}  # a value document: not itself selectable
end
```

A `Bool`, because there are exactly two states. A third state would be a rename,
and there is no third state.

The flag belongs to the **selection**, not to the node that holds it. That is
what makes every other part of this plan local. An earlier draft put a
`selection_state` field on each keeper, and the nodes below the keeper then had
nowhere to record their own state, which forced the answer to be pushed down the
printer context. It is not needed.

`primary` names the reference and reserves the shape for a secondary and for
named selections, which this plan does not build.

The type is declared as a **value document** — an explicit
`selection::ImmutableCell{Nothing}` — because a selection is not itself
selectable. This is the pivot `@document` already documents.

**Where it lives: the reference layer.** `@document` emits the injected field's
type as an *expression*, resolved in the caller's module
([DocumentMacro.jl:351-375](../../package/kernel/main/document/DocumentMacro.jl#L351)),
which is why the type has to be nameable in every module that declares a
document. The macro's own comment says a module that declares documents
necessarily uses the reference layer. So a `SelectionDocument` declared there
needs no new import anywhere.

### Rule 2 — at a divergence, ask

The ask starts **at the divergence**, not at the root. Above the divergence the
two paths agree, so nothing there is abandoned and there is nothing to ask.

One open generic on the document, defaulting to clear:

```julia
keeps_dormant_selection(document) -> Bool     # false by default
```

Five documents answer `true`. Every other document keeps today's behaviour
exactly, which is what bounds the blast radius of this plan.

### Rule 3 — the first keeper decides for the whole branch

The walk starts at the divergence node **inclusive** and goes down the abandoned
path. It stops at the first keeper. A node answers for the branch that hangs
below it, so the divergence node answers for the child it is abandoning.

Inclusive is not a detail. The two keeper trees put the keeper on opposite sides
of the divergence, and only an inclusive walk finds both:

- **Pane.** `PaneSplit.selection` is `.elements::CellVector[1]::PaneGroup…`, so the
  step that differs — `[1]` against `[2]` — belongs to the `CellVector`, which is
  a `@document` of its own. The divergence node is that collection, and the
  abandoned branch starts at the `PaneGroup`, which is the keeper.
- **Widget.** `WidgetTabbedPane.selection` is a bare `[i]`, so the divergence node
  is the tabbed pane itself. The abandoned branch starts at the pair and then the
  tab's content — a `JsonObject`, which can never be a keeper. Here the keeper is
  the divergence node.

An exclusive walk would fix the pane and leave the widget broken. If nobody
keeps, the branch is cleared exactly as today. If a keeper is found, the writer
walks the **whole** branch and sets every node's `live` field to `false`, leaving
every path in place.

Marking the whole branch is what makes Rule 4 local. It is the same walk
`clear_selection!` does today, so the cost and the invalidation are unchanged: it
writes `false` into a flag instead of `nothing` over a path.

Asking every node instead of stopping at the first keeper would let a keeper hold
a path into children that were cleared. The stored chain is one shared object —
`child.selection` **is** `parent.selection.tail` — so a half-kept chain is not a
state the writer can produce without breaking that sharing.

### Rule 4 — liveness is a local read

```julia
getfield(node, :selection)[].live
```

No printer context, no property to thread, no walk from the root, and none of the
laziness traps that a pushed-down answer would carry. Every node knows its own
state because the writer stamped it.

### Rule 5 — the property accessors unwrap

`@document` generates the property accessors, so the one place that reads the cell
does the unwrapping:

- `node.selection` gives `primary` when `live` is `true`, and `nothing` when it is
  `false`.
- `getfield(node, :selection)[]` gives the whole `SelectionDocument`.

Measured in the main packages: **170** property reads, **11** property writes,
**63** `getfield` accesses. The 170 reads keep working with no edit, and they
become *correct by default* — they never see a dormant path, so nothing draws a
stale caret. The selection layer already uses `getfield` throughout, so it sees
the document. Pale rendering opts in explicitly, and so does
`pane_shown_tab_index`, which must read the dormant path to answer at all.

### Rule 6 — restore

A focus move back writes `path_to_keeper ++ keeper.primary` and the writer sets
`live` back to `true` on the way down. The kept suffix is the whole memory, so the
existing writer rewrites the chain and the caret comes back. There is no separate
restore machinery.

Restoring is tied to `keeps_dormant_selection` on purpose. A whole-element
selection has exactly the shape of a restore — the path ends at node N and N holds
a deeper path — so if any node restored, "select the whole node" could never be
expressed once the node held a caret, and Escape would bounce back to the old
caret. A `JsonObject` is not a keeper, so ∅ on it stays ∅.

## What the implementation must handle

0. ✅ **Done. A tab switch bypasses the selection writer.**
   `evaluate_operation(editor, ::SelectTabOperation)` now calls `replace_selection!`
   on the widget
   ([Widget.jl:2027-2030](../../package/widget/main/Widget.jl#L2027)), not a bare
   field assignment. The widget stays the root, so the identity rooting is
   unchanged; only the writer runs.
1. ✅ **Done. The cell holds three shapes.** `nothing`, a bare `Reference`, or a
   `SelectionDocument`. One of the 11 writes is
   `output.selection = ComputedCell(() -> map_reference_forward(…))` — the
   forward-image pattern — and one assigns a bare `ConcreteReference` to a widget.
   The unwrap treats a bare `Reference` as live, and `setproperty` wraps
   symmetrically, so those sites keep working.
2. ✅ **Done. A forwarded selection loses its state.** `map_selection_forward` in
   `SelectionDefaults.jl` maps a path forward and carries the live/dormant state
   onto the image.
3. ✅ **Done, self-fixing as expected.** A moved document carries its state. The
   drop sets the focus, so a dragged dormant tab is no longer dormant once
   dropped; no separate mechanism was needed.
4. ✅ **Done. Both trees need the keeper methods.** A widget tree is sometimes the
   edited document and sometimes a projection output:
   - `make_widget_tabbed_pane_document_example` and
     `make_widget_split_pane_document_example` build a widget **as the document**
     ([Widget.jl:379](../../package/substrate/example/document/Widget.jl#L379),
     [:284](../../package/substrate/example/document/Widget.jl#L284)). The writer
     walks it, so the method on the widget fires.
   - The pane examples build a `PaneTree`. There the widget tree is the iomap
     output, which the writer never reaches, and the widget's selection is not
     stored at all — `_forward_selection!` makes it a computed image
     ([PaneToWidget.jl:177](../../package/pane/main/PaneToWidget.jl#L177)). Only the
     method on the pane documents fires.
5. ✅ **Done. A printer maps an absent selection too.** `map_selection_forward`
   answers `nothing` for a document that holds no selection. That is right for a
   hop which only re-expresses the selection it was given. Two hops do more than
   that, and both pass `map_missing = true`:
   - `_compose_node_selection` case 4 promotes the **first child's** caret when the
     node holds none of its own
     ([SyntaxToText.jl:802](../../package/syntax/main/SyntaxToText.jl#L802)).
   - `_atomic_print`'s unbound branch calls the mapper unconditionally
     ([ProjectionTemplate.jl:401](../../package/kernel/main/projection/ProjectionTemplate.jl#L401)),
     because a projection that *introduces* a selection answers a real image for
     `nothing`.

   The promoted caret is the child's, so case 4 carries the **child's** live state
   onto the image. The node has none of its own to lend it.
6. ✅ **Done. A tab click arrives re-rooted.** The strip emits its own
   `selector_element_pairs[i]`, but the widget tree prefixes the route from the
   reader's output down to that pane. A reader that claims the click matches the
   **tail** resolves the prefix to find which pane was clicked, and matches that
   pane against its own children by identity, falling through when no child owns
   the pane ([WorkbenchToWidget.jl](../../package/workbench/main/WorkbenchToWidget.jl)).

## What the rendering costs

A selection is painted in few places. In the text pipeline it is **one**:
`TextToGraphics` builds a single `overlay` cell and drives one `cursor_rect` plus
the highlight rects from it
([TextToGraphics.jl:282-309](../../package/text/main/TextToGraphics.jl#L282)).
Widgets that paint their own selection band are a second, smaller family.

The property reads are mostly **mapping** code — forward and backward maps,
printers computing a child's selection. Under Rule 5 they see a live path or
nothing, so none of them change. The pale decision belongs where the pixel is
painted, and it reads the document through `getfield`.

## Steps

Each step is one commit.

1. **`SelectionDocument`.** ✅ **Done.** The type in the reference layer, the
   widened field type, and the unwrapping accessors of Rule 5. The writer still
   clears at a divergence, so behaviour does not change. Test: the existing
   suites do not move, including the three write shapes.
2. **The trait and the ask.** ✅ **Done.** `keeps_dormant_selection`, default
   `false`, and the walk of Rules 2 and 3, in `SelectionDefaults.jl`
   (`_keeps_branch`).
3. **The keepers.** ✅ **Done.** The five methods: `PaneGroup`, `PaneTab`,
   `PaneSplit` in `package/pane/main/Pane.jl`; `WidgetTabbedPane`,
   `WidgetSplitPane` in `package/widget/main/Widget.jl` (plus `WidgetTabPage`,
   not in the original list).
4. **Restore.** ✅ **Done.** Rule 6, as `_restore_selection` in
   `SelectionDefaults.jl`.
5. **Pale rendering.** ✅ **Done.** `TextToGraphics.jl` draws a dormant caret and
   highlight muted (`hl_color_dormant`), and `map_selection_forward` carries the
   state through `SyntaxToText.jl` and `PaneToWidget.jl`.
6. **Stale dormant paths.** ✅ **Done.** `_matched_selection` re-validates a
   restored path and falls back to the plain path when the extension no longer
   matches.

## Open decisions

1. **An empty group.** A group with no tab is focused as the group itself, so a
   paste there replaces a `PaneGroup`. Unrelated to this plan, still open.

## Not in this plan

Multiple simultaneous selections — a secondary, and named ones for an operation
such as swap. `primary` reserves the shape, and a projection still maps one path
at a time, so `map_reference_forward` does not change. Building the set now would
put it in front of every reader with no test behind it.

## Sealed files

All four got explicit permission, were edited, and are sealed again (🔒 in
`CLAUDE.md` as of 2026-08-12).

Layer 7:

- `package/kernel/main/document/DocumentMacro.jl` — the injected field's type, and
  the unwrapping property accessors. The injected field type is now
  `Union{Nothing, Reference, SelectionDocument}`.

Layer 9:

- `package/kernel/main/selection/SelectionDefaults.jl` — the divergence walk, the
  trait default, the state writes, the restore.
- `package/kernel/main/selection/SelectionInterface.jl` — the new generics.
- `package/kernel/main/selection/SelectionModule.jl` — the exports.

Nothing else touches a sealed file. The reference layer gains a new file,
`package/kernel/main/document/SelectionDocument.jl`, for `SelectionDocument`,
which is an addition rather than a change. The pane slice, the widget slice and
the renderers are unsealed.
