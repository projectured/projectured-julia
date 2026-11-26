# `MemoryModule`: the walk of `compute_held_memory` on small graphs. Each case
# builds a graph whose bytes are known, and checks the total, the holders with
# their paths, and what the walk does not follow.

using Test

mutable struct _HeldBox
    value::Any
end

mutable struct _HeldPair
    left::Any
    right::Any
end

# Each holder of `report` by its path.
_get_held_paths(report) = Dict(holder.path => holder for holder in report.holders)

# The report with every holder that passes the rule of the largest part.
_compute_every_holder(root) = compute_held_memory(root; minimum_bytes = 0, minimum_share = 0, limit = 1000)

# The bytes of a list of `n` bytes: the list, and its memory with its header.
_get_byte_list_bytes(n) = sizeof(Vector{UInt8}) + 2 * sizeof(Int) + n

function test_held_memory()
@testset "what holds the memory of a root" begin
    @testset "a chain: the holder is the list at its end" begin
        root = _HeldBox(_HeldBox(_HeldBox(zeros(UInt8, 100_000))))
        report = compute_held_memory(root; minimum_bytes = 1000)
        @test report.total_bytes == 3 * sizeof(_HeldBox) + _get_byte_list_bytes(100_000)
        @test report.object_count == 5
        @test report.root_type === _HeldBox
        holder = only(report.holders)
        @test holder.path == ".value.value.value"
        @test holder.type === Vector{UInt8}
        @test holder.bytes == _get_byte_list_bytes(100_000)
        @test holder.object_count == 2
    end

    @testset "a diamond: a shared object counts once, under the holder of both paths" begin
        shared = zeros(UInt8, 100_000)
        root = _HeldPair(_HeldBox(shared), _HeldBox(shared))
        report = _compute_every_holder(root)
        @test report.total_bytes == sizeof(_HeldPair) + 2 * sizeof(_HeldBox) + _get_byte_list_bytes(100_000)
        paths = _get_held_paths(report)
        # The shortest path names the list; neither box keeps it.
        @test paths[".left.value"].bytes == _get_byte_list_bytes(100_000)
        @test paths[".left"].bytes == sizeof(_HeldBox)
        @test paths[".right"].bytes == sizeof(_HeldBox)
        @test !haskey(paths, ".right.value")
    end

    @testset "a weak reference: the walk does not follow its value" begin
        payload = zeros(UInt8, 100_000)
        root = _HeldBox(WeakRef(payload))
        GC.@preserve payload begin
            report = compute_held_memory(root)
            @test report.total_bytes == sizeof(_HeldBox) + sizeof(WeakRef)
            @test report.object_count == 2
        end
    end

    @testset "a cycle: the walk ends, and the holder is on the cycle" begin
        first_pair = _HeldPair(nothing, nothing)
        second_pair = _HeldPair(first_pair, zeros(UInt8, 100_000))
        first_pair.left = second_pair
        report = compute_held_memory(first_pair; minimum_bytes = 1000)
        @test report.total_bytes == 2 * sizeof(_HeldPair) + _get_byte_list_bytes(100_000)
        @test only(report.holders).path == ".left.right"
    end

    @testset "a closure: the walk enters it through its captured fields" begin
        kept = let data = zeros(UInt8, 100_000)
            () -> length(data)
        end
        @test only(compute_held_memory(_HeldBox(kept); minimum_bytes = 1000).holders).path == ".value.data"
        # A captured variable that the closure writes is in a box, which gives no step.
        written = let shown = nothing
            () -> (shown = zeros(UInt8, 100_000); length(shown))
        end
        written()
        @test only(compute_held_memory(_HeldBox(written); minimum_bytes = 1000).holders).path == ".value.shown"
    end

    @testset "a list of structs that hold references" begin
        items = [_HeldBox(zeros(UInt8, 50_000)) for _ in 1:3]
        report = _compute_every_holder(_HeldBox(items))
        paths = _get_held_paths(report)
        @test paths[".value"].type === Vector{_HeldBox}
        @test paths[".value"].bytes == sizeof(Vector{_HeldBox}) + 2 * sizeof(Int) + 3 * sizeof(Ptr{Cvoid}) +
                                       3 * (sizeof(_HeldBox) + _get_byte_list_bytes(50_000))
        @test all(index -> paths[".value[$index].value"].bytes == _get_byte_list_bytes(50_000), 1:3)
        # The memory of a list belongs to the list: no line names it.
        @test !any(holder -> holder.type <: GenericMemory, report.holders)
        # After an element goes from the start, an index is that of the list.
        popfirst!(items)
        paths = _get_held_paths(_compute_every_holder(_HeldBox(items)))
        @test haskey(paths, ".value[1].value") && haskey(paths, ".value[2].value")
        @test !haskey(paths, ".value[3].value")
    end

    @testset "a long list and a long dictionary" begin
        items = Any[_HeldBox(index) for index in 1:100]
        items[77] = _HeldBox(zeros(UInt8, 100_000))
        @test only(compute_held_memory(_HeldBox(items); minimum_bytes = 1000).holders).path == ".value[77].value"
        table = Dict{Any, Any}(index => index for index in 1:100)
        table[55] = zeros(UInt8, 100_000)
        @test only(compute_held_memory(_HeldBox(table); minimum_bytes = 1000).holders).path == ".value[55]"
    end

    @testset "elements that a list holds in place" begin
        root = _HeldBox(Tuple{Int, Any}[(1, zeros(UInt8, 10)), (2, zeros(UInt8, 100_000))])
        @test only(compute_held_memory(root; minimum_bytes = 1000).holders).path == ".value[2][2]"
    end

    @testset "the entries of a dictionary" begin
        root = _HeldBox(Dict{Any, Any}("big" => zeros(UInt8, 100_000), "small" => zeros(UInt8, 10)))
        holder = only(compute_held_memory(root; minimum_bytes = 1000).holders)
        @test holder.path == ".value[\"big\"]"
        # A key that is an object: its type and a mark of its identity, which stays
        # while the key lives, also when the table grows.
        key = _HeldBox(1)
        table = IdDict{Any, Any}(key => zeros(UInt8, 100_000))
        path = only(compute_held_memory(_HeldBox(table); minimum_bytes = 1000).holders).path
        @test occursin(r"^\.value\[#[0-9a-f]{6} _HeldBox\]$", path)
        foreach(index -> table[_HeldBox(index)] = index, 1:100)
        @test only(compute_held_memory(_HeldBox(table); minimum_bytes = 1000).holders).path == path
        root = _HeldBox(IdDict{Any, Any}(_HeldBox(zeros(UInt8, 100_000)) => 1))
        path = only(compute_held_memory(root; minimum_bytes = 1000).holders).path
        @test occursin(r"^\.value\[#[0-9a-f]{6} _HeldBox\]\.key\.value$", path)
        # A key that is a type shows the type.
        root = _HeldBox(Dict{Any, Any}(Vector{Int} => zeros(UInt8, 100_000)))
        @test only(compute_held_memory(root; minimum_bytes = 1000).holders).path == ".value[Array{Int64, 1}]"
    end

    @testset "a cell gives no step" begin
        root = _HeldBox(Cell(_HeldBox(zeros(UInt8, 100_000))))
        @test only(compute_held_memory(root; minimum_bytes = 1000).holders).path == ".value.value"
    end

    @testset "a task: the walk enters it through its result" begin
        task = Task(() -> zeros(UInt8, 100_000))
        schedule(task)
        wait(task)
        @test only(compute_held_memory(_HeldBox(task); minimum_bytes = 1000).holders).path == ".value.result"
    end

    @testset "a type and a module count by their own size" begin
        report = compute_held_memory(_HeldBox(Vector{Int}))
        @test report.total_bytes == sizeof(_HeldBox) + sizeof(DataType)
        @test report.unwalked_bytes == sizeof(DataType)
        # The walk does not walk into a module, and a module counts no bytes.
        report = compute_held_memory(_HeldBox(Base))
        @test report.object_count == 2 && report.total_bytes == sizeof(_HeldBox)
    end

    @testset "the bytes of each type" begin
        root = _HeldBox([zeros(UInt8, 10) for _ in 1:4])
        types = Dict(type.type => type for type in compute_held_memory(root).types)
        @test types[Vector{UInt8}].object_count == 4
        @test types[Vector{UInt8}].bytes == 4 * sizeof(Vector{UInt8})
        @test types[_HeldBox].object_count == 1
    end

    @testset "the text of a report" begin
        report = compute_held_memory(_HeldBox(_HeldBox(zeros(UInt8, 100_000))); minimum_bytes = 1000)
        text = sprint(show, MIME"text/plain"(), report)
        @test startswith(text, "The _HeldBox reaches 97.7 KiB in 4 objects.")
        @test occursin(".value.value  Array{UInt8, 1}", text)
        @test occursin("The walk needed", text)
        @test sprint(show, report) == "HeldMemory(97.7 KiB in 4 objects)"
    end
end
end
