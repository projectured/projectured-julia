# A row and a column of 60 cards in a scroll pane of a window of 1100 by 500
# pixels. Each card holds a picture whose pixels are a cell that records its read,
# as the pixel cell of a picture file is a cell that only a paint reads. The render
# and the dirty walk read the pictures of the cards that meet the clip, and no other.
function test_layout_render()
@testset "a row and a column paint only the cards that the clip shows" begin

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

end
end
