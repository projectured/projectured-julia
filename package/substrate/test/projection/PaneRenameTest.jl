# Renaming a tab in place. There is no rename mode and no rename operation: the
# title is a text document, the caret being in it is the editing state, and the
# keystrokes are answered by the title's own gesture table.
mutable struct _PaneRenameMockEditor
    document::Any
end

function test_pane_rename()
@testset "PaneTree rename" begin

_stub(t, f) = (max(1, length(t)) * 10, 24)
_chain() = make_pane_projection_example(measure = _stub)

function _press!(editor, event)
    proj = _chain()
    iomap = print_document(proj, editor.document)
    op = read_intent(proj, iomap, event)
    op === nothing || evaluate_operation(editor, op)
    op
end

_type!(editor, text) = for c in text
    _press!(editor, KeyPress(c, ModifierKeys()))
end

function _seeded()
    group = PaneGroup(PaneTab[PaneTab("notes", PrimitiveString("body")),
                              PaneTab("other", PrimitiveString(""))])
    tree = PaneTree(group)
    editor = _PaneRenameMockEditor(tree)
    evaluate_operation(editor, pane_focus_operation(tree, group, 1))
    (tree, group, editor)
end

@testset "F2 puts the caret at the end of the name" begin
    tree, group, editor = _seeded()
    @test pane_focus_title(tree) === nothing
    @test _press!(editor, KeyDown(:f2, ModifierKeys())) !== nothing
    @test pane_focus_title(tree) == (group, 1)
    # The caret sits after the last character, so typing appends.
    _type!(editor, "!")
    @test pane_tab_title_string(group.tabs[1]) == "notes!"
end

@testset "typing edits the name and nothing else" begin
    tree, group, editor = _seeded()
    _press!(editor, KeyDown(:f2, ModifierKeys()))
    _type!(editor, " today")
    @test pane_tab_title_string(group.tabs[1]) == "notes today"
    # The tab's content is untouched — the keys went to the name.
    @test group.tabs[1].content.value == "body"
    @test pane_tab_title_string(group.tabs[2]) == "other"
end

@testset "backspace and delete work in the name" begin
    tree, group, editor = _seeded()
    _press!(editor, KeyDown(:f2, ModifierKeys()))
    _press!(editor, KeyDown(:backspace, ModifierKeys()))
    @test pane_tab_title_string(group.tabs[1]) == "note"
    _press!(editor, KeyDown(:backspace, ModifierKeys()))
    @test pane_tab_title_string(group.tabs[1]) == "not"
end

@testset "Escape leaves the name and the caret returns to the tab" begin
    tree, group, editor = _seeded()
    _press!(editor, KeyDown(:f2, ModifierKeys()))
    @test pane_focus_title(tree) == (group, 1)
    @test _press!(editor, KeyDown(:escape, ModifierKeys())) !== nothing
    @test pane_focus_title(tree) === nothing
    @test pane_focus(tree) == (group, 1)
    # And typing no longer touches the name.
    before = pane_tab_title_string(group.tabs[1])
    _type!(editor, "x")
    @test pane_tab_title_string(group.tabs[1]) == before
end

@testset "the pane chords still work while the caret is in a name" begin
    tree, group, editor = _seeded()
    _press!(editor, KeyDown(:f2, ModifierKeys()))
    @test _press!(editor, KeyDown(:t, ModifierKeys(ctrl = true))) !== nothing
    @test length(group.tabs) == 3
end

@testset "a fresh tab is renamed the moment it is opened" begin
    # What the empty start state does: open a tab, name it, open another.
    tree = PaneTree(PaneGroup(PaneTab[]))
    group = tree.root
    editor = _PaneRenameMockEditor(tree)
    evaluate_operation(editor, pane_focus_operation(tree, group, 0))
    _press!(editor, KeyDown(:t, ModifierKeys(ctrl = true)))
    @test pane_tab_title_string(group.tabs[1]) == "untitled"

    _press!(editor, KeyDown(:f2, ModifierKeys()))
    for _ in 1:length("untitled")
        _press!(editor, KeyDown(:backspace, ModifierKeys()))
    end
    _type!(editor, "readme")
    @test pane_tab_title_string(group.tabs[1]) == "readme"
end

@testset "F2 on an empty group does nothing" begin
    group = PaneGroup(PaneTab[])
    tree = PaneTree(group)
    editor = _PaneRenameMockEditor(tree)
    evaluate_operation(editor, pane_focus_operation(tree, group, 0))
    @test _press!(editor, KeyDown(:f2, ModifierKeys())) === nothing
end

end # testset
end # function
