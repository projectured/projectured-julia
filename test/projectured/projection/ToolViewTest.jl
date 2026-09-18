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

_stub(t, f) = (max(1, length(t)) * 10, 24)

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

_stub(t, f) = (max(1, length(t)) * 10, 24)

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

end
end

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

_stub(t, f) = (max(1, length(t)) * 10, 24)

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
    press!(KeyDown(:tab, ModifierKeys(ctrl = true)))
    before = length(log.entries)
    @test press!(KeyDown(:t, ModifierKeys(ctrl = true))) !== nothing
    @test length(log.entries) > before
end

clear_gesture_log!(log)

end
end
