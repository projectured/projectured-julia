"""
`OperationModule` — the write of `ReplaceReferencedValueOperation` into a plain
value, a value that is no document and holds its fields with no cell.

The rules: a slot that a cell holds is written as it is; a carried cell with an
empty path is written itself; a field of an immutable struct, or an element of a
tuple, is written by a copy that goes into the slot one level up; a field of a
mutable struct changes in place, and the nearest cell above it is written again
so its readers read again; with no cell above, the write throws. Each case also
takes the way back, and a reader cell proves that the readers of the cell see
the write.
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.CellModule: Cell, set_cell_computation!
using ProjecturedKernel.OperationModule
using ProjecturedKernel.DocumentModule: @document
using ProjecturedKernel.ReferenceModule

struct PlainOpWindow
    title::String
    width::Int
end

struct PlainOpServer
    name::String
    capacity::Int
    window::PlainOpWindow
end

mutable struct PlainOpCounter
    count::Int
    ratio::Float64
end

# A struct whose constructor does not take all of its fields: it adds a method of
# the copy seam.
struct PlainOpPair
    left::Int
    right::Int
    PlainOpPair(left::Int) = new(left, 2 * left)
end
ProjecturedKernel.OperationModule.with_object_field(pair::PlainOpPair, name::Symbol, value) =
    name === :left ? PlainOpPair(value) : error("right follows left")

@document struct PlainOpHolder
    value::Any
end

mutable struct _PlainOpEditor
    document::Any
end

_plain_server() = PlainOpServer("gateway", 4, PlainOpWindow("Main", 800))
_plain_path(names...) = Reference((FieldReferenceStep(String(name)) for name in names)...)

# A cell that reads `f()`, so a test sees whether a write reaches the readers.
function _plain_reader(f)
    reader = Cell(nothing)
    set_cell_computation!(reader, f)
    reader
end

function test_operations()
@testset "Operations" begin

    @testset "a carried cell with an empty path is written itself" begin
        root = Cell(1)
        editor = _PlainOpEditor(nothing)
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(root, EmptyReference(), 2))
        @test root[] == 2
        evaluate_operation(editor, inverse)
        @test root[] == 1
    end

    @testset "a field of an immutable struct in a cell is written by a copy" begin
        root = Cell(_plain_server())
        reader = _plain_reader(() -> root[].name)
        @test reader[] == "gateway"
        editor = _PlainOpEditor(nothing)
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(root, _plain_path(:name), "gw2"))
        @test root[] isa PlainOpServer
        @test root[].name == "gw2"
        @test root[].capacity == 4
        @test reader[] == "gw2"
        evaluate_operation(editor, inverse)
        @test root[] == _plain_server()
        @test reader[] == "gateway"
    end

    @testset "a nested immutable field is copied up to the cell" begin
        root = Cell(_plain_server())
        editor = _PlainOpEditor(nothing)
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(root, _plain_path(:window, :title), "Side"))
        @test root[].window == PlainOpWindow("Side", 800)
        @test root[].name == "gateway"
        evaluate_operation(editor, inverse)
        @test root[] == _plain_server()
    end

    @testset "a plain value in a cell field of a document is copied up to that field" begin
        holder = PlainOpHolder(_plain_server(), nothing)
        reader = _plain_reader(() -> holder.value.window.width)
        @test reader[] == 800
        editor = _PlainOpEditor(nothing)
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(holder, _plain_path(:value, :window, :width), 1024))
        @test holder.value.window.width == 1024
        @test reader[] == 1024
        # The way back carries the holder of the cell, not the plain parent that
        # the copy replaced.
        @test inverse.document === holder
        evaluate_operation(editor, inverse)
        @test holder.value == _plain_server()
    end

    @testset "a named tuple and a tuple are written by a copy" begin
        named = Cell((a = 1, b = "x"))
        evaluate_operation(_PlainOpEditor(nothing),
            ReplaceReferencedValueOperation(named, _plain_path(:b), "y"))
        @test named[] == (a = 1, b = "y")

        pair = Cell((10, 20, 30))
        editor = _PlainOpEditor(nothing)
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(pair, Reference(RangeReferenceStep(1, 2)), 21))
        @test pair[] == (10, 21, 30)
        evaluate_operation(editor, inverse)
        @test pair[] == (10, 20, 30)
    end

    @testset "a type with its own constructor adds a method of the copy seam" begin
        root = Cell(PlainOpPair(3))
        evaluate_operation(_PlainOpEditor(nothing),
            ReplaceReferencedValueOperation(root, _plain_path(:left), 5))
        @test root[].left == 5
        @test root[].right == 10
        @test_throws ArgumentError with_object_field(_plain_server(), :missing, 1)
    end

    @testset "a field of a mutable struct changes in place and its readers read again" begin
        counter = PlainOpCounter(1, 0.5)
        root = Cell(counter)
        reader = _plain_reader(() -> root[].count)
        @test reader[] == 1
        editor = _PlainOpEditor(nothing)
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(root, _plain_path(:count), 7))
        @test root[] === counter
        @test counter.count == 7
        @test reader[] == 7
        # A value converts to the declared type of the field.
        evaluate_operation(editor, ReplaceReferencedValueOperation(root, _plain_path(:ratio), 2))
        @test counter.ratio === 2.0
        evaluate_operation(editor, inverse)
        @test counter.count == 1
        @test reader[] == 1
    end

    @testset "an element of a plain vector changes in place and its readers read again" begin
        items = Any[1, 2, 3]
        root = Cell(items)
        reader = _plain_reader(() -> root[][2])
        @test reader[] == 2
        editor = _PlainOpEditor(nothing)
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(root, Reference(RangeReferenceStep(1, 2)), 20))
        @test root[] === items
        @test items == Any[1, 20, 3]
        @test reader[] == 20
        evaluate_operation(editor, inverse)
        @test items == Any[1, 2, 3]
        @test reader[] == 2
    end

    @testset "a plain value with no cell above it can not be written" begin
        server = _plain_server()
        @test_throws ErrorException evaluate_operation(_PlainOpEditor(nothing),
            ReplaceReferencedValueOperation(server, _plain_path(:name), "gw2"))
        counter = PlainOpCounter(1, 0.5)
        @test_throws ErrorException evaluate_operation(_PlainOpEditor(nothing),
            ReplaceReferencedValueOperation(counter, _plain_path(:count), 7))
        @test counter.count == 1
    end

    @testset "a field step on a dictionary still names no slot to write" begin
        root = Cell(Dict("a" => 1))
        @test_throws ErrorException evaluate_operation(_PlainOpEditor(nothing),
            ReplaceReferencedValueOperation(root, _plain_path(:a), 2))
    end

    @testset "a cell field of a document is written as it is" begin
        holder = PlainOpHolder(1, nothing)
        editor = _PlainOpEditor(nothing)
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(holder, "value", 2))
        @test holder.value == 2
        @test inverse.document === holder
        evaluate_operation(editor, inverse)
        @test holder.value == 1
    end

end
end # test_operations
