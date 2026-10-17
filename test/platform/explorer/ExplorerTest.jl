# The explorer: a section of entries as a tree beside a navigator. A section is a
# node of a tree, lists its first children, and says where it holds a document;
# each editor has one root section; a press on a node shows its page beside the
# tree and keeps the keys in the tree, Ctrl+press opens the page in a new tab, a
# double press puts the keyboard in the page, a link on the page of a section
# opens the page of its entry, and the page and the tree follow the entries. The
# editor is the one of `NavigatorToWidgetTest.jl`.

@document struct _ExplorerNode
    name::String
    children::CellVector
end

TreeModule.get_tree_children_steps(::_ExplorerNode) = ((FieldReferenceStep("children"),),)
TreeModule.format_tree_node_label(node::_ExplorerNode) = node.name
DocumentModule.get_document_title(node::_ExplorerNode) = node.name

_explorer_node(name, children...) = _ExplorerNode(name, CellVector(Any[children...]))

# A root section with a node of two children, and a section inside it with one
# node.
function _explorer_make()
    alpha = _explorer_node("alpha", _explorer_node("alpha one"), _explorer_node("alpha two"))
    inner = ExplorerSection("Inner", Any[_explorer_node("beta")])
    ExplorerSection("Explorer", Any[alpha, inner])
end

_explorer_path(steps...) = extend_reference(EmptyReference(), steps...)
_explorer_entry_path(k) = _explorer_path(FieldReferenceStep("entries"), ElementReferenceStep(k))

# A press on the text `text` in the tree, the part on the left, or on the page, the
# part on the right: the drawn text that is the most to that side.
function _explorer_click(backend, text; side = :tree, count = 1, ctrl = false)
    found = filter(entry -> entry[1] == text, _nav_texts(backend))
    isempty(found) && return nothing
    xs = [entry[2] for entry in found]
    (_, x, y) = found[side === :tree ? argmin(xs) : argmax(xs)]
    MouseClick(:left, x + 2, y + 2, count, ModifierKeys(ctrl = ctrl); time = 0.0)
end

# The glyph of a closed chevron of a node.
const _EXPLORER_CLOSED_CHEVRON = string(Char(0xe06f))

function test_explorer()
@testset "the explorer" begin

    @testset "a section is a node of a tree, and lists its first children" begin
        content = _explorer_make()
        alpha, inner = content.entries[1], content.entries[2]
        @test format_tree_node_label(content) == "Explorer" && get_document_title(inner) == "Inner"
        children = collect_tree_children(content; limit = 5)
        @test length(children) == 2 && last(children[1]) === alpha && last(children[2]) === inner
        @test _nav_is(first(children[2]), _explorer_entry_path(2))
        @test length(collect_tree_children(alpha; limit = 1)) == 1
        @test isempty(collect_tree_children(ExplorerSection("Empty"); limit = 5))
        # A lazy list gives its first nodes from its head, and makes no other.
        made = Ref(0)
        lazy = _DocTreeLazy("runs", make_index_list(1_000_000, 1, k -> (made[] += 1; _doctree_node("run $k"))))
        runs = collect_tree_children(lazy; limit = 3)
        @test length(runs) == 3 && last(runs[3]).name == "run 3" && made[] <= 4
        @test _nav_is(first(runs[2]), _explorer_path(FieldReferenceStep("children"), ElementReferenceStep(2)))
    end

    @testset "a section says where it holds a document, also inside a section" begin
        content = _explorer_make()
        alpha, inner = content.entries[1], content.entries[2]
        beta = inner.entries[1]
        @test _nav_is(find_navigator_address(content, alpha), _explorer_entry_path(1))
        @test _nav_is(find_navigator_address(content, beta),
                      concat_references(_explorer_entry_path(2), _explorer_entry_path(1)))
        @test find_navigator_address(content, _explorer_node("elsewhere")) === nothing
    end

    @testset "each editor has one root section, which an explorer by name shows" begin
        @test get_insertion_aliases(Explorer) == ["explorer"]
        @test !("explorer" in get_insertion_aliases(WorkspaceExplorer))
        @test resolve_insertion(Document, "explorer") === Explorer
        # With no editor, each call makes a section that nothing keeps.
        @test get_session_explorer_content(; editor = nothing) !== get_session_explorer_content(; editor = nothing)
        editor, _ = _nav_editor(PrimitiveString("start"))
        content = get_session_explorer_content(; editor)
        @test content isa ExplorerSection && content.title == "Explorer"
        @test get_session_explorer_content(; editor) === content
        explorer = run_with_evaluation_editor(() -> make_insertion_document(Explorer), editor)
        @test explorer isa Explorer && explorer.tree.root === content && explorer.navigator.content === content
        # A duplicate shows the same section, with its own tree and navigator.
        copied = copy_document(DuplicatePolicy(), explorer)
        @test copied.tree.root === content && copied.tree !== explorer.tree && copied.navigator !== explorer.navigator
        @test has_document_duplicate(explorer) && !accepts_opened_file(explorer)
    end

    @testset "a press on a node shows its page beside the tree, and the keys stay in the tree" begin
        content = _explorer_make()
        alpha = content.entries[1]
        explorer = Explorer(content)
        navigator = explorer.navigator
        editor, backend = _nav_editor(explorer)
        # At the start the page is the page of the section: a card for each entry.
        @test get_navigator_page(navigator) === content
        @test _nav_has_text(backend, "alpha one") && _nav_has_text(backend, "beta")
        click = _explorer_click(backend, "alpha")
        @test click !== nothing
        _nav_press!(editor, backend, click)
        @test get_navigator_page(navigator) === alpha
        @test _nav_is(navigator.address, _explorer_entry_path(1))
        # The tree marks the row of the page.
        @test _nav_is(explorer.tree.current, _explorer_entry_path(1))
        selection = getfield(explorer, :selection)[]
        @test selection isa ConcreteReference && get_reference_head(selection) == FieldReferenceStep("tree")
    end

    @testset "a chevron opens a node, and its children show in the tree" begin
        content = _explorer_make()
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer)
        @test count(entry -> entry[1] == "beta", _nav_texts(backend)) == 1
        chevron = _explorer_click(backend, _EXPLORER_CLOSED_CHEVRON)
        @test chevron !== nothing
        # The first closed chevron is the one of the first entry, alpha.
        _nav_press!(editor, backend, chevron)
        @test count(entry -> entry[1] == "alpha one", _nav_texts(backend)) == 2
    end

    @testset "a double press on a node puts the keyboard in its page" begin
        content = _explorer_make()
        inner = content.entries[2]
        explorer = Explorer(content)
        navigator = explorer.navigator
        editor, backend = _nav_editor(explorer)
        click = _explorer_click(backend, "Inner")
        @test click !== nothing
        _nav_press!(editor, backend, click, _doctree_double(click))
        @test get_navigator_page(navigator) === inner
        selection = getfield(explorer, :selection)[]
        @test selection isa ConcreteReference && get_reference_head(selection) == FieldReferenceStep("navigator")
    end

    @testset "a link on the page of a section opens the page of its entry" begin
        content = _explorer_make()
        beta = content.entries[2].entries[1]
        explorer = Explorer(content)
        navigator = explorer.navigator
        editor, backend = _nav_editor(explorer)
        link = _explorer_click(backend, "beta"; side = :page)
        @test link !== nothing
        _nav_press!(editor, backend, link)
        @test get_navigator_page(navigator) === beta
        @test _nav_is(navigator.address, concat_references(_explorer_entry_path(2), _explorer_entry_path(1)))
        # The mark of the tree follows a link inside the page.
        @test _nav_is(explorer.tree.current, concat_references(_explorer_entry_path(2), _explorer_entry_path(1)))
    end

    @testset "the page and the tree follow the entries" begin
        content = _explorer_make()
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer)
        @test !_nav_has_text(backend, "gamma")
        push!(content.entries, _explorer_node("gamma"))
        run_frame!(editor)
        @test count(entry -> entry[1] == "gamma", _nav_texts(backend)) == 2
        empty = Explorer(ExplorerSection("Explorer"))
        _, empty_backend = _nav_editor(empty)
        @test _nav_has_text(empty_backend, "This section has no entry.")
    end

    @testset "Ctrl+press on a node opens its page in a new tab" begin
        content = _explorer_make()
        explorer = Explorer(content)
        navigator = explorer.navigator
        editor, backend = _nav_editor(explorer; tabs = true)
        tabs() = sum(length(group.tabs) for group in get_pane_groups(get_window_tree(editor.document)))
        before = tabs()
        click = _explorer_click(backend, "Inner"; ctrl = true)
        @test click !== nothing
        _nav_press!(editor, backend, click)
        drain_operations!(editor)
        run_frame!(editor)
        @test tabs() == before + 1
        # The navigator beside the tree keeps its page.
        @test get_navigator_page(navigator) === content
    end
end
end
