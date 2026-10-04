# Fragment of `SyntaxModule`.
#
# Projects an [`ObjectField`](@ref) — one field of one object — to the field node
# `ObjectNodeToSyntaxNode` builds inline for each field of a struct:
#
#     SyntaxNode([
#       SyntaxLeaf(field_name),
#       <the projected value>,
#     ]; sep = " ")
#
# The name comes from the last `FieldReferenceStep` of the field's path. When the
# last step names no field — an element step, for example — the value is emitted
# alone, because an index makes a poor label and the caller can put one beside it.
#
# This projection adds no render concept. It **names** one that
# `ObjectNodeToSyntaxNode` keeps private, and makes it addressable on its own, so a
# single field of an object can be shown next to a field of another object.
#
# # Why it does not replace the private one
#
# `ObjectNodeToSyntaxNode` projects each field's **`Cell`**, through `CellToSyntax`,
# not the field's value. That is what makes a field repaint when its cell is
# written. An `ObjectField` names a value reached by `evaluate_reference`, which has
# no cell to hand on. The two are reactive by different means, so the private
# version stays.
"""
    ObjectFieldToSyntax(; field_name = <green>, newlines = false)

`field_name` styles the name leaf. `newlines` puts the value on its own indented
line; the default keeps the name and the value on one line, which is what a field
of a form wants.
"""
@projection UntrackedCell struct ObjectFieldToSyntax
    field_name::StyleText
    newlines::Bool
end

ObjectFieldToSyntax(; theme = nothing,
                    field_name = get_syntax_style(theme, :field_name_text),
                    newlines::Bool = false) = ObjectFieldToSyntax(field_name, newlines)

function print_document(p::ObjectFieldToSyntax, recursion, field::ObjectField, ctx)
    name = get_object_field_name(field)
    # The value's path from THIS document is `object` followed by the field's own
    # path, so a child reference stays valid against the ObjectField.
    child_ctx = ctx === nothing ? ctx :
        make_child_context(ctx, FieldReferenceStep("object"),
                           get_reference_steps(strip_reference_types(field.path))...)
    # `make_reconciled_child_iomap_cell` reads the value inside the reconcile, so a write
    # to the object repaints the value and the child io map keeps its identity when
    # the value is merely edited (PAR-STABLE-IOMAP-IDENTITY).
    inner = make_reconciled_child_iomap_cell(() -> get_object_field_value(field),
                                  v -> print_child(recursion, v, child_ctx))
    ind = p.newlines ? 1 : 0
    output = Cell(@computation begin
        value_node = inner[].output
        name === nothing ? value_node :
            SyntaxNode(SyntaxDocument[SyntaxLeaf(TextString(name, p.field_name)), value_node];
                       sep = TextString(" ", p.field_name.font), indentation = ind)
    end)
    SimpleIoMap(p, field, output)
end
