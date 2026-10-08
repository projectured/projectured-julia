# ── One field of one object ───────────────────────────────────────────────────
#
# A root object and a `Reference` to a value inside it. The pair is a document in
# its own right, so a projection can render a single field of a document that is
# not itself one.
"""
    ObjectField(object, path::Reference)
    ObjectField(object, field::AbstractString)

One field of one object. `object` is the root and stays fixed; `path` addresses
the value from that root.

The value is [`get_object_field_value`](@ref), and the write is
`ReplaceReferencedValueOperation(get_object_field_root(field), path, value)`.

`object` can be a document, which holds its own cells, or a plain value, which
holds none. The field keeps its object in a cell, and a `Cell` given as `object`
is that cell: give the same `Cell` to every field of one plain value, so that
they share it, and an edit through one field shows in the others. A plain value
given as it is gets a cell of its own in each field. A write reaches the plain
value from that cell: an immutable value is replaced by a copy with the field
changed, and a mutable one changes in place.

There is deliberately **no label field**. The widget projection emits a bare
control and needs none. The syntax projection derives the name from the last
`FieldReferenceStep` of the path.

    ObjectField(server, "name")
    ObjectField(net, Reference(FieldReferenceStep("hosts"),
                               ElementReferenceStep(2),
                               FieldReferenceStep("address")))
    root = Cell(plain_server); ObjectField(root, "name"); ObjectField(root, "capacity")
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
    get_object_field_value(field::ObjectField)

The value `field` names. Read it inside a cell — a printer that reads it outside
one freezes at the value of the first render.
"""
get_object_field_value(field::ObjectField) = evaluate_reference(field.object, field.path)

"""
    get_object_field_root(field::ObjectField)

The root that a write on `field` carries: the object when it is a document,
which holds its own cells, and else the cell that holds the object. From that
cell a write reaches a plain value (`ReplaceReferencedValueOperation`).
"""
function get_object_field_root(field::ObjectField)
    object = field.object
    object isa Document ? object : getfield(field, :object)
end

"""
    get_object_field_name(field::ObjectField) -> String | Nothing

The name of the last step of the path, for a projection that wants to label the
value. `nothing` when the last step is not a field step, because an element step
has no name a reader would want. Type checkpoints are stripped first, so the
answer does not depend on whether the path carries them.
"""
function get_object_field_name(field::ObjectField)
    steps = get_reference_steps(strip_reference_types(field.path))
    isempty(steps) && return nothing
    last_step = steps[end]
    last_step isa FieldReferenceStep ? last_step.name : nothing
end

