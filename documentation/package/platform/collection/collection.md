# Collections

> **Kind:** design · **Status:** current · **Stands on:** [cell.md](../../kernel/cell.md), [document.md](../../kernel/document.md), [reference.md](../../kernel/reference.md)

The collection slice of `ProjecturedPlatform` holds four generic containers for the children of a document: a vector, a matrix, a table and a linked list. Each element is in a reactive cell of its own. It also holds the table interface, which reads the rows and the columns of any kind of table. This document says which kind of change reaches which reader, how the kernel uses these types without naming them, and what the table interface reads.

<img width="396" alt="Collection example" src="../../../asset/image/example/collection.png">

## How it works

| Document | Field | Shape |
| --- | --- | --- |
| `CellVector` | `elements`, a `Vector{Cell}` | a growable sequence, addressed `[i]` |
| `CellMatrix` | `elements`, a `Matrix{Cell}` | a fixed rectangle, addressed `[r, c]` |
| `CellTable` | `rows`, a `CellVector` of `CellVector` rows | a grid that grows a row at a time |
| `ListNode` | `value`, `prev`, `next` | a chain that is read from the node you hold |

`CollectionDocument` is the union of the four. Each is an `@document` struct, so each also has a `selection` field, and `CellVector()`, `CellMatrix()` and `CellTable()` make an empty one.

### A cell for each element

**Each element of a reactive collection is in a cell of its own, and the container is one more cell.** Reading `cv[i]` reads the `elements` cell and then the cell of slot `i`. Two kinds of change follow from this:

- **A value change**, `cv[i] = value`, writes into the existing cell of slot `i`. Only the readers of that slot get it.
- **A structural change**, `push!`, `pop!`, `insert!`, `deleteat!` or `cv[i] = cell`, changes the vector in place and then assigns the same vector to `cv.elements` again. That assignment invalidates every reader of the shape: a layout that reads `length(cv)`, and every reader that read an element through an index.

Every structural mutator must end with that assignment, or the readers of the shape keep a stale value. The module docstring of `CollectionModule` states the rule. `cv[i] = cell` with a `Cell` replaces the slot, so the readers of the old cell get no more changes.

An insert or a delete keeps the cells of the other elements. `get_cell_at(cv, i)` returns the cell of a slot, and a reader that holds that cell keeps its dependency when the slot moves. `make_inverse_operation` of the kernel reads the old element through the seam `get_slot_at`, which returns the cell. So an undo puts back the same cell, and whatever followed that cell follows it again.

A reactive vector stores `Vector{Cell}`. An immutable or mutable vector, made by the cell-kind variants of `@document`, stores a plain `Vector` of values with no cell for each element. Every method dispatches on the kind of the `elements` cell, so the reactive path is fully typed. An immutable vector raises an `ArgumentError` before it changes anything.

### A derived vector

`CellVector(@computation expr)` computes its whole element list from `expr` and puts each element in a new cell on each computation. A projection uses it for children that it builds from its input:

```julia
SyntaxNode(CellVector(@computation [project_child(c) for c in input.children]); open = "[", close = "]")
```

`CellVector(f)` with a plain function is a vector of one element, the function. Only `Computation` derives the element list, as with `Cell(Computation(f))`.

`CellVector(@computation(keys); element)` computes one slot for each key, and the slot computes `element(key)` at its first read. A read of the length computes the keys and nothing else, and a read of one element computes that element and no other. The listing of a folder and the children of a file tree use it:

```julia
entries = CellVector(@computation(readdir(folder)); element = name -> stat(joinpath(folder, name)))
```

### The list

A `ListNode` is the middle of a chain. `prev` and `next` are two tails that grow outward, and each is a cell, so a thunk can compute either one. A chain can then have no end in either direction, and only the nodes that a reader walks to exist. `head[1]` is the held node, `head[2]` walks `next` and `head[0]` walks `prev`. `find_list_node(head, index)` answers the node itself at that index, or `nothing` when the chain ends first, so an element `[k]` of a reference, which counts from the head, reaches its node. `push!` adds to the right tail, `pushfirst!` to the left tail, and iteration starts at `get_left_tail`. `take_first(node, n)` and `take_first(node, n_prev, n_next)` read a finite window. `find_list_index(head, node)` is the inverse of `find_list_node`: the index of `node` counted from `head`, or `nothing`. `make_index_list(count, at, value_of)` builds the list of the indices `1:count` with its head at `at`, and builds a node when a walk first reaches it, so a table of many rows builds only the rows that it shows; the data frame view and the statistics use it, with the anchor that their document owns.

`CopyingProjection` of [projection.md](../projection/projection.md) copies a list node by node on demand, so a copy of an endless list costs nothing until it is read. `copy_document` copies a list in the same way: it copies the held node at once, and a neighbour when `prev` or `next` of the copy is read. A link of the copy that was read keeps its node, and it does not follow a later change of the original. A `GraphicsCanvas` holds a `ListNode` for a view whose elements have no end; see [graphics.md](../graphics/graphics.md).

The kinded copy `copy_document(K, node)` makes every cell of kind `K`. The reactive copy is lazy in the same way. A mutable copy copies and links every node at once, so it does not end for a list without an end. An immutable cell can not hold the link back to a node that is made after it, so an immutable copy of a node with a neighbour raises a `DocumentCopyException`.

`sync_document!(shadow, source)` syncs a list shadow from the node that it holds outward, one direction at a time, so it never follows `next` back through `prev`. The generic walk of the kernel syncs each node without its links. The walk pairs the node of each place with the node of that place in the source, and it ends at a link of the shadow that nothing has read, at the end of either list, or where the source is longer: a reactive shadow then gets a link that copies the new node when it is read, and a shadow of a kind that holds a value copies every node to the end of the source. So a sync of a shadow of a list without an end ends, and it reads only the nodes that the shadow holds.

### The table interface

A stage that reads a table reads it through seven functions, whatever kind of value holds its rows. A table has rows, numbered from 1, and columns, each with a name:

| Function | What it gives |
| --- | --- |
| `is_table(value)` | whether the functions below read `value` |
| `get_table_row_count(table)` | the count of the rows |
| `get_table_column_names(table)` | the names of the columns, in their order |
| `get_table_column_type(table, column)` | the type of the values of a column, or `Any` |
| `get_table_value(table, row, column)` | one value |
| `find_table_column(table, column)` | the column as a vector with no copy, or `nothing` when the kind holds none |
| `make_table_part(table, rows)` | the part that holds the rows `rows`, in that order, with no copy |

The slice reads two kinds itself: a vector of named tuples, whose rows are its elements, and a named tuple of vectors of one length, whose columns are its fields. `make_table_part` gives a `TablePart` for a kind that has no view of its own rows: the rows of a table by their numbers. A `TablePart` is a table too, and a part of a part is a part of the table. A package that owns a kind of table adds the methods for it: `ProjecturedDataFrames` adds them for an `AbstractDataFrame`, whose part is a `SubDataFrame`. The pivot domain reads its source through these functions; see [pivot.md](../../domain/pivot/pivot.md).

### Seams for the kernel

The kernel names no collection type. This package adds methods to kernel generics instead:

| Method | What it gives the kernel |
| --- | --- |
| `is_element_collection(::CellVector)` | a reflection walk makes `[i]` paths and does not descend into `.elements` |
| `is_collection_field_type(::Val{:CellVector})` | `Foo([a, b])` wraps the vector for a `CellVector` field |
| `get_cell_layout_field_type(::Val{:Vector})` | a field declared `Vector{T}` is a `CellVector` in the reactive layout and a plain `Vector` in the native one |
| `child_reference_steps(::CellVector)` | the walk that finds the next insertion reaches each element as `RangeReferenceStep(i - 1, i)` |
| `get_slot_at(::CellVector, i)` | an inverse operation puts back the same cell |
| `make_children_container`, `get_children_container_type` | `@projection_template` builds children as a `CellVector` |
| `copy_document`, `has_document_duplicate` | a deep copy under a `CopyPolicy`; see [document.md](../../kernel/document.md) |
| `sync_document!(::ListNode, ::ListNode)` | a list shadow syncs from the node held outward, and never through a link back |

A reference addresses an element as `[i]`, from 1, and the place between two elements as `{k}`, from 0. Both are readings of one `RangeReferenceStep`; see [reference.md](../../kernel/reference.md).

## How it fits

The collection slice depends only on the kernel. Almost every other slice depends on it: the projection, text, syntax, graphics, layout, widget and pane slices, and every domain with a list of children. The projection slice holds the projections that sort, filter and search a collection.

It registers nothing at load time. The methods in the table above are what connect it to the kernel.

## Design decisions

- **A cell for each element, not one cell for the vector.** A write to one element must reach only the readers of that element.
- **A structural change assigns the same vector again.** The container cell then fires without a copy of the vector.
- **The storage depends on the cell kind.** A cell for each element of a vector that never changes costs memory and time. A branch on the storage at run time made the reactive read about two times slower, so each method dispatches on the kind.
- **The collection logic is in the collection types.** A document holds its children in a collection field, and a caller indexes that field: `node.children[i]`. The collection wraps a plain value in a cell, so no document writes its own `push!` or `getindex`. See [plan/done/fold-collection-methods.md](../../../../plan/done/fold-collection-methods.md). A domain can still give a node the vector methods of its field with `@forward_vector_protocol` of the kernel; JSON, YAML, Markdown and RST do.
- **The list is symmetric.** Both tails can be computed, so a reader walks either way from the held node and no end is the start.

## Usage

```julia
rows = CellVector(["one", "two"])
rows[2] = "three"                         # a value change: only the readers of slot 2
push!(rows, "four")                       # a structural change: the readers of the shape
slot = get_cell_at(rows, 1)

grid = CellMatrix(3, 3)
grid[2, 2] = "x"
insert_row!(grid, 1, Cell[Cell(nothing) for _ in 1:3])

table = CellTable(["name" "age"; "Alice" 30; "Bob" 25])
insert_row!(table, 2, ["Carol", 41])

head = ListNode("alpha"); push!(head, "beta")
take_first(head, 2)                       # ["alpha", "beta"]
```

- Examples: `collection_example` and the sorting, filtering, reversing and searching examples use `make_collection_document_example()`. The atomic catalog has a vector, a table and a list node, in `example/platform/CollectionDocumentExample.jl`.
- Test: `test_collection()` in `test/platform/document/CollectionDocumentTest.jl`, and `test_table_interface()` in `test/platform/document/TableInterfaceTest.jl`.

## Limits

- `CellVector(a, b)` with two arguments calls the constructor of the struct, `(elements, selection)`, and does not make a vector of two elements. Write `CellVector([a, b])`.
- An insert or a delete of a row or a column of a `CellMatrix` allocates a new matrix. The cells stay the same.
