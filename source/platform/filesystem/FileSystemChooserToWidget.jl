# Fragment of `FileSystemModule` — a chooser drawn as the tree it looks in and
# the name a person types.
#
# It composes rather than draws: the directory goes through
# `FileSystemToWidgetTree`, which already knows how to draw a file tree and how
# to answer a row, and the name is a `WidgetText`. What this printer adds is the
# arrangement and the one rule that joins them — **a row of the tree types its
# own name into the field**, so a person may click a file or type a file and the
# chooser says one path either way.

"""
    FileSystemChooserToWidget(position = Point2D(0, 0))

Draw a [`FileSystemChooser`](@ref): the directory it looks in, and the name.
"""
struct FileSystemChooserToWidget <: Projection
    position::Point2D
end
# The struct's own constructor already takes a position, so this adds the default
# and nothing else. A one-argument form here would overwrite the generated one.
FileSystemChooserToWidget() = FileSystemChooserToWidget(Point2D(0, 0))

function print_document(p::FileSystemChooserToWidget, recursion,
                        chooser::FileSystemChooser, ctx)
    # A row names a file, and naming a file is what typing the name does, so the
    # row writes the name rather than opening anything. The chooser chooses; it
    # does not act.
    name_file = path -> WriteChosenNameOperation(chooser, basename(path))
    tree = print_child(recursion, chooser.directory,
                       make_child_context(ctx, FieldReferenceStep("directory")))
    field = print_child(recursion, chooser.name,
                        make_child_context(ctx, FieldReferenceStep("name")))
    widget = WidgetComposite(Any[tree.output, field.output]; position = p.position)
    SimpleIoMap(p, chooser, widget)
end

"""
    WriteChosenNameOperation(chooser, name)

Put `name` in the chooser's name field. It is what a row of the tree answers: a
row names a file, and this is the chooser's way of holding a name.
"""
struct WriteChosenNameOperation <: Operation
    chooser::FileSystemChooser
    name::String
end

WriteChosenNameOperation(chooser::FileSystemChooser, name::AbstractString) =
    WriteChosenNameOperation(chooser, String(name))

OperationModule.is_self_contained_operation(::WriteChosenNameOperation) = true

function evaluate_operation(editor, operation::WriteChosenNameOperation)
    operation.chooser.name = operation.name
    nothing
end

# No caret goes into the chooser. The default backward mapping names a part of its
# widgets by an introduced reference, so a point names the widget under it, and
# only such a reference maps forward again.
map_reference_forward(p::FileSystemChooserToWidget, iomap, reference) =
    find_introduced_path(p, reference)
read_intent(::FileSystemChooserToWidget, iomap, operation) = nothing
