# Focus

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [selection.md](../kernel/selection.md)

Focus is selection: the generic walk that finds the first or last focusable
leaf of a document subtree for Tab traversal, the whole-element selection
that an Alt+click makes, the four Alt+arrow keys that walk one, and the
reference step that lets a selection name a widget a projection drew rather
than a field of a document. The walk names no widget type; a domain opts a
document type into focus by adding one trait method.

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/focus/FocusModule.jl` | the module, and what it exports |
| `source/focus/Focus.jl` | `is_focusable_document`, `get_first_focusable_path`, `get_last_focusable_path`, `get_next_focusable_index` — the Tab walk |
| `source/focus/WholeSelection.jl` | `is_whole_selection_press`, `is_whole_selection`, `convert_to_whole_selection` — the Alt+click selection |
| `source/focus/SelectionWalking.jl` | `SelectionWalkingProjection` — the four Alt+arrow keys |
| `source/focus/OutputSelection.jl` | `OutputReferenceStep` — a selection that names a drawn widget, not a document field |

## The Tab walk

`is_focusable_document(node)` defaults to `false`; a domain adds a method for
the document types a Tab press should be able to land on.
`get_first_focusable_path(node)` and `get_last_focusable_path(node)` return
the relative whole-element path to the first or last focusable document in
`node`'s subtree, skipping a disabled widget, or `nothing` when the subtree
holds none. The walk guards against a cycle in the document graph — an
embedded linked list points forward and back — by tracking visited object
identities, so it visits each node once regardless of how the graph closes on
itself. `get_next_focusable_index(children, after, reverse)` finds the next
sibling slot whose subtree contains a focusable document, for a container
stepping Tab across its own children. Both `LayoutToGraphics` and
`WidgetToGraphics` share this walk.

## The whole-element selection

`is_whole_selection_press(event)` is true for a left press with Alt held and
no other modifier — a plain press keeps its own meaning, so a button still
fires. `is_whole_selection(document, reference)` tells a whole-element
selection from a caret or a range: the reference must evaluate, inside
`document`, to a `Document` rather than a scalar position. A container that
gets an Alt+press answered by its child calls
`convert_to_whole_selection(operation, child)`. It keeps an answer that
already names a value inside `child`, such as a caret or a selection inside
it. Any other answer, including a control's own click action, becomes the
whole selection of `child`. `SelectionWalkingProjection(; inner)` wraps a
projection and answers the four Alt+arrow keys — up to the enclosing object,
down to the first object inside, left and right to a sibling — for whatever
nothing inside `inner` answered first.

`OutputReferenceStep(owner, node, output_path)` is for a widget a projection
drew that has no document of the domain behind it: a table's header, a
parameter box, a heading. It reaches `node` only from `owner`, so copying,
noting or Alt+clicking the drawn widget works the way it works for any other
document.

## How it fits

`FocusModule` depends on `ProjecturedKernel` and `ProjecturedCollection`
alone; every domain that wants Tab or Alt+click support adds a method to
`is_focusable_document` rather than this slice depending on the domain.
[widget.md](../widget/widget.md) is the main caller: `WidgetModule` marks its
enabled interactive leaves as Tab stops, and the whole-element machinery is
what an Alt+click on any widget resolves through.

## What a reader must know before changing this

There is no `test/focus/` folder; the walk and the whole-element selection
are exercised through `test/substrate/projection/SelectionWalkingTest.jl`,
`WidgetButtonTest.jl` and `WidgetSelectionTest.jl`. The cycle guard in
`get_first_focusable_path` / `get_last_focusable_path` is what keeps Tab from
stack-overflowing on a document that embeds a doubly-linked list, such as
text or syntax content in the assistant; removing it reintroduces that crash
rather than merely slowing the walk down.
