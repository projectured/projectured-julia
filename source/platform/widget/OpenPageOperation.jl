# Fragment of `WidgetModule` — the request of a link: open this part as a page.
# A part answers it, and the nearest document around the part that shows one page
# at a time takes it.

"""
    OpenPageOperation(document, reference[, place]; target = nothing)

The request of a link: show a part as a page. A part that a person presses
answers it, and the nearest document around the part that shows one page at a
time takes it.

- With `document === nothing`, `reference` is a path from the part that
  answers. Every reader on the way up maps it, as any path, so this form opens
  the part itself or a part under it: a row of a table, a node of a tree, a
  field of a form.
- With a `document`, the operation carries its own root, and `reference` is a
  path from it. It goes up unchanged, so this form opens any object: a node of
  another document, or an object of the program.
- With a `target`, the path form names the link, and `target` is the text of
  what the link names, as its domain writes it: `#install`, `guide.md`, the name
  of an rst target. The domain of the content that the page is a part of
  resolves it, and the open shows what the target names.
- `place` is `:here`, the default: the nearest document that shows pages shows
  the page. With `:new_tab`, a new tab shows it on its own, as Ctrl+click on a
  link does in a browser.

An open that no document around the part takes goes up to the editor, which
evaluates it.

# Example

    OpenPageOperation(nothing, EmptyReference())                 # the part itself
    OpenPageOperation(customers, @reference(customers, rows[7]), :new_tab)
    OpenPageOperation(nothing, EmptyReference(); target = "#install")
"""
struct OpenPageOperation <: Operation
    document::Any
    reference::Reference
    place::Symbol
    target::Union{Nothing,String}
end

# @optional: where the page opens follows what it opens, as a command names it, and
# most pages open here.
OpenPageOperation(document, reference::Reference, place::Symbol = :here;
                  target::Union{Nothing,AbstractString} = nothing) =
    OpenPageOperation(document, reference, place, target === nothing ? nothing : String(target))

operation_reference(operation::OpenPageOperation) =
    operation.document === nothing ? operation.reference : nothing
retarget_operation(operation::OpenPageOperation, reference::Reference) =
    OpenPageOperation(nothing, reference, operation.place, operation.target)
is_self_contained_operation(operation::OpenPageOperation) =
    operation.document !== nothing

function describe_operation(operation::OpenPageOperation)
    target = operation.target
    target === nothing && return operation.place === :new_tab ? "Open in a new tab" : "Open as a page"
    operation.place === :new_tab ? "Open $(target) in a new tab" : "Follow the link to $(target)"
end
