"""
`DocumentModule` — the document contract, exercised through a test-local
`ToyNode` type. Kernel tests must use ONLY toy documents/projections defined
test-locally, so the concrete engine documents (Collection, Primitive,
ScreenDocument) cannot leak in as fixtures — the resulting pressure is what
keeps the interface sufficient.

Covers:
- `@document` field auto-wrapping in Cells,
- `getproperty` unwraps stored Cells,
- `SelectionDocument` and `unwrap_selection`: the live or dormant selection,
- the seams of a wrapper: `get_wrapped_document`, `get_edited_field` and
  `replace_wrapped_document!`,
- `@forward_protocol` and `@adapt_map_protocol`,
- `copy_document` round-trips a document tree (same kind and kind-converting).
"""

using Test
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.CellModule: Cell, Computation, @computation, ImmutableCell,
                                    ReactiveCell, AbstractCell, is_cell_up_to_date
# The reference layer supplies the type our test-local selection field carries.
# Non-cell/document imports are allowed only to build the fixture; the contract
# tests below still exercise DocumentModule generics.
using ProjecturedKernel.ReferenceModule: EmptyReference, FieldReferenceStep,
                                         extend_reference, strip_reference_types

@document struct ToyNode
    label::String
    child::Union{ToyNode, Nothing}
end

# A field typed `Document` rather than one schema. That is what lets a *native*
# node into a tree of any layout, because a native node is a `Document`, and so it
# is the shape the layout rules are about. `ToyNode.child` above is typed to one
# schema and cannot hold a native node at all.
@document struct ToyBox
    content::Union{Document, Nothing} = nothing
end

# Two slots that can hold one child twice, or the pair itself.
@document struct ContractPair
    first::Any
    second::Any
end

# A graph whose text under Base's default `show` doubles with each level: every
# level holds the level under it twice.
mutable struct ContractShownGraph
    left::Any
    right::Any
end

# Stops at the node that carries `label`, and puts a node labelled "stopped" there.
struct ContractStopPolicy <: CopyPolicy
    label::String
end
ProjecturedKernel.DocumentModule.is_descendable_for_copy(p::ContractStopPolicy, document::ToyNode) =
    document.label != p.label
ProjecturedKernel.DocumentModule.make_copy_placeholder(::ContractStopPolicy, document) =
    ToyNode("stopped", nothing, nothing)

# Records each copy, so a child met twice is one copy.
struct ContractMemoPolicy <: CopyPolicy
    copies::IdDict{Any,Any}
end
ContractMemoPolicy() = ContractMemoPolicy(IdDict{Any,Any}())
ProjecturedKernel.DocumentModule.get_copy_memo(p::ContractMemoPolicy) = p.copies

# Refuses the node that carries `label`, and every cell that computes.
struct ContractRefusePolicy <: CopyPolicy
    label::String
end
function ProjecturedKernel.DocumentModule.is_descendable_for_copy(p::ContractRefusePolicy, document::ToyNode)
    document.label == p.label && throw(DocumentCopyException(document, "it is refused"))
    true
end
ProjecturedKernel.DocumentModule.copy_computed_cell(::ContractRefusePolicy, cell) =
    throw(DocumentCopyException(cell, "it computes"))

# The toy kinds that declare a duplicate. `ToyBox` declares none.
ProjecturedKernel.DocumentModule.has_document_duplicate(::ToyNode) = true
ProjecturedKernel.DocumentModule.has_document_duplicate(::ContractPair) = true

# Copies every node with its label in upper case: a method on the pair.
struct ContractShoutPolicy <: CopyPolicy end
ProjecturedKernel.DocumentModule.copy_document(p::ContractShoutPolicy, document::ToyNode) =
    copy_document_fields(p, document; label = uppercase(document.label))

# A first field of the immutable kind, beside a child in a reactive cell.
@document struct ContractMixedKinds
    tag::ImmutableCell{String} = ""
    child::Any = nothing
end

# A kind with a kinded copy of its own, in the four-argument form that a kind adds.
@document struct ContractOwnCopy
    label::String = ""
end
ProjecturedKernel.DocumentModule.copy_document(::Type{<:AbstractCell}, ::ContractOwnCopy,
                                               policy, depth::Int) =
    ContractOwnCopy(label = "own copy at depth $depth")

# A wrapper with the vector protocol of its field, and one with the map protocol.
@document struct ContractList
    items::Vector{Any} = Any[]
end
@forward_vector_protocol on ContractList to items

@document struct ContractEntry
    key::String
    value::Any
end
@document struct ContractMap
    entries::Vector{Any} = Any[]
end
@adapt_map_protocol on ContractMap to entries with ContractEntry(key, value)

# A wrapper that forwards three functions to its field, and no other.
@document struct ContractStack
    items::Vector{Any} = Any[]
end
@forward_protocol [Base.length, Base.getindex, Base.push!] on ContractStack to items

# A layer that holds the document a person edits in its field `content`, and
# stays in place when that document is replaced.
@document struct ContractHolder
    content::Any = nothing
end
ProjecturedKernel.DocumentModule.get_wrapped_document(holder::ContractHolder) =
    holder.content
ProjecturedKernel.DocumentModule.get_edited_field(::ContractHolder) = :content
function ProjecturedKernel.DocumentModule.replace_wrapped_document!(
        holder::ContractHolder, document)
    holder.content = document
    holder
end

function test_document_contract()
@testset "DocumentContract" begin

    @testset "@document constructs and unwraps cells" begin
        n = ToyNode("root", nothing, nothing)
        # Field auto-wrap: passing a bare value works; the field is stored as a
        # Cell under the hood but property access reads through.
        @test n.label == "root"
        @test n.child === nothing
        @test n isa Document
        # Every document carries a selection field per the contract.
        @test hasfield(typeof(n), :selection)
        @test get_selection(n) === nothing
    end

    @testset "a selection document holds the path and whether it is live" begin
        path = extend_reference(EmptyReference(), FieldReferenceStep("label"))
        live = SelectionDocument(; primary = path)
        dormant = SelectionDocument(; primary = path, live = false)
        @test live.live
        @test unwrap_selection(live) === path
        @test unwrap_selection(dormant) === nothing
        @test unwrap_selection(path) === path
        @test unwrap_selection(nothing) === nothing

        # The property read unwraps what the selection cell holds; the cell keeps it.
        node = ToyNode("root", nothing, nothing)
        getfield(node, :selection)[] = live
        @test node.selection === path
        getfield(node, :selection)[] = dormant
        @test node.selection === nothing
        @test getfield(node, :selection)[] === dormant

        # A copy keeps the dormant state, in a selection document of its own.
        copied = getfield(copy_document(node), :selection)[]
        @test copied isa SelectionDocument
        @test !copied.live
        @test strip_reference_types(copied.primary) == path
        @test copied !== dormant
    end

    @testset "a wrapper adds a method to each seam, a document keeps the default" begin
        node = ToyNode("inner", nothing, nothing)
        other = ToyNode("other", nothing, nothing)
        @test get_wrapped_document(node) === node
        @test get_edited_field(node) === nothing
        @test replace_wrapped_document!(node, other) === other

        holder = ContractHolder(content = node)
        @test get_wrapped_document(holder) === node
        @test get_edited_field(holder) === :content
        @test replace_wrapped_document!(holder, other) === holder
        @test holder.content === other
    end

    @testset "@forward_protocol forwards the listed functions to the field" begin
        stack = ContractStack(items = Any[1])
        @test push!(stack, 2) === stack
        @test length(stack) == 2
        @test stack[2] == 2
        @test stack.items == [1, 2]
        @test !hasmethod(pop!, Tuple{ContractStack})
        wrong_keyword = :(@forward_protocol [Base.length] at ContractStack to items)
        @test_throws "expected `on`" macroexpand(@__MODULE__, wrong_keyword)
        no_vector = :(@forward_protocol Base.length on ContractStack to items)
        @test_throws "vector literal" macroexpand(@__MODULE__, no_vector)
    end

    @testset "@adapt_map_protocol reads and writes the entries by key" begin
        table = ContractMap(entries = Any[])
        table["a"] = 1
        table["b"] = 2
        table["a"] = 3
        @test keys(table) == ["a", "b"]
        @test values(table) == [3, 2]
        @test table["a"] == 3
        @test haskey(table, "b")
        @test !haskey(table, "c")
        @test get(table, "c", 0) == 0
        @test_throws KeyError table["c"]
        # A second entry with the same key goes with the first.
        push!(table.entries, ContractEntry("a", 4))
        @test delete!(table, "a") === table
        @test collect(table) == [("b", 2)]
        no_constructor = :(@adapt_map_protocol on ContractMap to entries with key)
        @test_throws "constructor call" macroexpand(@__MODULE__, no_constructor)
    end

    @testset "copy_document round-trips a document tree" begin
        leaf = ToyNode("leaf", nothing, nothing)
        root = ToyNode("root", leaf, nothing)
        # `copy_document(K, doc)` returns a kind-converted form of the tree.
        snap = copy_document(ImmutableCell, root)
        @test snap isa ToyNode
        @test snap.label == "root"
        @test snap.child.label == "leaf"
        # `copy_document(doc)` produces an independent copy preserving the
        # source's kind that reads back equal at every level.
        clone = copy_document(root)
        @test clone !== root
        @test clone.label == "root"
        @test clone.child.label == "leaf"
    end

    @testset "copy_document preserves a function-valued field" begin
        # A copy re-boxes each field through the constructor of its cell. A function
        # in a field is a value, and the copy keeps it a value that no read calls.
        callback() = "called"
        node = ContractPair(callback, nothing, nothing)
        @test copy_document(node).first === callback
        @test copy_document(ImmutableCell, node).first === callback
    end

    @testset "show prints a field that reaches an object graph as its type name" begin
        level = ContractShownGraph(nothing, nothing)
        for _ in 1:12
            level = ContractShownGraph(level, level)
        end
        held = () -> level
        @test sprint(show, ContractPair("runs", Ref{Any}(held))) ==
              "ContractPair(\"runs\", RefValue(…))"
        text = sprint(show, ContractPair(held, level))
        @test endswith(text, "(…), ContractShownGraph(…))")
        @test length(text) < 100
        # A field value whose own `show` the value bounds prints as before.
        @test sprint(show, ContractPair([1, 2], identity)) == "ContractPair([1, 2], identity)"
        small = ContractShownGraph(1, ContractShownGraph("a", nothing))
        @test occursin(r"ContractShownGraph\(1, (\w+\.)*ContractShownGraph\(\"a\", nothing\)\)\)$",
                       sprint(show, ContractPair(nothing, small)))
        @test sprint(show, ContractPair(ToyNode("leaf", nothing, nothing), Dict(:a => "b"))) ==
              "ContractPair(ToyNode(\"leaf\", nothing), Dict(:a => \"b\"))"
    end

    @testset "the copy of a vector keeps its element type" begin
        # A vector of `Document` that holds one kind stays a vector of `Document`,
        # although a comprehension takes its element type from the values it makes.
        items = Document[ToyNode("one", nothing, nothing)]
        for copied in (copy_document(items), copy_document(ReactiveCell, items),
                       copy_document(ContractPair(items, nothing, nothing)).first)
            @test copied isa Vector{Document}
            push!(copied, ToyBox(nothing, nothing))
            @test length(copied) == 2
        end
        @test copy_document(Cell[]) isa Vector{Cell}
        @test copy_document(Any[1]) isa Vector{Any}
        # A kinded copy converts a native element, which then does not fit the
        # element type, so the copy takes the type of what it holds.
        converted = copy_document(ReactiveCell, [MToyNode("one", nothing, nothing)])
        @test only(converted) isa ToyNode
    end

    @testset "a kind that copies in its own way adds the four-argument form" begin
        # The walk calls the four-argument form for a child, and the shorter forms
        # call it too, so the method of the kind is reached at any depth.
        own = ContractOwnCopy(label = "source")
        @test copy_document(ReactiveCell, own).label == "own copy at depth 0"
        box = copy_document(ReactiveCell, ToyBox(own, nothing))
        @test box.content.label == "own copy at depth 1"
        @test startswith(only(copy_document(ReactiveCell, [own])).label, "own copy")
    end

    @testset "a forwarded mutator returns the wrapper, and a map has a length" begin
        list = ContractList(items = Any[])
        @test push!(list, 1) === list
        @test insert!(list, 1, 0) === list
        @test setindex!(list, 5, 2) === list
        @test deleteat!(list, 1) === list
        @test collect(list) == [5]
        @test pop!(list) == 5
        table = ContractMap(entries = Any[])
        table["a"] = 1
        table["b"] = 2
        @test length(table) == 2
        @test collect(table) == [("a", 1), ("b", 2)]
    end

    @testset "the hidden elements of a bounded walk check their bounds" begin
        hidden = HiddenElements([10, 20, 30, 40], 2, 3)
        @test collect(hidden) == [20, 30]
        @test_throws BoundsError hidden[3]
    end

    @testset "a kinded copy targets the cell layout, a plain copy keeps the layout" begin
        native = MToyNode("root", nothing, nothing)
        # A kind is a property of a cell, so a kinded copy of a native source converts
        # it to the cell layout. A native node in a cell shadow invalidates no reader.
        reactive = copy_document(ReactiveCell, native)
        @test reactive isa ToyNode
        @test getfield(reactive, :label) isa ReactiveCell
        @test reactive.label == "root"
        @test copy_document(ImmutableCell, native) isa ToyNode
        @test getfield(copy_document(ImmutableCell, native), :label) isa ImmutableCell
        # The plain copy preserves the layout, so a native document copies into one.
        @test copy_document(native) isa MToyNode
    end

    @testset "a new native child reaches a cell shadow as a cell node" begin
        source = MToyBox(nothing, nothing)
        shadow = ToyBox(nothing, nothing)
        source.content = MToyNode("first", nothing, nothing)
        sync_document!(shadow, source)
        # The child is rebuilt in the shadow's own layout, not copied across as it was.
        @test shadow.content isa ToyNode
        @test getfield(shadow.content, :label) isa AbstractCell

        # The point of the shadow: a reader of it runs again when the source moves.
        # A native child would read correctly here and never invalidate.
        seen = Cell(@computation(shadow.content === nothing ? "" :
                                 shadow.content.label))
        @test seen[] == "first"
        source.content.label = "second"
        sync_document!(shadow, source)
        @test seen[] == "second"
    end

    @testset "a sync rebuilds a child in the kind of the cell of its slot" begin
        source = ContractMixedKinds("tag", nothing, nothing)
        shadow = ContractMixedKinds("tag", nothing, nothing)
        @test getfield(shadow, :tag) isa ImmutableCell
        source.child = ToyNode("first", nothing, nothing)
        sync_document!(shadow, source)
        # The child takes the kind of its own slot, not the immutable kind of the
        # first field, so the next sync writes into it.
        @test getfield(shadow.child, :label) isa ReactiveCell
        source.child.label = "second"
        sync_document!(shadow, source)
        @test shadow.child.label == "second"
    end

    @testset "a sync keeps a dormant selection, and writes an unchanged one no more" begin
        path = extend_reference(EmptyReference(), FieldReferenceStep("label"))
        source = ToyNode("root", nothing, nothing)
        getfield(source, :selection)[] = SelectionDocument(; primary = path, live = false)
        shadow = ToyNode("root", nothing, nothing)
        sync_document!(shadow, source)
        kept = getfield(shadow, :selection)[]
        @test kept isa SelectionDocument && !kept.live && kept.primary == path
        @test shadow.selection === nothing
        reader = Cell(@computation getfield(shadow, :selection)[])
        reader[]
        sync_document!(shadow, source)
        @test getfield(shadow, :selection)[] === kept
        @test is_cell_up_to_date(reader)

        # A native source holds a live selection document as the value of its field.
        native = MToyNode("root", nothing, SelectionDocument(; primary = path))
        live = ToyNode("root", nothing, nothing)
        sync_document!(live, native)
        held = getfield(live, :selection)[]
        sync_document!(live, native)
        @test getfield(live, :selection)[] === held
        @test live.selection == path
    end

    @testset "a tree that holds no cells is not a shadow" begin
        source = MToyBox(nothing, nothing)
        source.content = MToyNode("first", nothing, nothing)
        # Nothing in a native tree can invalidate a reader, so it cannot serve as a
        # shadow.
        @test_throws ErrorException sync_document!(MToyBox(nothing, nothing), source)
        # A cell shadow of the same schema takes the very same source.
        @test sync_document!(ToyBox(nothing, nothing), source).content isa ToyNode
    end

    @testset "copy_document under a policy" begin
        tree() = ToyNode("root", ToyNode("middle", ToyNode("leaf", nothing, nothing), nothing), nothing)

        @testset "the plain copy is the walk under PlainCopyPolicy" begin
            root = tree()
            clone = copy_document(PlainCopyPolicy(), root)
            @test clone isa ToyNode
            @test clone !== root
            @test clone.child !== root.child
            @test clone.child.child.label == "leaf"
            @test getfield(clone, :label) !== getfield(root, :label)
        end

        @testset "a policy stops at a kind and puts its placeholder there" begin
            root = tree()
            clone = copy_document(ContractStopPolicy("middle"), root)
            @test clone.label == "root"
            @test clone.child.label == "stopped"
            @test clone.child.child === nothing
            # The root is asked too.
            @test copy_document(ContractStopPolicy("root"), root).label == "stopped"
        end

        @testset "a memo makes a child met twice one copy" begin
            shared = ToyNode("shared", nothing, nothing)
            pair = ContractPair(shared, shared, nothing)
            clone = copy_document(ContractMemoPolicy(), pair)
            @test clone.first === clone.second
            @test clone.first !== shared
            # With no memo, each slot gets a copy of its own.
            plain = copy_document(pair)
            @test plain.first !== plain.second
        end

        @testset "a memo stops a document that holds itself" begin
            pair = ContractPair(nothing, nothing, nothing)
            pair.second = pair
            @test_throws DocumentCopyException copy_document(ContractMemoPolicy(), pair)
        end

        @testset "a hook refuses the whole copy from any depth" begin
            exception = try
                copy_document(ContractRefusePolicy("leaf"), tree())
                nothing
            catch e
                e
            end
            @test exception isa DocumentCopyException
            @test exception.value.label == "leaf"
            @test occursin("is refused", sprint(showerror, exception))
        end

        @testset "a cell that computes is the policy's to copy" begin
            node = ToyNode("", nothing, nothing)
            set_cell_computation!(getfield(node, :label), () -> "computed")
            @test is_computed_cell(getfield(node, :label))
            # The plain copy keeps a moment of it, in a cell that stores.
            clone = copy_document(node)
            @test clone.label == "computed"
            @test !is_computed_cell(getfield(clone, :label))
            @test_throws DocumentCopyException copy_document(ContractRefusePolicy("none"), node)
        end

        @testset "a method on the pair replaces one step and keeps the walk" begin
            clone = copy_document(ContractShoutPolicy(), tree())
            @test clone.label == "ROOT"
            @test clone.child.child.label == "LEAF"
        end

        @testset "a replacement takes the value given, in a new cell" begin
            root = tree()
            clone = copy_document_fields(PlainCopyPolicy(), root; label = "renamed")
            @test clone.label == "renamed"
            @test root.label == "root"
            @test getfield(clone, :label) isa AbstractCell
            @test clone.child !== root.child
            @test_throws ArgumentError copy_document_fields(PlainCopyPolicy(), root; lable = "x")
        end
    end

    @testset "the duplicate of a document" begin
        # The reason a refusal gives, or `nothing` when the duplicate is made.
        refusal(document) = try
            make_document_duplicate(document)
            nothing
        catch e
            e isa DocumentCopyException || rethrow()
            e.reason
        end

        @testset "a kind that declares one gets an equal and independent copy" begin
            root = ToyNode("root", ToyNode("leaf", nothing, nothing), nothing)
            duplicate = make_document_duplicate(root)
            @test duplicate.child.label == "leaf"
            duplicate.child.label = "changed"
            @test root.child.label == "leaf"
            @test has_document_duplicate(root)
        end

        @testset "the selection is copied" begin
            path = extend_reference(EmptyReference(), FieldReferenceStep("label"))
            root = set_selection!(ToyNode("root", nothing, nothing), path)
            duplicate = make_document_duplicate(root)
            @test strip_reference_types(get_selection(duplicate)) ==
                  strip_reference_types(get_selection(root))
            @test getfield(duplicate, :selection) !== getfield(root, :selection)
        end

        @testset "a selection that a projection computes is copied as it is now" begin
            path = extend_reference(EmptyReference(), FieldReferenceStep("label"))
            node = ToyNode("root", nothing, nothing)
            set_cell_computation!(getfield(node, :selection), () -> path)
            @test is_computed_cell(getfield(node, :selection))
            duplicate = make_document_duplicate(node)
            @test !is_computed_cell(getfield(duplicate, :selection))
            @test strip_reference_types(getfield(duplicate, :selection)[]) ==
                  strip_reference_types(path)
        end

        @testset "a child whose kind declares none is shared" begin
            box = ToyBox(nothing, nothing)
            pair = ContractPair(box, ToyNode("own", nothing, nothing), nothing)
            duplicate = make_document_duplicate(pair)
            @test duplicate.first === box
            @test duplicate.second !== pair.second
            @test !has_document_duplicate(box)
            @test occursin("declares no duplicate", refusal(box))
        end

        @testset "what the duplicate can not own refuses it" begin
            computed = ToyNode("", nothing, nothing)
            set_cell_computation!(getfield(computed, :label), () -> "computed")
            @test occursin("computes", refusal(computed))
            @test occursin("action", refusal(ContractPair(() -> "called", nothing, nothing)))
            @test occursin("action", refusal(ContractPair(Ref{Any}(1), nothing, nothing)))
            looped = ContractPair(nothing, nothing, nothing)
            looped.second = looped
            @test occursin("back-link", refusal(looped))
            # A plain value and a shared data object are no reason to refuse.
            data = Dict(:a => 1)
            @test make_document_duplicate(ContractPair(data, 2, nothing)).first === data
        end
    end

end
end # test_document_contract
