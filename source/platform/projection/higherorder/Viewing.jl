# Fragment of `ProjectionAlgebraModule`.
#
# A view over its content, and the projection that prints a view and its content in
# one step. A content says what a thing is; a view keeps the state of one view of
# it: the tail of the caret, the fold and the part under the pointer. A view is a
# shadow of its content: it answers the paths of its content, so a path of a view is
# the path of its content, and a step of the viewing projection maps its paths with
# the maps of the content projection.

"""
    ContentView

The supertype of every view of a content. A view holds its content in the field
`content` and declares the child fields of its content, which hold the views of
the children. What every view does is written here once:

- a field step that the view does not have reads that field of its content, so a
  path into the content, such as `.value{3}`, is a path of the view, and the
  selection walk stops at the view;
- an edit of a field that the view does not have edits its content
  (`get_edited_field` names `content`);
- the view keeps its caret while the focus is elsewhere, as a dormant selection.
"""
abstract type ContentView <: Document end

DocumentModule.get_edited_field(::ContentView) = :content

SelectionModule.has_dormant_selection(::ContentView) = true

function ReferenceModule.evaluate_reference_step(step::AFieldReferenceStep, view::ContentView)
    hasfield(typeof(view), Symbol(step.name)) ||
        return evaluate_reference_step(step, getproperty(view, :content))
    invoke(evaluate_reference_step, Tuple{AFieldReferenceStep, Any}, step, view)
end

"""
    make_content_view(content) -> ContentView

The view of `content` that a step of `ViewingProjection` gives as its output: the
view of the next domain, over the content that the step printed. The step computes
its paths from the view that it printed, so it keeps no state of its own. Each
content type that a viewing step prints to declares a method.
"""
function make_content_view end

"""
    ViewingProjection(content)

A step that prints a view and its content together. `content` is the projection
of the contents of the stage, usually the table of its rows. For a `ContentView`,
the step prints the content of the view with `content`, and gives the view of the
printed content (`make_content_view`), whose paths are the paths of the view
mapped through the maps of that print. For any other input, it prints the input
with `content`, as a stage with no views does.

A key goes to the key table of the view. An operation from the next stage goes
back through the readers of the content print, because a path of the view is the
path of its content.
"""
struct ViewingProjection <: Projection
    content::Any
end

"""
    ViewingIoMap

IoMap for `ViewingProjection` of a view: `content` is the IO map of the print of
the content of the view.
"""
@iomap struct ViewingIoMap
    projection::Any
    input::ContentView
    output::Any
    content::Any
end

function print_document(p::ViewingProjection, recursion, input, ctx)
    input isa ContentView || return print_document(p.content, recursion, input, ctx)
    content = print_document(p.content, recursion, getproperty(input, :content), ctx)
    output = make_content_view(content.output)
    set_output_path_computations!(output, input,
                                  path -> map_reference_forward(p.content, content, _get_content_path(input, path)))
    ViewingIoMap(p, input, output, content)
end

# A path of a view as a path of its content: the same steps, with the types of the
# nodes of the content, which the maps of a content projection match.
_get_content_path(view::ContentView, path) =
    annotate_reference_types(getproperty(view, :content), strip_reference_types(path))

map_reference_forward(p::ViewingProjection, iomap::ViewingIoMap, reference) =
    map_reference_forward(p.content, iomap.content, _get_content_path(iomap.input, reference))
map_reference_forward(p::ViewingProjection, iomap, reference) =
    map_reference_forward(p.content, iomap, reference)

map_reference_backward(p::ViewingProjection, iomap::ViewingIoMap, reference) =
    map_reference_backward(p.content, iomap.content, reference)
map_reference_backward(p::ViewingProjection, iomap, reference) =
    map_reference_backward(p.content, iomap, reference)

# A gesture that no later stage took goes to the key table of the view. An
# operation goes back through the readers of the content print.
function read_intent(p::ViewingProjection, recursion, change::Intent, iomap::ViewingIoMap)
    if change.operation === nothing && change.route === nothing
        return Intent(change.gesture, read_gesture(iomap.input, change.gesture),
                      change.description, change.domain)
    end
    read_intent(p.content, recursion, change, iomap.content)
end

read_intent(p::ViewingProjection, recursion, change::Intent, iomap) =
    read_intent(p.content, recursion, change, iomap)

read_intent(p::ViewingProjection, iomap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation
