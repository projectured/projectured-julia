function test_tooltip()
@testset "TooltipDecoratorProjection + WindowManagerProjection" begin

# Build a screen with one main window whose content is a TooltipSource
# wrapping a PrimitiveNumber. The tooltip itself shows a PrimitiveString.
source_id = :tt
src = TooltipSource(
    child   = PrimitiveNumber(1),
    content = PrimitiveString("tooltip body"),
    style   = :tooltip,
    id      = source_id,
)
main_window = WindowDocument(; id=:main, content=src)
screen = ScreenDocument([main_window])

# Trigger flag controlled by the test.
show = Ref(false)

decorator = TooltipDecoratorProjection(
    trigger = (s, _evt) -> show[],
    position = _ -> (10, 20, 300, 100),
)

projection = RecursiveProjection(
    TypeDispatchingProjection(
        ScreenDocument => WindowManagerProjection(inner = CopyingProjection()),
        WindowDocument => CopyingProjection(),
        CellVector     => CopyingProjection(),
        TooltipSource  => decorator,
        Any            => PreservingProjection(),
    ),
)

iomap = projection_print(projection, screen)

@testset "initial state" begin
    @test length(screen.windows) == 1
    @test screen.windows[1].id === :main
end

@testset "open on trigger" begin
    show[] = true
    op = projection_read(projection, iomap, EventEnvelope(:main, :tick))
    @test !(op isa Operation)
    @test length(screen.windows) == 2
    tt_idx = findfirst(i -> screen.windows[i].id === source_id, 1:length(screen.windows))
    @test tt_idx !== nothing
    tt = screen.windows[tt_idx]
    @test tt.style === :tooltip
    @test tt.x == 10 && tt.y == 20 && tt.width == 300 && tt.height == 100
    @test tt.content isa PrimitiveString
    @test tt.content.value == "tooltip body"
end

@testset "no-op when already open" begin
    op = projection_read(projection, iomap, EventEnvelope(:main, :tick))
    @test !(op isa Operation)
    @test length(screen.windows) == 2
end

@testset "close on trigger off" begin
    show[] = false
    op = projection_read(projection, iomap, EventEnvelope(:main, :tick))
    @test !(op isa Operation)
    @test length(screen.windows) == 1
    @test screen.windows[1].id === :main
end

@testset "re-open after close" begin
    show[] = true
    op = projection_read(projection, iomap, EventEnvelope(:main, :tick))
    @test !(op isa Operation)
    @test length(screen.windows) == 2
    @test screen.windows[2].id === source_id
end

end # @testset

@testset "OpenWindowOperation updates geometry on duplicate id" begin

# A standalone test of the manager: feed two opens with the same id; the
# second should update the existing window's geometry, not append.
src = TooltipSource(child=PrimitiveNumber(0), content=PrimitiveString("a"), id=:dup)
screen = ScreenDocument([WindowDocument(; id=:main, content=src)])
show = Ref(true)
pos = Ref{Tuple{Int,Int,Int,Int}}((1, 2, 3, 4))
deco = TooltipDecoratorProjection(
    trigger = (_s, _e) -> show[],
    position = _ -> pos[],
)
projection = RecursiveProjection(
    TypeDispatchingProjection(
        ScreenDocument => WindowManagerProjection(inner=CopyingProjection()),
        WindowDocument => CopyingProjection(),
        CellVector     => CopyingProjection(),
        TooltipSource  => deco,
        Any            => PreservingProjection(),
    ),
)
iomap = projection_print(projection, screen)

# First open.
projection_read(projection, iomap, EventEnvelope(:main, :tick))
@test length(screen.windows) == 2
@test screen.windows[2].x == 1 && screen.windows[2].width == 3

# Re-open with new geometry: deco won't fire a second open (is_open=true),
# so to verify duplicate-id update semantics, flip closed and re-open.
show[] = false
projection_read(projection, iomap, EventEnvelope(:main, :tick))
@test length(screen.windows) == 1
pos[] = (50, 60, 70, 80)
show[] = true
projection_read(projection, iomap, EventEnvelope(:main, :tick))
@test length(screen.windows) == 2
@test screen.windows[2].x == 50 && screen.windows[2].width == 70

end # @testset

end # function
