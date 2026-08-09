# Dormant selections: a document can keep the selection it loses

> **Status: PENDING.** No code is written yet. The core needs permission to edit
> four sealed files, in layer 7 and layer 9. See **Sealed files**.

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
selection is gone ([PaneSurgery.jl:232](../../package/visual/main/pane/PaneSurgery.jl#L232)).
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

0. **A tab switch bypasses the selection writer.**
   `evaluate_operation(editor, ::SelectTabOperation)` assigns the widget's field
   directly — `op.widget.selection = ConcreteReference(ElementReferenceStep(i), ∅)`
   ([Widget.jl:1912](../../package/visual/main/widget/Widget.jl#L1912)). It never reaches
   `_sync_selection!`, and the bare `[i]` wipes whatever suffix was there, which is
   the "forgets the caret" bug in the widget tree. It has to call
   `replace_selection!` on the widget instead. The widget stays the root, so the
   identity rooting is unchanged; only the writer runs.
1. **The cell holds three shapes.** `nothing`, a bare `Reference`, or a
   `SelectionDocument`. One of the 11 writes is
   `output.selection = ComputedCell(() -> map_reference_forward(…))` — the
   forward-image pattern — and one assigns a bare `ConcreteReference` to a widget.
   The unwrap treats a bare `Reference` as live, and `setproperty` wraps
   symmetrically, or those sites break.
2. **A forwarded selection loses its state.** `_forward_selection!` maps a path
   forward, so a widget showing a dormant document selection would look live. That
   one site carries the state into the image.
3. **A moved document carries its state.** Drag a dormant tab into the focused
   group and it stays dormant until the writer touches it. The drop already sets
   the focus, so this is probably self-fixing. It gets a test, not a mechanism.
4. **Both trees need the keeper methods.** A widget tree is sometimes the edited
   document and sometimes a projection output:
   - `widget_tabbed_pane_example` and `widget_split_pane_example` build a widget
     **as the document** ([Widget.jl:379](../../package/visual/example/document/Widget.jl#L379),
     [:284](../../package/visual/example/document/Widget.jl#L284)). The writer walks it, so
     the method on the widget fires.
   - The pane examples build a `PaneTree`. There the widget tree is the iomap
     output, which the writer never reaches, and the widget's selection is not
     stored at all — `_forward_selection!` makes it a computed image
     ([PaneToWidget.jl:172](../../package/visual/main/pane/PaneToWidget.jl#L172)). Only the
     method on the pane documents fires.

## What the rendering costs

A selection is painted in few places. In the text pipeline it is **one**:
`TextToGraphics` builds a single `overlay` cell and drives one `cursor_rect` plus
the highlight rects from it
([TextToGraphics.jl:271-299](../../package/visual/main/text/TextToGraphics.jl#L271)).
Widgets that paint their own selection band are a second, smaller family.

The property reads are mostly **mapping** code — forward and backward maps,
printers computing a child's selection. Under Rule 5 they see a live path or
nothing, so none of them change. The pale decision belongs where the pixel is
painted, and it reads the document through `getfield`.

## Steps

Each step is one commit.

1. **`SelectionDocument`.** The type in the reference layer, the widened field
   type, and the unwrapping accessors of Rule 5. The writer still clears at a
   divergence, so behaviour does not change. Test: the existing suites do not
   move, including the three write shapes.
2. **The trait and the ask.** `keeps_dormant_selection`, default `false`, and the
   walk of Rules 2 and 3. No document answers `true` yet, so nothing changes.
3. **The keepers.** The five methods. Test: the two-group case above, asserting
   `shown(g1) == 3` after the focus moves away, and the same with a widget tabbed
   pane as the document. `pane_shown_tab_index` reads the dormant path.
4. **Restore.** Rule 6. Test: put a caret in a tab of group 1, move the focus to
   group 2, come back, and the caret is where it was.
5. **Pale rendering.** A dormant caret and a dormant highlight draw muted, and
   `_forward_selection!` carries the state. This is the step that makes two
   selections on one screen readable.
6. **Stale dormant paths.** An edit can remove the node a dormant path names.
   Validate on restore and truncate to the longest matching part, and drop a
   dormant path that no longer matches where it is drawn.

## Open decisions

1. **An empty group.** A group with no tab is focused as the group itself, so a
   paste there replaces a `PaneGroup`. Unrelated to this plan, still open.

## Not in this plan

Multiple simultaneous selections — a secondary, and named ones for an operation
such as swap. `primary` reserves the shape, and a projection still maps one path
at a time, so `map_reference_forward` does not change. Building the set now would
put it in front of every reader with no test behind it.

## Sealed files

Layer 7:

- `package/kernel/main/document/DocumentMacro.jl` — the injected field's type, and
  the unwrapping property accessors.

Layer 9:

- `package/kernel/main/selection/SelectionDefaults.jl` — the divergence walk, the
  trait default, the state writes, the restore.
- `package/kernel/main/selection/SelectionInterface.jl` — the new generics.
- `package/kernel/main/selection/SelectionModule.jl` — the exports.

Nothing else touches a sealed file. The reference layer gains a new file for
`SelectionDocument`, which is an addition rather than a change. The pane slice,
the widget slice and the renderers are unsealed.
