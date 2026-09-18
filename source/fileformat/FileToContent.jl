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
    FileToContent()

The projection a `FileDocument` (`JsonFile`, `XmlFile`, `JuliaFile`, …) is
drawn through: it prints the file's `content` via the recursion argument and
answers that child's own output, so a tab holding the file shows its content
exactly as an ordinary document of that domain would.
"""
struct FileToContent <: Projection end

function print_document(p::FileToContent, recursion, file::FileDocument, ctx)
    step = @reference_step(content)
    # Single-child reconciliation (`reconcile_child_iomap`, not the plural
    # collection form `reconcile_child_iomaps`): `content` is one field, not a
    # collection, so there is exactly one child to reconcile by identity.
    # Reading `get_file_content(file)` inside the thunk is what makes the
    # printed output re-derive when `Ctrl+O` replaces the cell wholesale.
    child = reconcile_child_iomap(
        () -> get_file_content(file),
        v -> print_child(recursion, v, make_child_context(ctx, file, step)))
    ContentIoMap(p, file, ComputedCell(() -> child[].output), ComputedCell(() -> child[]))
end

# Forward: `.content.rest...` is entirely the child's own domain, and this
# projection introduces no structure of its own — the image is exactly the
# child projection's forward image of `rest`.
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
    register_natural_graphics!(:fileformat, (; measure) -> Pair{Type,Any}[
        FileDocument => FileToContent(),
    ])
end
