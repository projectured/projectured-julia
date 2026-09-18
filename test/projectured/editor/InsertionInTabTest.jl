# A person opens an empty tab and makes a document in it with the keyboard only.
#
# `Ctrl+T` opens a tab that holds a `DocumentNothing` and puts the cursor on the
# placeholder. The Insert key turns the placeholder into a `DocumentInsertion`,
# the name buffer. The buffer draws its prompt, narrows as the person types, and
# Enter commits the typed name to a fresh document.
#
# The whole sequence runs through **one standing iomap**, as a live editor keeps
# it. A fresh print for each step would hide the case this test is for: a row
# that the renderer resolves once and then reuses.

using Test

# `evaluate_operation` reads the `document` field of an editor.
mutable struct _InsertTabMockEditor; document::Any; end

function test_insertion_in_tab()
@testset "A tab makes a document from the Insert key" begin

_stub(t, f) = (max(1, length(t)) * 10, 24)

# The layout starts with one tab, not with an empty group. A group that was
# printed with no tab does not draw the first tab that arrives — the standing
# iomap keeps the empty pane it printed — so the key would reach nothing. That is
# a defect of its own, older than this test, and it is reproduced on `main`.
tree = PaneTree(PaneGroup(PaneTab[PaneTab("first", PrimitiveString("x"))]))
editor = _InsertTabMockEditor(tree)
projection = make_pane_json_projection_example(measure = _stub)
iomap = print_document(projection, nothing, tree,
                       PrinterContext(EmptyReference(), Cell(800), Cell(600),
                                      Dict{Symbol,Any}()))

# One gesture, read through the standing iomap and applied.
function press!(event)
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(editor, operation)
    operation
end

type!(text) = for c in text; press!(KeyPress(c, ModifierKeys())); end

# What the tab that has the focus holds.
function content()
    focus = get_pane_focus(tree)
    focus === nothing && return nothing
    group, index = focus
    index == 0 ? nothing : group.tabs[index].content
end

# Every word the canvas draws, joined. A `show` of the canvas elides the nested
# elements, so it can not answer what a leaf deep in the tree says.
function drawn(node = get_iomap_output(iomap), depth = 0)
    depth > 40 && return ""
    node isa GraphicsText && return String(node.text) * " "
    node isa GraphicsCanvas &&
        return join([drawn(node.elements[i], depth + 1) for i in 1:length(node.elements)])
    node isa GraphicsViewport && return drawn(node.content, depth + 1)
    ""
end

@testset "Ctrl+T opens a tab on an empty placeholder" begin
    # Ctrl+Tab gives the first tab the focus, as opening a window does.
    press!(KeyDown(:tab, ModifierKeys(ctrl = true)))
    press!(KeyDown(:t, ModifierKeys(ctrl = true)))
    @test length(get_pane_groups(tree)[1].tabs) == 2
    @test content() isa DocumentNothing
    # The cursor is on the placeholder, not on the tab. Without this the Insert
    # key below reaches the tab strip and nothing happens.
    @test get_selection(tree) !== nothing
end

@testset "Insert turns the placeholder into the name buffer" begin
    press!(KeyDown(:insert, ModifierKeys()))
    @test content() isa DocumentInsertion
end

@testset "The name buffer draws its prompt" begin
    # The row this test was written for. Without it the buffer reflects as a
    # struct with a `value` field, and a person sees no prompt at all.
    @test occursin("Insert a new", drawn())
end

@testset "A typed name narrows and commits" begin
    type!("json")
    # @broken: a printable key does not reach the name buffer. The caret is on
    # `content.value{0}`, and the text layer needs the FORWARD image of that path
    # to place it. `_tab_forward` splices the content image with the `^` operator
    # of `@reference`, which moves the spliced path's leading type onto the node
    # before it — the same defect the backward map had. Fix the forward map the
    # same way, with `concat_references`.
    @test_broken occursin("json", drawn())
    press!(KeyDown(:enter, ModifierKeys()))
    # "json" is the alias `@domain Json` gives its own insertion, and an exact
    # name wins over every prefix, so the commit is unambiguous.
    # @broken: nothing was typed, so there is no name to commit.
    @test_broken content() isa JsonInsertion
end

end
end
