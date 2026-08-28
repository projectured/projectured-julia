"""
    ObjectFieldModule

`ObjectField` — a document that names **one field of one object**.

The document holds a root object and a [`Reference`](@ref) from that root to a
value. It is the reification of the binding `ObjectToWidget` keeps privately in
its `controls` vector: a control, and the path that control writes.

Two projections present it. `ObjectFieldToWidget` emits the bare control, so a
person lays out `WidgetLabel`s and `ObjectField`s in a grid and gets a form. The
fields can come from different objects, which `ObjectToWidget` can not do — it
takes one root and emits a fixed grid of its own fields. `ObjectFieldToSyntax`
emits the field-name leaf and the projected value.

# Why a `Reference` and not a name

1. An element is not a field. A row of a vector needs `ElementReferenceStep`; a
   name can not say `items[3]`.
2. A path from a stable root re-derives on every read. If the document held the
   intermediate object, a write to `node.config` would leave the form pointed at
   a dead object.
3. `FocusingProjection` already maps a prefixed path both ways, and a one-step
   path runs the same code as an n-step path.

The kernel made the same choice one layer down: `ReplaceReferencedValueOperation`
stores a `Reference` and adds an `AbstractString` shorthand. This module adds the
same shorthand.
"""
module ObjectFieldModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference, ConcreteReference, EmptyReference,
                          FieldReferenceStep, evaluate_reference,
                          get_reference_steps, strip_reference_types

export ObjectField, object_field_value, object_field_name

"""
    ObjectField(object, path::Reference)
    ObjectField(object, field::AbstractString)

One field of one object. `object` is the root and stays fixed; `path` addresses
the value from that root.

The value is [`object_field_value`](@ref), and the write is
`ReplaceReferencedValueOperation(object, path, value)`.

There is deliberately **no label field**. The widget projection emits a bare
control and needs none. The syntax projection derives the name from the last
`FieldReferenceStep` of the path.

    ObjectField(server, "name")
    ObjectField(net, Reference(FieldReferenceStep("hosts"),
                               ElementReferenceStep(2),
                               FieldReferenceStep("address")))
"""
@document struct ObjectField
    object::Any
    path::Reference
end

# A field name is sugar for a one-step path. The type on the second argument is
# what separates this from the generated constructor, so neither shadows the
# other: a `Reference` takes the generated one, a name takes this one.
ObjectField(object, field::AbstractString) =
    ObjectField(object, ConcreteReference(FieldReferenceStep(String(field)), EmptyReference()))

"""
    object_field_value(field::ObjectField)

The value `field` names. Read it inside a cell — a printer that reads it outside
one freezes at the value of the first render.
"""
object_field_value(field::ObjectField) = evaluate_reference(field.object, field.path)

"""
    object_field_name(field::ObjectField) -> String | Nothing

The name of the last step of the path, for a projection that wants to label the
value. `nothing` when the last step is not a field step, because an element step
has no name a reader would want. Type checkpoints are stripped first, so the
answer does not depend on whether the path carries them.
"""
function object_field_name(field::ObjectField)
    steps = get_reference_steps(strip_reference_types(field.path))
    isempty(steps) && return nothing
    last_step = steps[end]
    last_step isa FieldReferenceStep ? last_step.name : nothing
end

end # module
