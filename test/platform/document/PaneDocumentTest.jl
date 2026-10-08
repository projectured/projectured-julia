# Pane-tree surgery. Each builder returns a generic operation, so every test here
# evaluates that operation against a mock editor and asserts the tree it leaves —
# and, where it matters, that the surviving nodes are the *same objects*.
mutable struct _PaneMockEditor
    document::Any
end

function test_pane_surgery()
@testset "PaneTree surgery" begin

_tab(name) = PaneTab(name, PrimitiveString("content of $name"))

# Apply a builder's operation and answer it, so a test can assert on both.
function _apply!(editor, op)
    op === nothing && return nothing
    evaluate_operation(editor, op)
    op
end

# A tree of one group with `n` tabs.
function _flat(n::Int)
    tabs = PaneTab[_tab(string('a' + i - 1)) for i in 1:n]
    group = PaneGroup(tabs)
    tree = PaneTree(group)
    (tree, group, tabs)
end

@testset "paths resolve, and carry their node types" begin
    tree, group, tabs = _flat(2)
    @test evaluate_reference(tree, get_pane_path(tree, group)) === group
    @test evaluate_reference(tree, get_pane_tab_reference(tree, group, 2)) === tabs[2]
    @test evaluate_reference(tree, get_pane_collection_path(tree, group, :tabs)) === group.tabs
    # The type checkpoints are folded into the nodes, so a path built by the
    # surgery is fully typed and compares equal to the annotated form.
    @test get_pane_tab_reference(tree, group, 1) ==
          annotate_reference_types(tree, strip_reference_types(get_pane_tab_reference(tree, group, 1)))
    # A group's path when it is the whole tree, and a tab index of 0.
    @test get_pane_tab_reference(tree, group, 0) == get_pane_path(tree, group)
    @test get_pane_path(tree, PaneGroup(PaneTab[])) === nothing
end

@testset "focus is the selection" begin
    tree, group, tabs = _flat(3)
    editor = _PaneMockEditor(tree)
    @test get_pane_focus(tree) === nothing                 # nothing selected yet
    _apply!(editor, make_pane_focus_operation(tree, group, 2))
    @test get_pane_focus(tree) == (group, 2)
    @test get_pane_focused_group(tree) === group
    @test get_pane_focused_tab_index(tree) == 2
    # An empty group is named whole.
    empty_tree = PaneTree(PaneGroup(PaneTab[]))
    empty_editor = _PaneMockEditor(empty_tree)
    root = empty_tree.root
    _apply!(empty_editor, make_pane_focus_operation(empty_tree, root, 0))
    @test get_pane_focus(empty_tree) == (root, 0)
end

@testset "open a tab" begin
    tree, group, tabs = _flat(2)
    editor = _PaneMockEditor(tree)
    fresh = _tab("z")
    _apply!(editor, make_pane_open_tab_operation(tree, group, fresh))
    @test length(group.tabs) == 3
    @test group.tabs[3] === fresh
    @test get_pane_focus(tree) == (group, 3)               # the new tab takes the focus

    middle = _tab("m")
    _apply!(editor, make_pane_open_tab_operation(tree, group, middle; index = 2))
    @test length(group.tabs) == 4
    @test group.tabs[2] === middle
    @test get_pane_focus(tree) == (group, 2)
    # Every other tab is the same object — an insert is a splice, not a rebuild.
    @test group.tabs[1] === tabs[1]
    @test group.tabs[3] === tabs[2]
end

@testset "duplicate a tab" begin
    tree, group, tabs = _flat(3)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_duplicate_tab_operation(tree, group, 2))
    @test length(group.tabs) == 4
    duplicate = group.tabs[3]
    # The next tab, with a number in its title, the focus, and a content of its own.
    @test get_pane_tab_title_string(duplicate) == "b (2)"
    @test get_pane_focus(tree) == (group, 3)
    @test duplicate.content !== tabs[2].content
    @test duplicate.content.value == "content of b"
    @test group.tabs[2] === tabs[2]
    @test group.tabs[4] === tabs[3]
    # A second duplicate of the same tab takes the next number, and so does the
    # duplicate of a duplicate.
    _apply!(editor, make_pane_duplicate_tab_operation(tree, group, 2))
    @test get_pane_tab_title_string(group.tabs[3]) == "b (3)"
    _apply!(editor, make_pane_duplicate_tab_operation(tree, group, 3))
    @test get_pane_tab_title_string(group.tabs[4]) == "b (4)"
    @test make_pane_duplicate_tab_operation(tree, group, 9) === nothing
    # A content whose kind declares no duplicate gives no edit, and says why.
    inner = PaneTree(PaneGroup([PaneTab("layout", PaneGroup(PaneTab[]))]))
    @test (@test_logs (:warn, "The pane has no duplicate") make_pane_duplicate_tab_operation(
               inner, inner.root, 1)) === nothing
    # A value inside the content that refuses is named in the reason.
    field = WidgetText("12"; validator = make_numeric_validator())
    refusing = PaneTree(PaneGroup([PaneTab("field", field)]))
    logger = Test.TestLogger()
    Base.CoreLogging.with_logger(logger) do
        make_pane_duplicate_tab_operation(refusing, refusing.root, 1)
    end
    @test occursin("a function inside it is refused", logger.logs[1].kwargs[:reason])
end

@testset "close a tab, others remain" begin
    tree, group, tabs = _flat(3)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_close_tab_operation(tree, group, 2))
    @test length(group.tabs) == 2
    @test group.tabs[1] === tabs[1]
    @test group.tabs[2] === tabs[3]
    # The next tab took the deleted one's place, and the focus with it.
    @test get_pane_focus(tree) == (group, 2)
    @test evaluate_reference(tree, get_selection(tree)) === tabs[3]

    # Closing the last tab moves the focus back one.
    _apply!(editor, make_pane_close_tab_operation(tree, group, 2))
    @test length(group.tabs) == 1
    @test get_pane_focus(tree) == (group, 1)
end

@testset "close a tab releases its document, and an undo brings the tab back" begin
    tree, group, tabs = _flat(2)
    editor = _PaneMockEditor(tree)
    operation = make_pane_close_tab_operation(tree, group, 1)
    release = last(operation.operations)
    @test release isa ReleaseDocumentOperation
    @test release.document === tabs[1].content
    # The release changes no document, so its way back is to do nothing.
    @test make_inverse_operation(tree, release) isa DoNothingOperation
    inverse = evaluate_invertible_operation!(editor, operation)
    @test length(group.tabs) == 1
    @test inverse !== nothing
    _apply!(editor, inverse)
    @test length(group.tabs) == 2
    @test group.tabs[1].content === tabs[1].content
end

@testset "close the last tab of the root group: the empty group stays" begin
    tree, group, tabs = _flat(1)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_close_tab_operation(tree, group, 1))
    @test tree.root === group
    @test isempty(group.tabs)
    @test get_pane_focus(tree) == (group, 0)               # the group itself is named
end

@testset "split a group" begin
    tree, group, tabs = _flat(2)
    editor = _PaneMockEditor(tree)
    fresh = _tab("new")
    _apply!(editor, make_pane_split_operation(tree, group; orientation = :vertical,
                                              side = :right, tab = fresh))

    @test tree.root isa PaneSplit
    @test tree.root.orientation === :vertical
    @test length(tree.root.elements) == 2
    @test tree.root.elements[1] === group              # the group is reused, not rebuilt
    @test get_pane_weights(tree.root) == [0.5, 0.5]
    new_group = tree.root.elements[2]
    @test new_group isa PaneGroup
    @test new_group.tabs[1] === fresh
    @test get_pane_focus(tree) == (new_group, 1)           # the new tab takes the focus
    @test evaluate_reference(tree, get_selection(tree)) === fresh
end

@testset "split to the left puts the new pane first" begin
    tree, group, _ = _flat(1)
    editor = _PaneMockEditor(tree)
    fresh = _tab("new")
    _apply!(editor, make_pane_split_operation(tree, group; orientation = :vertical,
                                              side = :left, tab = fresh))
    @test tree.root.elements[2] === group
    @test tree.root.elements[1].tabs[1] === fresh
end

@testset "a same-orientation split flattens into the parent" begin
    tree, group, _ = _flat(1)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_split_operation(tree, group; orientation = :vertical,
                                              side = :right, tab = _tab("b")))
    second = tree.root.elements[2]
    _apply!(editor, make_pane_split_operation(tree, second; orientation = :vertical,
                                              side = :right, tab = _tab("c")))

    @test length(tree.root.elements) == 3              # three siblings, not a nested split
    @test all(e -> e isa PaneGroup, tree.root.elements)
    # The split group's weight was halved and the half given to the new pane.
    @test get_pane_weights(tree.root) == [0.5, 0.25, 0.25]
    @test get_pane_focus(tree)[1] === tree.root.elements[3]
end

@testset "a cross-orientation split nests" begin
    tree, group, _ = _flat(1)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_split_operation(tree, group; orientation = :vertical,
                                              side = :right, tab = _tab("b")))
    _apply!(editor, make_pane_split_operation(tree, group; orientation = :horizontal,
                                              side = :below, tab = _tab("c")))
    @test length(tree.root.elements) == 2
    inner = tree.root.elements[1]
    @test inner isa PaneSplit
    @test inner.orientation === :horizontal
    @test inner.elements[1] === group
end

@testset "close a group out of a three-way split" begin
    tree, group, _ = _flat(1)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_split_operation(tree, group; orientation = :vertical,
                                              side = :right, tab = _tab("b")))
    _apply!(editor, make_pane_split_operation(tree, tree.root.elements[2];
                                              orientation = :vertical, side = :right,
                                              tab = _tab("c")))
    middle = tree.root.elements[2]

    _apply!(editor, make_pane_close_tab_operation(tree, middle, 1))
    @test length(tree.root.elements) == 2
    @test tree.root.elements[1] === group
    @test sum(get_pane_weights(tree.root)) ≈ 1.0           # the weights are renormalized
    @test evaluate_reference(tree, get_selection(tree)) !== nothing
    @test get_pane_focus(tree)[1] === tree.root.elements[2]
end

@testset "close the second-to-last group: the split collapses into its sibling" begin
    tree, group, tabs = _flat(2)
    editor = _PaneMockEditor(tree)
    fresh = _tab("new")
    _apply!(editor, make_pane_split_operation(tree, group; orientation = :vertical,
                                              side = :right, tab = fresh))
    new_group = tree.root.elements[2]

    _apply!(editor, make_pane_close_tab_operation(tree, new_group, 1))
    @test tree.root === group                          # the sibling is reused as the root
    @test length(group.tabs) == 2
    @test get_pane_focus(tree) == (group, 1)
    @test evaluate_reference(tree, get_selection(tree)) === tabs[1]
end

@testset "move a tab inside one group is a reorder" begin
    # `target_index` names the slot the tab is inserted *before*, so a forward
    # move to slot 3 lands at 2 — the tab left its own slot first.
    tree, group, tabs = _flat(3)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_move_tab_operation(tree, group; source_index = 1,
                                                 target = group, target_index = 3))
    @test group.tabs[1] === tabs[2]
    @test group.tabs[2] === tabs[1]                    # the same object moved
    @test group.tabs[3] === tabs[3]
    @test get_pane_focus(tree) == (group, 2)

    # A drop past the last slot lands last.
    tree, group, tabs = _flat(3)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_move_tab_operation(tree, group; source_index = 1,
                                                 target = group, target_index = 4))
    @test group.tabs[3] === tabs[1]
    @test get_pane_focus(tree) == (group, 3)

    # A backward move lands exactly on the named slot.
    tree, group, tabs = _flat(3)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_move_tab_operation(tree, group; source_index = 3,
                                                 target = group, target_index = 1))
    @test group.tabs[1] === tabs[3]
    @test get_pane_focus(tree) == (group, 1)
end

@testset "move a tab into another group" begin
    tree, group, tabs = _flat(3)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_split_operation(tree, group; orientation = :vertical,
                                              side = :right, tab = _tab("x")))
    other = tree.root.elements[2]

    moved = tabs[2]
    _apply!(editor, make_pane_move_tab_operation(tree, group; source_index = 2,
                                                 target = other, target_index = 1))
    @test length(group.tabs) == 2
    @test length(other.tabs) == 2
    @test other.tabs[1] === moved                      # identity is preserved
    @test get_pane_focus(tree) == (other, 1)
    @test evaluate_reference(tree, get_selection(tree)) === moved
end

@testset "a move that empties its group collapses the split" begin
    tree, group, tabs = _flat(1)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_split_operation(tree, group; orientation = :vertical,
                                              side = :right, tab = _tab("x")))
    other = tree.root.elements[2]

    moved = tabs[1]
    _apply!(editor, make_pane_move_tab_operation(tree, group; source_index = 1,
                                                 target = other, target_index = 1))
    @test tree.root === other                          # the emptied group went away with its split
    @test length(other.tabs) == 2
    @test other.tabs[1] === moved
    # The cursor is named through the collapse, so it still resolves.
    @test evaluate_reference(tree, get_selection(tree)) === moved
end

@testset "resize a split" begin
    tree, group, _ = _flat(1)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_split_operation(tree, group; orientation = :vertical,
                                              side = :right, tab = _tab("b")))
    # Raw extents are accepted and normalized.
    _apply!(editor, make_pane_resize_operation(tree, tree.root, [300.0, 100.0]))
    @test get_pane_weights(tree.root) == [0.75, 0.25]
    @test make_pane_resize_operation(tree, tree.root, [1.0]) === nothing   # wrong arity
end

@testset "the traversal order is the depth-first order" begin
    tree, group, _ = _flat(1)
    editor = _PaneMockEditor(tree)
    _apply!(editor, make_pane_split_operation(tree, group; orientation = :vertical,
                                              side = :right, tab = _tab("b")))
    right = tree.root.elements[2]
    _apply!(editor, make_pane_split_operation(tree, right; orientation = :horizontal,
                                              side = :below, tab = _tab("c")))
    groups = get_pane_groups(tree)
    @test length(groups) == 3
    @test groups[1] === group
    @test groups[2] === right
end

end # testset
end # function
