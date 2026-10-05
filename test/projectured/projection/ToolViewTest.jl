# A tool view draws in a tab because its own slice told the renderer how.
#
# A person opens a tool by typing its name into an empty tab, and the tab then
# holds an ordinary document. Nothing about that tab knows what a tool is: it
# draws its content through the render-anything projection, the same one that
# draws a JSON file or a table. So each tool registers one row from its own
# `__init__`, the way the file system slice already does, and no application
# names a tool anywhere.
#
# The failure this test is for is silent. A document no row claims falls through
# to the reflection tail and renders as its field names, or as the phrase "no
# natural rendering for X" — a person sees a page of nothing useful rather than
# an error.

using Test

# `evaluate_operation` reads the `document` field of an editor.
mutable struct _ToolViewMockEditor; document::Any; end

function test_tool_views()
@testset "every tool view draws itself" begin

_stub = FixedMeasure(10, 18, 6, 0)

# Every word the canvas draws, joined.
function drawn(node, depth = 0)
    depth > 40 && return ""
    node isa GraphicsText && return String(node.text) * " "
    node isa GraphicsCanvas &&
        return join([drawn(node.elements[i], depth + 1) for i in 1:length(node.elements)])
    node isa GraphicsViewport && return drawn(node.content, depth + 1)
    ""
end

function render(document)
    iomap = print_document(NaturalToGraphics(measure = _stub), nothing, document,
                           PrinterContext(EmptyReference(), Cell(600), Cell(400),
                                          Dict{Symbol,Any}()))
    drawn(get_iomap_output(iomap))
end

# Each tool is built the way the insertion builds it: with no argument at all.
# A tool that needs one is a tool a person cannot open by typing its name.
@testset "a tool takes no argument" begin
    @test Assistant() isa Document
    @test GestureLog() isa Document
    @test ReferenceInspector() isa Document
end

@testset "the renderer claims each tool" begin
    for tool in (Assistant(), GestureLog(), ReferenceInspector())
        @test !occursin("no natural rendering", render(tool))
    end
    # The reflection tail draws the fields of a table that no row claims, so
    # the phrase is not enough. The head line is what `FrameStatisticsToWidget`
    # draws, and the fields do not say it.
    @test occursin("0 frames", render(FrameStatistics()))
    # The plot draws through the chart renderer, which writes the chart title.
    @test occursin("Frame times", render(FrameTimeSeries()))
end

@testset "the file explorer opens by name, seeded" begin
    # `Workspace()` holds no folder, and an empty explorer shows nothing. A
    # person who opens one by name gets the working directory in it.
    explorer = make_insertion_document(Workspace)
    @test length(explorer.folders) == 1
    @test resolve_insertion(Document, "explorer") === Workspace
    @test get_pane_tab_title_string(PaneTab("", explorer)) == "Explorer"
    @test !occursin("no natural rendering", render(explorer))
end

# The file system slice declares the intent to open a file, and the slice that
# knows where to put one defines what happens. Without that inversion the
# explorer could not draw without the pane tree, which owns the operation.
@testset "opening a file is an intent the file system declares" begin
    @test OpenFileOperation("a.json") isa Operation
    # It carries its own subject and names no reference, so every reader between
    # the click and the editor passes it up unchanged.
    @test is_self_contained_operation(OpenFileOperation("a.json"))
end

@testset "a file names the tab that holds it" begin
    # A tab with no name of its own is called after what it holds. A file holds
    # its own name, and the base name is what fits a tab strip.
    @test get_document_title(JsonFile("a.json", JsonNull())) == "a.json"
    @test get_pane_tab_title_string(PaneTab("", JsonFile("a.json", JsonNull()))) == "a.json"
end

# The insertion reaches each tool by its own name, which is what makes
# Ctrl+T, Insert, a name, Enter work.
@testset "the insertion resolves each tool by name" begin
    @test resolve_insertion(Document, "Assistant") === Assistant
    @test resolve_insertion(Document, "GestureLog") === GestureLog
    @test resolve_insertion(Document, "ReferenceInspector") === ReferenceInspector
end

end
end

# The selection view shows one selection, and its `source` says which.
#
# Four forms answer, and the type of what the field holds picks the form. The
# case that needs care is the function: a plain cell would store it as a value
# and the view would show nothing, so a function goes into a computed cell whose
# thunk it becomes. The assertion that proves it is the type the field reads
# back as — a reference, not a function.
function test_selection_inspector()
@testset "the selection view follows what its source names" begin

_stub = FixedMeasure(10, 18, 6, 0)

function drawn(node, depth = 0)
    depth > 40 && return ""
    node isa GraphicsText && return String(node.text) * " "
    node isa GraphicsCanvas &&
        return join([drawn(node.elements[i], depth + 1) for i in 1:length(node.elements)])
    node isa GraphicsViewport && return drawn(node.content, depth + 1)
    ""
end

function make_context(root)
    context = PrinterContext(EmptyReference(), Cell(600), Cell(400), Dict{Symbol,Any}())
    root === nothing ? context : with_property(context, :root, root)
end

render(document; root = nothing) =
    drawn(get_iomap_output(print_document(NaturalToGraphics(measure = _stub),
                                          nothing, document, make_context(root))))

# A document with a caret in it, to point the four forms at.
other = PrimitiveString("hello")
at(k) = extend_reference(EmptyReference(PrimitiveString), PositionReferenceStep(k))
set_selection!(other, at(2))

@testset "no source shows the editor's own selection" begin
    # The editor hands its document to the printer under `:root`. Without that
    # there is nothing to show, and the view says so rather than drawing a blank.
    @test occursin("no selection", render(SelectionInspector()))
    @test occursin("2", render(SelectionInspector(); root = other))
end

@testset "a document source shows that document's selection" begin
    @test occursin("2", render(SelectionInspector(other)))
end

@testset "a reference source shows that reference" begin
    @test occursin("2", render(SelectionInspector(at(2)); root = other))
end

@testset "a function source goes into a computed cell" begin
    view = SelectionInspector(() -> get_selection(other))
    # The field answers the reference the function produced, not the function.
    # A plain value cell would answer the function itself and draw nothing.
    @test view.source isa Reference
    @test occursin("2", render(view))
end

@testset "the view follows a selection that moves" begin
    # One standing render, as a live editor keeps it. A printer that read the
    # selection as a value would freeze the view at the first draw.
    view = SelectionInspector(other)
    iomap = print_document(NaturalToGraphics(measure = _stub), nothing, view,
                           make_context(other))
    before = drawn(get_iomap_output(iomap))
    set_selection!(other, at(4))
    after = drawn(get_iomap_output(iomap))
    @test before != after
    @test occursin("4", after)
end

@testset "an inspector prints its subtree with the clock of the editor" begin
    # Each inspector derives the context of what it prints from the context it
    # gets, so an animation in the subtree follows the clock of the editor.
    clock = Clock()
    context = with_clock(make_context(other), clock)
    empty!(_PROBED_CLOCKS)
    # A text block computes its spans when they are read.
    view = SelectionInspector(_ClockProbeReference())
    shown = print_document(SelectionInspectorToText(), nothing, view, context).output
    length(shown.elements)
    probe = ReferenceInspector(reference = _ClockProbeReference())
    shown = print_document(ReferenceInspectorToText(), nothing, probe, context).output
    length(shown.elements)
    @test length(_PROBED_CLOCKS) == 4
    @test all(probed -> probed === clock, _PROBED_CLOCKS)
end

end
end

# A reference whose two renderings record the clock of the context they get.
struct _ClockProbeReference <: Reference end
const _PROBED_CLOCKS = Any[]
function _print_clock_probe(projection, reference, context)
    push!(_PROBED_CLOCKS, context.clock)
    SimpleIoMap(projection, reference, TextBlock(TextDocument[]))
end
ProjectionModule.print_document(p::ReferenceToText, recursion,
                                reference::_ClockProbeReference, ctx) =
    _print_clock_probe(p, reference, ctx)
ProjectionModule.print_document(p::ReferenceToHumanReadableText, recursion,
                                reference::_ClockProbeReference, ctx) =
    _print_clock_probe(p, reference, ctx)

# A gesture log opened in a tab fills while a person works.
#
# What records is a decorator at the root of the projection, and it records into
# the log it holds. A log a person opens is therefore the session's own log, not
# a fresh empty one — a fresh one would draw an empty list for ever.
#
# There is one editor and one history of what a person did to it, so two logs
# show the same entries. A view that shows only part of that history is a filter
# over this log, not a log of its own.
function test_gesture_log_in_tab()
@testset "a gesture log in a tab fills" begin

_stub = FixedMeasure(10, 18, 6, 0)

log = get_session_gesture_log()
clear_gesture_log!(log)

@testset "opening a log by name gives the session's own" begin
    @test make_insertion_document(GestureLog) === log
    # Two tabs, one history. This is the ruling, not an accident of sharing.
    @test make_insertion_document(GestureLog) === make_insertion_document(GestureLog)
    # A log built by hand is still an empty one, which a test wants.
    @test isempty(GestureLog().entries)
end

@testset "a gesture the pane claims reaches the log" begin
    tree = PaneTree(PaneGroup(PaneTab[PaneTab("first", PrimitiveString("x"))]))
    editor = _ToolViewMockEditor(tree)
    projection = GestureLogRecordingProjection(
        inner = make_pane_json_projection_example(measure = _stub), log = log)
    iomap = print_document(projection, nothing, tree,
                           PrinterContext(EmptyReference(), Cell(800), Cell(600),
                                          Dict{Symbol,Any}()))
    function press!(event)
        change = read_intent(projection, nothing, Intent(event), iomap)
        operation = change isa Intent ? change.operation : change
        operation === nothing || evaluate_operation(editor, operation)
        operation
    end
    # A layout with no selection has no focus, and a layout gesture needs one.
    press!(KeyDown(:tab, ModifierKeys(ctrl = true); time = 0.0))
    before = length(log.entries)
    @test press!(KeyDown(:t, ModifierKeys(ctrl = true); time = 0.0)) !== nothing
    @test length(log.entries) > before
end

clear_gesture_log!(log)

end
end

# A log view captures what the program says.
#
# The capture is a Julia logger installed for the session. It records each
# message into the store of the session and then forwards it to the logger it
# replaced, so the terminal still shows what it showed. The feed moves the
# stored lines into the log, once per frame in an editor, and here by a drain
# that the test calls. A log a person opens by name is the session's own log,
# because a fresh empty one would never fill.
function test_message_log()
@testset "a log view captures log statements" begin

_stub = FixedMeasure(10, 18, 6, 0)

function drawn(node, depth = 0)
    depth > 40 && return ""
    node isa GraphicsText && return String(node.text) * " "
    node isa GraphicsCanvas &&
        return join([drawn(node.elements[i], depth + 1) for i in 1:length(node.elements)])
    node isa GraphicsViewport && return drawn(node.content, depth + 1)
    ""
end

log = get_session_message_log()
feed = MessageLogFeed(store = get_session_message_log_store(), log = log)
clear_message_log!(log)
# The store can hold lines that another test of the session logged.
take_message_lines!(get_session_message_log_store())
previous = install_message_log_capture!()
try
    @testset "the capture records and forwards" begin
        @info "a message the log view keeps"
        @warn "and a warning"
        # The capture writes the store, and only the drain writes the log.
        @test length(log.entries) == 0
        @test drain_changes!(feed, nothing) == 2
        @test length(log.entries) == 2
        @test any(occursin("a message the log view keeps", String(log.entries[i].message))
                  for i in 1:length(log.entries))
    end

    @testset "a second install does not double every message" begin
        # Each install wraps the current logger, so two of them would record
        # every message twice and the view would read as if the program said
        # everything twice.
        install_message_log_capture!()
        before = length(log.entries)
        @info "once"
        @test drain_changes!(feed, nothing) == 1
        @test length(log.entries) == before + 1
    end

    @testset "the view draws what it captured" begin
        text = drawn(get_iomap_output(
            print_document(NaturalToGraphics(measure = _stub), nothing, log,
                           PrinterContext(EmptyReference(), Cell(600), Cell(400),
                                          Dict{Symbol,Any}()))))
        @test !occursin("no natural rendering", text)
        @test occursin("a message the log view keeps", text)
    end
finally
    remove_message_log_capture!(previous)
    take_message_lines!(get_session_message_log_store())
    clear_message_log!(log)
end

@testset "a person opens it by name" begin
    @test make_insertion_document(MessageLog) === log
    @test resolve_insertion(Document, "log") === MessageLog
    @test get_document_title(MessageLog()) == "Log"
end

end
end
