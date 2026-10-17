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

# A press on the closed chevron of the row whose label is `label`: the chevron on
# the line of that label, left of it.
function _explorer_open_chevron(backend, label)
    texts = _nav_texts(backend)
    found = filter(entry -> entry[1] == label, texts)
    isempty(found) && return nothing
    (_, label_x, label_y) = found[argmin([entry[2] for entry in found])]
    chevrons = filter(entry -> entry[1] == _EXPLORER_CLOSED_CHEVRON && abs(entry[3] - label_y) <= 4 && entry[2] < label_x,
                      texts)
    isempty(chevrons) && return nothing
    (_, x, y) = chevrons[argmax([entry[2] for entry in chevrons])]
    MouseClick(:left, x + 2, y + 2, 1, ModifierKeys(); time = 0.0)
end

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

    @testset "the folders of a workspace are nodes, and the open of a folder reads it" begin
        root = mktempdir()
        write(joinpath(root, "notes.md"), "# Notes")
        mkdir(joinpath(root, "inner"))
        write(joinpath(root, "inner", "deep.jl"), "x = 1")
        workspace = Workspace([WorkspaceFolder("work", root)])
        content = ExplorerSection("Explorer", Any[workspace])
        explorer = Explorer(content)
        @test format_tree_node_label(workspace) == "Files" && get_document_decoration(workspace).icon === :files
        # A tab holds the explorer, so an open node holds its document.
        editor, backend = _nav_editor(explorer; tabs = true)
        # Open Files, then the folder: the open reads the folder on its task.
        for label in ("Files", "work")
            chevron = _explorer_open_chevron(backend, label)
            @test chevron !== nothing
            _nav_press!(editor, backend, chevron)
            for _ in 1:50
                drain_operations!(editor)
                run_frame!(editor)
                _nav_has_text(backend, label == "Files" ? "work" : "notes.md") && break
                sleep(0.02)
            end
        end
        @test _nav_has_text(backend, "notes.md") && _nav_has_text(backend, "inner")
        # A press on the folder shows its page: its path, its entries and their kind.
        click = _explorer_click(backend, "work")
        _nav_press!(editor, backend, click)
        folder = workspace.folders[1].directory
        @test get_navigator_page(explorer.navigator) === workspace.folders[1]
        @test format_tree_node_label(folder) == basename(root)
        @test _nav_has_text(backend, "folder") && _nav_has_text(backend, "md file")
        page = print_document(FileSystemDirectoryToWidget(), nothing, folder, nothing).output
        @test page isa VerticalLayout
        @test occursin("2 entries", page.children[1].content)
    end

    @testset "a file is one document: its page, its tab and the open files show the same one" begin
        root = mktempdir()
        path = joinpath(root, "notes.txt")
        write(path, "hello")
        workspace = Workspace([WorkspaceFolder("work", root)])
        explorer = Explorer(ExplorerSection("Explorer", Any[workspace]))
        editor, backend = _nav_editor(explorer; tabs = true)
        for label in ("Files", "work")
            _nav_press!(editor, backend, _explorer_open_chevron(backend, label))
            for _ in 1:50
                drain_operations!(editor)
                run_frame!(editor)
                _nav_has_text(backend, label == "Files" ? "work" : "notes.txt") && break
                sleep(0.02)
            end
        end
        # A press on the file shows its page: the text of the file.
        _nav_press!(editor, backend, _explorer_click(backend, "notes.txt"))
        drain_operations!(editor)
        run_frame!(editor)
        file = workspace.folders[1].directory.elements[1]
        @test file isa FileSystemFile && file.document isa FilePage
        @test _nav_has_text(backend, "hello")
        open = get_session_open_file_list(; editor)
        @test any(listed -> listed === file.document, open.files)
        @test find_open_file_document(path; editor) === file.document
        # An open of the same file reaches that document and reads no second one.
        tabs() = sum(length(group.tabs) for group in get_pane_groups(get_window_tree(editor.document)))
        before = tabs()
        evaluate_operation(editor, OpenFileOperation(path))
        drain_operations!(editor)
        run_frame!(editor)
        @test tabs() == before + 1
        shown = [tab.content for group in get_pane_groups(get_window_tree(editor.document)) for tab in group.tabs]
        @test any(content -> content === file.document, shown)
        @test count(listed -> listed isa FilePage, open.files) == 1
        # A second open focuses that tab, and opens no other.
        evaluate_operation(editor, OpenFileOperation(path))
        drain_operations!(editor)
        run_frame!(editor)
        @test tabs() == before + 1
    end

    @testset "the first content of a window holds the work of the session and the tools of the editor" begin
        editor, _ = _nav_editor(PrimitiveString("start"))
        content = make_editor_explorer_content(; editor, entries = Any[Workspace([WorkspaceFolder("work", pwd())])])
        titles = [format_tree_node_label(entry) for entry in content.entries]
        @test titles == ["Files", "Open files", "Tasks", "Assistants", "Evaluators", "Dashboards", "Editor", "Settings",
                         "Help"]
        @test content.entries[2] === get_session_open_file_list(; editor)
        @test content.entries[3] === get_session_task_group_list(; editor)
        @test content.entries[4] === get_session_assistant_list(; editor)
        editor_section = content.entries[7]
        @test any(entry -> entry === get_session_fault_log(; editor), editor_section.entries)
        @test length(content.entries[9].entries) == 3
    end

    @testset "the list of `+` holds the kinds that a person adds, each made by its insertion" begin
        kinds = ExplorerModule._collect_entry_kinds()
        names = first.(kinds)
        @test all(name -> name in names, ("Folder", "Tasks", "Assistants", "Section"))
        @test !any(kind -> last(kind) === Explorer, kinds)
        @test is_explorer_entry_type(WorkspaceFolder) && !is_explorer_entry_type(Explorer) &&
              !is_explorer_entry_type(Int)
        @test resolve_insertion(Document, "tasks") === TaskGroupList &&
              resolve_insertion(Document, "folder") === WorkspaceFolder &&
              resolve_insertion(Document, "section") === ExplorerSection
        editor, _ = _nav_editor(PrimitiveString("start"))
        tasks = run_with_evaluation_editor(() -> make_insertion_document(TaskGroupList), editor)
        @test tasks === get_session_task_group_list(; editor)
        @test make_insertion_document(ExplorerSection).title == "New section"
        # A file keeps that an entry is the task list of the session, and no group.
        @test pred_arguments(tasks) == ((), Pair{Symbol,Any}[])
        @test run_with_evaluation_editor(() -> make_pred_document(TaskGroupList, (), Pair{Symbol,Any}[]), editor) === tasks
    end

    @testset "a folder with no place asks for its place on its page, and reads there" begin
        root = mktempdir()
        write(joinpath(root, "notes.md"), "# notes")
        folder = make_insertion_document(WorkspaceFolder)
        @test format_tree_node_label(folder) == "New folder" && has_tree_children(folder) === false
        explorer = Explorer(ExplorerSection("Explorer", Any[folder]))
        editor, backend = _nav_editor(explorer; tabs = true)
        _nav_press!(editor, backend, _explorer_click(backend, "New folder"))
        @test get_navigator_page(explorer.navigator) === folder
        @test _nav_has_text(backend, "The place of the folder on the disk:")
        # A press in the field puts the caret in the place, and each key types there.
        field = _explorer_click(backend, "/home/person/data"; side = :page)
        @test field !== nothing
        _nav_press!(editor, backend, field)
        _nav_press!(editor, backend, (KeyPress(character; time = 0.0) for character in root)...)
        @test folder.pathname == root && !_nav_has_text(backend, "notes.md")
        # Return opens the folder there: it takes the name of the place and reads it.
        _nav_press!(editor, backend, KeyPress('\n'; time = 0.0))
        for _ in 1:50
            drain_operations!(editor)
            run_frame!(editor)
            _nav_has_text(backend, "notes.md") && break
            sleep(0.02)
        end
        @test folder.name == basename(root) && folder.directory.pathname == root
        @test _nav_has_text(backend, "md file") && !_nav_has_text(backend, "The place of the folder")
        @test format_tree_node_label(folder) == basename(root)
    end

    @testset "Insert offers the kinds, and an item adds its entry after the selected one with its page" begin
        content = _explorer_make()
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer)
        _nav_press!(editor, backend, _explorer_click(backend, "alpha"))
        opened = get_wrapped_operation(read_gesture(explorer, KeyDown(:insert, ModifierKeys(); time = 0.0)))
        menu = opened.layers[1][2]
        labels = [string(item.action.label) for item in menu.elements]
        @test labels[end] == "Other document" && issorted(labels[1:(end - 1)])
        @test all(label -> label in labels, ("Folder", "Section", "Tasks", "Assistants"))
        # The item "Folder" adds a folder after alpha: its node is selected and its
        # page shows.
        add = menu.elements[findfirst(==("Folder"), labels)].operation
        @test add isa AddExplorerEntryOperation && add.index == 2
        inverse = make_inverse_operation(editor.document, add)
        evaluate_operation(editor, add)
        run_frame!(editor)
        folder = content.entries[2]
        @test folder isa WorkspaceFolder && format_tree_node_label(content.entries[3]) == "Inner"
        @test get_navigator_page(explorer.navigator) === folder
        @test _nav_is(getfield(explorer, :selection)[],
                      _explorer_path(FieldReferenceStep("tree"), FieldReferenceStep("root"), FieldReferenceStep("entries"),
                                     ElementReferenceStep(2)))
        @test _nav_has_text(backend, "New folder")
        # Its way back takes the entry out again.
        evaluate_operation(editor, inverse)
        @test length(content.entries) == 2 && content.entries[2].title == "Inner"
        # On a section, Insert adds at the end of that section.
        _nav_press!(editor, backend, _explorer_click(backend, "Inner"))
        opened = get_wrapped_operation(read_gesture(explorer, KeyDown(:insert, ModifierKeys(); time = 0.0)))
        add = last(opened.layers[1][2].elements).operation
        @test add.section === content.entries[2] && add.index == 2
        evaluate_operation(editor, add)
        @test content.entries[2].entries[2] isa DocumentInsertion
        # An add with no section adds at the end of the root section of the editor.
        evaluate_operation(editor, AddExplorerEntryOperation(ExplorerSection("Later")))
        @test last(get_session_explorer_content(; editor).entries).title == "Later"
    end

    @testset "Delete removes the selected entry, and Ctrl+Shift+arrows move it" begin
        content = _explorer_make()
        alpha, inner = content.entries[1], content.entries[2]
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer)
        key(name; shift = false, ctrl = false) = KeyDown(name, ModifierKeys(ctrl = ctrl, shift = shift); time = 0.0)
        # A node below an entry is no entry: Delete leaves it.
        _nav_press!(editor, backend, _explorer_open_chevron(backend, "alpha"))
        _nav_press!(editor, backend, _explorer_click(backend, "alpha one"))
        _nav_press!(editor, backend, key(:delete))
        @test length(content.entries) == 2 && length(alpha.children) == 2
        # Ctrl+Shift+Down moves alpha after Inner; it stays selected with its page.
        _nav_press!(editor, backend, _explorer_click(backend, "alpha"))
        _nav_press!(editor, backend, key(:down; ctrl = true, shift = true))
        @test content.entries[1] === inner && content.entries[2] === alpha
        @test get_navigator_page(explorer.navigator) === alpha
        @test _nav_is(getfield(explorer, :selection)[],
                      _explorer_path(FieldReferenceStep("tree"), FieldReferenceStep("root"), FieldReferenceStep("entries"),
                                     ElementReferenceStep(2)))
        # At the end of its section it moves no further.
        _nav_press!(editor, backend, key(:down; ctrl = true, shift = true))
        @test content.entries[2] === alpha
        _nav_press!(editor, backend, key(:up; ctrl = true, shift = true))
        @test content.entries[1] === alpha
        # Delete takes alpha out of the section, and the section shows with its page.
        _nav_press!(editor, backend, key(:delete))
        @test length(content.entries) == 1 && content.entries[1] === inner
        @test get_navigator_page(explorer.navigator) === content
        # The root section is no entry of a section.
        _nav_press!(editor, backend, key(:delete))
        @test length(content.entries) == 1
        # "New section" adds a section at the end of a selected section.
        run_gesture_command = binding -> binding.description == "New section"
        binding = only(filter(run_gesture_command, collect_document_gesture_bindings(Explorer)))
        evaluate_operation(editor, binding.operation(explorer, nothing))
        @test content.entries[2] isa ExplorerSection && content.entries[2].title == "New section"
    end

    @testset "F2 on a section puts the caret in its title on its page, and each key edits it" begin
        content = _explorer_make()
        inner = content.entries[2]
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer)
        # F2 on a node that is no section leaves the key.
        _nav_press!(editor, backend, _explorer_click(backend, "alpha"))
        @test read_gesture(explorer, KeyDown(:f2, ModifierKeys(); time = 0.0)) === nothing
        _nav_press!(editor, backend, _explorer_click(backend, "Inner"))
        _nav_press!(editor, backend, KeyDown(:f2, ModifierKeys(); time = 0.0))
        @test get_navigator_page(explorer.navigator) === inner
        @test _nav_is(getfield(explorer, :selection)[],
                      _explorer_path(FieldReferenceStep("navigator"), FieldReferenceStep("content"),
                                     FieldReferenceStep("entries"), ElementReferenceStep(2), FieldReferenceStep("title"),
                                     RangeReferenceStep(5, 5)))
        _nav_press!(editor, backend, (KeyPress(character; time = 0.0) for character in " parts")...)
        @test inner.title == "Inner parts"
        @test _nav_has_text(backend, "Inner parts")
    end

    @testset "a command adds the document of the focused tab to the explorer" begin
        document = PrimitiveString("start")
        editor, backend = _nav_editor(document; tabs = true)
        tree = get_window_tree(editor.document)
        @test PaneModule._find_tab_document(only(only(get_pane_groups(tree)).tabs)) === document
        binding = only(filter(binding -> binding.description == "Add the tab to the explorer",
                              collect_document_gesture_bindings(PaneTree)))
        # With no focused tab the command adds nothing; a press in the tab focuses it.
        @test binding.operation(tree, nothing) === nothing
        _nav_press!(editor, backend, MouseClick(:left, 10, 32, 1, ModifierKeys(); time = 0.0))
        evaluate_operation(editor, binding.operation(tree, nothing))
        @test last(get_session_explorer_content(; editor).entries) === document
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
