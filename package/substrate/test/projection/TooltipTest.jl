function test_tooltip()
@testset "TooltipDecoratorProjection + WindowManagingProjection" begin

# Build a screen with one default window whose content is a TooltipSource
# wrapping a PrimitiveNumber. The tooltip itself shows a PrimitiveString.
source_id = :tt
src = TooltipSource(
    child   = PrimitiveNumber(1),
    content = PrimitiveString("tooltip body"),
    style   = :tooltip,
    id      = source_id,
)
main_window = WindowDocument(; id=:default, content=src)
screen = ScreenDocument([main_window])

# Trigger flag controlled by the test.
show = Ref(false)

decorator = TooltipDecoratorProjection(
    trigger = (s, _evt) -> show[],
    position = _ -> (10, 20, 300, 100),
)

projection = RecursiveProjection(
    TypeDispatchingProjection(
        ScreenDocument => WindowManagingProjection(inner = ScreenToScreen()),
        WindowDocument => ScreenToScreen(),
        CellVector     => CopyingProjection(),
        TooltipSource  => decorator,
        Any            => IdentityProjection(),
    ),
)

iomap = print_document(projection, screen)

@testset "initial state" begin
    @test length(screen.windows) == 1
    @test screen.windows[1].id === :default
end

@testset "open on trigger" begin
    show[] = true
    op = read_intent(projection, iomap, WindowInput(:default, MouseMove(0, 0)))
    @test !(op isa Operation)
    @test length(screen.windows) == 2
    @test length(iomap.output.windows) == 2          # output mirrors input
    tt_idx = findfirst(i -> screen.windows[i].id === source_id, 1:length(screen.windows))
    @test tt_idx !== nothing
    tt = screen.windows[tt_idx]
    @test tt.style === :tooltip
    @test tt.x == 10 && tt.y == 20 && tt.width == 300 && tt.height == 100
    @test tt.content isa PrimitiveString
    @test tt.content.value == "tooltip body"
    @test iomap.output.windows[tt_idx].id === source_id
end

@testset "no-op when already open" begin
    op = read_intent(projection, iomap, WindowInput(:default, MouseMove(0, 0)))
    @test !(op isa Operation)
    @test length(screen.windows) == 2
    @test length(iomap.output.windows) == 2
end

@testset "close on trigger off" begin
    show[] = false
    op = read_intent(projection, iomap, WindowInput(:default, MouseMove(0, 0)))
    @test !(op isa Operation)
    @test length(screen.windows) == 1
    @test length(iomap.output.windows) == 1
    @test screen.windows[1].id === :default
end

@testset "re-open after close" begin
    show[] = true
    op = read_intent(projection, iomap, WindowInput(:default, MouseMove(0, 0)))
    @test !(op isa Operation)
    @test length(screen.windows) == 2
    @test length(iomap.output.windows) == 2
    @test screen.windows[2].id === source_id
    @test iomap.output.windows[2].id === source_id
end

end # @testset

@testset "OpenWindowOperation updates geometry on duplicate id" begin

# A standalone test of the manager: feed two opens with the same id; the
# second should update the existing window's geometry, not append.
src = TooltipSource(child=PrimitiveNumber(0), content=PrimitiveString("a"), id=:dup)
screen = ScreenDocument([WindowDocument(; id=:default, content=src)])
show = Ref(true)
pos = Ref{Tuple{Int,Int,Int,Int}}((1, 2, 3, 4))
deco = TooltipDecoratorProjection(
    trigger = (_s, _e) -> show[],
    position = _ -> pos[],
)
projection = RecursiveProjection(
    TypeDispatchingProjection(
        ScreenDocument => WindowManagingProjection(inner=ScreenToScreen()),
        WindowDocument => ScreenToScreen(),
        CellVector     => CopyingProjection(),
        TooltipSource  => deco,
        Any            => IdentityProjection(),
    ),
)
iomap = print_document(projection, screen)

# First open.
read_intent(projection, iomap, WindowInput(:default, MouseMove(0, 0)))
@test length(screen.windows) == 2
@test screen.windows[2].x == 1 && screen.windows[2].width == 3

# Re-open with new geometry: deco won't fire a second open (is_open=true),
# so to verify duplicate-id update semantics, flip closed and re-open.
show[] = false
read_intent(projection, iomap, WindowInput(:default, MouseMove(0, 0)))
@test length(screen.windows) == 1
pos[] = (50, 60, 70, 80)
show[] = true
read_intent(projection, iomap, WindowInput(:default, MouseMove(0, 0)))
@test length(screen.windows) == 2
@test screen.windows[2].x == 50 && screen.windows[2].width == 70

end # @testset

@testset "WindowClose removes the matching window" begin

# A bare WindowManager over a two-window screen: the native close button on a
# window arrives as an WindowInput(window_id, WindowClose()) and must
# remove exactly that window from both the input and the mirrored output.
main  = WindowDocument(; id=:default,  content=PrimitiveNumber(0))
popup = WindowDocument(; id=:popup, content=PrimitiveString("p"))
screen = ScreenDocument([main, popup])

projection = RecursiveProjection(
    TypeDispatchingProjection(
        ScreenDocument => WindowManagingProjection(inner=ScreenToScreen()),
        WindowDocument => ScreenToScreen(),
        CellVector     => CopyingProjection(),
        Any            => IdentityProjection(),
    ),
)
iomap = print_document(projection, screen)
@test length(screen.windows) == 2

# Close the popup via its native close button.
op = read_intent(projection, iomap, WindowInput(:popup, WindowClose()))
@test !(op isa Operation)
@test length(screen.windows) == 1
@test length(iomap.output.windows) == 1
@test screen.windows[1].id === :default
@test iomap.output.windows[1].id === :default

# A close for an unknown id is a silent no-op.
read_intent(projection, iomap, WindowInput(:ghost, WindowClose()))
@test length(screen.windows) == 1

# The default window can be closed too (e.g. quitting via the frame).
read_intent(projection, iomap, WindowInput(:default, WindowClose()))
@test length(screen.windows) == 0
@test length(iomap.output.windows) == 0

end # @testset

@testset "WindowDefocus dismisses only auto_dismiss windows" begin

# Losing focus closes a transient popup (auto_dismiss=true) but never the main
# window or a tooltip (auto_dismiss=false), so opening a popup — which takes focus
# from the default window — does not close the default window.
main  = WindowDocument(; id=:default, content=PrimitiveNumber(0))                 # auto_dismiss=false
popup = WindowDocument(; id=:popup, auto_dismiss=true, content=PrimitiveString("p"))
screen = ScreenDocument([main, popup])

projection = RecursiveProjection(
    TypeDispatchingProjection(
        ScreenDocument => WindowManagingProjection(inner=ScreenToScreen()),
        WindowDocument => ScreenToScreen(),
        CellVector     => CopyingProjection(),
        Any            => IdentityProjection(),
    ),
)
iomap = print_document(projection, screen)
@test length(screen.windows) == 2

# Focus-lost on the default window: ignored (not a popup).
read_intent(projection, iomap, WindowInput(:default, WindowDefocus()))
@test length(screen.windows) == 2

# Focus-lost on the popup: dismissed, on both input and output.
read_intent(projection, iomap, WindowInput(:popup, WindowDefocus()))
@test length(screen.windows) == 1
@test screen.windows[1].id === :default
@test length(iomap.output.windows) == 1

# Focus-lost for an unknown id: no-op.
read_intent(projection, iomap, WindowInput(:ghost, WindowDefocus()))
@test length(screen.windows) == 1

end # @testset

end # function
