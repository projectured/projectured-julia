# A fault in one element of the output, met while the renderer reads it, costs
# that element: the renderer skips it and draws the rest, and the editor that
# paints records the fault. Outside the paint of an editor the fault goes on, so
# a test sees it.

# A backend that the editor of this test only holds: the test renders itself.
struct PaintFaultTestBackend <: ProjecturedKernel.BackendModule.Backend end

function test_paint_fault()
@testset "a fault in one element costs that element" begin

SDL = ProjecturedSDL.SdlModule
background = (0xff, 0xff, 0xff, 0xff)

# Three rows; row 2 throws when its content is read. `read` records each row whose
# content the renderer read.
function read_row(read::Vector{Int}, k::Int)
    k == 2 && error("row 2 is broken")
    push!(read, k)
    Any[GraphicsRect(0, 0, 100, 10)]
end

make_row(read::Vector{Int}, k::Int) =
    GraphicsCanvas(CellVector(Computation(() -> read_row(read, k))); y = (k - 1) * 10,
                   w = 100, h = 10)

function make_column(read::Vector{Int})
    rows = CellVector(Cell[Cell(make_row(read, k)) for k in 1:3])
    GraphicsCanvas(Any[GraphicsCanvas(rows; w = 100, h = 30)]; w = 800, h = 600)
end

function render(window)
    off = SDL.open_offscreen_renderer(800, 600; supersample = 1)
    try
        SDL._render_canvas_offscreen!(off, window, 800, 600, background)
    finally
        SDL.close_offscreen_renderer(off)
    end
end

function make_painting_editor(policy)
    editor = Editor(GraphicsCanvas(Any[]; w = 1, h = 1), IdentityProjection();
                    backend = PaintFaultTestBackend(), devices = Device[])
    editor.fault_policy = policy
    editor
end

paint(editor, window) =
    Base.ScopedValues.with(() -> render(window),
                           ProjecturedKernel.EditorModule._PAINTING_EDITOR => editor)

@testset "outside the paint of an editor the fault goes on" begin
    @test_throws ErrorException render(make_column(Int[]))
end

@testset "a strict editor lets the fault go on" begin
    editor = make_painting_editor(make_strict_fault_policy())
    @test_throws ErrorException paint(editor, make_column(Int[]))
end

@testset "an editor with its barriers on draws the other rows" begin
    editor = make_painting_editor(FaultPolicy(is_console_enabled = false,
                                              is_sound_enabled = false))
    read = Int[]
    paint(editor, make_column(read))
    @test read == [1, 3]
    records = get_fault_records(editor.faults)
    @test length(records) == 1
    @test only(records).site === :print
    @test only(records).origin === :GraphicsCanvas
end

end
end
