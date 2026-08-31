# ObjectField — a document for one field of one object

**Status: IMPLEMENTED 2026-08-28** on branch `object-field`, except step 5,
which was dropped for a reason found during the work. See **Steps** and
**What the work settled**.

## Goal

Add a document that names **one field of one object**, and two projections that
present it: one to widget and one to syntax.

The widget projection makes arbitrary forms cheap. A person lays out
`WidgetLabel`s and `ObjectField`s in a `GridLayout`, and gets a form that edits
the fields of the original objects. The fields can come from different objects.

## Why the code today does not do this

Five things come close. None of them is this document.

- [Focusing.jl](../../source/projection/generic/Focusing.jl) —
  `FocusingProjection(part_type, part::Reference)` navigates into the input along
  a reference path and maps references both ways. It is a **projection**, not a
  document. It focuses one whole pipeline on one part, so it can not gather
  three fields of two objects into one form.
- [ObjectToWidget.jl](../../source/widget/ObjectToWidget.jl) — takes one
  root object and emits a fixed 2-column grid of its fields. Its io map holds
  `controls::Vector{Tuple{Any,Reference}}`, which is exactly the binding this
  plan reifies, but that binding is private to the projection.
- [ReferenceInspector.jl](../../source/inspector/ReferenceInspector.jl) —
  `ReferenceInspector(reference, target)` has the right shape, but it is
  display-only and renders as prose.
- [DocumentCore.jl](../../source/domain/DocumentCore.jl) —
  `DocumentReference(path)` holds a path and no root object, so it can not name a
  value.
- [DocumentReflection.jl](../../source/reflection/DocumentReflection.jl) —
  `ReflectedNode` is a bounded read-only shadow. The link to the original cell is
  lost.

Related pending plan: [document-locator.md](document-locator.md) proposes a
general `DocumentLocator` abstraction across many features. `ObjectField` is the
narrow, concrete case of the same idea. If the locator plan is ever implemented,
`ObjectField` becomes one of its subtypes. Do not wait for it.

## Design

### The document

```julia
@document struct ObjectField
    object::Any        # the root; stable across a rewire of the object graph
    path::Reference    # from the root to the value
end

# Sugar, the same shape the kernel already uses for ReplaceReferencedValueOperation:
ObjectField(object, field::AbstractString) =
    ObjectField(object, ConcreteReference(FieldReferenceStep(field), EmptyReference()))
```

The value is `evaluate_reference(object, path)`, read inside a `ComputedCell`.
The write is `ReplaceReferencedValueOperation(object, path, value)`.

**No `label` field.** Decided 2026-08-28 by the user: do not add it yet. The
syntax projection derives the name from the last `FieldReferenceStep` of the
path. The widget projection emits no label at all, so it needs none.

### Why a `Reference` and not a `Symbol`

1. An element is not a field. A row of a vector needs `ElementReferenceStep` or
   `RangeReferenceStep`. A name can not say `items[3]`.
2. Rewire safety. If the document held the intermediate object, a write to
   `node.config` would leave the form pointed at a dead object. A path from a
   stable root re-derives on every read.
3. The caret. If the value is itself a document that projects to text, the caret
   path must carry the field's prefix. `FocusingProjection` already does this
   with `_concat_path` and `_strip_prefix`, and a one-step path runs the same
   code as an n-step path.

The kernel made this same choice one layer down:
[Operations.jl:230](../../source/kernel/operation/Operations.jl#L230) stores
a `Reference` and adds an `AbstractString` shorthand. Note that
[FieldReferenceStep](../../source/kernel/reference/ReferenceStep.jl#L130)
holds a `String`, not a `Symbol`.

**The one cost.** Every `ReferencePath` node carries a type checkpoint. A path
built by hand must use `reference_node_type(doc)`, and comparisons must use the
`*_ignoring_types` functions. This trap is not new; it applies to every path the
code builds by hand.

### Where the code goes

`ObjectField` goes in **`package/primitive/main/ObjectField.jl`**.

The reason is the dependency graph. `ProjecturedWidget` does **not** depend on
`ProjecturedDomain`, so `DocumentCore.jl` is not visible to the widget
projection. `ProjecturedPrimitive` depends only on `ProjecturedKernel`, and both
`ProjecturedWidget` and `ProjecturedSyntax` already depend on it. Placement there
costs **no** dependency edit and no `[sources]` edit anywhere.

The package name is a small stretch — `ObjectField` names a place, not a
primitive value. But the package already holds `PrimitiveInsertion`, which is an
authoring placeholder and not a value either. The package is in practice "the
domain-neutral small documents".

**Alternative, if the name is judged wrong:** a new one-file package
`package/field/` (`ProjecturedField`), as `package/focus/` already is. The cost
is a `Project.toml`, a module root, an entry in the root `Project.toml` and
`Manifest.toml`, an entry in the `Projectured` umbrella, a new dependency in both
`ProjecturedWidget` and `ProjecturedSyntax`, and a layering-guard update. Take
this option only if the placement above is rejected.

The two projections go beside their siblings:

- `package/widget/main/ObjectFieldToWidget.jl`, next to `ObjectToWidget.jl`.
- `package/syntax/main/ObjectFieldToSyntax.jl`, next to `ObjectToSyntax.jl`.

### ObjectFieldToWidget

It emits the **bare control**, not a label and a control. A `GridLayout` takes a
flat child list, so the label must be a separate child. The caller places the
`WidgetLabel`.

The value type picks the control. Do not write a second classification. Reuse the
one in [ObjectToWidget.jl:148](../../source/widget/ObjectToWidget.jl#L148):

| Value | Control |
| --- | --- |
| `Bool` | `WidgetCheckbox` |
| `String`, `Real` | `WidgetText` |
| struct with `Cell` fields | a card holding its own grid |
| vector, tuple | a card holding a vertical list |

Pick the control with a `TypeDispatchingProjection` on the value type, and
default to the four rows above. A domain then adds a row without a change here —
`Quantity => QuantityToWidgetSpinBox()` for the omnetpp-julia units, for example.

Reuse `_coerce` as well. The capacity control returns the string `"8"`; the
reader must convert it to the type of the current value.

### ObjectFieldToSyntax

It emits the per-field node that
[ObjectToSyntax.jl:250](../../source/syntax/ObjectToSyntax.jl#L250) already
builds inline:

```julia
SyntaxNode("", "", " ", SyntaxDocument[
    SyntaxLeaf(TextString(name, field_name_style)),
    <the value, projected by the recursion>,
]; indentation = 0)
```

`name` comes from the last `FieldReferenceStep` of the path. If the last step is
not a field step, omit the name leaf and emit the value alone.

This projection adds no new render concept. It **names** one that
`ObjectNodeToSyntaxNode` hides inside `_field_entry`.

## Examples

```julia
@document struct Server
    name::String = "srv"
    capacity::Int = 4
    enabled::Bool = true
end

srv = Server("gateway", 4, true)
cli = Server("laptop",  1, false)
```

Widget:

```julia
ObjectField(srv, "name")      →  WidgetText(TextBlock(TextString("gateway")))   →  [gateway  ]
ObjectField(srv, "capacity")  →  WidgetText(TextBlock(TextString("4")))         →  [4        ]
ObjectField(srv, "enabled")   →  WidgetCheckbox(true)                           →  [x]
```

A deeper path works the same way:

```julia
ObjectField(net, Reference(FieldReferenceStep("hosts"),
                           ElementReferenceStep(2),
                           FieldReferenceStep("address")))
→  WidgetText(TextBlock(TextString("10.0.0.2")))  →  [10.0.0.2 ]
```

The form — two different objects in one grid, which `ObjectToWidget` can not do:

```julia
GridLayout(Any[
    WidgetLabel("Server name"), ObjectField(srv, "name"),
    WidgetLabel("Client name"), ObjectField(cli, "name"),
    WidgetLabel("Capacity"),    ObjectField(srv, "capacity"),
    WidgetLabel("Enabled"),     ObjectField(srv, "enabled"),
], 2)
```

```
Server name  [gateway  ]
Client name  [laptop   ]
Capacity     [4        ]
Enabled      [x]
```

Syntax:

```julia
ObjectField(srv, "name")      →   name "gateway"
ObjectField(srv, "capacity")  →   capacity 4
ObjectField(srv, "enabled")   →   enabled true
```

Stacked:

```julia
SyntaxNode("{", "}", " ", [ObjectField(srv, "name"), ObjectField(cli, "name")])
```

```
{ name "gateway"
  name "laptop" }
```

## The round trip

1. A person types `gw2` in the first control. `WidgetText` recurses through the
   Text domain, so `TextToGraphics` emits a `ReplaceStringRangeOperation` rooted
   in the control's `TextBlock`.
2. `ObjectFieldToWidget.read_intent` sees its own output, applies the character
   range, and returns `ReplaceReferencedValueOperation(srv, ⟨name⟩, "gw2")`.
3. The default handler writes `srv.name`.
4. `srv.name` is a `Cell`, so the `ComputedCell` re-derives and the control
   repaints — and so does every other view of `srv`. That is the payoff over a
   copied value.

## Steps

One commit per step. Do the work in a dedicated git worktree.

- [x] **1. The document.** Landed. Add `package/primitive/main/ObjectField.jl` with
      `ObjectField`, the string-name constructor, and a `field_value(f)` reader
      built on `evaluate_reference`. Include it from
      `package/primitive/main/ProjecturedPrimitive.jl` and export `ObjectField`.
- [x] **2. ObjectFieldToWidget.** Landed. `_coerce`, `_apply_range`, `_as_string`
      and `_end_cursor` are imported from `ObjectToWidgetModule`, not copied. Add
      `package/widget/main/ObjectFieldToWidget.jl`. The printer emits the bare
      control through a `TypeDispatchingProjection`. The reader converts a
      control edit to `ReplaceReferencedValueOperation` on the field's object and
      path, and reuses `_coerce`. Add `map_reference_forward` and
      `map_reference_backward` following the `FocusingProjection` pattern.
      Include it from `ProjecturedWidget.jl` after `ObjectToWidget.jl`.
- [x] **3. ObjectFieldToSyntax.** Landed. Add
      `package/syntax/main/ObjectFieldToSyntax.jl`. The printer emits the
      name-leaf plus value node. Derive the name from the last
      `FieldReferenceStep`. Include it from `ProjecturedSyntax.jl` after
      `ObjectToSyntax.jl`.
- [x] **4. Tests.** Landed: 56 assertions across the two files, all passing. Add `package/substrate/test/projection/ObjectFieldToWidgetTest.jl`
      and `ObjectFieldToSyntaxTest.jl`, beside `ObjectToWidgetTest.jl` and
      `FocusingTest.jl`. Cover: each control type, a deep path, a two-object
      form, the edit round trip, and a write from outside that repaints the
      control. Run only the two new files, then `test_substrate()`.
- [ ] **5. Extract the syntax field entry. DROPPED — do not do this.**
      `ObjectNodeToSyntaxNode` projects each field's **`Cell`**, through
      `CellToSyntax`. That is what makes a field repaint when its cell is
      written. An `ObjectField` names a value reached by `evaluate_reference` and
      has no cell to hand on. The two are reactive by different means, so the
      delegation would change the reactive wiring of every object rendering in
      the tree. The duplication is two lines of node building; the risk is not
      worth it. The reason is recorded in the `ObjectFieldToSyntaxModule`
      docstring. The original step read: Make
      `ObjectNodeToSyntaxNode._field_entry` delegate to `ObjectFieldToSyntax`, so
      one code path builds a field node. Assert the output of
      `test_printer` on an object example does not change.
- [x] **6. Examples and the guides.** Landed: two examples, and sections in
      widget.md, syntax.md and architecture.md. Add a form example under
      `package/substrate/example/`. Update
      [package/widget/doc/widget.md](../../documentation/package/widget/widget.md) and
      [package/syntax/doc/syntax.md](../../documentation/package/syntax/syntax.md).

## What the work settled

**The element write works.** `ElementReferenceStep` is not a type —
[ReferenceStep.jl:59](../../source/kernel/reference/ReferenceStep.jl#L59)
defines it as `RangeReferenceStep(index - 1, index)` — and
`_write_slot!(parent, ::RangeReferenceStep, value)` writes `parent[i] = value`.
No new kernel method was needed. A test writes `server.tags[2]` through an
`ObjectField`, in the same testset that shows `ObjectToWidget` registers no
control whose path starts at `tags`.

One trap was found while checking it:
[Operations.jl:196](../../source/kernel/operation/Operations.jl#L196)
overloads the same terminal step with an `AbstractVector` value as a **splice**.
An `ObjectField` whose value is itself a vector can not be written by a plain
replace. Recorded in both guides.

**`ObjectField` is the field a `FormLayout` row wanted.** `FormLayout(rows)`
already existed, taking `(label, field)` pairs of documents and building the
two-column grid. A bare control is exactly what fits that slot, which is a second
reason the projection emits no label of its own.

**The placement held.** `ObjectField` in `package/primitive/main/` needed no
dependency edit and no `[sources]` edit. Both `ProjecturedWidget` and
`ProjecturedSyntax` reach it through a dependency they already had.

## Open questions

- Tab traversal between the controls of a form. `is_focusable_document` in
  [Focus.jl](../../source/focus/Focus.jl) is the trait, and `WidgetModule`
  marks its enabled interactive leaves. A control here is an ordinary
  `WidgetText` or `WidgetCheckbox`, so it should already be marked — but no test
  asserts it. Add one.
- Caret navigation from a control's text into the object's reference space. Both
  mappers return `nothing`, which is what `ObjectToWidget` does. The caret is
  pinned to the end of the text, so there is nothing yet for a mapper to answer.
- A value whose **type** changes after the first print keeps the old control.
  `ObjectToWidget` has the same bound. Choosing the control once is what keeps
  the control identity, and with it the caret, stable across an ordinary edit.
