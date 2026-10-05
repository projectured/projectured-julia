# The keyboard: every chord of the pane table, driven through the whole chain so
# the test sees what a real keystroke sees — the widget layers get their say
# first, and the pane table answers what they declined.
mutable struct _PaneGestureMockEditor
    document::Any
end

# A document that has a title of its own.
@document struct _PaneTitledContent <: Document
    name::Any
end
PaneModule.get_document_title(content::_PaneTitledContent) = String(content.name)

function test_pane_gestures()
@testset "PaneTree gestures" begin

_stub = FixedMeasure(10, 18, 6, 0)
_tab(name) = PaneTab(name, WidgetLabel(name))
# The example projection, so a fresh tab's own content (an empty text document)
# renders like it does in the real layout.
_chain() = make_pane_projection_example(measure = _stub)

# Press a chord and apply whatever it produced, then re-print: a structural edit
# changes the tree the next keystroke is read against.
function _press!(editor, chord)
    proj = _chain()
    iomap = print_document(proj, editor.document)
    op = read_intent(proj, iomap, chord)
    op === nothing || evaluate_operation(editor, op)
    op
end

_ctrl(key) = KeyDown(key, ModifierKeys(ctrl = true); time = 0.0)
_ctrl_shift(key) = KeyDown(key, ModifierKeys(ctrl = true, shift = true); time = 0.0)
_ctrl_alt(key) = KeyDown(key, ModifierKeys(ctrl = true, alt = true); time = 0.0)

# A tree of one group with two tabs, the first focused.
function _seeded()
    group = PaneGroup(PaneTab[_tab("a"), _tab("b")])
    tree = PaneTree(group)
    editor = _PaneGestureMockEditor(tree)
    evaluate_operation(editor, make_pane_focus_operation(tree, group, 1))
    (tree, group, editor)
end

@testset "Ctrl+T opens a tab in the focused group" begin
    tree, group, editor = _seeded()
    @test _press!(editor, _ctrl(:t)) !== nothing
    @test length(group.tabs) == 3
    @test get_pane_focus(tree) == (group, 3)
    @test get_pane_tab_title_string(group.tabs[3]) == "untitled"
    # The selection is on the new tab's empty content, as a whole, so a paste
    # fills it.
    @test string(strip_reference_types(get_selection(tree))) ==
          string(strip_reference_types(get_pane_content_path(tree, group, 3)))
    @test evaluate_reference(tree, get_selection(tree)) isa DocumentNothing
    # The tab's own keys still work from there.
    @test _press!(editor, KeyDown(:f2, ModifierKeys(); time = 0.0)) !== nothing
    @test get_pane_focus_title(tree) == (group, 3)
    _press!(editor, KeyDown(:escape, ModifierKeys(); time = 0.0))
    _press!(editor, _ctrl(:w))
    @test length(group.tabs) == 2
end

@testset "a tab with an empty name is called after what it holds" begin
    tab = default_new_pane_tab()
    @test get_pane_tab_title_string(tab) == "untitled"
    tab.content = _PaneTitledContent("results")
    @test get_pane_tab_title_string(tab) == "results"
    tab.title.name.value = "mine"
    @test get_pane_tab_title_string(tab) == "mine"
    tab.title.name.value = ""
    @test get_pane_tab_title_string(tab) == "results"
    tab.content = _PaneTitledContent("   ")
    @test get_pane_tab_title_string(tab) == "untitled"
end

@testset "a split selects the empty content of its new tab" begin
    tree, group, editor = _seeded()
    _press!(editor, _ctrl(:backslash))
    right = tree.root.elements[2]
    @test get_pane_focus(tree) == (right, 1)
    @test evaluate_reference(tree, get_selection(tree)) === right.tabs[1].content
    @test right.tabs[1].content isa DocumentNothing
end

@testset "Ctrl+W closes the focused tab" begin
    tree, group, editor = _seeded()
    kept = group.tabs[2]
    _press!(editor, _ctrl(:w))
    @test length(group.tabs) == 1
    @test group.tabs[1] === kept
end

@testset "Ctrl+Shift+D duplicates the focused tab" begin
    tree, group, editor = _seeded()
    original = group.tabs[1]
    @test _press!(editor, _ctrl_shift(:d)) !== nothing
    @test length(group.tabs) == 3
    @test get_pane_focus(tree) == (group, 2)
    @test get_pane_tab_title_string(group.tabs[2]) == "a (2)"
    @test group.tabs[2].content !== original.content
    @test group.tabs[2].content.content == "a"
    # The plain chord is not the duplicate.
    @test _press!(editor, _ctrl(:d)) === nothing
    @test length(group.tabs) == 3
end

@testset "Ctrl+backslash splits vertically, the new pane on the right" begin
    tree, group, editor = _seeded()
    _press!(editor, _ctrl(:backslash))
    @test tree.root isa PaneSplit
    @test tree.root.orientation === :vertical
    @test tree.root.elements[1] === group
    @test get_pane_focus(tree)[1] === tree.root.elements[2]
end

@testset "Ctrl+Shift+backslash splits horizontally, the new pane below" begin
    tree, group, editor = _seeded()
    _press!(editor, _ctrl_shift(:backslash))
    @test tree.root isa PaneSplit
    @test tree.root.orientation === :horizontal
    @test tree.root.elements[1] === group
end

@testset "Ctrl+Alt and an arrow move the focus in that direction" begin
    tree, group, editor = _seeded()
    _press!(editor, _ctrl(:backslash))             # a second group, on the right
    right = tree.root.elements[2]
    @test get_pane_focus(tree)[1] === right

    _press!(editor, _ctrl_alt(:left))
    @test get_pane_focus(tree)[1] === group
    _press!(editor, _ctrl_alt(:right))
    @test get_pane_focus(tree)[1] === right
    # Nothing lies further right, so the focus stays.
    _press!(editor, _ctrl_alt(:right))
    @test get_pane_focus(tree)[1] === right
    # Nothing lies above or below a side-by-side pair either.
    _press!(editor, _ctrl_alt(:up))
    @test get_pane_focus(tree)[1] === right
end

@testset "Ctrl+Tab traverses the groups and wraps around" begin
    tree, group, editor = _seeded()
    _press!(editor, _ctrl(:backslash))
    right = tree.root.elements[2]
    @test get_pane_focus(tree)[1] === right

    _press!(editor, _ctrl(:tab))
    @test get_pane_focus(tree)[1] === group            # wrapped past the end
    _press!(editor, _ctrl(:tab))
    @test get_pane_focus(tree)[1] === right
    _press!(editor, _ctrl_shift(:tab))
    @test get_pane_focus(tree)[1] === group
end

@testset "Ctrl+PageDown and Ctrl+PageUp walk the tabs of the focused group" begin
    tree, group, editor = _seeded()
    @test get_pane_focus(tree) == (group, 1)
    _press!(editor, _ctrl(:page_down))
    @test get_pane_focus(tree) == (group, 2)
    _press!(editor, _ctrl(:page_down))
    @test get_pane_focus(tree) == (group, 1)           # wrapped
    _press!(editor, _ctrl(:page_up))
    @test get_pane_focus(tree) == (group, 2)
end

@testset "the chords still reach the pane with the caret inside a text document" begin
    # The reason the table needs modifiers at all: the plain keys belong to the
    # content. Put the caret *in* a text document and press each chord — the text
    # layer must decline every one of them, and the pane must act.
    group = PaneGroup(PaneTab[PaneTab("a", PrimitiveString("hello")),
                              PaneTab("b", PrimitiveString("world"))])
    tree = PaneTree(group)
    editor = _PaneGestureMockEditor(tree)
    caret = @reference ::PaneTree.root::PaneGroup.tabs::CellVector[1]::PaneTab.content::PrimitiveString.value::String{2}::Position
    evaluate_operation(editor, ReplaceSelectionOperation(caret))

    @test _press!(editor, _ctrl(:t)) !== nothing
    @test length(group.tabs) == 3

    _seed!() = evaluate_operation(editor, ReplaceSelectionOperation(caret))
    _seed!(); @test _press!(editor, _ctrl(:page_down)) !== nothing
    _seed!(); @test _press!(editor, _ctrl(:backslash)) !== nothing
    @test tree.root isa PaneSplit
    # With two groups there is somewhere to traverse to; with one there is not,
    # and Ctrl+Tab rightly does nothing.
    @test _press!(editor, _ctrl(:tab)) !== nothing
end

@testset "an unfocused tree declines every chord" begin
    tree = PaneTree(PaneGroup(PaneTab[_tab("a")]))
    editor = _PaneGestureMockEditor(tree)
    # Nothing is selected, so there is no focused group to act on. The one
    # exception is the traversal, which starts the focus at the first group.
    @test _press!(editor, _ctrl(:t)) === nothing
    @test _press!(editor, _ctrl(:w)) === nothing
    @test _press!(editor, _ctrl(:backslash)) === nothing
    @test _press!(editor, _ctrl_alt(:right)) === nothing
    @test _press!(editor, _ctrl(:tab)) !== nothing
    @test get_pane_focus(tree)[1] === tree.root
end

@testset "an empty group takes a new tab but has none to close" begin
    group = PaneGroup(PaneTab[])
    tree = PaneTree(group)
    editor = _PaneGestureMockEditor(tree)
    evaluate_operation(editor, make_pane_focus_operation(tree, group, 0))
    @test _press!(editor, _ctrl(:w)) === nothing
    @test _press!(editor, _ctrl(:t)) !== nothing
    @test length(group.tabs) == 1
    @test get_pane_focus(tree) == (group, 1)
end

@testset "Alt and an arrow walk from a whole tab, and stay inside its content" begin
    tree, group, editor = _seeded()
    _alt(key) = KeyDown(key, ModifierKeys(alt = true); time = 0.0)
    whole_tab(i) = strip_reference_types(get_selection(tree)) ==
                   strip_reference_types(get_pane_tab_reference(tree, group, i))
    whole_content(i) = strip_reference_types(get_selection(tree)) ==
                       strip_reference_types(get_pane_content_path(tree, group, i))
    @test whole_tab(1)
    # Sideways from a whole tab: its neighbour, and the ends stay.
    _press!(editor, _alt(:right))
    @test whole_tab(2)
    _press!(editor, _alt(:right))
    @test whole_tab(2)
    _press!(editor, _alt(:left))
    @test whole_tab(1)
    _press!(editor, _alt(:left))
    @test whole_tab(1)
    # A whole tab is the top of the walk.
    _press!(editor, _alt(:up))
    @test whole_tab(1)
    # Down is the tab's content, as a whole, and not its title.
    _press!(editor, _alt(:down))
    @test whole_content(1)
    @test evaluate_reference(tree, get_selection(tree)) === group.tabs[1].content
    # The content has no sibling: the title is not an object of the content.
    _press!(editor, _alt(:right))
    @test whole_content(1)
    _press!(editor, _alt(:left))
    @test whole_content(1)
end

end # testset
end # function
