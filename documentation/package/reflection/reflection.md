# Reflection

> **Kind:** design · **Status:** current · **Stands on:** [bounded-sync.md](bounded-sync.md), [document.md](../kernel/document.md), [widget.md](../widget/widget.md)

`ProjecturedReflection` shows any Julia value on the screen with no projection written for it. It keeps a bounded shadow of the value, a tree of `ReflectedNode`, and draws the tree as a `WidgetTree` whose chevrons grow the shadow one level at a time. This document says how the shadow, the view and the value viewer fit together, and how this path differs from `ObjectToWidget` and `NaturalToGraphics`; [bounded-sync.md](bounded-sync.md) describes the bounded walk in detail.

## How it works

### The bounded sync

The kernel has one walk for `sync_document!` and `copy_document`, and a policy is a parameter of it. At each child, the walk calls three open functions: `is_descendable_for_sync`, `sync_element_limit` and `make_unsynced_placeholder`. This package answers them. `DepthPolicy(depth, elements)` grows an empty slot only within `depth`, keeps a slot that already holds a document, and descends into a marker only when it is `requested`. Past `elements` items of a collection, one tail marker holds the count of the rest. `UNBOUNDED_SYNC` walks everything.

`UnsyncedDocument` is the marker: a `kind` for the label, a `size` when the count is cheap to know, and `requested`. `make_unsynced_marker(document)` collapses a subtree at once. `request_sync!(marker)` only flags the marker, and the next sync fills that node one level deeper. So a collapse costs nothing, and an expand costs nothing until something syncs. A shadow must start bounded, with `copy_document(kind, document, policy)`, because a bound can only withhold what has not grown yet.

### The shadow of a value

`sync_document!` needs a `Document` on both sides, and most values that a person inspects are plain structs. `reflect_document(value, policy)` walks any value into a tree of `ReflectedNode`:

- `label` is the field name, the index or the key in the parent;
- `kind` is the type name, and the schema name for a document, from `get_document_schema_name`;
- `value` is a short text for a leaf, at most 64 characters;
- `children` is a `CellVector` of nodes when open, an `UnsyncedDocument` when closed, and `nothing` for a leaf.

The three states of `children` are the three states of the policy. So the open state of a node needs no table of its own: it is the presence of a marker. `sync_reflection!(shadow, value, policy)` brings the shadow up to date in place. A node that exists keeps its identity, so a widget that holds it keeps holding it.

`reflect_child_count(x)` and `reflect_child_pairs(x)` give the children of a value. A type whose useful structure is not its fields adds a method to both. They are a count and an iterator, not a vector: a vector of a thousand pairs to show eight costs what the bound saves, up to 162 KB for each sync. `is_reflection_leaf(x)` is `true` for a number, a string, a symbol, a function, a type, and a value with no children.

### The view

`ReflectionToWidget(; show_kind)` prints the shadow as a `WidgetTree`. Each node becomes a `WidgetTreeNode` whose label is `name = value` for a leaf, or `name: kind` for a composite. The tree draws a chevron only for a node with children. So a node on a marker gets one placeholder child that says how much is behind it, such as "100 items not loaded".

The open state has one record, the shadow. The printer derives the `collapsed` set of the `WidgetTree` from the nodes on markers. The chevron of a tree writes a new `collapsed` set with a `ReplaceReferencedValueOperation`. The reader compares that set with the derived one, finds the node of each path that changed, and returns `SetReflectedDisclosureOperation(changes)`. It does not write the shadow, because a reader has no side effect. `evaluate_operation` of the operation writes a marker for a close and calls `request_sync!` for an open.

The printer walks the shadow inside a cell, and the roots and the `collapsed` set of the `WidgetTree` read that cell. So a sync that fills a node prints the tree again, and an editor that keeps its IoMap shows the node open.

### The feed

A request only flags a marker, so something must run the sync. `ReflectionFeed(shadow, value; policy)` is the feed that does it: the editor drains it once per frame, on its own task, and the drain calls `sync_reflection!` with the policy that made the shadow. A sync writes only what changed, so a frame with no change writes no cell. While a marker waits with `requested`, `compute_wake_deadline` answers `0.0`, so the frame after a click runs at once and opens the node. A drain that throws leaves the request to the next input, so a value whose walk throws does not make a frame for each fault.

### Three ways to draw a value

| Path | What it is for | What it costs |
| --- | --- | --- |
| `ReflectionToWidget`, this package | any value: large, running, or one that refers to itself | one level at a time; a chevron flags the next level |
| `NaturalToGraphics`, [natural.md](../natural/natural.md) | a document of a registered domain, or a small struct | every field that it reaches |
| `ObjectToWidget`, [widget.md](../widget/widget.md#from-a-domain-to-widgets) | the fields of one object as a form that a person edits | the fields of the object, to depth 16 |

`NaturalToGraphics` reflects a value that no domain registered through `ObjectToSyntax`, which prints the type name and the fields. That flat view suits a small value. `ObjectToWidget` also reflects an object, but it makes a card for each nested value and a control for each field, which is a form to edit. The value of a running program needs a compact row for each node and no edit, so this package has its own tree.

`make_value_viewer(value; tree, depth, elements)` in `example/projectured/ValueViewer.jl` builds the pair: `reflect_document` with a `DepthPolicy`, and `ChainingProjection(ReflectionToWidget(), WidgetToGraphics(…))`. With `tree = false`, it returns the value itself and `NaturalToGraphics`. `make_value_viewer_feeds(document, value; depth, elements)` gives the `ReflectionFeed` of the tree, and none for the flat view. `run_value_viewer(value)` opens the view in a window with its feeds. [view-your-data-guide.md](../../guide/view-your-data-guide.md) is the guide for a user.

## How it fits

`ProjecturedReflection` depends on the kernel, `ProjecturedCollection` and `ProjecturedWidget`. The kernel gives it the feed contract of `ReflectionFeed`. The dependency goes from reflection to widget: a projection belongs to the package of what it reads, and `ReflectionToWidget` reads a `ReflectedNode`. The widget package has no reference to this package.

The package registers nothing. It adds methods to the three open functions of the kernel walk, and a caller extends `reflect_child_count` and `reflect_child_pairs` for its own types. The umbrella package loads it, and the value viewer of the examples is its one direct caller.

## Design decisions

- **The sync is bounded, not the projection.** A lazy projection leaves the whole sync in place and then discards its result. A bounded sync costs what is on the screen. See [plan/done/bounded-document-sync.md](../../../plan/done/bounded-document-sync.md).
- **One walk, in the kernel.** A second, bounded walk in this package would repeat the kernel walk line for line and would need internals of the kernel, which the module boundary forbids. See [bounded-sync.md](bounded-sync.md#where-the-walk-lives).
- **The open state is the marker.** A side table of open nodes can disagree with the shadow; a marker can not.
- **A collapse is immediate, and an expand is a request.** A click does not start a deep walk, and a close only drops data.
- **A feed runs the sync.** The reader stays pure and the operation does not know the value, so the sync runs on the editor task where the feeds of the editor drain; see [editor.md](../kernel/editor.md#the-feeds).
- **The children are an iterator and a count.** A vector builds what the cap withholds.
- **A tree, not `ObjectToWidget`, for the value viewer.** Both would draw the same node tree, and a compact row per node suits a value that a person drills into. `ObjectToWidget` also edits, which is wrong for the inside of a running program.

## Usage

```julia
shadow = reflect_document(value, DepthPolicy(depth = 1, elements = 20))
sync_reflection!(shadow, value, DepthPolicy(depth = 1, elements = 20))
projection = ChainingProjection(ReflectionToWidget(),
                                WidgetToGraphics(font_ubuntu_monospace_regular_20;
                                                 measure = FontFileMeasure()))
run_value_viewer(Dict("a" => 1, "b" => [1, 2, 3]))   # the tree, one level at a time
run_value_viewer(value; tree = false)                # the flat view
```

- Tests: `test_reflection_to_widget()` in `test/substrate/projection/ReflectionToWidgetTest.jl` checks the label of a closed node, the round trip of a chevron, and a printed tree that follows a sync. `test_document_reflection()` in `test/substrate/document/DocumentReflectionTest.jl` checks the shadow, and `test_value_viewer()` in `test/projectured/editor/ValueViewerTest.jl` checks the kinds of value that the viewer must draw and a chevron that opens a node in an editor with the feeds of the viewer.

## Limits

- The shadow is not the value. A change of the value shows only after a `sync_reflection!`. In the value viewer, the feed runs one on each frame, and a change with no input makes no frame.
- The view shows values and does not edit them. An edit needs a projection of the domain that owns the value.
- The flat view of a dictionary raises an error, because `NaturalToGraphics` reflects the fields of its implementation. `ValueViewerTest.jl` marks it `@test_broken`; the tree view draws a dictionary.
