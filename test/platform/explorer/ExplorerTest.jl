# The explorer: a section of entries as a tree beside a navigator. A section is a
# node of a tree, lists its first children, and says where it holds a document;
# each editor has one root section; a press on a node shows its page beside the
# tree and keeps the keys in the tree, a drag of the divider between the tree and
# the page moves it, Ctrl+press opens the page in a new tab, a
# double press puts the keyboard in the page, a link on the page of a section
# opens the page of its entry, and the page and the tree follow the entries. The
# page of the open files is a table of the files, whose names are links. The
# editor is the one of `NavigatorToWidgetTest.jl`.

@document struct _ExplorerNode
    name::String
    children::CellVector
end

TreeModule.get_tree_children_steps(::_ExplorerNode) = ((FieldReferenceStep("children"),),)
TreeModule.format_tree_node_label(node::_ExplorerNode) = node.name
DocumentModule.get_document_title(node::_ExplorerNode) = node.name

_explorer_node(name, children...) = _ExplorerNode(name, CellVector(Any[children...]))

# A kind whose session document the first content of an explorer holds while
# `_SESSION_ENTRY_PROBE_ON` holds `true`. It keeps the editor of the evaluation that
# made it. Its type is parametric, as the type of a `@document` is.
mutable struct _SessionEntryProbe{T}
    editor::T
end
_SessionEntryProbe() = _SessionEntryProbe{Any}(find_evaluation_editor())
const _SESSION_ENTRY_PROBE_ON = Ref(false)
TreeModule.is_session_explorer_entry_type(::Type{_SessionEntryProbe}) = _SESSION_ENTRY_PROBE_ON[]
DocumentModule.get_document_title(::_SessionEntryProbe) = "Probe entry"

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

# Whether the frame draws `text` on the left, in the tree: before the button Back
# of the bar of the navigator.
function _explorer_has_tree_text(backend, text)
    texts = _nav_texts(backend)
    back = findfirst(entry -> entry[1] == _NAV_BACK, texts)
    limit = back === nothing ? typemax(Int) : texts[back][2]
    any(entry -> entry[1] == text && entry[2] < limit, texts)
end

# The answer of a right click on the row `label` in the tree, after a move there.
function _explorer_right_click(editor, backend, label)
    click = _explorer_click(backend, label)
    _nav_press!(editor, backend, MouseMove(click.x, click.y; time = 0.0))
    answer = read_intent(editor.projection, nothing, Intent(MouseClick(:right, click.x, click.y, 1, ModifierKeys(); time = 0.0)),
                         editor.iomap).operation
    answer isa WrappingOperation ? get_wrapped_operation(answer) : answer
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

    @testset "a tree of the help opens in the explorer, and a press on a group shows its page" begin
        list = DocumentTypeList()
        explorer = Explorer(ExplorerSection("Explorer", Any[list]))
        navigator = explorer.navigator
        editor, backend = _nav_editor(explorer)
        evaluate_operation(editor, AcquireDocumentOperation(explorer))
        run_frame!(editor)
        # The visit holds the page, and its acquire builds the groups.
        _nav_press!(editor, backend, _explorer_click(backend, "Documents"))
        @test get_navigator_page(navigator) === list
        @test !isempty(list.children)
        @test _nav_has_text(backend, "Platform")
        chevron = _explorer_open_chevron(backend, "Documents")
        @test chevron !== nothing
        _nav_press!(editor, backend, chevron)
        @test _explorer_has_tree_text(backend, "Platform")
        _nav_press!(editor, backend, _explorer_click(backend, "Platform"))
        platform = only(group for group in list.children if group.name == "Platform")
        @test get_navigator_page(navigator) === platform
        k = findfirst(group -> group === platform, collect(list.children))
        @test _nav_is(navigator.address, concat_references(_explorer_entry_path(1),
                                                           _explorer_path(FieldReferenceStep("children"),
                                                                          ElementReferenceStep(k))))
        @test _nav_has_text(backend, "Widget")
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

    @testset "the page starts three times as wide as the tree, and a drag of the divider between them moves it" begin
        explorer = Explorer(_explorer_make())
        backend = HeadlessBackend()
        editor = build_editor(explorer, _nav_natural(); backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = (; title = "W", width = 1000, height = 500), tabs = false, appearance = false,
                              settings = false)
        run_frame!(editor)
        window() = last(rendered_output(backend)).windows[1].content
        back_x() = only(entry[2] for entry in _nav_drawn(window()) if entry[1] == _NAV_BACK)
        send!(event) = (push_event!(backend, WindowInput(:W, event)); run_frame!(editor); run_frame!(editor))
        # The divider is where the pointer is a double arrow, at a quarter of the
        # window, and the page starts right of it.
        y = 250
        band = filter(x -> find_pointer_shape(window(), x, y) === :double_arrow_horizontal, 0:999)
        @test !isempty(band)
        divider = band[(length(band) + 1) ÷ 2]
        @test abs(divider - 250) <= 4
        before = back_x()
        @test divider < before < divider + 12
        send!(MouseDown(:left, divider, y, ModifierKeys(); time = 1.0))
        send!(MouseMove(divider + 100, y, MouseButtons(:left), ModifierKeys(); time = 1.1))
        @test back_x() == before + 100
        send!(MouseUp(:left, divider + 100, y, ModifierKeys(); time = 1.2))
        @test back_x() == before + 100
        # After the release, a move of the pointer moves no divider.
        send!(MouseMove(divider + 200, y; time = 1.3))
        @test back_x() == before + 100
        # The right edge of the split pane: of the canvas that holds the region of
        # the double arrow.
        function split_end(canvas = window(), ox = 0)
            x = ox + Int(canvas.x)
            for element in canvas.elements
                element = element isa Cell ? element[] : element
                element isa GraphicsPointerShape && element.shape === :double_arrow_horizontal &&
                    return x + Int(canvas.w[])
                found = element isa GraphicsCanvas ? split_end(element, x) :
                        element isa GraphicsViewport ? split_end(element.content, x + Int(element.x) +
                                                                 round(Int, element.transform.e)) : nothing
                found === nothing || return found
            end
            nothing
        end
        @test split_end() == Int(window().w[])
        # A narrower window: the tree keeps its width, and the page takes the change,
        # so the split pane ends at the edge of the window and cuts nothing off.
        push_event!(backend, WindowInput(:W, WindowResize(800, 500; time = 1.4)))
        run_frame!(editor)
        run_frame!(editor)
        @test Int(window().w[]) == 800
        @test back_x() == before + 100
        @test split_end() == 800
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

    @testset "the pointer on a link of the page of a section draws the line under it" begin
        explorer = Explorer(_explorer_make())
        editor, backend = _nav_editor(explorer)
        drawing() = last(rendered_output(backend))
        on_page = _explorer_click(backend, "beta"; side = :page)
        @test on_page !== nothing && !is_link_text_underlined(drawing(), "beta")
        _nav_press!(editor, backend, MouseMove(on_page.x, on_page.y; time = 0.0))
        @test is_link_text_underlined(drawing(), "beta")
        # The pointer on another link moves the line; on a node of the tree, which
        # is no link, no line shows.
        other = _explorer_click(backend, "alpha one"; side = :page)
        _nav_press!(editor, backend, MouseMove(other.x, other.y; time = 0.1))
        @test is_link_text_underlined(drawing(), "alpha one") && !is_link_text_underlined(drawing(), "beta")
        in_tree = _explorer_click(backend, "Inner"; side = :tree)
        _nav_press!(editor, backend, MouseMove(in_tree.x, in_tree.y; time = 0.2))
        @test !is_link_text_underlined(drawing(), "alpha one") && !is_link_text_underlined(drawing(), "Inner")
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
        # The pointer on the name of an entry, a link, draws the line under it.
        on_page = _explorer_click(backend, "notes.md"; side = :page)
        @test !is_link_text_underlined(last(rendered_output(backend)), "notes.md")
        _nav_press!(editor, backend, MouseMove(on_page.x, on_page.y; time = 0.0))
        @test is_link_text_underlined(last(rendered_output(backend)), "notes.md")
        page = print_document(FileSystemDirectoryToWidget(), nothing, folder, nothing).output
        @test page isa VerticalLayout
        @test occursin("2 entries", page.children[1].content)
    end

    @testset "the filter, the kinds and the add items say what they do" begin
        content = _explorer_make()
        explorer = Explorer(content)
        output = print_document(ExplorerToWidget(), nothing, explorer, nothing).output
        texts = _find_widgets_below(output, WidgetText)
        field = _read_widget_note(first(text for text in texts if text.placeholder == "Filter"))
        @test field.title == "Filter" && !isempty(field.keys) && occursin("Escape", field.hint)
        add, kinds = _find_widgets_below(output, WidgetToolbarItem)
        @test first.(_read_widget_note(add).facts) == ["Kinds"]
        @test _read_widget_note(kinds).facts == ["Shown" => "every kind"]
        page = print_document(ExplorerSectionToWidget(), nothing, content, nothing).output
        cards = _find_widgets_below(page, WidgetCard)
        @test length(cards) == 2
        @test _read_widget_note(cards[1]) === nothing
        @test _read_widget_note(cards[2]).title == "Inner"
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

    @testset "the page of the open files is a table of the files, which a person filters and opens" begin
        root = mktempdir()
        content = ExplorerSection("Explorer", Any[])
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer; tabs = true)
        list = get_session_open_file_list(; editor)
        push!(content.entries, list)
        run_frame!(editor)
        frame!() = (drain_operations!(editor); run_frame!(editor))
        table = list.table
        roster = table.document
        @test table isa ArrangementDocument && roster isa Roster && isempty(table.entries)
        # The page of the list counts the files above its table.
        _nav_press!(editor, backend, _explorer_click(backend, "Open files"))
        @test get_navigator_page(explorer.navigator) === list
        @test _nav_has_text(backend, "No file is open.")
        # A row comes for each file that opens: a file, or the page of a file.
        buffer = UndoBuffer(PrimitiveString("alpha"))
        file = TextFile(joinpath(root, "a.txt"), buffer)
        page = FilePage(; content = TextFile(joinpath(root, "b.txt"), UndoBuffer(PrimitiveString("beta"))))
        add_open_file!(editor, file)
        add_open_file!(editor, page)
        frame!()
        @test [collect(row.values) for row in roster.rows] == [Any["a.txt", root, ""], Any["b.txt", root, ""]]
        @test _nav_has_text(backend, "2 open files") && _nav_has_text(backend, "a.txt") && _nav_has_text(backend, "b.txt")
        # An edit in one file changes the state of its row, and the other row stays.
        other = roster.rows[2]
        push_undo_entry!(buffer, UndoEntry("an edit", nothing, nothing))
        frame!()
        @test roster.rows[1].values[3] == "unsaved edits" && roster.rows[2] === other && other.values[3] == ""
        @test _nav_has_text(backend, "2 open files · 1 unsaved") && _nav_has_text(backend, "unsaved edits")
        # A filter on the state hides the other file, and Show all keeps the
        # arrangement of the list with no entry.
        filter = ProjecturedPlatform.ArrangementModule._make_filter(("state" => ==("unsaved edits"),))
        evaluate_operation(editor, make_arrangement_change_edit(
            table, ArrangeCollectionOperation(extend_reference(EmptyReference(), FieldReferenceStep("rows")), filter)))
        frame!()
        @test list.table === table && length(table.entries) == 1
        @test _nav_has_text(backend, "a.txt") && !_nav_has_text(backend, "b.txt")
        _nav_press!(editor, backend, _explorer_click(backend, "Show all"; side = :page))
        frame!()
        @test list.table === table && isempty(table.entries)
        @test _nav_has_text(backend, "b.txt") && !_nav_has_text(backend, "Show all")
        steps_of(parts...) = collect(get_reference_steps(extend_reference(EmptyReference(), parts...)))
        files_at(j) = steps_of(FieldReferenceStep("files"), ElementReferenceStep(j))
        last_steps(reference, n) = (steps = get_reference_steps(strip_reference_types(reference)); steps[(end - n + 1):end])
        # A press on a label of a row selects the row, which the table shows.
        _nav_press!(editor, backend, _explorer_click(backend, "unsaved edits"; side = :page))
        frame!()
        @test last_steps(editor.document.selection, 3) ==
              steps_of(FieldReferenceStep("rows"), ElementReferenceStep(1), FieldReferenceStep("item"))
        # The name of a file is a link: one press opens the page of the file, at
        # its place in the list, also while a filter shows it as the first row.
        filter = ProjecturedPlatform.ArrangementModule._make_filter(("state" => ==(""),))
        evaluate_operation(editor, make_arrangement_change_edit(
            table, ArrangeCollectionOperation(extend_reference(EmptyReference(), FieldReferenceStep("rows")), filter)))
        frame!()
        @test !_nav_has_text(backend, "a.txt")
        _nav_press!(editor, backend, _explorer_click(backend, "b.txt"; side = :page))
        frame!()
        @test get_navigator_page(explorer.navigator) === page
        @test last_steps(explorer.navigator.address, 2) == files_at(2)
        @test _nav_count(backend, "Open files") == 2 && !_nav_has_text(backend, "rows[")
        @test find_open_file_document(joinpath(root, "b.txt"); editor) === page
        # A row goes when the editor lets its file go.
        remove_open_file!(editor, file)
        @test [row.values[1] for row in roster.rows] == ["b.txt"]
    end

    @testset "the first content of a window holds the work of the session and the tools of the editor" begin
        editor, _ = _nav_editor(PrimitiveString("start"))
        content = make_editor_explorer_content(; editor, entries = Any[Workspace([WorkspaceFolder("work", pwd())])])
        titles = [format_tree_node_label(entry) for entry in content.entries]
        # The kinds of the loaded packages stand after the lists of the session.
        kinds = length(ApplicationModule._collect_session_explorer_entry_types())
        @test titles[[1:4; (5 + kinds):end]] ==
              ["Files", "Open files", "Tasks", "Assistants", "Evaluators", "Dashboards", "Editor", "Settings", "Help"]
        @test content.entries[2] === get_session_open_file_list(; editor)
        @test content.entries[3] === get_session_task_group_list(; editor)
        @test content.entries[4] === get_session_assistant_list(; editor)
        editor_section = content.entries[7 + kinds]
        @test any(entry -> entry === get_session_fault_log(; editor), editor_section.entries)
        @test length(content.entries[9 + kinds].entries) == 3
    end

    @testset "the first content holds the session document of each kind that a loaded package marks" begin
        @test !is_session_explorer_entry_type(Int)
        editor, _ = _nav_editor(PrimitiveString("start"))
        @test !any(entry -> entry isa _SessionEntryProbe, make_editor_explorer_content(; editor).entries)
        _SESSION_ENTRY_PROBE_ON[] = true
        try
            content = make_editor_explorer_content(; editor)
            probe = get_session_document!(_SessionEntryProbe, editor, _SessionEntryProbe)
            @test count(entry -> entry === probe, content.entries) == 1
            @test probe.editor === editor
            titles =[format_tree_node_label(entry) for entry in content.entries]
            place = findfirst(==("Probe entry"), titles)
            @test findfirst(==("Assistants"), titles) < place < findfirst(==("Evaluators"), titles)
            # The same editor gives the same document again, and another editor its own.
            @test any(entry -> entry === probe, make_editor_explorer_content(; editor).entries)
            other, _ = _nav_editor(PrimitiveString("other"))
            other_entries = make_editor_explorer_content(; editor = other).entries
            @test count(entry -> entry isa _SessionEntryProbe, other_entries) == 1
            @test !any(entry -> entry === probe, other_entries)
            # A host that gives the document already gets it once.
            given = make_editor_explorer_content(; editor, entries = Any[probe]).entries
            @test count(entry -> entry === probe, given) == 1
        finally
            _SESSION_ENTRY_PROBE_ON[] = false
        end
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
        # A key a frame, as a person types: a frame takes a bounded count of
        # events, and a long place has more keys than that.
        foreach(character -> _nav_press!(editor, backend, KeyPress(character; time = 0.0)), root)
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
        @test PaneModule._get_tab_document(only(only(get_pane_groups(tree)).tabs)) === document
        binding = only(filter(binding -> binding.description == "Add the tab to the explorer",
                              collect_document_gesture_bindings(PaneTree)))
        # With no focused tab the command adds nothing; a press in the tab focuses it.
        @test binding.operation(tree, nothing) === nothing
        _nav_press!(editor, backend, MouseClick(:left, 10, 32, 1, ModifierKeys(); time = 0.0))
        evaluate_operation(editor, binding.operation(tree, nothing))
        @test last(get_session_explorer_content(; editor).entries) === document
    end

    @testset "the content of a folder is kept in the state folder, and reads back as the session of the next editor" begin
        state = mktempdir()
        withenv("XDG_STATE_HOME" => state) do
            work, other = mkpath(joinpath(mktempdir(), "work")), mkpath(joinpath(mktempdir(), "work"))
            path = get_explorer_content_file(work)
            @test startswith(path, joinpath(state, "projectured", "explorer", "work-")) && endswith(path, ".pred")
            @test get_explorer_content_file(work * "/") == path && get_explorer_content_file(other) != path
            @test load_explorer_content(path) === nothing
            first_editor, _ = _nav_editor(PrimitiveString("first"))
            content = make_editor_explorer_content(; editor = first_editor,
                                                   entries = Any[Workspace([WorkspaceFolder("work", work)])])
            # The kinds of the loaded packages stand after the lists of the session.
            kinds = length(ApplicationModule._collect_session_explorer_entry_types())
            push!(content.entries[6 + kinds].entries, ExplorerSection("Queue study"))
            save_explorer_content!(content, path; editor = first_editor)
            @test isfile(path)
            # The next editor reads the same entries: its own lists of the session,
            # the folder at its place, and the sections with their titles.
            next_editor, _ = _nav_editor(PrimitiveString("next"))
            loaded = load_explorer_content(path; editor = next_editor)
            @test loaded isa ExplorerSection
            @test [format_tree_node_label(entry) for entry in loaded.entries] ==
                  [format_tree_node_label(entry) for entry in content.entries]
            folder = only(loaded.entries[1].folders)
            @test folder.name == "work" && folder.pathname == work
            @test loaded.entries[2] === get_session_open_file_list(; editor = next_editor)
            @test loaded.entries[3] === get_session_task_group_list(; editor = next_editor)
            @test loaded.entries[4] === get_session_assistant_list(; editor = next_editor)
            @test only(loaded.entries[6 + kinds].entries).title == "Queue study"
            tools = loaded.entries[7 + kinds].entries
            @test tools[1] === get_session_message_log(; editor = next_editor)
            @test tools[3] === get_session_fault_log(; editor = next_editor)
            @test any(tool -> tool === get_session_frame_statistics(; editor = next_editor), tools)
            processes = only(filter(tool -> tool isa SystemProcessTree, tools))
            @test processes.root_process_ids == [getpid()] && processes.title == "System processes"
            # A file that does not read gives nothing, and a warning says so.
            write(path, "ExplorerSection(")
            @test (@test_logs (:warn, r"does not read") match_mode = :any load_explorer_content(path)) === nothing
        end
    end

    @testset "the filter shows the rows that the tree read and that match, with the rows above them open" begin
        content = _explorer_make()
        alpha = content.entries[1]
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer)
        # Only the rows of open nodes are read: alpha opens, and Inner stays closed.
        _nav_press!(editor, backend, _explorer_open_chevron(backend, "alpha"))
        _nav_press!(editor, backend, _explorer_click(backend, "alpha"))
        _nav_press!(editor, backend, KeyDown(:f, ModifierKeys(ctrl = true); time = 0.0))
        @test _nav_is(getfield(explorer, :selection)[],
                      _explorer_path(FieldReferenceStep("filter"), FieldReferenceStep("text"), RangeReferenceStep(0, 0)))
        # Each key edits the filter as view state, so an undo records none of it.
        answer = read_intent(editor.projection, nothing, Intent(KeyPress('t'; time = 0.0)), editor.iomap).operation
        @test answer isa ReplaceViewStateOperation
        _nav_press!(editor, backend, (KeyPress(character; time = 0.0) for character in "two")...)
        @test explorer.filter.text == "two"
        matches = explorer.matches
        @test matches isa DocumentTree && only(matches.root.children).document === alpha
        @test _explorer_has_tree_text(backend, "alpha two") && !_explorer_has_tree_text(backend, "alpha one") &&
              !_explorer_has_tree_text(backend, "Inner")
        # A press on a match shows the page of its document, at its place in the
        # section.
        _nav_press!(editor, backend, _explorer_click(backend, "alpha two"))
        @test get_navigator_page(explorer.navigator) === alpha.children[2]
        @test _nav_is(explorer.navigator.address,
                      concat_references(_explorer_entry_path(1),
                                        _explorer_path(FieldReferenceStep("children"), ElementReferenceStep(2))))
        # Escape in the filter empties it: the tree shows, with the node of the page
        # selected.
        _nav_press!(editor, backend, KeyDown(:f, ModifierKeys(ctrl = true); time = 0.0))
        @test explorer.filter.text == "two"
        _nav_press!(editor, backend, KeyDown(:escape, ModifierKeys(); time = 0.0))
        @test explorer.filter.text == "" && explorer.matches === nothing
        @test _explorer_has_tree_text(backend, "Inner") && _explorer_has_tree_text(backend, "alpha one")
        @test _nav_is(getfield(explorer, :selection)[],
                      _explorer_path(FieldReferenceStep("tree"), FieldReferenceStep("root"), FieldReferenceStep("entries"),
                                     ElementReferenceStep(1), FieldReferenceStep("children"), ElementReferenceStep(2)))
        # A duplicate starts with the same filter; a file keeps only the section.
        explorer.filter.text = "beta"
        copied = copy_document(DuplicatePolicy(), explorer)
        @test copied.filter.text == "beta" && copied.filter !== explorer.filter
        @test pred_arguments(explorer) == ((content,), Pair{Symbol,Any}[])
    end

    @testset "+ opens the menu of the kinds, after the selected entry or at the end of the root" begin
        content = _explorer_make()
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer)
        plus = string(Char(Dict(WidgetModule.LUCIDE_ICON_GLYPHS)[:plus]))
        press() = begin
            click = _explorer_click(backend, plus)
            @test click !== nothing
            answer = read_intent(editor.projection, nothing, Intent(click), editor.iomap).operation
            get_wrapped_operation(answer)
        end
        opened = press()
        @test opened isa OpenContextMenuOperation
        add = last(opened.layers[1][2].elements).operation
        @test add.section === content && add.index == 3
        _nav_press!(editor, backend, _explorer_click(backend, "alpha"))
        add = last(press().layers[1][2].elements).operation
        @test add.section === content && add.index == 2
    end

    @testset "▾ lists the kinds of the read rows, and a chosen kind keeps only its rows and those above" begin
        content = _explorer_make()
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer)
        funnel = string(Char(Dict(WidgetModule.LUCIDE_ICON_GLYPHS)[:funnel]))
        menu() = begin
            click = _explorer_click(backend, funnel)
            answer = read_intent(editor.projection, nothing, Intent(click), editor.iomap).operation
            only(get_wrapped_operation(answer).layers)[2]
        end
        items = menu().elements
        labels = [string(item.action.label) for item in items]
        @test labels[1] == "Every kind" && "Section" in labels && length(labels) == 3
        @test items[1].action.icon === :check
        evaluate_operation(editor, items[findfirst(==("Section"), labels)].operation)
        run_frame!(editor)
        @test only(explorer.filter.kinds) === ExplorerSection
        @test _explorer_has_tree_text(backend, "Inner") && !_explorer_has_tree_text(backend, "alpha")
        # The chosen kind has the check, and a second choice takes it out.
        items = menu().elements
        section = items[findfirst(item -> string(item.action.label) == "Section", items)]
        @test section.action.icon === :check
        evaluate_operation(editor, section.operation)
        run_frame!(editor)
        @test isempty(explorer.filter.kinds) && explorer.matches === nothing
    end

    @testset "the menu of a row opens, adds, removes and renames, and runs the commands of its document" begin
        content = _explorer_make()
        alpha, inner = content.entries[1], content.entries[2]
        long = _explorer_node("long", (_explorer_node("item $k") for k in 1:60)...)
        push!(content.entries, long)
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer)
        row_menu(label) = begin
            opened = _explorer_right_click(editor, backend, label)
            layer = only(filter(layer -> layer[1] == label, opened.layers))
            (opened, layer[2])
        end
        labels(menu) = [string(item.action.label) for item in menu.elements if item isa WidgetMenuItem]
        # An entry that is no section: open it, remove it, and move it; the first
        # entry moves only later.
        (_, menu) = row_menu("alpha")
        @test labels(menu) == ["Open in a new tab", "Remove from explorer", "Move the entry later"]
        # A section: rename it, and add to it.
        (_, menu) = row_menu("Inner")
        @test labels(menu) == ["Open in a new tab", "Remove from explorer", "Move the entry earlier",
                               "Move the entry later", "Rename", "New section", "Add…"]
        # A verb that acts at the row gets the same commands, with no caret in the
        # title and no menu of the kinds, and with the keys that run them.
        inner_steps = (FieldReferenceStep("tree"), FieldReferenceStep("root"), FieldReferenceStep("entries"),
                       ElementReferenceStep(2))
        rows = collect_part_commands(explorer, inner_steps)
        @test [row.description for row in rows] ==
              ["Open in a new tab", "Remove from explorer", "Move the entry earlier", "Move the entry later",
               "New section"]
        @test [row.gesture for row in rows][2:4] ==
              [describe_gesture_pattern(only(find_bound_keys(Explorer, name)))
               for name in ("Remove from explorer", "Move the entry earlier", "Move the entry later")]
        @test isempty(collect_part_commands(explorer, (FieldReferenceStep("filter"),)))
        # A long list of children opens as a page.
        (opened, menu) = row_menu("long")
        @test "Open as a list" in labels(menu)
        _nav_choose!(editor, opened, _nav_find_item(menu, "Open as a list"))
        @test get_navigator_page(explorer.navigator) === long.children
        # A node below an entry adds to the root of the explorer of the editor.
        _nav_press!(editor, backend, _explorer_open_chevron(backend, "alpha"))
        (opened, menu) = row_menu("alpha one")
        @test labels(menu) == ["Open in a new tab", "Add to explorer"]
        _nav_choose!(editor, opened, _nav_find_item(menu, "Add to explorer"))
        @test last(get_session_explorer_content(; editor).entries) === alpha.children[1]
        (opened, menu) = row_menu("alpha")
        _nav_choose!(editor, opened, _nav_find_item(menu, "Remove from explorer"))
        @test content.entries[1] === inner
        # The commands of the document of a row follow the items of the explorer.
        log = get_session_fault_log(; editor)
        logs = Explorer(ExplorerSection("Explorer", Any[log]))
        editor, backend = _nav_editor(logs)
        (_, menu) = row_menu(format_tree_node_label(log))
        @test any(element -> element isa WidgetSeparator, menu.elements)
        @test "Clear the fault log" in labels(menu)
    end

    @testset "a dashboard shows its cards in columns, a key in a card reaches its content, and Insert adds a card" begin
        @test "Dashboard" in first.(ExplorerModule._collect_entry_kinds())
        @test make_insertion_document(Dashboard).title == "New dashboard"
        dashboard = Dashboard("Queue study", Any[DashboardCard("First", PrimitiveString("one")),
                                                DashboardCard("Second", PrimitiveString("two")),
                                                DashboardCard("Third", PrimitiveString("three"))])
        @test [format_tree_node_label(card) for card in dashboard.cards] == ["First", "Second", "Third"]
        content = ExplorerSection("Explorer", Any[dashboard])
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer)
        _nav_press!(editor, backend, _explorer_click(backend, "Queue study"))
        @test get_navigator_page(explorer.navigator) === dashboard
        @test all(text -> _nav_has_text(backend, text), ("First", "Second", "Third", "one", "two", "three"))
        # The editor of the test has no size of its window, so the page gets no exact
        # width at its print, and the cards stand in one column.
        ys = [only(entry[3] for entry in _nav_texts(backend) if entry[1] == title) for title in ("First", "Second", "Third")]
        @test ys[1] < ys[2] < ys[3]
        # A press in the content of a card puts the caret in that document.
        _nav_press!(editor, backend, _explorer_click(backend, "two"; side = :page))
        selection = getfield(explorer, :selection)[]
        @test selection isa ConcreteReference
        @test _nav_steps(selection)[1:5] == [FieldReferenceStep("navigator"), FieldReferenceStep("content"),
                                             FieldReferenceStep("entries"), ElementReferenceStep(1), FieldReferenceStep("cards")]
        @test _nav_steps(selection)[6:7] == [ElementReferenceStep(2), FieldReferenceStep("content")]
        # With an exact width at the print, as many columns as cards of the least
        # width fit, and no more than the cards.
        grid_of(width) = begin
            context = PrinterContext(EmptyReference(), Cell(width), Cell(600), Dict{Symbol,Any}())
            page = print_document(DashboardToWidget(; gap = 10, card_width = 100), nothing, dashboard, context).output
            page.children[2].child.content
        end
        @test grid_of(430).columns == 3 && grid_of(205).columns == 1 && grid_of(220).columns == 2
        # The count follows the cell of the width while the page shows.
        width_cell = Cell(430)
        follow_page = print_document(DashboardToWidget(; gap = 10, card_width = 100), nothing, dashboard,
                              PrinterContext(EmptyReference(), width_cell, Cell(600), Dict{Symbol,Any}())).output
        holder() = follow_page.children[2].child.content
        @test holder().columns == 3
        width_cell[] = 205
        @test holder().columns == 1
        # In a live window, a resize lays the cards out again.
        card(title) = DashboardCard(title, PrimitiveString("text of " * title))
        study = Dashboard("Study", Any[card("One"), card("Two"), card("Three"), card("Four"), card("Five")])
        live_backend = HeadlessBackend()
        live = build_editor(study, _nav_natural(); backend = live_backend, devices = Device[Keyboard(), Mouse(), Display()],
                            window = (; title = "W", width = 1100, height = 500), tabs = true, appearance = false,
                            settings = false)
        run_frame!(live)
        rows() = (texts = _nav_drawn(last(rendered_output(live_backend)).windows[1].content);
                  length(unique(only(t[3] for t in texts if t[1] == name) for name in ("One", "Two", "Three", "Four", "Five"))))
        @test rows() == 2
        for (resized, expected) in ((640, 3), (400, 5), (1100, 2))
            push_event!(live_backend, WindowInput(:W, WindowResize(resized, 500; time = 0.0)))
            run_frame!(live)
            run_frame!(live)
            @test rows() == expected
        end
        # The path of a card in the grid names it back, whether the rows are a list,
        # `children[r][c]`, or the cards a vector, `children[k]`.
        for rows_are_list in (true, false), k in 1:7
            steps = (ExplorerModule._make_card_steps(k, 3, rows_are_list)..., FieldReferenceStep("content"),
                     FieldReferenceStep("rest"))
            @test ExplorerModule._find_card_below(steps, 3, rows_are_list) == (k, (FieldReferenceStep("rest"),))
        end
        @test ExplorerModule._make_card_steps(5, 3, true)[2:3] == (RangeReferenceStep(1, 2), RangeReferenceStep(1, 2))
        # Insert on the page adds a card at the end, whose content takes a name.
        _nav_press!(editor, backend, KeyDown(:insert, ModifierKeys(); time = 0.0))
        @test length(dashboard.cards) == 4 && dashboard.cards[4].content isa DocumentInsertion
        @test _nav_has_text(backend, "New card")
        # F2 on its node puts the caret in its title.
        _nav_press!(editor, backend, _explorer_click(backend, "Queue study"))
        _nav_press!(editor, backend, KeyDown(:f2, ModifierKeys(); time = 0.0))
        @test _nav_steps(getfield(explorer, :selection)[])[end - 1] == FieldReferenceStep("title")
    end

    @testset "the task list says where its groups and tasks are, so the explorer finds them" begin
        editor, _ = _nav_editor(PrimitiveString("start"))
        tasks = get_session_task_group_list(; editor)
        group = wrap_task_group_document(TaskGroup(_make_task_group_probe_tasks(0.0); name = "probe"))
        add_task_group!(tasks, group)
        # A host that puts the task list first has it once in the first content.
        content = make_editor_explorer_content(; editor, entries = Any[ExplorerSection("Projects"), tasks])
        @test count(entry -> entry === tasks, content.entries) == 1 && content.entries[2] === tasks
        groups_step = (FieldReferenceStep("groups"), ElementReferenceStep(1))
        @test _nav_is(find_navigator_address(tasks, group), _explorer_path(groups_step...))
        task = first(collect(getfield(group, :tasks)[]))
        @test _nav_is(find_navigator_address(tasks, task),
                      _explorer_path(groups_step..., FieldReferenceStep("tasks"), ElementReferenceStep(1)))
        @test _nav_is(find_navigator_address(content, task),
                      concat_references(_explorer_entry_path(2),
                                        _explorer_path(groups_step..., FieldReferenceStep("tasks"), ElementReferenceStep(1))))
        @test find_navigator_address(TaskGroupList(), group) === nothing
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

    @testset "Return in the filter searches below the node of the page, and reads the folders that nobody opened" begin
        root = mktempdir()
        mkpath(joinpath(root, "a", "b"))
        write(joinpath(root, "a", "b", "smoke.txt"), "")
        write(joinpath(root, "a", "other.txt"), "")
        mkpath(joinpath(root, "c", "d", "e"))
        write(joinpath(root, "c", "d", "e", "smoke.jl"), "")
        write(joinpath(root, "c", "smoke-test.jl"), "")
        workspace = Workspace([WorkspaceFolder("work", root)])
        content = ExplorerSection("Explorer", Any[workspace])
        explorer = Explorer(content)
        tree = explorer.tree
        editor, backend = _nav_editor(explorer; tabs = true)
        tasks = get_session_task_group_list(; editor)
        push!(content.entries, tasks)
        run_frame!(editor)
        # The page of Files, then the text in the filter, then Return.
        _nav_press!(editor, backend, _explorer_click(backend, "Files"))
        _nav_press!(editor, backend, KeyDown(:f, ModifierKeys(ctrl = true); time = 0.0))
        _nav_press!(editor, backend, (KeyPress(character; time = 0.0) for character in "smoke")...)
        _nav_press!(editor, backend, KeyPress('\n'; time = 0.0))
        search = only(collect_work_items(tasks))
        @test search isa ExplorerSearch && search.identifier == "S1"
        @test get_document_title(search) == "Find \"smoke\" below Files"
        @test get_navigator_page(explorer.navigator) === search
        # The page reads the result in each frame, so each folder below is read, one
        # level a frame, and no node of the tree opens for it.
        @test _explorer_wait_until(editor) do
            !is_cell_provisional(getfield(search, :result))
        end
        @test [format_tree_node_label(match.document) for match in search.result.matches] ==
              ["smoke.txt", "smoke.jl", "smoke-test.jl"]
        @test [join(match.labels, " / ") for match in search.result.matches] ==
              ["Files / work / a / b", "Files / work / c / d / e", "Files / work / c"]
        @test collect(keys(tree.expanded[content])) == Any[]
        @test _nav_has_text(backend, "smoke.jl") && _nav_has_text(backend, "Files / work / c / d / e")
        @test occursin("3 matches", get_document_decoration(search).detail)
        @test get_document_decoration(search).conditions[1].name === :done
        # A press on a match shows its page, and opens the nodes above it in the tree.
        _nav_press!(editor, backend, _explorer_click(backend, "smoke.txt"; side = :page))
        file = search.result.matches[1].document
        @test get_navigator_page(explorer.navigator) === file
        @test _explorer_wait_until(() -> _explorer_has_tree_text(backend, "smoke.txt"), editor)
        @test haskey(tree.expanded[content], workspace)
        # The search is a row of the task list, which the verbs find.
        @test find_task_group("S1"; editor) === search
        @test startswith(string(describe_task_group(search; editor)), "Find \"smoke\" below Files\n3 matches")
        @test occursin("smoke.txt — Files / work / a / b", string(describe_task_group(search; editor)))
        words = _collect_task_view_words(tasks)
        @test all(in(words), ("S1", "Find \"smoke\" below Files", "search", "done", "1 search · 0 running"))
    end

    @testset "a search goes on while its page or its row shows, and waits while neither does" begin
        root = mktempdir()
        mkpath(joinpath(root, "a", "b"))
        write(joinpath(root, "a", "b", "smoke.txt"), "")
        workspace = Workspace([WorkspaceFolder("work", root)])
        content = ExplorerSection("Explorer", Any[workspace])
        explorer = Explorer(content)
        editor, backend = _nav_editor(explorer; tabs = true)
        tasks = get_session_task_group_list(; editor)
        push!(content.entries, tasks)
        run_frame!(editor)
        _nav_press!(editor, backend, _explorer_click(backend, "Files"))
        _nav_press!(editor, backend, KeyDown(:f, ModifierKeys(ctrl = true); time = 0.0))
        _nav_press!(editor, backend, (KeyPress(character; time = 0.0) for character in "smoke")...)
        _nav_press!(editor, backend, KeyPress('\n'; time = 0.0))
        search = only(collect_work_items(tasks))
        # The page shows once and asks for the first folder; then the page of Files
        # shows, and the closed node of the tasks shows no row of the search.
        visit = make_navigator_open_operation(explorer.navigator, _explorer_entry_path(1))
        evaluate_operation(editor, ProjecturedPlatform.ExplorerModule._get_visit_writes(visit))
        @test get_navigator_page(explorer.navigator) === workspace
        # The frames run until the read of the first folder ends and nothing more
        # runs, so a read that the search started would end too.
        _explorer_run_until_idle(editor)
        directory = workspace.folders[1].directory
        a = only(directory.elements)
        @test a.state === :unread && a.read_count == 0
        # The row of the search shows under the node of the tasks, and its
        # decoration reads the result: the search goes on to its end.
        _nav_press!(editor, backend, KeyDown(:escape, ModifierKeys(); time = 0.0))
        @test get_navigator_page(explorer.navigator) === workspace
        _nav_press!(editor, backend, _explorer_open_chevron(backend, "Tasks"))
        @test _explorer_wait_until(editor) do
            !is_cell_provisional(getfield(search, :result))
        end
        @test [format_tree_node_label(match.document) for match in search.result.matches] == ["smoke.txt"]
        @test a.state === :read
    end

    @testset "a search stops at its depth and at its limit, and a stop keeps its matches and reads nothing more" begin
        content = ExplorerSection("Explorer", Any[_explorer_node("x top", _explorer_node("x one", _explorer_node("x deep")),
                                                                _explorer_node("x two"), _explorer_node("x three"))])
        deep = ExplorerSearch(content, Any[], "x"; depth = 2)
        @test [format_tree_node_label(match.document) for match in deep.result.matches] ==
              ["x top", "x one", "x two", "x three"]
        @test deep.result.is_deep && !deep.result.is_limited
        @test occursin("not below a depth of 2", get_document_decoration(deep).detail)
        few = ExplorerSearch(content, Any[], "x"; limit = 2)
        @test length(few.result.matches) == 2 && few.result.is_limited
        @test occursin("stopped at 2 matches", get_document_decoration(few).detail)
        # A search of a folder that is not read waits; a stop keeps what it found,
        # and the frames that show it read nothing.
        root = mktempdir()
        write(joinpath(root, "x.txt"), "")
        workspace = Workspace([WorkspaceFolder("work", root)])
        explorer = Explorer(ExplorerSection("Explorer", Any[workspace]))
        editor, backend = _nav_editor(explorer; tabs = true)
        search = ExplorerSearch(getfield(explorer, :tree)[].root, Any[FieldReferenceStep("entries"),
                                                                      ElementReferenceStep(1)], "x")
        add_task_group!(get_session_task_group_list(; editor), search)
        folder = workspace.folders[1].directory
        stop_work_item!(search)
        @test search.stopped && isempty(search.result.matches)
        @test get_document_decoration(search).conditions[1].name === :stopped
        visit = make_navigator_open_operation(getfield(explorer, :navigator)[], search, EmptyReference())
        evaluate_operation(editor, ProjecturedPlatform.ExplorerModule._get_visit_writes(visit))
        for _ in 1:10
            drain_operations!(editor)
            run_frame!(editor)
            sleep(0.02)
        end
        @test folder.state === :unread && folder.read_count == 0 && isempty(search.result.matches)
    end
end
end

# Run frames of `editor` until `test()` holds, while the editor has work that can
# change what a frame shows: a work of a background cell that runs or whose answers
# wait, or an operation that the last drain applied. A frame after which nothing
# runs or waits ends the wait, so the wait follows the work, and a slow machine
# waits as long as its work takes. The deadline only ends a work that never ends.
function _explorer_wait_until(test, editor)
    deadline = time() + 120
    while time() < deadline
        drained = drain_operations!(editor)
        run_frame!(editor)
        test() && return true
        (drained > 0 || _explorer_has_running_work(editor)) || return false
        sleep(0.02)
    end
    false
end

# Run frames of `editor` until nothing runs or waits, as a wait for a test that
# never holds ends.
_explorer_run_until_idle(editor) = (_explorer_wait_until(() -> false, editor); nothing)

# Whether a work of a background cell of `editor` runs, or ended and its answers
# wait in the inbox: its record ends when the editor writes the answers.
_explorer_has_running_work(editor) =
    any(record -> record.finished === nothing, get_background_work_store(editor).records)
