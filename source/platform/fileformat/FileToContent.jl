# Fragment of `FileFormatModule` — draws a `FileDocument`'s own content, and
# registers the row that lets the render-anything projection reach it.
#
# `FileDocument` carries `filename` and `content`; only `content` is a
# document worth drawing. The printer hands it to `recursion` — the
# render-anything dispatcher this row is registered on — instead of answering
# it directly: a registered row for the content's own type is reached by the
# dispatcher recursing through `print_child`, not by a projection returning an
# unprojected document as its output.
"""
    FileToContent(; content = nothing)

The projection a `FileDocument` (`JsonFile`, `XmlFile`, `JuliaFile`, …) is
drawn through: it prints the file's `content` via the recursion argument and
answers that child's own output, so a tab holding the file shows its content
exactly as an ordinary document of that domain would.

`content`, when given, is the projection that prints the content in place of the
recursion, and reads its gestures: the view of a file of a domain, such as the
code of a Julia file with its gutter, which a document of that domain inside
another document does not have.
"""
struct FileToContent <: Projection
    content::Any
end

FileToContent(; content = nothing) = FileToContent(content)

# The projection that prints and reads the content of a file.
_get_content_recursion(p::FileToContent, recursion) = p.content === nothing ? recursion : p.content

function print_document(p::FileToContent, recursion, file::FileDocument, ctx)
    step = @reference_step(content)
    # Single-child reconciliation (`make_reconciled_child_iomap_cell`, not the plural
    # collection form `make_reconciled_child_iomaps_cell`): `content` is one field, not a
    # collection, so there is exactly one child to reconcile by identity.
    # Reading `get_file_content(file)` inside the thunk is what makes the
    # printed output re-derive when `Ctrl+O` replaces the cell wholesale.
    child = make_reconciled_child_iomap_cell(
        () -> get_file_content(file),
        v -> print_child(_get_content_recursion(p, recursion), v, make_child_context(ctx, file, step)))
    ContentIoMap(p, file, Cell(@computation child[].output),
                 Cell(@computation child[]))
end

# Forward: `.content.rest...` is entirely the child's own domain, and this
# projection introduces no structure of its own — the image is exactly the
# child projection's forward image of `rest`.
# A gesture goes to the content first, and its answer comes back with the step
# `content` in front. When the content does not answer, the file's own gestures
# answer: Ctrl+S and Ctrl+O. A collection takes both, merged, and an operation
# with a route follows it through `content`.
const _CONTENT_STEPS = (FieldReferenceStep("content"),)

function read_intent(p::FileToContent, recursion, change::Intent, iomap::ContentIoMap)
    child = iomap.inner_iomap
    file = iomap.input
    recursion = _get_content_recursion(p, recursion)
    if change.gesture isa CollectIntents
        inner = reroot_operation(read_intent(get_iomap_projection(child), recursion, change, child).operation,
                                 _CONTENT_STEPS)
        own = read_gesture(file, change.gesture)
        return Intent(change.gesture,
                      merge_collected_intents(_get_collected_intents(inner),
                                              _get_collected_intents(own)))
    end
    if change.route !== nothing
        routed = follow_intent_route(change, _CONTENT_STEPS...)
        routed === nothing && return Intent(change.gesture, nothing)
        answer = reroot_operation(read_routed_intent(get_iomap_projection(child), recursion,
                                                     routed, child).operation,
                                  _CONTENT_STEPS)
        return Intent(change.gesture, answer isa Operation ? answer : nothing)
    end
    inner = read_intent(get_iomap_projection(child), recursion, change, child)
    answer = reroot_operation(inner.operation, _CONTENT_STEPS)
    answer isa Operation && return Intent(change.gesture, answer)
    own = change.operation === nothing ? read_gesture(file, change.gesture) : nothing
    own === nothing || return Intent(change.gesture, own)
    # Neither answered: hand back what the content answered, so a layer above
    # still sees the gesture it declined.
    Intent(change.gesture, answer)
end

read_intent(p::FileToContent, iomap::ContentIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Only a real collection merges; anything else a reader answered is not one.
_get_collected_intents(operation::CollectedIntentsOperation) = operation
_get_collected_intents(::Any) = nothing

function map_reference_forward(::FileToContent, iomap::ContentIoMap, reference)
    @reference_case reference begin
        ::FileDocument.content.rest... => begin
            inner = iomap.inner_iomap
            map_reference_forward(get_iomap_projection(inner), inner, rest)
        end
    end
end

# Backward: a path in the child's own output domain never carries a `content`
# step — only this projection can prepend it. `concat_references`, not the
# `^` splice of `@reference`: the splice hoists the spliced path's own leading
# type onto the `content` node and drops its interior checkpoints, and a
# selection whose checkpoints moved matches no document (see the identical
# comment above `PaneToWidget.jl`'s own use of `concat_references`).
function map_reference_backward(::FileToContent, iomap::ContentIoMap, reference)
    inner = iomap.inner_iomap
    inner_path = map_reference_backward(get_iomap_projection(inner), inner, reference)
    inner_path === nothing && return nothing
    concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()), inner_path)
end

# ── Natural-graphics registration ───────────────────────────────────────────

function __init__()
    register_natural_graphics!(:fileformat, (; measure, appearance) -> Pair{Type,Any}[
        FileDocument => FileToContent(),
    ])
end
