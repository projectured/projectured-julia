# A row, a column and a grid of 60 cards in a scroll pane of a window of 1100 by 500
# pixels. Each card holds a picture whose pixels are a cell that records its read,
# as the pixel cell of a picture file is a cell that only a paint reads. The render
# and the dirty walk read the pictures of the cards that meet the clip, and no other.
function test_layout_render()
@testset "a row, a column and a grid paint only the cards that the clip shows" begin

SDL = ProjecturedSDL.SdlModule
projection_module = ProjecturedKernel.ProjectionModule
background = (0xff, 0xff, 0xff, 0xff)
card_size = 200

# 60 cards of `card_size` pixels. The pixels of card `k` are a cell that pushes `k`
# to `read` when something reads it, in a colour of its own.
function make_cards(read::Vector{Int})
    Any[GraphicsCanvas(Any[GraphicsImage(0, 0, card_size, card_size,
            Cell(Computation(() -> (push!(read, k);
                 repeat(UInt8[4 * k, 255 - 4 * k, 128, 255], card_size * card_size)))))];
        w = card_size, h = card_size) for k in 1:60]
end

# The layout of `kind` in a pane that grows on the axis of the layout, and the
# cell of the scroll position of the pane.
function make_pane(kind::Symbol, read::Vector{Int})
    scroll = Cell(Point2D(0, 0))
    layout = kind === :column ? VerticalLayout(make_cards(read)) : HorizontalLayout(make_cards(read))
    grows = kind === :column ? (width = false, height = true) : (width = true, height = false)
    (pane = WidgetScrollPane(layout; grows, scroll_position = scroll), layout = layout, scroll = scroll)
end

# A scroll of 300 pixels along the axis of `kind`.
make_scroll(kind::Symbol) = kind === :column ? Point2D(0, 300) : Point2D(300, 0)

function print_pane(pane)
    natural = RecursiveProjection(NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0)))
    offer = projection_module.with_exact_size(projection_module.PrinterContext();
                                              width = Cell(Int32(1100)), height = Cell(Int32(500)))
    print_document(natural, nothing, pane, offer)
end

function render!(output)
    off = SDL.open_offscreen_renderer(1100, 500; supersample = 1)
    try
        SDL._render_canvas_offscreen!(off, output, 1100, 500, background)
    finally
        SDL.close_offscreen_renderer(off)
    end
end

make_res() = SDL.SdlWindowResources(
    C_NULL, C_NULL, :test, UInt32(0), "t", 1100, 500, 0, 0, :default,
    (0x00, 0x00, 0x00, 0xff), 1, 1.0, 1.0, C_NULL, 0, 0, false,
    Dict{UInt,NTuple{4,Int}}(), SDL._PaintedGeometry(), Vector{NTuple{4,Int}}[], C_NULL)

function read_pixels(off)
    surface = unsafe_load(off.surface)
    copy(unsafe_wrap(Array, Ptr{UInt8}(surface.pixels), Int(surface.pitch) * Int(surface.h)))
end

# Paint `output` by the rectangles of the dirty walk into one renderer, and in full
# into another, once before the changes and once after each of them. Answer the
# frames whose pixels differ.
function find_differing_frames(output, changes)
    partial = SDL.open_offscreen_renderer(1100, 500; supersample = 1)
    full = SDL.open_offscreen_renderer(1100, 500; supersample = 1)
    differing = Int[]
    try
        state = SDL.make_offscreen_paint_state(partial)
        for (frame, change!) in enumerate(Any[() -> nothing; changes])
            change!()
            SDL.render_offscreen_changes!(partial, state, output; background)
            SDL._render_canvas_offscreen!(full, output, 1100, 500, background)
            read_pixels(partial) == read_pixels(full) || push!(differing, frame)
        end
    finally
        SDL.close_offscreen_renderer(partial)
        SDL.close_offscreen_renderer(full)
    end
    differing
end

# The cards whose box meets the window: a column of cards of 200 pixels shows cards 1 to 3 of
# 500 pixels, a row shows cards 1 to 6 of 1100.
shown = Dict(:column => [1, 2, 3], :row => [1, 2, 3, 4, 5, 6])
# After a scroll of 300 pixels the window starts in card 2 and ends where card 5 of a column
# starts (300 to 800), and where card 8 of a row starts (300 to 1400): neither is read.
shown_after = Dict(:column => [2, 3, 4], :row => [2, 3, 4, 5, 6, 7])

for kind in (:column, :row)
    @testset "a $kind: the render reads the cards that the clip shows" begin
        read = Int[]
        parts = make_pane(kind, read)
        iomap = print_pane(parts.pane)
        @test isempty(read)
        render!(iomap.output)
        @test sort(read) == shown[kind]
    end

    @testset "a $kind: a walk on a fresh print reads the same cards" begin
        read = Int[]
        iomap = print_pane(make_pane(kind, read).pane)
        @test SDL._compute_dirty_region(make_res(), iomap.output) !== nothing
        @test sort(read) == shown[kind]
    end

    @testset "a $kind: a scroll reads the cards that come on the screen and no other" begin
        read = Int[]
        parts = make_pane(kind, read)
        iomap = print_pane(parts.pane)
        render!(iomap.output)
        empty!(read)
        parts.scroll[] = make_scroll(kind)
        render!(iomap.output)
        @test sort(read) == setdiff(shown_after[kind], shown[kind])
    end

    @testset "a $kind: the pixels of a partial paint equal a full paint" begin
        read = Int[]
        parts = make_pane(kind, read)
        iomap = print_pane(parts.pane)
        differing = find_differing_frames(iomap.output,
            [() -> (parts.scroll[] = make_scroll(kind)), () -> (parts.scroll[] = Point2D(0, 0))])
        @test isempty(differing)
    end

    @testset "a $kind: a selected card shows its ring when a card after it lies past the far edge" begin
        read = Int[]
        parts = make_pane(kind, read)
        iomap = print_pane(parts.pane)
        off_plain = SDL.open_offscreen_renderer(1100, 500; supersample = 1)
        off_ring = SDL.open_offscreen_renderer(1100, 500; supersample = 1)
        try
            SDL._render_canvas_offscreen!(off_plain, iomap.output, 1100, 500, background)
            set_selection!(parts.layout, ConcreteReference(FieldReferenceStep("children"),
                ConcreteReference(RangeReferenceStep(1, 2), EmptyReference())))
            SDL._render_canvas_offscreen!(off_ring, iomap.output, 1100, 500, background)
            plain, ring = read_pixels(off_plain), read_pixels(off_ring)
            surface = unsafe_load(off_ring.surface)
            pitch = Int(surface.pitch)
            differing = [(div(i - 1, pitch), div(mod(i - 1, pitch), 4))
                         for i in eachindex(plain) if plain[i] != ring[i]]
            @test !isempty(differing)
            # The ring lies around card 2 only: its box starts at 190 on the axis.
            ys = extrema(first.(differing)); xs = extrema(last.(differing))
            around = kind === :column ? (xs[1] >= 0 && xs[2] <= card_size + 8 && ys[1] >= card_size - 8 && ys[2] <= 2 * card_size + 8) :
                                        (ys[1] >= 0 && ys[2] <= card_size + 8 && xs[1] >= card_size - 8 && xs[2] <= 2 * card_size + 8)
            @test around
        finally
            SDL.close_offscreen_renderer(off_plain)
            SDL.close_offscreen_renderer(off_ring)
        end
    end
end

# A grid of 60 cards in a scroll pane. `columns` is the count of columns and `policy` their
# policy. The cards touch: no gap. The cards of a row stand in the columns from the left, and the
# card in row `r` and column `c` is card `(r - 1) * columns + c`.
function make_grid_pane(columns::Int, policy, grows, read::Vector{Int})
    scroll = Cell(Point2D(0, 0))
    layout = GridLayout(make_cards(read), columns; column_policy = policy,
                        horizontal_gap = 0, vertical_gap = 0)
    (pane = WidgetScrollPane(layout; grows, scroll_position = scroll), layout = layout, scroll = scroll)
end

# The cards whose box meets the window in a grid of `columns` columns of `column_width` pixels,
# the window at (`scroll_x`, `scroll_y`) (the offset of its near corner) and 1100 by 500 pixels. A box that starts
# on the far edge is past it.
function compute_shown_cards(columns::Int, column_width::Int, scroll_x::Int, scroll_y::Int)
    shown = Int[]
    for k in 1:60
        row, column = div(k - 1, columns), mod(k - 1, columns)
        left, top = column * column_width, row * card_size
        left < scroll_x + 1100 && left + card_size > scroll_x &&
            top < scroll_y + 500 && top + card_size > scroll_y && push!(shown, k)
    end
    shown
end

# Three columns in a pane that grows down: with `Relative(1)` each column is a third of the
# window, with `Content` each is a card wide. In both the rows stand at 0, 200, 400, ... so
# three rows show.
tall = (width = false, height = true)
wide = (width = true, height = false)
for (name, policy, column_width) in (("Relative(1)", Relative(1), 1100 ÷ 3), ("Content", Content, card_size))
    cards = compute_shown_cards(3, column_width, 0, 0)
    cards_after = compute_shown_cards(3, column_width, 0, 300)
    @testset "a grid of 3 $name columns: the render reads the cards that the clip shows" begin
        @test cards == collect(1:9)
        read = Int[]
        parts = make_grid_pane(3, policy, tall, read)
        iomap = print_pane(parts.pane)
        @test isempty(read)
        render!(iomap.output)
        @test sort(read) == cards
    end

    @testset "a grid of 3 $name columns: a walk on a fresh print reads the same cards" begin
        read = Int[]
        iomap = print_pane(make_grid_pane(3, policy, tall, read).pane)
        @test SDL._compute_dirty_region(make_res(), iomap.output) !== nothing
        @test sort(read) == cards
    end

    @testset "a grid of 3 $name columns: a scroll reads the cards that come on the screen and no other" begin
        read = Int[]
        parts = make_grid_pane(3, policy, tall, read)
        iomap = print_pane(parts.pane)
        render!(iomap.output)
        empty!(read)
        parts.scroll[] = Point2D(0, 300)
        render!(iomap.output)
        @test cards_after == collect(4:12)
        @test sort(read) == setdiff(cards_after, cards)
    end

    @testset "a grid of 3 $name columns: the pixels of a partial paint equal a full paint" begin
        read = Int[]
        parts = make_grid_pane(3, policy, tall, read)
        iomap = print_pane(parts.pane)
        differing = find_differing_frames(iomap.output,
            [() -> (parts.scroll[] = Point2D(0, 300)), () -> (parts.scroll[] = Point2D(0, 0))])
        @test isempty(differing)
    end
end

# 12 columns of 200 pixels are 2400 wide, wider than the pane. The window shows the columns 1 to
# 6 (the sixth starts at 1000) of the rows 1 to 3 (the third starts at 400); scrolled by 300 to
# the side it shows the columns 2 to 7 (the seventh ends at 1400, the eighth starts there).
@testset "a grid wider than its pane: the render reads the cards of the columns on the screen" begin
    cards = compute_shown_cards(12, card_size, 0, 0)
    @test cards == [12 * r + c for r in 0:2 for c in 1:6]
    read = Int[]
    iomap = print_pane(make_grid_pane(12, Content, wide, read).pane)
    render!(iomap.output)
    @test sort(read) == cards
end

@testset "a grid wider than its pane: a walk on a fresh print reads the same cards" begin
    read = Int[]
    iomap = print_pane(make_grid_pane(12, Content, wide, read).pane)
    @test SDL._compute_dirty_region(make_res(), iomap.output) !== nothing
    @test sort(read) == compute_shown_cards(12, card_size, 0, 0)
end

@testset "a grid wider than its pane: a scroll to the side reads the cards of the columns that come on the screen" begin
    cards = compute_shown_cards(12, card_size, 0, 0)
    cards_after = compute_shown_cards(12, card_size, 300, 0)
    @test cards_after == [12 * r + c for r in 0:2 for c in 2:7]
    read = Int[]
    parts = make_grid_pane(12, Content, wide, read)
    iomap = print_pane(parts.pane)
    render!(iomap.output)
    empty!(read)
    parts.scroll[] = Point2D(300, 0)
    render!(iomap.output)
    @test sort(read) == setdiff(cards_after, cards)
end

@testset "a grid wider than its pane: the pixels of a partial paint equal a full paint" begin
    read = Int[]
    parts = make_grid_pane(12, Content, wide, read)
    iomap = print_pane(parts.pane)
    differing = find_differing_frames(iomap.output,
        [() -> (parts.scroll[] = Point2D(300, 0)), () -> (parts.scroll[] = Point2D(0, 0))])
    @test isempty(differing)
end

# A flow of 60 cards in a pane that grows down. The cards touch: no gap. A line holds as many
# cards as fit in `max_width`, and the card in line `r` and place `c` is card
# `(r - 1) * per_line + c`.
function make_flow_pane(max_width::Int, read::Vector{Int})
    scroll = Cell(Point2D(0, 0))
    layout = FlowLayout(make_cards(read); max_width, horizontal_gap = 0, vertical_gap = 0)
    (pane = WidgetScrollPane(layout; grows = tall, scroll_position = scroll), layout = layout, scroll = scroll)
end

# `max_width` 1000 puts 5 cards in a line and the lines at 0, 200, 400, ...: the window of 500
# shows the lines 1 to 3, the cards 1 to 15; after a scroll of 300 it shows the lines 2 to 4 (the
# fifth starts on the far edge), the cards 6 to 20. A `max_width` of 600 puts 3 cards in a line.
flow_cards = compute_shown_cards(5, card_size, 0, 0)
flow_cards_after = compute_shown_cards(5, card_size, 0, 300)

@testset "a flow: the render reads the cards of the lines that the clip shows" begin
    @test flow_cards == collect(1:15)
    read = Int[]
    iomap = print_pane(make_flow_pane(1000, read).pane)
    @test isempty(read)
    render!(iomap.output)
    @test sort(read) == flow_cards
end

@testset "a flow: a walk on a fresh print reads the same cards" begin
    read = Int[]
    iomap = print_pane(make_flow_pane(1000, read).pane)
    @test SDL._compute_dirty_region(make_res(), iomap.output) !== nothing
    @test sort(read) == flow_cards
end

@testset "a flow: a scroll reads the cards that come on the screen and no other" begin
    read = Int[]
    parts = make_flow_pane(1000, read)
    iomap = print_pane(parts.pane)
    render!(iomap.output)
    empty!(read)
    parts.scroll[] = Point2D(0, 300)
    render!(iomap.output)
    @test flow_cards_after == collect(6:20)
    @test sort(read) == setdiff(flow_cards_after, flow_cards)
end

@testset "a flow: a new width moves cards to other lines, and the pixels of a partial paint equal a full paint" begin
    read = Int[]
    parts = make_flow_pane(1000, read)
    iomap = print_pane(parts.pane)
    differing = find_differing_frames(iomap.output,
        [() -> (parts.layout.max_width = 600), () -> (parts.scroll[] = Point2D(0, 300)),
         () -> (parts.layout.max_width = 1000), () -> (parts.scroll[] = Point2D(0, 0))])
    @test isempty(differing)
end

@testset "a flow: a new width before the first paint reads the cards of the new lines" begin
    read = Int[]
    parts = make_flow_pane(1000, read)
    iomap = print_pane(parts.pane)
    parts.layout.max_width = 600
    render!(iomap.output)
    # Lines of 3 cards at 0, 200, 400: the cards 1 to 9 show.
    @test sort(read) == compute_shown_cards(3, card_size, 0, 0)
end

# The reference of card `k` in a flow of 5 cards in a line, printed alone: the canvas of the lines,
# the canvas of line `ceil(k / 5)`, and the wrapper of the card at its place in that line, then
# the card. Back, it is the card again.
@testset "a flow: the reference of a card maps forward through its line and back" begin
    read = Int[]
    flow_iomap = getfield(print_pane(make_flow_pane(1000, read).layout), :inner_iomap)
    flow_iomap isa Cell && (flow_iomap = flow_iomap[])
    @test flow_iomap isa ProjecturedPlatform.LayoutModule.FlowLayoutIoMap
    @test flow_iomap.lines == [cld(k, 5) for k in 1:60]
    projection = flow_iomap.projection
    step_of(reference, name) = (@test reference.head.name == name; reference.tail)
    index_of(reference) = (reference.head.start, reference.tail)
    for k in (1, 5, 6, 14, 60)
        card = ConcreteReference(FieldReferenceStep("children"),
                                 ConcreteReference(RangeReferenceStep(k - 1, k), EmptyReference()))
        forward = projection_module.map_reference_forward(projection, flow_iomap, card)
        @test forward !== nothing
        rest = step_of(forward, "elements")
        first_step, rest = index_of(rest)
        rest = step_of(rest, "elements")
        line_step, rest = index_of(rest)
        rest = step_of(rest, "elements")
        place_step, rest = index_of(rest)
        @test first_step == 0
        @test line_step == cld(k, 5) - 1
        @test place_step == mod(k - 1, 5)
        back = projection_module.map_reference_backward(projection, flow_iomap, forward)
        @test back !== nothing
        @test repr(strip_reference_types(back)) == repr(card)
    end
end

# Cards of 200 pixels with a title bar at the top and a picture from y = 100 on. The pixels of the
# picture of card `k` are a cell that pushes `k` to `read` when something reads it.
function make_titled_cards(read::Vector{Int})
    Any[GraphicsCanvas(Any[GraphicsRect(0, 0, card_size, 20),
                           GraphicsImage(0, 100, card_size, 100,
                               Cell(Computation(() -> (push!(read, k);
                                    repeat(UInt8[4 * k, 255 - 4 * k, 128, 255], card_size * 100)))))];
                       w = card_size, h = card_size) for k in 1:60]
end

@testset "a column: the edge of the pane cuts a card below its title and the card reads no picture" begin
    # The window ends at 500, where the picture of card 3 starts (400 + 100). Its title at 400 to
    # 420 shows, and its picture does not.
    read = Int[]
    pane = WidgetScrollPane(VerticalLayout(make_titled_cards(read));
                            grows = (width = false, height = true), scroll_position = Cell(Point2D(0, 0)))
    iomap = print_pane(pane)
    @test isempty(read)
    render!(iomap.output)
    @test sort(read) == [1, 2]
    read = Int[]
    iomap = print_pane(WidgetScrollPane(VerticalLayout(make_titled_cards(read));
                       grows = (width = false, height = true), scroll_position = Cell(Point2D(0, 0))))
    @test SDL._compute_dirty_region(make_res(), iomap.output) !== nothing
    @test sort(read) == [1, 2]
end

end
end
