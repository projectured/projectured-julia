# Fragment of `SystemProcessModule` — a tree of processes that shows alone, as the
# page of a navigator or in a card, draws as a tree: it prints as a `DocumentTree`
# of itself, which the tree slice draws.

"""
    SystemProcessTreeToDocumentTree()

Prints a [`SystemProcessTree`](@ref) as a `DocumentTree` whose root is the tree
of processes, with its title. A path of the tree of processes is the same path
below the field `root` of the `DocumentTree`, so a node selects its process, and
a double click on a node opens its process as a page.
"""
struct SystemProcessTreeToDocumentTree <: Projection end

@iomap struct SystemProcessTreeToDocumentTreeIoMap
    projection::Any
    input::Any          # SystemProcessTree
    output::Any         # DocumentTree
end

const _ROOT_STEP = FieldReferenceStep("root")

function print_document(p::SystemProcessTreeToDocumentTree, recursion, tree::SystemProcessTree, context)
    output = DocumentTree(tree; title = tree.title)
    iomap = SystemProcessTreeToDocumentTreeIoMap(p, tree, output)
    set_output_path_computations!(output, tree, path -> map_reference_forward(p, iomap, path))
    iomap
end

function map_reference_forward(p::SystemProcessTreeToDocumentTree, iomap::SystemProcessTreeToDocumentTreeIoMap,
                               reference)
    reference isa Reference || return nothing
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    concat_references(extend_reference(EmptyReference(), _ROOT_STEP), strip_reference_types(reference))
end

# A path below `root` is the same path of the tree of processes. Any other part of
# the `DocumentTree`, itself as well, is a part that the view drew.
function map_reference_backward(p::SystemProcessTreeToDocumentTree, iomap::SystemProcessTreeToDocumentTreeIoMap,
                                reference)
    reference isa Reference || return nothing
    path = strip_reference_types(reference)
    path isa ConcreteReference && path.head == _ROOT_STEP && return path.tail
    make_introduced_reference(p, iomap, path)
end

# A tree of processes draws as the tree slice draws a `DocumentTree`, inside any
# document that a renderer draws.
make_graphics_projection(::Type{SystemProcessTree}; measure, appearance) =
    ChainingProjection(SystemProcessTreeToDocumentTree(), make_graphics_projection(DocumentTree; measure, appearance))
