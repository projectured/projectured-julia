# A form edits a plain value

> **Status (2026-10-08): DONE.** Steps 1 to 6 are on the branch
> `plain-value-form`, in the worktree `projectured-julia-plain-value-form`, and
> steps 7 to 10 on the branch `text-config-in-documents` on top of it, after
> [text-projection-config-into-document.md](text-projection-config-into-document.md)
> retired `ProjectionConfiguringProjection` (decision 17). The owner
> answered the first six questions on 2026-10-06, chose the design of parts C and
> D on 2026-10-08 (see "Decisions"), and asked for the implementation on
> 2026-10-08. Not on main and not pushed.

## Goal

An author has a plain Julia value: a `struct` that is not a `@document`, and
that can hold other plain values. The author lays out a form for it with
`FormLayout`, `ObjectField` and `ObjectFieldToWidget`, and the form edits the
value.

The author chooses one of two ways to edit:

- **A, a copy in a schema.** The author writes a `@document` schema with the same
  field names. The library copies the value into a document of that schema. The
  form edits the document. The author copies the document back into a plain
  value at a commit, or drops it at a cancel.
- **B, the value in a cell.** The author puts the plain value into one `Cell`.
  Each edit writes a new value into the cell at once, and the form updates.

Two more parts close the gaps that the first version leaves:

- **C, a control for each field.** The author builds the widget tree as usual,
  and puts an `ObjectField` in a widget slot where a value goes. The widget asks
  the field for the operation that stores each value. A bare `ObjectField`, for
  example in a markdown document, still becomes the default control for the type
  of its value.
- **D, `ObjectToWidget` shows a plain nested value.** The form that
  `ObjectToWidget` makes edits at any depth, and opens a plain struct into a card.

The layout and the projection are the same for A and for B. Only the root of
each `ObjectField` changes:

```julia
struct Server            # a plain value, not a @document
    name::String
    capacity::Int
    enabled::Bool
end

form(root) = FormLayout([
    (WidgetLabel("Name"),     WidgetText(ObjectField(root, "name"))),
    (WidgetLabel("Capacity"), WidgetSpinBox(ObjectField(root, "capacity"))),
    (WidgetLabel("Enabled"),  WidgetCheckbox(ObjectField(root, "enabled"))),
])

# A: a copy in a schema
@document struct ServerForm
    name::String
    capacity::Int
    enabled::Bool
end
server_form = convert_object_to_document(ServerForm, server)
document = form(server_form)
server = convert_document_to_object(Server, server_form)   # at a commit

# B: the value in a cell
root = Cell(server)
document = form(root)
server = root[]                                        # the value after the edits
```

## The choice, in one table

The two ways are two corners of a table with two axes: does the author write a
schema, and does an edit reach the value at once.

| | an edit writes at once | the author commits |
| --- | --- | --- |
| **a schema** | a `@document` value of the author's own (exists now) | **A** |
| **no schema** | **B** | B on a copy: `draft = Cell(deepcopy(server))`, then `server = draft[]` |

A gives a cell for each field. So only the control of the field that changed
computes again, and the document works with all of the document machinery:
`ObjectToWidget`, `copy_document`, `sync_document!` and the search. The cost is
one schema for each type and a copy at each end.

B needs no schema. All the controls under the cell compute again after each
write. That is a small cost for a form, and a large one for a large value.

## What the code does now

Facts from the code on 2026-10-06:

- **A read works on any object.** `_get_field` uses `getfield` and then
  `unwrap_cell` ([ReferenceStep.jl:137](../../source/kernel/reference/ReferenceStep.jl#L137)).
- **A write needs a `Cell` in the slot.** `_write_slot!` throws
  `field … is not a Cell` for a plain field
  ([Operations.jl:232](../../source/kernel/operation/Operations.jl#L232)). There is
  no `setfield!` for a mutable struct, and no copy for an immutable one.
- **A carried root that is a cell has no write.** `evaluate_operation` throws for
  a carried root with an empty reference, and a field step on a `Cell` reads a
  field of the cell itself.
- **The inverse of a write carries the parent object**
  ([Inversion.jl](../../source/kernel/operation/Inversion.jl), `_make_slot_inverse`).
  For B that is wrong: a write replaces an immutable parent, so the old parent is
  no longer in the value.
- **A `ReactiveCell` write always tells its readers**, also when the new value is
  the same object (`Base.setindex!` in
  [ReactiveCell.jl](../../source/kernel/cell/ReactiveCell.jl)). So a cell can be
  written with its own value to make its readers compute again.
- **A `MutableCell` write tells no reader.** `MutableCell.jl` is sealed (🔒), and
  this plan does not change it.
- **The mouse target chain of a write** (`_find_written_chain` in
  [PathChain.jl](../../source/kernel/operation/PathChain.jl)) answers `nothing`
  for a parent that is not a `Document`, so a plain parent needs no change there.
- **The kernel has no runtime dependency**
  ([Project.toml](../../package/ProjecturedKernel/Project.toml)). So B can not use
  ConstructionBase to make a copy of a struct.
- **The macro has a native layout and a shadow sync** (`@document [M, C]`,
  `sync_document!`). Both need a schema on both sides, so neither copies a plain
  type that the author can not declare again.
- **The reflection shadow** (`reflect_document`) copies any value, but its paths
  are `children[i]`, not field names. So a form of `ObjectField(x, "name")` can not
  use it.

## Design of A

Two functions, matched by field name:

- `convert_object_to_document(T, object)` makes a document of schema `T`. Each
  field of `T` takes the value of the field of `object` that has the same name.
- `convert_document_to_object(T, document)` makes a plain `T`. Each field of `T`
  takes the value of the field of `document` that has the same name. The
  function calls the default constructor of `T` with the fields in their order.

The rules:

1. **A field of the schema that the object does not have** is an error. The
   owner decided this on 2026-10-06: a silent default hides a typing error in a
   field name.
2. **A field of the object that the schema does not have** is not copied. So a
   schema can show a part of a value.
3. **A nested value converts too.** When the value type of a field of the schema
   is a document schema and the value is not a document, the function converts
   the value to that schema. The way back converts with the field type of the
   plain `T`.
4. **A vector** copies element by element. An element converts when the element
   type of the schema is a document schema.

A uses only public functions of the kernel: `fieldnames`, `unwrap_cell`,
`get_cell_value_type` and the constructors that `@document` writes. So it needs
no change in the kernel. A lives in the platform primitive slice, beside
`ObjectField` (decided 2026-10-06).

A commit or a cancel needs no helper of the library. B on a copy needs none
either: the author writes `draft = Cell(deepcopy(x))` and `x = draft[]`
(decided 2026-10-06).

## Design of B

### The write

`evaluate_operation` of `ReplaceReferencedValueOperation` finds the slot to write
in this order:

1. **A cell field of a document, or an element of a document collection.** The
   write does what it does now.
2. **A carried root that is a cell, with an empty reference.** The write puts the
   value into the cell.
3. **A plain immutable parent**, such as a `struct`, a `NamedTuple` or a `Tuple`.
   `with_object_field(parent, name, value)` makes a copy of the parent with the
   one field changed. The write then puts that copy into the slot one level up,
   and goes back to rule 1 for that slot.
4. **A plain mutable parent**, such as a `mutable struct` with a field step, or a
   `Vector` with an element step. The write changes the parent in place:
   `setfield!` with a `convert` to the field type, or `setindex!`. Then it writes
   the nearest cell above the parent with the value that the cell holds, so the
   readers of the cell compute again. The owner chose a change in place over a
   copy on 2026-10-06: an author who shares the object with other code expects it
   to change.
5. **No cell above the slot.** The write throws an exception that tells the
   author to put the value into a `Cell`.

A field step on a plain `Dict` names a key, and the write refuses it, as it does
now (decided 2026-10-06).

One private function finds the slot by these rules. Both the write and the
inverse use it, so the two can not disagree.

### The inverse

The inverse writes the old value at the same full path, from the holder of the
nearest cell above:
`ReplaceReferencedValueOperation(holder, path from the holder, old value)`. The
holder is the cell itself for a cell root, and the document for a cell field. So
the inverse goes through the same rules, and an undo also updates the form.

### The copy of a struct

`with_object_field(object, name::Symbol, value)` is a new open function. Its name
follows the rule for a derived copy (`with_<stem>`) in
[naming-rules.md](../../documentation/rule/naming-rules.md). Its methods:

- a struct: the default constructor of `typeof(object)` with all the fields, and
  the one field changed;
- a `NamedTuple`: `merge`;
- a `Tuple`, with an element step: `Base.setindex`.

A type whose inner constructor does not take all of its fields adds a method.

### The read

`get_object_field_value` reads the root through `unwrap_cell`. The read is in a
cell computation, so the control depends on the root cell, and a write to that
cell updates the control.

### The limits of B

- Each write makes every control under the cell compute again.
- An immutable value is replaced by a new object at each write. A mutable value
  is changed in place and keeps its identity.
- A mutable value that other code changes, not with an operation, does not
  update the form. The author can write the cell with its own value to update it.
- A `MutableCell` root does not update the form, because its write tells no
  reader.
- `ObjectToWidget` does not show a plain nested struct until part D lands.

## Design of C: a widget slot holds an `ObjectField`

The owner chose this design on 2026-10-08. See "Decisions" for the designs that
it replaces.

### Now

`ObjectFieldToWidget` selects the control by the type of the value: `Bool` gives
a `WidgetCheckbox`, a `String` or a number gives a `WidgetText`, and all other
values give a read-only `WidgetLabel`. Its `controls` table adds a row for a
value type. So two `String` fields can not get two different controls, and a
`Symbol` from a fixed set is read only. The chart inspector shows this:
`draw_style`, `line_style` and `symbol` of a `ChartSeries` are `Symbol` values
([ChartDocument.jl:124](../../source/domain/chart/ChartDocument.jl#L124)), so the
inspector shows them and can not edit them.

The reader maps back two edits only: a `ReplaceReferencedValueOperation` sent
from the control itself, and a `ReplaceStringRangeOperation` in a `WidgetText`.
No test sends a click through a whole hand-laid form. The tests in
`ObjectFieldToWidgetTest.jl` call the reader of one field directly.

### The model

The author builds the widget tree as usual, and puts an `ObjectField` where a
value goes. The widget is the choice of control, and its settings, such as
`min`, `max` and `options`, are fields of the widget:

```julia
FormLayout([
    (WidgetLabel("Name"),     WidgetText(ObjectField(server, "name"))),
    (WidgetLabel("Enabled"),  WidgetCheckbox(ObjectField(server, "enabled"))),
    (WidgetLabel("Capacity"), WidgetSpinBox(ObjectField(server, "capacity");
                                            min = 1, max = 64)),
    (WidgetLabel("Style"),    WidgetSelect(ObjectField(series, "draw_style");
                                           options = Any[:linear, :step, :bar])),
    (WidgetLabel("Ratio"),    ObjectField(server, "ratio")),    # a bare field
])
```

Each part has one job:

- **The widget** decides how the user sees a value and how the user picks or
  enters a new one: a box, a popup, a row of buttons, a text.
- **The field** decides how a value is read and how a value is stored. It
  knows nothing about the widget.

SwiftUI works the same way: a `Picker` lists its options, and a pick calls
`binding.set(v)`.

### The composition

Two rows decide what an `ObjectField` becomes:

- **In the shared recursion, a bare field becomes a control.** The row
  `ObjectField => ObjectFieldToWidget` stays. A bare field can be in a layout, in
  a card, or in a document that nobody builds by hand, such as a markdown
  document whose reader makes `ObjectField` nodes. No builder function runs in
  such a document, and its domain does not know about widgets.
- **In a value widget, a field in a slot becomes a value.** The row of the
  widget is a nesting:

  ```julia
  WidgetCheckbox => NestingProjection(WidgetCheckboxToGraphicsCanvas(...), ObjectFieldToValue())
  ```

  `NestingProjection` gives the widget printer a recursion made from
  `ObjectFieldToValue` for its direct children only. Further down, it falls back
  to the outer recursion
  ([Nesting.jl:44-55](../../source/platform/projection/higherorder/Nesting.jl#L44-L55)).
  `CollectionToSyntax` uses the same shape
  ([CollectionToSyntax.jl:184](../../source/platform/syntax/CollectionToSyntax.jl#L184)).

Only a higher-order projection of the projection algebra holds a projection
field. The owner set this rule on 2026-10-08. So no widget projection takes a
value projection as a parameter, and the algebra makes the composition.

A factory of the widget slice makes the table. It takes the rows of
`WidgetToGraphics(...).dispatch`, and puts the row of each value widget into
the nesting. It uses the type-dispatch idiom behind a factory with no
argument, as `PAR-HIGHER-ORDER-IS-DOMAIN-FREE` asks.

- **The value widgets** are the checkbox, the switch, the toggle, the slider,
  the spin box, the radio group, the select and the text. The step checks that
  each of these printers recurses no child other than its value slot.
- **A container keeps its row.** For example, a bare field as the content of a
  card must stay a control.
- **There is no loop.** `ObjectFieldToWidget` makes the default widget with the
  field in its slot, and prints that widget through the recursion. The row of
  that widget is a nesting, so its slot goes to `ObjectFieldToValue`.

### How a widget uses a value slot

- **A slot that holds a document** is printed with `print_child`. Through the
  nesting it reaches `ObjectFieldToValue`. The widget keeps the child IO map, as
  `WidgetText` keeps the IO map of its content now
  (`make_reconciled_child_iomap_cell`).
- **A slot that holds a plain value** has no child. The widget reads and writes
  the slot itself, as now. So a widget with plain values pays nothing.

**Forward.** The widget reads the value from the output of the child, in its
reactive print.

**Backward.** For each value that the widget offers or that the user enters,
the widget asks the child for the operation that stores it. It calls the reader
of the child IO map directly, with an ordinary operation: "replace your output
with `v`", which is `ReplaceReferencedValueOperation(nothing, EmptyReference(),
v)`. `CopyingProjection` gives a payload to the reader of its child in the same
way (`_route_to_child`). The widget needs no recursion for this, which fits:
the reader of `NestingProjection` passes the outer recursion to the widget
([Nesting.jl:57-62](../../source/platform/projection/higherorder/Nesting.jl#L57-L62)).
The answer for an `ObjectField` is `ReplaceReferencedValueOperation(F.object,
F.path, v)`, with `v` converted to the type of the value that the field holds.

One helper of the widget slice does this for every widget. With a child, it asks
the child. With no child, it answers `ReplaceReferencedValueOperation(widget,
slot, v)`, as the widgets do now. If the child answers an operation that still
names a place in the output of the child, the slot does not take that value,
and the widget sends no edit. The kernel reads such an operation as a write at
the root of the editor, so it must never leave the widget.

### The edit sites

Each value widget asks the helper where it now builds
`ReplaceReferencedValueOperation(w, slot, v)` (`WidgetToGraphics.jl`,
2026-10-07):

| widget | slot | the value that it asks to store |
| --- | --- | --- |
| `WidgetCheckbox` | `content` | the opposite of the value |
| `WidgetSwitch` | `checked` | the opposite of the value |
| `WidgetToggle` | `pressed` | the opposite of the value |
| `WidgetSlider` | `value` | the new position, a `Float64` |
| `WidgetSpinBox` | `value` | the value after a step, inside `min` and `max` |
| `WidgetRadioGroup` | `selected` | the option at the new index |
| `WidgetSelect` | `value` | each option, when the popup opens |
| `WidgetText` | `content` | the whole string after a key |

Two widgets convert in their own code:

- **`WidgetRadioGroup`.** When `selected` holds a document, the value of the
  child is an option, and the index to draw is its place in `options`. A value
  that is not an option draws no selected option.
- **`WidgetSlider`.** The value of the child becomes a `Float64` for the drawing.
  The field converts the stored `Float64` back to its type. An `Integer` field
  takes the nearest integer.

### The popup of `WidgetSelect`

The select asks its child for the operation of each option when the popup
opens. That is in its reader, in the window of the form
(`_open_select_popup`). `WidgetOption` gets an `operation` field, as
`WidgetMenuItem` has one now. A pick sends the operation of the option and the
close of the popup. The operation names the object of the field, so the pipeline
of the popup passes it on unchanged. A select with a plain value fills each
operation with a write on the select itself, which is what a pick does now.

### The text slot

`WidgetText.content` can be a `TextBlock`, which must still reach `TextToGraphics`
through the outer recursion. So the inner element of the nesting of `WidgetText`
is a dispatch with a fallback:
`TypeDispatchingProjection(ObjectField => ObjectFieldToValue(), Any => <back into
the outer recursion>)`. The algebra has no named projection that only sends its
input back into the recursion. An empty `NestingProjection` does that
([Nesting.jl:51-53](../../source/platform/projection/higherorder/Nesting.jl#L51-L53)),
but its public constructor needs at least one element, and its reader answers
nothing when it holds no stored recursion
([Nesting.jl:59](../../source/platform/projection/higherorder/Nesting.jl#L59)).
The fallback is an empty `NestingProjection` (decision 13). The step adds a
public constructor with no element. It also makes the reader pass the payload
to the IO map that the print made (`iomap.child_iomap`), through the projection
of that IO map. The reader can not use its recursion argument, because a widget
that asks its child directly calls the reader with no recursion.

`WidgetText` sends a document content through the recursion now, and expects
graphics back ([WidgetToGraphics.jl:1803](../../source/platform/widget/WidgetToGraphics.jl#L1803)).
`ObjectFieldToValue` gives a value. So `WidgetText` gets a third case: a child
output that is not graphics is drawn through its plain-text path. A character
edit then makes the new string, and the widget asks the child to store it.

### `ObjectFieldToValue`

It is the inner element of the nesting of a value widget, not a row of the
shared recursion.

- **Its output** is a live value: a computed cell that reads the field. The step
  checks how `@iomap` keeps a cell as the output.
- **Its reader** answers a replace of its whole output with a write on the field,
  converted to the type of the value. It passes every other payload on
  unchanged.

### `ObjectFieldToWidget`

It stays, for a bare field (decision 12). It makes the widget for the field,
and prints that widget through the recursion. Its reader gives each payload to
the IO map of that widget. Its readers for the checkbox and for the text go
away.

The widget comes from a seam and a function argument (decision 16):

```julia
# The seam: the default widget for a field, chosen by the type of its value.
make_object_field_widget(field) = make_object_field_widget(get_object_field_value(field), field)
make_object_field_widget(::Bool, field)           = WidgetCheckbox(field)
make_object_field_widget(::AbstractString, field) = WidgetText(field)
make_object_field_widget(::Real, field)           = WidgetText(field)
make_object_field_widget(_, field)                = WidgetLabel(field)     # read only
make_object_field_widget(::Quantity, field)       = WidgetSpinBox(field)  # a domain adds one

# The argument: a projection that makes a widget for a field takes it.
ObjectFieldToWidget(; make_widget = make_object_field_widget)
```

- **The seam reads the value once**, when the projection prints. A value that
  changes its type after the print keeps the old widget, as now.
- **The function gets the `ObjectField`**, which carries the object, the path
  and the value. So a function can decide by any of them, and fall back to the
  seam.
- **The argument covers a type that the author does not own.** A method of the
  seam for such a type would be type piracy.
- **The field of the projection holds a function, not a projection**, so it
  keeps the rule that only a higher-order projection of the algebra holds a
  projection field.
- **The `controls` table goes away.** Julia dispatch on the type of the value
  takes its place. No caller passes the table on 2026-10-06. The step checks
  whether the release rule counts the removed keyword of the exported
  constructor. Nothing exported is removed.

A hand-laid form then needs one stage, not two: the recursion that draws the
widgets, with the nesting rows and the row of `ObjectFieldToWidget`.
`make_object_field_form_projection_example` changes to that one stage.

### The typed slots

Four slots can not hold an `ObjectField`: `WidgetSwitch.checked::Bool`,
`WidgetToggle.pressed::Bool`, `WidgetSlider.value::Float64` and
`WidgetRadioGroup.selected::Int`. Each declared type becomes `Union{T, Document}`,
for example `checked::Union{Bool, Document}` (decision 11). A plain value keeps
the type check of the slot, and any document can go into the slot.

### The names

The step chooses the names by
[naming-rules.md](../../documentation/rule/naming-rules.md). The plan uses these
working names: `ObjectFieldToValue`, "the helper" for the function that asks a
child for the operation that stores a value, "the factory" for the function
that makes the table, the seam `make_object_field_widget` and its argument
`make_widget`, and, for part D, the trait `is_form_record` and its argument
`is_record`.

### The risks of C

- **The caret of a text slot that holds a field.** The caret of the plain-text
  path is `content[i:j]` in the selection of the widget. When `content` holds an
  `ObjectField`, that path must step into the value of the field. The step
  checks whether `ObjectField` can answer as a transparent wrapper
  (`get_wrapped_document`, [document.md](../../documentation/package/kernel/document.md)).
- **An output that is a cell.** The widget reads the value of the child inside
  its own reactive print. The step checks that a write to the field reprints the
  widget, and that a reprint of the child keeps the widget.
- **Eight printers change.** Each change is the same call of the helper. The
  tests of each widget must still pass with a plain value.

## Design of D: `ObjectToWidget` shows a plain nested value

### Now

- `_value_kind` gives `:opaque` for a struct that has no cell field, and the form
  does not show it. The rule keeps a style value, such as a `StyleColor` or an
  `Inset`, from opening into a card of numbers.
- A leaf edits only when its own slot is a cell. A text edit maps back only for a
  field of the root, because the reader finds the field from the row of the grid
  (`_parse_control_edit`). A vector element is read only.

### The design

`ObjectToWidget` makes the same form that an author makes by hand, and projects
it with the same stage:

1. A new first stage walks the object and makes a layout document. Each leaf
   becomes a `WidgetLabel` and a widget in a `GridLayout`. The widget comes from
   the function argument `make_widget` of `ObjectToWidget`, applied to
   `ObjectField(root, path)` (decision 16). Each nested value becomes a
   `WidgetCard`. The name of the stage must follow the naming rules, and the
   step chooses it.
2. The second stage is the recursion of a hand-laid form from part C: the
   nesting rows of the value widgets, and the row
   `ObjectField => ObjectFieldToWidget`.
3. `ObjectToWidget` stays the name of the chain, so its callers do not change.

Each `ObjectField` has its own IO map in the chain, and its own reader maps its
edit. So an edit at any depth goes through `ObjectField` and the write rules of
B: a nested text edit, a vector element and a plain nested value all edit. The
reader of `ObjectToWidget`, with its parse of the grid row, goes away.

`ObjectToWidget` takes the same function argument as `ObjectFieldToWidget`,
with the same seam as its default. The function sees the whole path, so a
nested field can get a chosen control too:

```julia
ObjectToWidget(; make_widget = field ->
    get_object_field_name(field) == "draw_style" ?
        WidgetSelect(field; options = Any[:linear, :step, :bar]) :
        make_object_field_widget(field))
```

With this, the chart inspector edits `draw_style`, `line_style` and `symbol`.

A trait and a function argument decide which nested value opens into a card
(decision 15):

```julia
is_form_record(value) = <the value has a cell field>      # the trait, today's rule
is_form_record(::Server) = true                           # the author opts a type in

ObjectToWidget(; is_record = is_form_record)              # the default
ObjectToWidget(; is_record = _ -> false)                  # a form with no depth
ObjectToWidget(; is_record = x -> x isa ThirdPartyType || is_form_record(x))
```

- **The trait gives the default for every form.** Its default method keeps
  today's rule: a `@document` value with a cell field opens, and a plain struct
  opens only when its type gets a method. So a `StyleColor` stays closed, and no
  form that exists now changes.
- **The argument lets one form decide differently.** It also covers a type that
  the author does not own: a method of the trait for such a type would be type
  piracy.
- **The trait takes a value**, and a method can name a type, as
  `is_form_record(::Server)` does.
- **"Record" keeps the meaning that the document layer gives it**: a document
  whose children are named fields
  ([DocumentSync.jl](../../source/kernel/document/DocumentSync.jl)).
- **The field holds a function, not a projection**, so it keeps the rule that
  only a higher-order projection of the algebra holds a projection field.
  `PAR-USE-PROJECTION-MACRO` allows a function field.
- The trait lives in the widget slice, beside `ObjectToWidget`. The first stage
  reads the function from the argument. `is_form_record` and `is_record` are
  working names, and the step checks them against the naming rules.

### The risks of D

- `ProjectionConfiguringProjection` sets `visible` on the `WidgetComposite` that
  `ObjectToWidget` makes, and `ObjectToWidgetTest.jl` checks that shape. The
  chain must keep the composite as its root. The plan
  [text-projection-config-into-document.md](../done/text-projection-config-into-document.md)
  retires `ProjectionConfiguringProjection`. If that plan lands first, this risk
  goes away.
- A card keeps its collapse state on the card. After the change, the first stage
  makes the card at print time. The step must check that a print again keeps
  the state.
- D replaces the body of `ObjectToWidget`. It is the largest part of this plan,
  and it stays in this plan (decision 14).

## Steps

Each step is one commit. Run the test of the step, not `test_all()`. The order
puts part C before the read of a cell root, so the tests of that read use the
form of part C and not readers that part C removes.

1. ✅ **The write rules of B, in the kernel.**
   [Operations.jl](../../source/kernel/operation/Operations.jl),
   [Inversion.jl](../../source/kernel/operation/Inversion.jl), and
   `with_object_field` in `OperationInterface.jl` with its default methods in
   `OperationDefaults.jl`. None of these files is sealed on 2026-10-06; check
   [SEALING.md](../../SEALING.md) again before each edit. Tests: a new
   `test/kernel/operation/OperationsTest.jl` for the five rules, and new
   testsets in `InversionTest.jl` for the inverse of rules 3 and 4.

   **Done 2026-10-08.** What the implementation found and decided:
   - The tests of the inverse are in `OperationsTest.jl` too: each case of the
     write takes its way back there, so `InversionTest.jl` did not change.
   - **A container that declares `is_element_collection` keeps its own rules.**
     Such a collection is no `Document`, but it keeps its elements in its own
     way, for example in a cell for each element. The first version treated it
     as a plain value and anchored its way back at the document above it; the
     test "an inverse carries the object it writes into" of `InversionTest.jl`
     failed. So a plain container is one that is no document and declares no
     `is_element_collection` (`_is_plain_container`).
   - **Rule 5 throws only for a field.** An element of a plain vector with no
     cell above it is written in place, as callers expect. Only a plain field,
     mutable or immutable, with no cell above it throws.
   - **The default `with_object_field` calls `T(fields...)`**, so the copy keeps
     the type of the value; a value of another type converts or throws there.
   - **One walk, `_find_cell_anchor`, finds the nearest cell above a slot.** The
     write uses its cell to tell the readers, and the inverse uses its holder and
     path. A computed cell is not written again, because a write would end its
     computation.
   - `test_operations()` 43 pass; `test_inversion()` 74, `test_rerooting()` 60
     and `test_description()` 27 pass; `test_kernel()` 4258 pass, 2 broken, 0
     fail, which is the baseline of 2 broken in memory.
2. ✅ **The two functions of A, in the platform primitive slice.** A new fragment
   beside `ObjectField.jl`. Check the file name against the naming rules before
   it is made. Tests: a flat value, a nested value, a vector, a schema that
   shows a part of a value, a schema field that the object does not have, and a
   round trip.

   **Done 2026-10-08.** What the implementation found and decided:
   - The fragment is `source/platform/primitive/ObjectConversion.jl`. The name
     carries no `Document`, because only a file that defines a document carries
     that word by the naming rules.
   - **The declared type of a schema field comes from the native layout.** The
     cells of a `@document` value are untyped (`Cell`), so a cell can not tell
     the declared type. `@document` emits the native layout `M<Name>` by
     default, and `get_document_native_type(T)` finds it; its field types are
     the declared types. A schema declared with `[C]` only has no native layout,
     so its values copy as they are and no nested value converts.
   - **The way back takes `base`:** `convert_document_to_object(T, document;
     base = nothing)`. Rule 2 lets a schema show a part of a value, so the way
     back needs the value that the document was made from, to fill the fields
     that the schema does not have. With no `base`, such a field is an error.
   - **A value that does not convert is deep-copied when it can change**, at
     both ends, so the document and the value share no object that an edit of
     one would change in the other.
   - **A vector converts element by element** in both directions, and a
     collection of elements, such as the `CellVector` that the macro makes from
     a `Vector` field in the platform, becomes a vector on the way back.
   - `test_object_conversion()` 24 pass. The naming guard and
     `test_platform_layering()` pass.
3. ✅ **C: a test of the hand-laid form of today, before any change of C.** Send a
   click on the checkbox and a key in a text field through the whole chain of
   `make_object_field_form_projection_example`, in an editor, not to the reader
   of one field. Record in this plan whether the form of today writes the field.
   The result is the baseline for step 4.

   **Done 2026-10-08.** The testset "a press and a key through the whole
   hand-laid form write the fields" of `ObjectFieldToWidgetTest.jl` runs an
   editor on a `HeadlessBackend`, finds each control by the text that the frame
   draws, and presses it. The baseline:
   - **A press on the text and a key write the field.** The press puts the caret
     into the control through the path that `ObjectFieldToWidget` introduces,
     and the key `X` writes `name = "Xgateway"`.
   - **A press on the checkbox does not write the field.** The operation is
     `set .content = false` on the control itself: it names the control, so
     `CopyingProjection` routes it by the selection only, and it reaches the
     reader of no `ObjectField`. It writes the `content` cell of the control,
     which also ends the computation that binds the control to the field. The
     assertion is `@test_broken` with a `# @broken:` comment, and part C must
     promote it.
4. ✅ **C: the widgets ask their value child.** `ObjectFieldToValue`, the helper
   that asks a child for the operation that stores a value, the factory that
   puts each value widget into a `NestingProjection`, the change at each edit
   site of the table in part C, the `operation` field of `WidgetOption`, the
   third case of `WidgetText` with its fallback (decision 13), and the four slot
   types of decision 11. Files: a new fragment in `source/platform/widget/` for
   `ObjectFieldToValue`, the helper and the factory,
   [WidgetToGraphics.jl](../../source/platform/widget/WidgetToGraphics.jl),
   [WidgetDocument.jl](../../source/platform/widget/WidgetDocument.jl) and
   [Nesting.jl](../../source/platform/projection/higherorder/Nesting.jl). The
   change of the reader of an empty nesting gets its own test in
   `test/platform/projection/HigherOrderTest.jl`. On 2026-10-08 only
   `GraphProjectionTest.jl` uses `NestingProjection` in a test. Tests, in
   a new test file and through an editor: each widget of the table with an
   `ObjectField` in its slot, an edit and an undo; a pick in the popup of a
   select; the caret of a text field after a key and after a click; a
   `TextBlock` content of a `WidgetText` that still draws as text; a child whose
   answer still names a place, which sends no edit. Run the tests of each
   changed widget with a plain value too.

   **Done 2026-10-08.** What the implementation found and decided:
   - **The IO map of a value widget.** The checkbox, the switch and the toggle
     answer a new `WidgetValueIoMap(projection, input, output, value_iomap)`. The
     slider, the spin box, the radio group, the select and the text keep their
     own IO maps, each with a new field `value_iomap`. A `ContentIoMap` was
     rejected: `get_child_iomaps` lists its inner IO map, and
     `find_first_baseline` looks into it, but the child of a value slot draws
     nothing. An IO map type that generic code does not know is not walked.
   - **The fragment `WidgetValueSlot.jl`** holds the IO map, the print of a slot
     (`_print_value_slot`), the read of its value (`_get_slot_value`), the
     helper `make_slot_store_operation`, and the factory
     `make_object_field_widget_dispatch`. `ObjectFieldToValue.jl` holds the
     projection. Both are in the widget slice.
   - **A slot is printed once, at print time.** A slot that holds a document
     when the widget prints gets a reconciled child; a plain value gets none, so
     a widget with plain values pays nothing.
   - **A loop to avoid.** A value widget prints its slot through the recursion
     that it gets. If that recursion makes a widget of an `ObjectField`, and the
     row of the widget is no nesting, the print makes the widget again without
     end. The header of `WidgetValueSlot.jl` says so; step 5 makes the factory
     give a table that can not loop.
   - **The slider and the toggle group already have `target` and `field`**, a
     write-only binding: a drag writes `(target, field, value)`, and the knob
     still draws the slider's own `value`. This plan keeps it. When the value
     slot of a slider holds a document, the child makes the write and `target`
     is not used. The toggle group is no value widget of this plan. Unifying the
     two mechanisms is outside this plan.
   - **The select** gives each `WidgetOption` its final `operation` when the
     popup opens. A value that the child does not take gets
     `DoNothingOperation()`, so that option does not fall back to a write on the
     select, which would end the binding.
   - **The text** decides at print time, with `run_untracked`, whether the child
     of a document content gives graphics or a value, so the print does not
     follow the value. Its caret goes through the child as a path that the child
     introduces, as for today's `ObjectFieldToWidget`. A store moves no caret, so
     an edit answers a `CompoundOperation` of the store and a
     `ReplaceSelectionOperation` after the inserted text.
   - **`_coerce`** rounds a `Float64` into an integer field, and converts a
     number into a `Float64` field. New methods for a number were ambiguous with
     the method for a `Bool`, so the two existing bodies changed.
   - **The constructors take the value positionally**: `WidgetCheckbox(field)`,
     `WidgetSpinBox(field; min, max)`, `WidgetSelect(field; options)`. The
     examples of this plan are corrected.
   - **The empty nesting** (decision 13): `NestingProjection()`; with no element
     and no stored recursion, its reader and its mappers go to the IO map that
     its print made, through that IO map's own projection.
   - `test_widget_value_slot()` 25 pass, `test_empty_nesting()` 4 pass,
     `test_object_field_to_widget()` keeps its baseline (1 broken), and
     `test_object_conversion()` 24 pass. `test_platform()`: 102505 pass, 2 fail,
     9 broken, in 22 minutes. The 2 failures are in `test_interface_api()`: the
     interface list holds 32 names where the test expects 31, and the docstring
     of `WidgetProgressRing` has no line "Use it to". The ring entered the list
     in `8353fc722` (2026-10-06), which is in the base of this branch, and this
     branch changes neither the list nor that docstring, so `main` fails the
     same way. One of the 9 broken is the baseline marker of step 3.

5. ✅ **C: `ObjectFieldToWidget` makes the default widget.** It makes the widget
   with the field in its slot and prints it through the recursion. Its readers
   for the checkbox and for the text go away. The seam `make_object_field_widget`
   and the argument `make_widget` take the place of its `controls` table. The
   form example becomes one stage. Files:
   [ObjectFieldToWidget.jl](../../source/platform/widget/ObjectFieldToWidget.jl),
   [ObjectFieldDocumentExample.jl](../../example/platform/ObjectFieldDocumentExample.jl)
   and [ObjectFieldProjectionExample.jl](../../example/platform/ObjectFieldProjectionExample.jl).
   Tests: `ObjectFieldToWidgetTest.jl` follows the new form, and repeats the test
   of step 3. A bare field inside another domain's document, such as a card,
   becomes a control. Run `test_object_field_to_widget()`,
   `test_object_field_to_syntax()` and `test_example(object_field_form_example)`.

   **Done 2026-10-08.** What the implementation found and decided:
   - **The table can not loop.** `make_object_field_widget_dispatch(dispatch;
     make_widget)` puts the row `ObjectField => ObjectFieldToWidget(;
     make_widget)` first, and nests the value widgets. A table with the one kind
     of row and not the other is what makes a bare field and a field in a slot
     make each other without end.
   - **A value that no control edits gives a `WidgetLabel` whose content is a
     computed cell** that shows the text of the value. `WidgetLabel(field)` would
     draw the text of the `ObjectField` itself, because the label draws
     `string(content)` and recurses nothing; making the label a value widget would
     change how it draws other documents, such as an image.
   - **The made widget follows the field.** Its `selection` and `mouse_target`
     are cells computed from the path that the field keeps, which the defaults of
     `Projection` make a path that `ObjectFieldToWidget` introduces. No path from
     the root reaches the made widget, so nothing else writes them.
   - **An operation is an answer, never a payload for the widget.** The first
     reader gave every payload to the widget and mapped the answer with the
     default reader of `Projection`. That default maps each member of a compound
     through this reader again, so the store and the caret move of a key went to
     the widget as new payloads and the whole answer was lost. The reader now
     maps an operation with the default, and gives only a gesture to the widget.
   - **The exported constructor changed:** `ObjectFieldToWidget(; make_widget)`.
     The keywords `theme`, `style` and `controls` and the call
     `print_document(p, field)` with no recursion are gone; nothing outside this
     repository's tests and examples used them. `ProjecturedPlatform` already
     takes the version 0.2.0 at its next release (the rename of
     `WidgetProgress`), and this change falls into that step.
   - The form example is one recursion. `test_object_field_to_widget()` 40 pass,
     with the baseline of step 3 now a plain `@test`;
     `test_widget_value_slot()` 25 and `test_object_field_to_syntax()` 13 pass;
     `walk_printer_output` and `walk_repl_loop` report no error on the form and
     on the syntax example; the naming guard and `test_platform_layering()` pass.
     `test_example` lives in the umbrella test package, which this worktree has
     not instantiated, so the walkers stand in for it.

6. ✅ **B in a form: the read of a cell root, in `ObjectField`.**
   [ObjectField.jl](../../source/platform/primitive/ObjectField.jl). Tests,
   through the form of part C in an editor: a nested plain struct in a `Cell`, a
   checkbox press, a text edit, an undo, a mutable struct changed in place, and
   the exception when no cell holds the value. Run
   `test_object_field_to_widget()`.

   **Done 2026-10-08.** What the implementation found and decided:
   - **The read needed no change.** The `@document` constructor of `ObjectField`
     uses a `Cell` given as `object` as the cell of that field, and two fields
     made from one `Cell` share it. So `field.object` already reads the plain
     value, in a computation, with the dependency on the cell.
   - **The write needed the change:** `get_object_field_root(field)` is the
     object when it is a document, which holds its own cells, and else the cell
     of the `object` field. `ObjectFieldToValue` writes from that root, so the
     rules of step 1 reach the plain value.
   - **A plain value given as it is gets a cell of its own in each field.** A
     mutable value then changes in place and the form repaints, because that
     cell is above it. An immutable value is replaced in the cell of that one
     field, so two fields of it would not see each other's edits; the docstring
     of `ObjectField` says to give one `Cell` to every field of a plain value.
     So no write through an `ObjectField` meets rule 5, which stays for a direct
     `ReplaceReferencedValueOperation` and is tested in step 1.
   - `test_object_field_to_widget()` 49 pass, with a nested immutable value in
     one shared `Cell`, two edits and two undos, and a mutable value changed in
     place; `test_widget_value_slot()` 25 and `test_object_field_to_syntax()` 13
     pass.

   **Changed 2026-10-08, by step 4 of
   [text-projection-config-into-document.md](../done/text-projection-config-into-document.md)
   (its decision 11).** The caret in the widget of a field is a path in the
   document, `object.<path of the field>{start:stop}`, and no longer a path that
   `ObjectFieldToWidget` and `ObjectFieldToValue` introduce: the two map it to the
   caret of the widget and back. A bare `ObjectField` is a focus stop. The
   documents of step 9 describe this caret.
7. ✅ **D: `ObjectToWidget` as a chain.** Waits for the retirement of
   `ProjectionConfiguringProjection` (decision 17). Files: [ObjectToWidget.jl](../../source/platform/widget/ObjectToWidget.jl)
   and a new file for the first stage. Tests: `ObjectToWidgetTest.jl` keeps its
   shape assertions, and gets a nested text edit, a vector element and a plain
   nested value. Run the chart inspector example with `test_example(...)`, and
   the test of `ProjectionConfiguringProjection` if it still exists.

   **Done 2026-10-08**, on the branch `text-config-in-documents`. What the
   implementation found and chose (choices of the implementation):
   - **`ObjectToWidget` is the first stage, and keeps its name.** It walks the
     object and makes the form as a document: a `WidgetComposite` around a
     2-column `GridLayout`, with a `WidgetLabel` and the widget that
     `make_widget` makes for `ObjectField(root, path)` for each leaf, a
     collapsible `WidgetCard` for each record, and a `VerticalLayout` of fields
     for each vector. The root of a plain value is one `Cell` for all its
     fields. No new name was needed.
   - **A chain that draws the form needs the field rows.** Design item 3 said
     that the callers do not change; they can not, because the renderer must
     hold `make_object_field_widget_dispatch`, as decision 17 found. The three
     example chains (the object form, the chart inspector, the sequence chart
     inspector) change one line each, and drop the keyword `style`, which the
     widgets of the fields take from the widget theme.
   - **The reader goes.** Each widget asks its field for the store, so the
     parse of the grid row and the redirect of a control edit are gone. The
     `controls` of the IO map hold `(widget, path, steps, slot)`.
   - **A caret in the form is a path in the object**, such as `window.title{3}`
     (decision 11 of the retirement plan). The maps put it under the widget,
     its slot and the step `object` of the field, and take them off; a part
     with no path in the object is a path that the projection introduces. The
     output takes its paths with `set_output_path_computations!` and
     `set_output_tree_path_computations!`.
   - **The object of an `ObjectField` is no child of the field**
     (`child_reference_steps(::ObjectField) = ()`). Without it, the walk that
     wires the paths of the output went from a field into the input document
     and replaced its selection cell. A selection still goes through `object`.
   - `is_form_record(value)` is the trait and `is_record` the argument, as
     decision 15 named them; `make_widget` defaults to
     `make_object_field_widget`.
   - A card keeps its collapse while a field is edited, because the form is made
     once for its input and a value is read through its field.
   - Tests: `test_object_to_widget()` 60 pass. New: a widget of each field holds
     a field of the object; a field of an object whose parameters are cells
     writes the cell; `make_widget` and `is_record`; keys through an editor edit
     a field, a nested field and an element of a vector, at the caret, and a
     press on a tick writes a flag; a card keeps its collapse; a plain value
     that a document holds opens with `is_record` and edits through a copy. The
     tests of the old reader are gone. `test_chart_projection()` 322 pass, with
     the property inspector on the field model. `test_object_field_to_widget()`,
     `test_find_bar_view_to_widget()`, `test_widget_card_fold()` and
     `test_widget_value_slot()` pass; `walk_printer_output` and
     `walk_repl_loop` report no error on `object_to_widget`,
     `nested_object_to_widget`, `chart_inspector` and
     `sequencechart_inspector`; the naming guard and the layering guard pass.
   - For step 9: `widget.md` still says, under "From a domain to widgets" and in
     its limits, that `ObjectToWidget` maps no reference.

8. ✅ **The examples.** One form for A and one for B, on the same plain value and
   the same layout, and a form whose widgets hold `ObjectField` values (C).
   Register them in
   [PlatformExamples.jl](../../example/platform/PlatformExamples.jl). Run
   `test_example(...)` for each.

   **Done 2026-10-08**, on the branch `text-config-in-documents`. In
   `ObjectFieldDocumentExample.jl`: a plain `PlainServer` with a plain
   `PlainServerWindow`, the schemas `PlainServerForm` and
   `PlainServerWindowForm`, and one layout, `_make_plain_server_form(root)`, of
   four fields with a nested title. `plain_server_copy_form` (A) lays it on
   `convert_object_to_document(PlainServerForm, server)`; `plain_server_cell_form`
   (B) lays it on `Cell(server)`; `object_field_widget_form` (C) is a form whose
   widgets the author chooses (`WidgetText`, `WidgetSpinBox`, `WidgetSwitch`),
   each with a field in its value slot. All three draw with
   `make_object_field_form_projection_example`. The comment of the old form
   example no longer says that `ObjectToWidget` shows a vector element as
   read-only.
   - `walk_printer_output` and `walk_repl_loop` report no error on the three.
   - `test_example(...)` (in `environment/all`): `plain_server_copy_form` 2088
     pass 122 fail, `plain_server_cell_form` 2075/122,
     `object_field_widget_form` 1669/104, `object_field_form` 2389/198. On
     main 24746844d, `object_field_form` gives 2531/181/7 broken. The failures
     follow the pattern of every widget example on main: the type-in walk
     types into the labels, and a `WidgetLabel` draws no caret, also in a form
     with no field; the seed key Ctrl+Home selects nothing; and a key in the
     text box of a field answers the store and the caret move
     (`CompoundOperation`, decision 9) where the walk expects a
     `ReplaceStringRangeOperation`. On main the same keys answered nothing, and
     the labels failed one check later, because the example copied the form in
     a first stage.
9. ✅ **The documents.**
   [primitive.md](../../documentation/package/platform/primitive/primitive.md)
   gets the two ways and the table.
   [operation.md](../../documentation/package/kernel/operation.md) gets the write
   rules and the inverse.
   [widget.md](../../documentation/package/platform/widget/widget.md) gets the
   rule for a value slot that holds a document, the nesting rows, the helper,
   the popup of the select, the new form of `ObjectFieldToWidget`, and the new
   form of `ObjectToWidget` if D lands.

   **Done 2026-10-08.** `primitive.md` has the section "Two ways a form edits a
   plain value", with A, B, the table and the caret of a field.
   `operation.md` has the write rules of a plain value and the anchor of the
   inverse. `widget.md` has the section "The value slot of a widget", and its
   items of `ObjectToWidget` and `ObjectFieldToWidget` describe the form as a
   document and the caret of a field; its limit that `ObjectToWidget` maps no
   reference is gone, and the limit of a range step that splices a vector stays,
   because `_write_slot!` still splices. `test_documentation()` passes; its
   report names no sentence of these sections. A link of `text.md` follows the
   retirement plan to `plan/done/`.

10. ✅ Move this plan to `plan/done/`.

## Decisions

The owner answered these on 2026-10-06:

1. **A mutable struct in B changes in place.** It does not become a copy. The
   write then writes the nearest cell again, so the form updates.
2. **A lives in the platform primitive slice**, not in the kernel document layer.
3. **A field of the schema that the object does not have is an error.**
4. **B on a copy gets no helper.** The author writes `Cell(deepcopy(x))` and
   `x = draft[]`.
5. **The two gaps get a design**: part C and part D.
6. **B keeps the refusal of a write to a `Dict` key.**

The owner decided these on 2026-10-07:

7. **The author puts an `ObjectField` in a widget slot**, and does not name a
   control on the `ObjectField`. The widget is the choice of control, and its
   settings are fields of the widget.
8. **The projection handles an `ObjectField` in a slot.** The printer context
   gets no field that says what a slot wants.

The owner decided these on 2026-10-08:

9. **The widget asks the field for the operation that stores a value.** A widget
   prints a slot that holds a document as its child, reads the value from the
   child, and asks the reader of the child for the operation that stores each
   value that it offers or that the user enters. The field knows nothing about
   how the widget offers values. The widget printers change at each edit site.
10. **The select asks for the operation of each option when its popup opens**
    (question C2). `WidgetOption` holds that operation, so a pick needs no route
    from the popup back to the select.
11. **The four typed slots become `Union{T, Document}`** (question C3). The
    widget prints any document in a slot through the recursion, and does not know
    that the child is an `ObjectField`.
12. **A value widget gets a `NestingProjection` row**, with `ObjectFieldToValue`
    as its inner element. The shared recursion keeps
    `ObjectField => ObjectFieldToWidget` for a bare field (question C4), so
    nothing exported is removed. The architectural rule behind it: only a
    higher-order projection of the projection algebra holds a projection field.
13. **The fallback row of the nesting of `WidgetText` is an empty
    `NestingProjection`** (question C5). It gets a public constructor with no
    element, and its reader passes the payload to the IO map that its print
    made. The owner chose it over a new projection of the algebra.
14. **Part D stays in this plan, as step 7** (question D3). It is not a plan of
    its own.
15. **A trait and a function argument decide which nested value opens into a
    card** (question D1). The trait `is_form_record(value)` gives the default for
    every form and keeps today's rule. The argument `is_record` of
    `ObjectToWidget` lets one form decide differently. The owner chose this over
    a keyword with a list of types, a trait alone, and opening every plain
    struct.
16. **A seam and a function argument choose the widget for a field** (question
    D2). The seam `make_object_field_widget(field)` dispatches on the type of
    the value. The argument `make_widget` of `ObjectFieldToWidget` and of
    `ObjectToWidget` lets one form choose differently, by the path, the value or
    the object. The owner chose this over a table whose keys are a type, a field
    name or a path.

The owner decided this on 2026-10-08, before step 7:

17. **`ProjectionConfiguringProjection` is retired before part D**, by
    [text-projection-config-into-document.md](../done/text-projection-config-into-document.md),
    which builds on part C. Before step 7 it showed that part D would have to
    change that projection: every chain that draws the output of
    `ObjectToWidget` needs the table of `make_object_field_widget_dispatch`; its
    reader hands a control edit to the control, which now lets it pass, and then
    gives the whole answer, with a caret move under the control slot, to the
    inner projection, which drops it; and its root, a projection object, has no
    `selection` for a caret. Rejected: change that projection in part D, work
    that its retirement removes again; keep the old behaviour of
    `ObjectToWidget` for it alone, two ways to do one thing.

The designs that decisions 7 to 13 replace:

- **A control description on `ObjectField`**, such as
  `ObjectField(series, "draw_style"; control = ChoiceControl([...]))`, with two
  open functions for each description. The widget already says which control it
  is.
- **Each value widget reads an `ObjectField` in its slot itself.** Each widget
  would name `ObjectField`. In decision 9 the widget asks its child, and it does
  not know what the child is.
- **A value projection for the state slots**, given to the widget projections as
  a parameter, or one recursion in which the child context says whether a slot
  wants graphics or a value. The owner: this is not a matter of the context; the
  projection handles it.
- **A chain for each widget row: a field stage, then the widget printer that
  exists now** (decision 9 of 2026-10-07). The widget printers would not change.
  But the field stage converts an edit only after the widget sends it, so a
  widget can not ask it for operations in advance, such as the options of a
  popup.
- **An operation that exposes the operations it carries**, such as the open of a
  popup, so that the chain converts each of them. It needs a new protocol in the
  operation layer of the kernel.
- **A value projection as a parameter of the widget projection.** It breaks the
  rule that only a higher-order projection of the algebra holds a projection
  field.
- **One recursion, with a marker document** that means "the value of this
  slot". It makes a new document for each slot at each print.
- **A builder function in place of `ObjectFieldToWidget`.** A markdown document
  whose reader makes `ObjectField` nodes runs no builder, so a bare field needs a
  projection that makes its control.

## Open questions

None on 2026-10-08. The step that meets a new question records it here.
