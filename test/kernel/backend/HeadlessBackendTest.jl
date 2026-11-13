"""
`HeadlessBackend` — the dependency-free in-memory backend test double. Exercises
construction, the lifecycle no-ops, the write and read paths, how far a paint reads
into a list, and the defaults of `get_display_size`, `get_pointer_position`,
`find_system_colors`, `configure_devices!` and `open_native_windows!`.
"""

using Test
using ProjecturedKernel.BackendModule
using ProjecturedKernelExample
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.EventModule: SystemColors

# A link of a list that the paint walks, as a `ListNode` is: a value, and a cell
# that holds the next link or makes it.
struct _HeadlessPaintLink
    value::Any
    next::Any
end

# A drawn part whose elements are a list.
struct _HeadlessPaintCanvas
    elements::Any
end

# A link of an endless lazy list whose values hold a block of `size` bytes, which
# the paint does not walk; each link that a read makes adds one to `made`.
function _make_headless_lazy_link(made::Ref{Int}, size::Int)
    made[] += 1
    _HeadlessPaintLink(Ref(zeros(UInt8, size)), Cell(@computation _make_headless_lazy_link(made, size)))
end

function test_headless_backend()
@testset "HeadlessBackend" begin

    @testset "HeadlessBackend() constructs a Backend" begin
        b = HeadlessBackend()
        @test b isa HeadlessBackend
        @test b isa Backend
    end

    @testset "lifecycle is a no-op" begin
        b = HeadlessBackend()
        @test initialize_backend!(b) === nothing
        @test quit_backend!(b) === nothing
    end

    @testset "write_to_devices! logs the document" begin
        b = HeadlessBackend()
        write_to_devices!(b, Any[], :first)
        write_to_devices!(b, Any[], :second)
        @test rendered_output(b) == [:first, :second]
    end

    @testset "a paint reads as far into a lazy list as the paint before it" begin
        made = Ref(0)
        canvas = _HeadlessPaintCanvas(_make_headless_lazy_link(made, 10_000))
        b = HeadlessBackend()
        write_to_devices!(b, Any[], canvas)
        # The first paint makes the links of its viewport, 200 from the head.
        @test made[] == 200
        GC.gc()
        live = Base.gc_live_bytes()
        foreach(_ -> write_to_devices!(b, Any[], canvas), 1:20)
        GC.gc()
        # A paint with nothing new makes no link and keeps no memory: a paint that
        # made 200 links more each time kept 40 MB here.
        @test made[] == 200
        @test Base.gc_live_bytes() - live < 4 * 2^20
    end

    @testset "a paint follows a written link past the viewport" begin
        reads = Ref(0)
        head = nothing
        for k in 300:-1:1
            head = _HeadlessPaintLink(Cell(@computation (reads[] += 1; k)), Cell(head))
        end
        write_to_devices!(HeadlessBackend(), Any[], _HeadlessPaintCanvas(head))
        @test reads[] == 300
    end

    @testset "take_from_devices! pops the scripted queue" begin
        b = HeadlessBackend()
        @test take_from_devices!(b, Any[]) === nothing
        push_event!(b, :ev1)
        push_event!(b, :ev2)
        @test take_from_devices!(b, Any[]) === :ev1
        @test take_from_devices!(b, Any[]) === :ev2
        @test take_from_devices!(b, Any[]) === nothing
    end

    @testset "get_display_size falls back to the display-free default" begin
        b = HeadlessBackend()
        @test get_display_size(b) == (1280, 800)
    end

    @testset "get_pointer_position falls back to (-1, -1)" begin
        @test get_pointer_position(HeadlessBackend()) == (-1, -1)
    end

    @testset "find_system_colors falls back to nothing, and the double answers its script" begin
        @test invoke(find_system_colors, Tuple{Backend}, HeadlessBackend()) === nothing
        @test find_system_colors(HeadlessBackend()) === nothing
        dark = SystemColors(; mode = :dark)
        @test find_system_colors(HeadlessBackend(; system_colors = dark)) === dark
    end

    @testset "open_native_windows! is a no-op for a backend with no windows" begin
        @test open_native_windows!(HeadlessBackend(), :document) === nothing
    end

    @testset "configure_devices! is a no-op for a backend that discovers nothing" begin
        b = HeadlessBackend()
        s = Display()
        @test configure_devices!(b, Device[s, Mouse(), Keyboard()]) === nothing
        @test (s.width, s.height, s.density) == (1280, 800, 1.0)   # unchanged
    end

end
end # test_headless_backend
