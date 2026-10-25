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

# The gestures that open a page, each with the place where the page opens: a
# click and Return here, and Ctrl and a click and a middle click in a new tab.
# `open(part, place)` makes the open of the part that answers the gesture.
function _make_open_page_bindings(open; domain::AbstractString)
    at(place) = (part, _) -> open(part, place)
    GestureBinding[GestureBinding(MouseClickPattern(:left; modifiers = Symbol[]), at(:here);
                                  description = "Open as a page", domain),
                   GestureBinding(MouseClickPattern(:left; modifiers = [:ctrl]), at(:new_tab);
                                  description = "Open in a new tab", domain),
                   GestureBinding(MouseClickPattern(:middle; modifiers = Symbol[]), at(:new_tab);
                                  description = "Open in a new tab", domain),
                   GestureBinding(KeyPressPattern('\n'; modifiers = Symbol[]), at(:here);
                                  description = "Open as a page", domain)]
end

"""
    make_open_page_gestures(document, reference; domain) -> Vector{GestureBinding}

The gestures of a button that opens the part at `reference` from `document`: a
click or Return opens its page here, and Ctrl and a click or a middle click open
it in a new tab, each with an [`OpenPageOperation`](@ref). With `document ===
nothing`, `reference` is a path from the part that answers, so
`EmptyReference()` opens the part itself. `domain` names the slice of the button
in a listing of the bindings.

Use it for a button whose label is a command that opens a page, such as "Open
stdout". A text that names what it opens is a [`WidgetLink`](@ref), which has
these gestures of its own.

# Example

    WidgetButton("Open stdout"; gestures = make_open_page_gestures(task, reference; domain = "task"))
"""
make_open_page_gestures(document, reference::Reference; domain::AbstractString) =
    _make_open_page_bindings((_, place) -> OpenPageOperation(document, reference, place); domain)

"""
    make_target_open_operation(target, place) -> Operation

The open that a link makes of `target`, at `place`, `:here` or `:new_tab`: any
object opens as its page, a `DocumentLocator` as the page of the part at its
reference, and a `Reference` as the part at that path from the link. A locator
with an empty reference opens as the object that it names would, so a kind of
target that opens in its own way does so also behind a locator.

Use it to add a kind of target to a link: a method for the type of the target,
such as an address outside the editor.

# Example

    make_target_open_operation(DocumentLocator(folder, reference), :new_tab)
"""
function make_target_open_operation end

make_target_open_operation(target, place::Symbol) = OpenPageOperation(target, EmptyReference(), place)
make_target_open_operation(target::DocumentLocator, place::Symbol) =
    target.reference isa EmptyReference ? make_target_open_operation(target.start, place) :
                                          OpenPageOperation(target.start, target.reference, place)
make_target_open_operation(target::Reference, place::Symbol) = OpenPageOperation(nothing, target, place)

# The open of a link: the open of its target.
_make_link_open(link::WidgetLink, place::Symbol) = make_target_open_operation(link.target, place)

const _WIDGET_LINK_BINDINGS = _make_open_page_bindings(_make_link_open; domain = "widget")

get_document_gesture_bindings_own(::Type{WidgetLink}) = _WIDGET_LINK_BINDINGS
