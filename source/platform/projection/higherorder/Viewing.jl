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
    make_content_view(content) -> ContentView or nothing

The view of `content`: the view that a parent view makes for a child content, and
the view of the next domain that a step of `ViewingProjection` gives over the
content that it printed. Each content type that has a view declares a method; any
other content answers `nothing`, and prints as content.
"""
function make_content_view end
make_content_view(content) = nothing

"""
    make_child_views(content, field::Symbol) -> CellVector

The views of the children in the collection `field` of `content`, in their order:
what the field of the same name of a view of `content` holds. A child keeps its
view while it stays in the collection, at any place, so the caret and the fold of
its view stay with it; a child that goes takes its view with it. A child that has
no view (`make_content_view` answers `nothing`) has `nothing` at its place.
"""
function make_child_views(content, field::Symbol)
    views = IdDict{Any,Any}()
    CellVector(Computation(function ()
        children = collect(getproperty(content, field))
        present = IdDict{Any,Nothing}(child => nothing for child in children)
        for child in collect(keys(views))
            haskey(present, child) || delete!(views, child)
        end
        Any[get!(() -> make_content_view(child), views, child) for child in children]
    end))
end

"""
    get_content_path(view::ContentView, path) -> Reference

A path of `view` as a path of its content: the same steps, typed with the nodes
of the content, which the maps and the key tables of the content match.
"""
get_content_path(view::ContentView, path) =
    annotate_reference_types(getproperty(view, :content), strip_reference_types(path))

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
    content = print_document(p.content, ViewRecursion(input, recursion, ctx),
                             getproperty(input, :content), ctx)
    output = make_content_view(content.output)
    output === nothing && throw(ArgumentError(
        "ViewingProjection: the print of the content of a $(nameof(typeof(input))) gives a " *
        "$(nameof(typeof(content.output))), which has no view (make_content_view)"))
    set_output_path_computations!(output, input,
                                  path -> map_reference_forward(p.content, content, get_content_path(input, path)))
    ViewingIoMap(p, input, output, content)
end

"""
    ViewRecursion(view, recursion, context)

The recursion that a viewing step gives the content projection of `view`. The
content projection prints each child through it, with the context of the child,
whose path is the path of the view and the step of the child, such as
`.children[2]`. The same step of the view gives the view of the child, because a
view answers the paths of its content. The child view prints through `recursion`,
and the content projection gets the IO map of the content of the child, so it
builds its output as it does with no view. A child that the view has no view for
prints as content.
"""
struct ViewRecursion <: Projection
    view::ContentView
    recursion::Any
    context::Any
end

function print_document(r::ViewRecursion, recursion, input, ctx)
    child_view = _find_child_view(r, input, ctx)
    child_view === nothing && return print_child(r.recursion, input, ctx)
    iomap = print_child(r.recursion, child_view, ctx)
    iomap isa ViewingIoMap ? iomap.content : iomap
end

# The view of the child `input` of the view of `r`: the steps that the context of the
# child adds to the path of the view, applied to the view. `nothing` when they reach
# no view of `input`.
function _find_child_view(r::ViewRecursion, input, ctx)
    (r.context === nothing || ctx === nothing) && return nothing
    parent = get_reference_steps(strip_reference_types(r.context.reference[]))
    child = get_reference_steps(strip_reference_types(ctx.reference[]))
    (length(child) > length(parent) && child[1:length(parent)] == parent) || return nothing
    view = try_evaluate_reference(r.view, Reference(child[length(parent)+1:end]...), nothing)
    (view isa ContentView && getproperty(view, :content) === input) ? view : nothing
end

map_reference_forward(p::ViewingProjection, iomap::ViewingIoMap, reference) =
    map_reference_forward(p.content, iomap.content, get_content_path(iomap.input, reference))
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
