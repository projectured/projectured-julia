# Fragment of `FileSystemModule` — the page of a file: the page of its document,
# the same document that a tab of the file shows, so an edit here is an edit of
# the file.
#
#     children[1].<rest>    document.<rest>

"""
    FileSystemFileToWidget()

Draw a [`FileSystemFile`](@ref) as its page: the page of its document, which its
acquire gives it, drawn by the row of its own type, or a line that says that the
file is not read while it has none. A path in the document goes to the page and
back, so a key and a press on the page edit the file.
"""
struct FileSystemFileToWidget <: Projection end

function print_document(p::FileSystemFileToWidget, recursion, file::FileSystemFile, context)
    output = VerticalLayout(CellVector(@computation Any[something(file.document,
                                                                  WidgetLabel(file.pathname * " · not read yet"))]),
                            Cell(:left), Cell(0), Cell(Fill), Cell(Fill), Cell(nothing))
    iomap = SimpleIoMap(p, file, output)
    set_output_path_computations!(output, file, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

function map_reference_forward(::FileSystemFileToWidget, iomap, reference)
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(iomap.output))
    reference isa ConcreteReference || return nothing
    head = get_reference_head(reference)
    (head isa FieldReferenceStep && head.name == "document" && iomap.input.document !== nothing) || return nothing
    annotate_reference_types(iomap.output, concat_references(
        extend_reference(EmptyReference(), FieldReferenceStep("children"), RangeReferenceStep(0, 1)),
        strip_reference_types(get_reference_tail(reference))))
end

function map_reference_backward(::FileSystemFileToWidget, iomap, reference)
    reference isa ConcreteReference || return EmptyReference()
    steps = get_reference_steps(strip_reference_types(reference))
    (length(steps) >= 2 && steps[1] == FieldReferenceStep("children") && steps[2] == RangeReferenceStep(0, 1)) ||
        return EmptyReference()
    extend_reference(EmptyReference(), FieldReferenceStep("document"), steps[3:end]...)
end

# The document of the page comes back through the recursion of the renderer, which
# draws it with the row of its own type.
make_graphics_projection(::Type{FileSystemFile}; measure, appearance) =
    ChainingProjection(FileSystemFileToWidget(), VerticalLayoutToGraphicsCanvas())
