# Fragment of `ProjectionAlgebraModule`.
#
# A view over its content, and the projection that prints a view and its content in
# one step. A content says what a thing is; a view keeps the state of one view of
# it: the tail of the caret, the fold and the part under the pointer. A view is a
# shadow of its content: it answers the paths of its content, so a path of a view is
# the path of its content, and a step of the viewing projection maps its paths with
# the maps of the content projection.

"""
    View

The supertype of every view: a document that keeps the state of one showing. A
[`ContentView`](@ref) shows one content, which it names in the field `viewed`. A
widget, a layout, a graphics document and a pane keep the state of their own
showing in fields of their own, and their families are below `View` too.
"""
abstract type View <: Document end

"""
    ContentView

The supertype of every view of a content. A view holds its content in the field
`viewed`. It has a child field for each list of its content, which holds the view
of that list ([`CellVectorView`](@ref)), and a child field for each field of its
content that takes any document, which holds the view of that document. What
every view does is written here once:

- a field step that the view does not have reads that field of its content, so a
  path into the content, such as `.value{3}`, is a path of the view, and the
  selection walk stops at the view;
- an edit of a field that the view does not have edits its content
  (`get_edited_field` names `viewed`), and a write of a child of its content goes
  to the content below `viewed` (`make_content_edit`);
- the view keeps its caret while the focus is elsewhere, as a dormant selection;
- a copy of the view is a new view of the copy of its content, and a paste of the
  view puts a second view of the same content (`make_sibling_view`), each with the
  folds of the view.
"""
abstract type ContentView <: View end

DocumentModule.get_edited_field(::ContentView) = :viewed

SelectionModule.has_dormant_selection(::ContentView) = true

function ReferenceModule.evaluate_reference_step(step::AFieldReferenceStep, view::ContentView)
    hasfield(typeof(view), Symbol(step.name)) ||
        return evaluate_reference_step(step, getproperty(view, :viewed))
    invoke(evaluate_reference_step, Tuple{AFieldReferenceStep, Any}, step, view)
end

ReferenceModule.has_reference_step_child(step::AFieldReferenceStep, view::ContentView) =
    hasfield(typeof(view), Symbol(step.name)) ||
    has_reference_step_child(step, getproperty(view, :viewed))

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
    make_content_view(content, children) -> ContentView or nothing

The view of `content` that a viewing step gives over a content with children:
`children` holds the views of the next domain that the steps of the children gave.
A content type whose view holds the views of its children declares a method, which
puts each view at the index of its content; any other content takes no children.
"""
make_content_view(content, children) = make_content_view(content)

"""
    make_content_edit(view::ContentView, operation) -> Operation or nothing

`operation`, whose paths are paths of the tree of views from `view`, as an edit of
the content that the views show. A write of a value goes to the same place of the
content: the steps to the deepest view above the written place, the step `viewed`,
and the steps that remain. The view of a list is a view, so a write of element 2
of `.elements` is a write of `.elements.viewed[2]`. The value that a write puts in
keeps no caret of its own. Each caret stays a path of the tree of views, which the
view of the new part takes. A write of a field of state of a view, such as a fold,
stays a write of the view.

`nothing` when a write has no view above its place: the content of `view` itself
has its place in what holds that content, above `view`.

The step of a view applies it to each operation that it answers. So a row of the
key table of a view answers with a path from its view, as a row of a content
answers with a path from its document.

# Example

    replace = make_replace_document_operation(@reference(array_view, elements[2]), JsonNull())
    edit = make_content_edit(array_view, replace)
    # the write of `edit` is at `.elements.viewed[2]`, and its caret is at `.elements[2]`
"""
function make_content_edit end
make_content_edit(view::ContentView, operation) = operation

function make_content_edit(view::ContentView, operation::CompoundOperation)
    members = Any[]
    for member in operation.operations
        edit = make_content_edit(view, member)
        edit === nothing && return nothing
        push!(members, edit)
    end
    CompoundOperation(members)
end

function make_content_edit(view::ContentView, operation::WrappingOperation)
    edit = make_content_edit(view, get_wrapped_operation(operation))
    edit === nothing ? nothing : rewrap_operation(operation, edit)
end

# Each row of a list of rows, as a palette collects them. A row whose write has no
# place can not act, so the list leaves it out.
function make_content_edit(view::ContentView, operation::CollectedIntentsOperation)
    intents = Intent[]
    for intent in operation.intents
        edit = make_content_edit(view, intent.operation)
        (edit === nothing && intent.operation !== nothing) && continue
        push!(intents, Intent(intent.gesture, edit, intent.description, intent.domain, intent.route))
    end
    CollectedIntentsOperation(intents)
end

function make_content_edit(view::ContentView, operation::ReplaceReferencedValueOperation)
    operation.document === nothing || return operation
    steps = get_reference_steps(strip_reference_types(operation.reference))
    isempty(steps) && return nothing
    holder, count = _find_deepest_view(view, steps)
    step = steps[count + 1]
    # The path names a place of a content already, or a field of state of a view.
    step == _VIEWED_STEP && return operation
    (count == length(steps) - 1 && step isa AFieldReferenceStep && _is_view_state(holder, Symbol(step.name))) &&
        return operation
    foreach(_clear_written_selection!, operation.value isa AbstractVector ? operation.value : (operation.value,))
    place = Reference(steps[1:count]..., _VIEWED_STEP, steps[(count + 1):end]...)
    ReplaceReferencedValueOperation(nothing, place, operation.value)
end

# The step from a view to its content.
const _VIEWED_STEP = FieldReferenceStep("viewed")

# The deepest view above the place that `steps` name from `view`, and the count of
# the steps that lead to it: the walk goes through the views of the children, and it
# stops before the last step, and at the first step that reaches no view.
function _find_deepest_view(view::ContentView, steps)
    holder, count = view, 0
    for index in 1:(length(steps) - 1)
        next = try_evaluate_reference(holder, Reference(steps[index]), nothing)
        next isa ContentView || break
        holder, count = next, index
    end
    (holder, count)
end

# Whether the field `name` of `view` holds state of the view, and not the content or
# the view of a child of the content.
function _is_view_state(view::ContentView, name::Symbol)
    (hasfield(typeof(view), name) && name !== :viewed) || return false
    declared = find_declared_field_type(typeof(view), name)
    declared isa Type ? !(declared <: Union{ContentView, Nothing}) : !(getproperty(view, name) isa ContentView)
end

# A content that an edit writes carries no caret: its caret is the caret of the view.
_clear_written_selection!(value::Document) = clear_selection!(value)
_clear_written_selection!(value) = nothing

# An operation of the next stage as an operation of the content that a step printed.
# The next stage writes below the field `viewed` of a view of `output`, the view that
# the step gave. The same write with no step `viewed` is a write of the printed
# content, which the readers of the content print map back.
_make_printed_edit(output, operation) = operation
_make_printed_edit(output::ContentView, operation::CompoundOperation) =
    CompoundOperation(Any[_make_printed_edit(output, member) for member in operation.operations])
_make_printed_edit(output::ContentView, operation::WrappingOperation) =
    rewrap_operation(operation, _make_printed_edit(output, get_wrapped_operation(operation)))
_make_printed_edit(output::ContentView, operation::CollectedIntentsOperation) =
    CollectedIntentsOperation(Intent[Intent(intent.gesture, _make_printed_edit(output, intent.operation),
                                            intent.description, intent.domain, intent.route)
                                     for intent in operation.intents])
function _make_printed_edit(output::ContentView, operation::ReplaceReferencedValueOperation)
    operation.document === nothing || return operation
    steps = get_reference_steps(strip_reference_types(operation.reference))
    isempty(steps) && return operation
    _, count = _find_deepest_view(output, steps)
    steps[count + 1] == _VIEWED_STEP || return operation
    place = Reference(steps[1:count]..., steps[(count + 2):end]...)
    ReplaceReferencedValueOperation(nothing, get_content_path(output, place), operation.value)
end

"""
    make_sibling_view(view::ContentView) -> ContentView

A second view of the content of `view`. It starts with the state of `view`: its
folds, and its caret as a dormant one, so the two views show the same thing until
a person changes one of them. An edit of the content shows in both views, because
they hold the same content.

It is what a paste of a stored view puts in, and the duplicate of a view
(`make_document_duplicate`).

# Example

    view_a = JsonArrayView(array)
    view_b = make_sibling_view(view_a)
    view_b.viewed === view_a.viewed     # true
"""
make_sibling_view(view::ContentView) =
    _copy_view_state!(make_content_view(getproperty(view, :viewed)), view)

# Copy the state of `view` to `copy`, a new view of the same kind over the same
# content or over a copy of it: each field of state, and the stored caret as a
# dormant one, which the next selection of the copy wakes. A child field holds a
# view, of a list or of a document: the view in the same field of `copy` takes its
# state, and the child field of `copy` keeps the view that it follows.
function _copy_view_state!(copy::ContentView, view::ContentView)
    for name in fieldnames(typeof(view))
        (name === :viewed || is_view_state_field(name)) && continue
        value = getproperty(view, name)
        if value isa ContentView
            child = getproperty(copy, name)
            child isa ContentView && _copy_view_state!(child, value)
        elseif value !== getproperty(copy, name)
            setproperty!(copy, name, value)
        end
    end
    _copy_stored_caret!(copy, view)
end

# The stored caret of `view` goes to `copy` as a dormant caret.
function _copy_stored_caret!(copy::ContentView, view::ContentView)
    path = get_stored_selection(view)
    path isa ConcreteReference &&
        (getfield(copy, :selection)[] = SelectionDocument(; primary = copy_reference(path), live = false))
    copy
end

# A copy of a view is a new view of the copy that the policy makes of its content,
# because the child fields of a view follow the content by identity. A document
# met twice is one copy, as in the walk.
function copy_document(policy::CopyPolicy, view::ContentView)
    memo = get_copy_memo(policy)
    earlier = memo === nothing ? nothing : get(memo, view, nothing)
    earlier === nothing || return earlier
    copy = make_content_view(copy_document(policy, getproperty(view, :viewed)))
    memo === nothing || (memo[view] = copy)
    _copy_view_state!(copy, view)
end

# The duplicate of a view owns the state of a view and shares the content, whatever
# the kind of the content declares.
has_document_duplicate(::ContentView) = true
copy_document(::DuplicatePolicy, view::ContentView) = make_sibling_view(view)

# A view owns no place that takes a pasted value: its parts are the views of the
# parts of its content, and a paste of a part is an edit of the content. A paste
# can still replace the view itself, in the place that its container owns.
is_admitted_by_declared_type(::ContentView, declared_type::Type, value) = false

"""
    get_content_path(view::ContentView, path) -> Reference

A path of `view` as a path of its content: the same steps, typed with the nodes
of the content, which the maps and the key tables of the content match.
"""
get_content_path(view::ContentView, path) =
    annotate_reference_types(getproperty(view, :viewed), strip_reference_types(path))

"""
    ViewingProjection(content)

A step that prints a view and its content together. `content` is the projection
of the contents of the stage, usually the table of its rows. For a `ContentView`,
the step prints the content of the view with `content`, and gives the view of the
printed content (`make_content_view`), whose paths are the paths of the view
mapped through the maps of that print. The caret of the output view is live only
when the place of the print is on the path of the live selection, so a view at
two places shows a live caret at one of them. For any other input, it prints the
input with `content`, as a stage with no views does.

A key goes down along the live caret of the view: each view on the path of the
caret reads it with its own key table, the deepest first, as the documents on the
path of a selection do (`read_gesture_outward`). So a view of a part answers its
keys inside the view of the document that holds the part, of any domain. An
operation from the next stage goes back through the readers of the content print,
because a path of the view is the path of its content.
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
    view_recursion = ViewRecursion(input, recursion, ctx, IdDict{Any,Any}())
    viewed = getproperty(input, :viewed)
    hasfield(typeof(viewed), :viewed) && throw(ArgumentError(
        "ViewingProjection: a $(nameof(typeof(viewed))) has a field `viewed`, the name of the field in " *
        "which a view keeps what it shows, so a path of its view can not name that field"))
    content = print_document(p.content, view_recursion, viewed, ctx)
    output = make_content_view(content.output, _make_output_children(view_recursion, content))
    output === nothing && throw(ArgumentError(
        "ViewingProjection: the print of the content of a $(nameof(typeof(input))) gives a " *
        "$(nameof(typeof(content.output))), which has no view (make_content_view)"))
    set_output_path_computations!(output, input,
                                  path -> map_reference_forward(content.projection, content, get_content_path(input, path));
                                  context = ctx)
    map_view_state!(output, input, content)
    ViewingIoMap(p, input, output, content)
end

"""
    map_view_state!(output, view, content_iomap)

Map the state of `view` that is not a path, such as its folds, to `output`, the view
that a viewing step gives over the print of the content of `view`; `content_iomap`
is the IO map of that print. It sets the computations of the cells of `output`, so
the state follows the view. A pair of view types declares a method where such
state crosses the step; the default maps nothing.
"""
function map_view_state! end
map_view_state!(output, view, content_iomap) = output

"""
    read_view_operation(view, content_iomap, operation) -> Operation or nothing

The operation that `operation`, an operation of the next stage, is when the state
of `view` decides it. A toggle of a fold of its text is a toggle of the fold of a
view of a node. A character typed at a place of the text that two parts of a node
share is an edit of the part that holds the caret of the view. `nothing` when the
state of the view decides nothing for `operation`, and then it goes back through
the readers of the content print. A pair of view types declares a method where
such state crosses the step.
"""
function read_view_operation end
read_view_operation(view, content_iomap, operation) = nothing

"""
    ToggleFoldOperation(path)

Open the fold of the view at `path` when it is closed, and close it when it is
open. A fold is state of a view, so the content does not change, and a second view
of the same content keeps its own fold. Each stage maps `path` back as it maps a
caret.
"""
struct ToggleFoldOperation <: Operation
    path::Reference
end

OperationModule.operation_reference(op::ToggleFoldOperation) = op.path
OperationModule.retarget_operation(::ToggleFoldOperation, path::Reference) = ToggleFoldOperation(path)

# A stage that maps the path back types it with the nodes of its content, so the
# path is read on the views by its steps alone.
function evaluate_operation(editor, op::ToggleFoldOperation)
    view = try_evaluate_reference(editor.document, strip_reference_types(op.path), nothing)
    (view isa ContentView && hasproperty(view, :collapsed)) || return
    view.collapsed = !view.collapsed
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

The caret is state of the view, so the recursion tells the child view whether its
place is on the path of the live selection: it is when the place of the view is,
and the live caret of the view goes on into the child.
"""
struct ViewRecursion <: Projection
    view::ContentView
    recursion::Any
    context::Any
    # The IO map of the print of each child view, by the content IO map that the
    # content projection got for it.
    prints::IdDict{Any,Any}
end

function print_document(r::ViewRecursion, recursion, input, ctx)
    steps = _find_child_steps(r, ctx)
    child_view = steps === nothing ? nothing : _find_child_view(r, input, steps)
    child_view === nothing && return print_child(r.recursion, input, ctx)
    view, parent_context = r.view, r.context
    child_context = with_live_place(ctx, () -> is_live_place(parent_context) &&
                                               has_live_selection_below(view, steps))
    iomap = print_child(r.recursion, child_view, child_context)
    iomap isa ViewingIoMap || return iomap
    r.prints[iomap.content] = iomap
    iomap.content
end

# The output views of the children of a viewing step, in the order of the children
# that the content print holds: the output view of the step of each child view, and
# `nothing` for a child that printed as content. A print that a child no longer has
# leaves the table.
function _make_output_children(r::ViewRecursion, content)
    CellVector(Computation(function ()
        child_iomaps = something(get_child_iomaps(content), Any[])
        present = IdDict{Any,Nothing}(child => nothing for child in child_iomaps)
        for child in collect(keys(r.prints))
            haskey(present, child) || delete!(r.prints, child)
        end
        Any[(print = get(r.prints, child, nothing); print === nothing ? nothing : print.output)
            for child in child_iomaps]
    end))
end

# The steps that the context `ctx` of a child adds to the path of the view of `r`, or
# `nothing` when `ctx` is no context below that path.
function _find_child_steps(r::ViewRecursion, ctx)
    (r.context === nothing || ctx === nothing) && return nothing
    parent = get_reference_steps(strip_reference_types(r.context.reference[]))
    child = get_reference_steps(strip_reference_types(ctx.reference[]))
    (length(child) > length(parent) && child[1:length(parent)] == parent) || return nothing
    child[length(parent)+1:end]
end

# The view of the child `input` of the view of `r`: `steps`, the steps of the child,
# applied to the view. `nothing` when they reach no view of `input`.
function _find_child_view(r::ViewRecursion, input, steps)
    view = try_evaluate_reference(r.view, Reference(steps...), nothing)
    (view isa ContentView && getproperty(view, :viewed) === input) ? view : nothing
end

# The maps of a step are the maps of the projection that printed the content, which
# the IO map of the print names: a path of a view is a path of its content.
map_reference_forward(p::ViewingProjection, iomap::ViewingIoMap, reference) =
    map_reference_forward(iomap.content.projection, iomap.content, get_content_path(iomap.input, reference))
map_reference_forward(p::ViewingProjection, iomap, reference) =
    map_reference_forward(iomap.projection, iomap, reference)

map_reference_backward(p::ViewingProjection, iomap::ViewingIoMap, reference) =
    map_reference_backward(iomap.content.projection, iomap.content, reference)
map_reference_backward(p::ViewingProjection, iomap, reference) =
    map_reference_backward(iomap.projection, iomap, reference)

# A gesture that no later stage took goes to the key tables of the views on the
# live caret of the view, the deepest first. An operation goes back through the
# readers of the content print, as an operation of the printed content. Each answer
# is an edit of the content that the views show (`make_content_edit`).
function read_intent(p::ViewingProjection, recursion, change::Intent, iomap::ViewingIoMap)
    view = iomap.input
    if change.operation === nothing && change.route === nothing
        operation = read_gesture_outward(nothing, change.gesture, view;
                                         steps = _find_caret_view_steps(view), with_part = true)
        return Intent(change.gesture, make_content_edit(view, operation), change.description, change.domain)
    end
    if change.operation !== nothing
        operation = read_view_operation(view, iomap.content, change.operation)
        operation === nothing ||
            return Intent(change.gesture, operation, change.description, change.domain)
        change = Intent(change.gesture, _make_printed_edit(iomap.output, change.operation),
                        change.description, change.domain, change.route)
    end
    answer = read_intent(p.content, recursion, change, iomap.content)
    Intent(answer.gesture, make_content_edit(view, answer.operation), answer.description, answer.domain,
           answer.route)
end

read_intent(p::ViewingProjection, recursion, change::Intent, iomap) =
    read_intent(p.content, recursion, change, iomap)

# The steps of the live caret of `view` that lead to the deepest view on it: the
# steps into the child views, and no step into a field of a content. Empty when
# `view` has no live caret, and when its caret names no child view.
function _find_caret_view_steps(view::ContentView)
    steps, pending = ReferenceStep[], ReferenceStep[]
    caret = get_selection(view)
    path = caret isa Reference ? strip_reference_types(caret) : nothing
    node = view
    while path isa ConcreteReference
        node = try_evaluate_reference(node, Reference(path.head), nothing)
        # A list of child views is on the way to a view; any other value is a
        # field of a content, or a child that has no view.
        (node isa ContentView || node isa AbstractVector || node isa CellVector) || break
        push!(pending, path.head)
        if node isa ContentView && !(node isa CellVectorView)
            append!(steps, pending)
            empty!(pending)
        end
        path = path.tail
    end
    steps
end

read_intent(p::ViewingProjection, iomap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation
