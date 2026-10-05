# Renaming a tab in place. There is no rename mode and no rename operation: the
# title is a text document, the caret being in it is the editing state, and the
# keystrokes are answered by the title's own gesture table.
mutable struct _PaneRenameMockEditor
    document::Any
end

function test_pane_rename()
@testset "PaneTree rename" begin

_stub = FixedMeasure(10, 18, 6, 0)
_chain() = make_pane_projection_example(measure = _stub)

function _press!(editor, event)
    proj = _chain()
    iomap = print_document(proj, editor.document)
    op = read_intent(proj, iomap, event)
    op === nothing || evaluate_operation(editor, op)
    op
end

_type!(editor, text) = for c in text
    _press!(editor, KeyPress(c, ModifierKeys(); time = 0.0))
end

function _seeded()
    group = PaneGroup(PaneTab[PaneTab("notes", PrimitiveString("body")),
                              PaneTab("other", PrimitiveString(""))])
    tree = PaneTree(group)
    editor = _PaneRenameMockEditor(tree)
    evaluate_operation(editor, make_pane_focus_operation(tree, group, 1))
    (tree, group, editor)
end

@testset "F2 puts the caret at the end of the name" begin
    tree, group, editor = _seeded()
    @test get_pane_focus_title(tree) === nothing
    @test _press!(editor, KeyDown(:f2, ModifierKeys(); time = 0.0)) !== nothing
    @test get_pane_focus_title(tree) == (group, 1)
    # The caret sits after the last character, so typing appends.
    _type!(editor, "!")
    @test get_pane_tab_title_string(group.tabs[1]) == "notes!"
end

@testset "typing edits the name and nothing else" begin
    tree, group, editor = _seeded()
    _press!(editor, KeyDown(:f2, ModifierKeys(); time = 0.0))
    _type!(editor, " today")
    @test get_pane_tab_title_string(group.tabs[1]) == "notes today"
    # The tab's content is untouched — the keys went to the name.
    @test group.tabs[1].content.value == "body"
    @test get_pane_tab_title_string(group.tabs[2]) == "other"
end

@testset "backspace and delete work in the name" begin
    tree, group, editor = _seeded()
    _press!(editor, KeyDown(:f2, ModifierKeys(); time = 0.0))
    _press!(editor, KeyDown(:backspace, ModifierKeys(); time = 0.0))
    @test get_pane_tab_title_string(group.tabs[1]) == "note"
    _press!(editor, KeyDown(:backspace, ModifierKeys(); time = 0.0))
    @test get_pane_tab_title_string(group.tabs[1]) == "not"
end

@testset "Escape leaves the name and the caret returns to the tab" begin
    tree, group, editor = _seeded()
    _press!(editor, KeyDown(:f2, ModifierKeys(); time = 0.0))
    @test get_pane_focus_title(tree) == (group, 1)
    @test _press!(editor, KeyDown(:escape, ModifierKeys(); time = 0.0)) !== nothing
    @test get_pane_focus_title(tree) === nothing
    @test get_pane_focus(tree) == (group, 1)
    # And typing no longer touches the name.
    before = get_pane_tab_title_string(group.tabs[1])
    _type!(editor, "x")
    @test get_pane_tab_title_string(group.tabs[1]) == before
end

@testset "the pane chords still work while the caret is in a name" begin
    tree, group, editor = _seeded()
    _press!(editor, KeyDown(:f2, ModifierKeys(); time = 0.0))
    @test _press!(editor, KeyDown(:t, ModifierKeys(ctrl = true); time = 0.0)) !== nothing
    @test length(group.tabs) == 3
end

@testset "a fresh tab is renamed the moment it is opened" begin
    # What the empty start state does: open a tab, name it, open another.
    tree = PaneTree(PaneGroup(PaneTab[]))
    group = tree.root
    editor = _PaneRenameMockEditor(tree)
    evaluate_operation(editor, make_pane_focus_operation(tree, group, 0))
    _press!(editor, KeyDown(:t, ModifierKeys(ctrl = true); time = 0.0))
    @test get_pane_tab_title_string(group.tabs[1]) == "untitled"

    _press!(editor, KeyDown(:f2, ModifierKeys(); time = 0.0))
    for _ in 1:length("untitled")
        _press!(editor, KeyDown(:backspace, ModifierKeys(); time = 0.0))
    end
    _type!(editor, "readme")
    @test get_pane_tab_title_string(group.tabs[1]) == "readme"
end

# The tabbed pane of a tree of one group: the pane layer is the first element of
# the composite that the tree prints as.
_tab_bar(iomap) = iomap.step_iomaps[1][].output.elements[1]
_steps(reference) = reference === nothing ? nothing :
                    get_reference_steps(strip_reference_types(reference))

@testset "the tab bar holds the caret in the name" begin
    tree, group, editor = _seeded()
    _press!(editor, KeyDown(:f2, ModifierKeys(); time = 0.0))
    caret() = _steps(get_stored_selection(_tab_bar(print_document(_chain(), editor.document))))
    steps = caret()
    @test steps[1:4] == [FieldReferenceStep("selector_element_pairs"), ElementReferenceStep(1),
                         FieldReferenceStep("selector"), FieldReferenceStep("text")]
    @test (steps[5].start, steps[5].stop) == (5, 5)
    # The caret follows the typing.
    _type!(editor, "!")
    @test (caret()[5].start, caret()[5].stop) == (6, 6)
    # Out of the name, the tab bar names the tab and holds no caret.
    _press!(editor, KeyDown(:escape, ModifierKeys(); time = 0.0))
    @test caret() == [FieldReferenceStep("selector_element_pairs"), ElementReferenceStep(1)]
end

# Every caret drawn, at its place: the text domain draws a caret as a rectangle
# 2 pixels wide, and a text with no caret draws that rectangle 0 pixels wide.
function _carets(node, ox = 0, oy = 0, found = Tuple{Int,Int}[], depth = 0)
    depth > 60 && return found
    if node isa GraphicsRect
        Int(node.w) == 2 && Int(node.h) > 0 && push!(found, (ox + Int(node.x), oy + Int(node.y)))
    elseif node isa GraphicsCanvas
        for i in 1:length(node.elements)
            _carets(node.elements[i], ox + Int(node.x), oy + Int(node.y), found, depth + 1)
        end
    elseif node isa GraphicsViewport
        _carets(node.content, ox + Int(node.x), oy + Int(node.y), found, depth + 1)
    end
    found
end

@testset "the tab bar draws the caret in the name" begin
    tree, group, editor = _seeded()
    drawn() = _carets(get_iomap_output(print_document(_chain(), editor.document)))
    @test isempty(drawn())
    _press!(editor, KeyDown(:f2, ModifierKeys(); time = 0.0))
    at_end = only(drawn())
    # The stub measures 10 pixels for each character, so one more character moves
    # the caret 10 pixels to the right.
    _type!(editor, "!")
    @test only(drawn()) == (at_end[1] + 10, at_end[2])
    _press!(editor, KeyDown(:escape, ModifierKeys(); time = 0.0))
    @test isempty(drawn())
end

@testset "F2 on an empty group does nothing" begin
    group = PaneGroup(PaneTab[])
    tree = PaneTree(group)
    editor = _PaneRenameMockEditor(tree)
    evaluate_operation(editor, make_pane_focus_operation(tree, group, 0))
    @test _press!(editor, KeyDown(:f2, ModifierKeys(); time = 0.0)) === nothing
end

@testset "a rename edits the name and keeps the icon and the badges" begin
    finished = Cell(1)
    title = PaneTabTitle("tasks"; icon = :loader,
                         badges = () -> Any[WidgetBadge(string(finished[], "/3"); role = :accent)],
                         tooltip = "the tasks")
    group = PaneGroup(PaneTab[PaneTab(title, PrimitiveString("body"))])
    tree = PaneTree(group)
    editor = _PaneRenameMockEditor(tree)
    evaluate_operation(editor, make_pane_focus_operation(tree, group, 1))
    _press!(editor, KeyDown(:f2, ModifierKeys(); time = 0.0))
    _type!(editor, "!")
    tab = group.tabs[1]
    @test get_pane_tab_title_string(tab) == "tasks!"
    @test tab.title === title
    @test tab.title.icon === :loader
    @test tab.title.tooltip == "the tasks"
    # The badges still follow their cell after the rename.
    finished[] = 2
    @test only(tab.title.badges).content == "2/3"
    # The strip draws the label of the title: the name, the icon and the badge.
    label = _tab_bar(print_document(_chain(), editor.document)).selector_element_pairs[1].selector
    @test label isa WidgetTabLabel
    @test label.text == "tasks!" && label.icon === :loader
    @test only(label.badges).content == "2/3"
end

@testset "a file builds a title from a name with an icon beside it" begin
    serialization = ProjecturedPlatform.SerializationModule
    body = PrimitiveString("body")
    old = serialization.make_pred_document(PaneTab, (),
        Pair{Symbol,Any}[:title => PrimitiveString("plot"), :content => body, :icon => :chart])
    @test old.title isa PaneTabTitle
    @test get_pane_tab_title_string(old) == "plot" && old.title.icon === :chart
    new = serialization.make_pred_document(PaneTab, (),
        Pair{Symbol,Any}[:title => PaneTabTitle("plot"; icon = :chart), :content => body])
    @test get_pane_tab_title_string(new) == "plot" && new.title.icon === :chart
    # What a file writes of a title is the name and the values of its parts.
    _, keywords = serialization.pred_arguments(PaneTabTitle("plot"; icon = () -> :chart))
    @test Dict(keywords)[:icon] === :chart
end

end # testset
end # function
