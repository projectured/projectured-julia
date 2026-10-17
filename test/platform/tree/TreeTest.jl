# A tree of documents: the nodes of plain documents with one or two collections of
# children, the maps of a path both ways, the open nodes by the identity of their
# documents, a node that computes again alone, the verb that shows a tree, and a
# double click on a node of a tree and on a row of a roster that opens a page in a
# navigator, which Back leaves. The editor is the one of `NavigatorToWidgetTest.jl`.

# A node with a name and one collection of children.
@document struct _DocTreeNode
    name::String
    children::CellVector
end

# A node with a title and two collections: its parts and its notes.
@document struct _DocTreePair
    name::String
    parts::CellVector
    notes::CellVector
end

# A node whose children are a lazy list.
@document struct _DocTreeLazy
    name::String
    children::Any
end

# A document that says nothing of itself.
@document struct _DocTreeLeaf
    value::Int
end

# A node that notes each acquire and each release of it, by its name.
@document struct _DocTreeHeld
    name::String
    children::CellVector
end

const _DOCTREE_HOLD_EVENTS = Tuple{Symbol,String}[]

# A node that says whether it has children: `true`, `false`, or `nothing` while
# that is not known, whatever its collection holds.
@document struct _DocTreeKnown
    known::Any
    children::CellVector
end

ProjecturedPlatform.DomainModule.acquire_document!(editor, node::_DocTreeHeld) =
    (push!(_DOCTREE_HOLD_EVENTS, (:acquire, node.name)); nothing)
ProjecturedPlatform.DomainModule.release_document!(editor, node::_DocTreeHeld) =
    (push!(_DOCTREE_HOLD_EVENTS, (:release, node.name)); nothing)

_doctree_held(name, children...) = _DocTreeHeld(name, CellVector(Any[children...]))

# An editor that counts the holders of the documents, and draws nothing.
_doctree_hold_editor(document) =
    Editor(document, IdentityProjection(); backend = HeadlessBackend(), devices = Device[])

# How often the label of each node is computed.
const _DOCTREE_LABEL_COUNTS = IdDict{Any,Int}()

TreeModule.get_tree_children_steps(::_DocTreeNode) = ((FieldReferenceStep("children"),),)
TreeModule.get_tree_children_steps(::_DocTreeHeld) = ((FieldReferenceStep("children"),),)
TreeModule.get_tree_children_steps(::_DocTreeKnown) = ((FieldReferenceStep("children"),),)
TreeModule.get_tree_children_steps(::_DocTreeLazy) = ((FieldReferenceStep("children"),),)
TreeModule.has_tree_children(node::_DocTreeKnown) = node.known
TreeModule.get_tree_children_steps(::_DocTreePair) = ((FieldReferenceStep("parts"),), (FieldReferenceStep("notes"),))
TreeModule.get_tree_node_icon(::_DocTreePair) = :folder
DocumentModule.get_document_title(pair::_DocTreePair) = pair.name

function TreeModule.format_tree_node_label(node::_DocTreeNode)
    _DOCTREE_LABEL_COUNTS[node] = get(_DOCTREE_LABEL_COUNTS, node, 0) + 1
    node.name
end

_doctree_node(name, children...) = _DocTreeNode(name, CellVector(Any[children...]))

# A root with two parts and a note; the first part holds two nodes.
function _doctree_make()
    first_part = _doctree_node("alpha", _doctree_node("alpha one"), _doctree_node("alpha two"))
    root = _DocTreePair("root", CellVector(Any[first_part, _doctree_node("beta")]),
                        CellVector(Any[_doctree_node("gamma")]))
    root
end

_doctree_path(steps...) = extend_reference(EmptyReference(), steps...)

# The path of the node at the index path `indices` of the widget.
function _doctree_node_path(indices...)
    steps = Any[FieldReferenceStep("roots"), ElementReferenceStep(indices[1])]
    foreach(k -> push!(steps, FieldReferenceStep("children"), ElementReferenceStep(k)), indices[2:end])
    _doctree_path(steps...)
end

# The write of the open nodes of the widget that a chevron makes.
_doctree_chevron(widget, paths...) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(widget, "expanded", Set{Vector{Int}}(paths)))

_doctree_double(click) = MouseClick(click.button, click.x, click.y, 2, ModifierKeys(); time = 0.0)

# Whether the open nodes of `tree` are the documents `documents`, by identity.
_doctree_is_open(tree, documents...) =
    length(tree.expanded) == length(documents) && all(document -> haskey(tree.expanded, document), documents)

function test_document_tree()
@testset "a tree of documents" begin
    projection = DocumentTreeToWidgetTree()
    root_step = FieldReferenceStep("root")

    @testset "the nodes of plain documents, with one or two collections" begin
        @test get_tree_children_steps(_DocTreeLeaf(1)) == ()
        @test get_tree_node_icon(_DocTreeLeaf(1)) === nothing
        @test format_tree_node_label(_DocTreeLeaf(1)) == "_DocTreeLeaf"
        @test format_tree_node_label(_doctree_make()) == "root"
        root = _doctree_make()
        tree = DocumentTree(root)
        @test tree.title == "root" && get_document_title(tree) == "root"
        @test DocumentTree(root; title = "Parts").title == "Parts"
        # The root is open at the start, by the identity of its document.
        @test _doctree_is_open(tree, root)
        widget = print_document(projection, nothing, tree, nothing).output
        @test widget isa WidgetTree && length(widget.roots) == 1
        node = widget.roots[1]
        @test node.label == "root" && node.icon === :folder
        # The children of a node are its parts, then its notes.
        @test [child.label for child in node.children] == ["alpha", "beta", "gamma"]
        @test [child.label for child in node.children[1].children] == ["alpha one", "alpha two"]
        @test isempty(node.children[2].children)
        @test widget.expanded == Set([[1]])
        # A file keeps the root and the title, and no open node.
        (positional, keywords) = pred_arguments(tree)
        @test length(positional) == 1 && positional[1] === root && keywords == Pair{Symbol,Any}[:title => "root"]
        read = parse_pred_text(print_pred_text(DocumentTree(PrimitiveString("x"); title = "Leaf")))
        @test read isa DocumentTree && read.title == "Leaf" && read.root.value == "x"
        @test _doctree_is_open(read, read.root)
    end

    @testset "a path maps both ways" begin
        root = _doctree_make()
        tree = DocumentTree(root)
        iomap = print_document(projection, nothing, tree, nothing)
        widget = iomap.output
        forward(path) = map_reference_forward(projection, iomap, path)
        backward(path) = map_reference_backward(projection, iomap, path)
        notes_first = _doctree_path(root_step, FieldReferenceStep("notes"), ElementReferenceStep(1))
        alpha_two = _doctree_path(root_step, FieldReferenceStep("parts"), ElementReferenceStep(1),
                                  FieldReferenceStep("children"), ElementReferenceStep(2))
        @test _nav_is(forward(_doctree_path(root_step)), _doctree_node_path(1))
        @test _nav_is(forward(notes_first), _doctree_node_path(1, 3))
        @test _nav_is(forward(alpha_two), _doctree_node_path(1, 1, 2))
        # A path inside a document maps to the row of its node.
        @test _nav_is(forward(extend_reference(alpha_two, FieldReferenceStep("name"))), _doctree_node_path(1, 1, 2))
        @test forward(_doctree_path(FieldReferenceStep("title"))) === nothing
        @test _nav_is(backward(_doctree_node_path(1)), _doctree_path(root_step))
        @test _nav_is(backward(_doctree_node_path(1, 3)), notes_first)
        @test _nav_is(backward(_doctree_node_path(1, 1, 2)), alpha_two)
        @test backward(_doctree_node_path(1, 9)) === nothing
        # Any other part of the widget is a part that the view drew.
        @test has_introduced_step(backward(_doctree_path(FieldReferenceStep("scroll_position"))))
        @test has_introduced_step(backward(EmptyReference()))
        # The selection of the tree document is the selection of the widget.
        getfield(tree, :selection)[] = alpha_two
        @test _nav_is(widget.selection, _doctree_node_path(1, 1, 2))
        # A press on a node selects its document.
        answer = read_intent(projection, iomap, ReplaceSelectionOperation(_doctree_node_path(1, 3)))
        @test answer isa ReplaceSelectionOperation && _nav_is(answer.path, notes_first)
        # A double click on a node and Return on it open its document as a page.
        double = MouseClick(:left, 0, 0, 2, ModifierKeys(); time = 0.0)
        gamma = widget.roots[1].children[3]
        for gesture in (double, KeyPress('\n'; time = 0.0))
            open = read_bound_gesture(gamma, gesture, nothing)
            @test open isa OpenPageOperation && _nav_is(open.reference, _doctree_node_path(1, 3))
            mapped = read_intent(projection, iomap, open)
            @test mapped isa OpenPageOperation && _nav_is(mapped.reference, notes_first)
        end
        @test read_bound_gesture(gamma, MouseClick(:left, 0, 0, 1, ModifierKeys(); time = 0.0), nothing) === nothing
    end

    @testset "an open node stays open when a node comes before it" begin
        root = _doctree_make()
        tree = DocumentTree(root)
        iomap = print_document(projection, nothing, tree, nothing)
        widget = iomap.output
        alpha = root.parts[1]
        # A chevron writes the open nodes of the tree document, as view state.
        write = read_intent(projection, iomap, _doctree_chevron(widget, [1], [1, 1]))
        @test write isa ReplaceViewStateOperation
        writes = get_wrapped_operation(write).operations
        @test first(writes).document === tree
        @test last(writes) isa ChangeHeldDocumentsOperation && last(writes).acquired == Any[alpha]
        evaluate_operation(nothing, write)
        @test _doctree_is_open(tree, root, alpha)
        @test widget.expanded == Set([[1], [1, 1]])
        insert!(root.parts, 1, _doctree_node("first"))
        @test widget.expanded == Set([[1], [1, 2]])
        @test widget.roots[1].children[2].label == "alpha"
        # A node under a closed node is not open.
        evaluate_operation(nothing, read_intent(projection, iomap, _doctree_chevron(widget, [1, 2])))
        @test isempty(widget.expanded)
        @test [child.label for child in widget.roots[1].children] == ["first", "alpha", "beta", "gamma"]
        # The next write holds only the documents of the nodes that are there.
        evaluate_operation(nothing, read_intent(projection, iomap, _doctree_chevron(widget, [1], [1, 2])))
        deleteat!(root.parts, 2)
        @test widget.expanded == Set([[1]])
        evaluate_operation(nothing, read_intent(projection, iomap, _doctree_chevron(widget, [1], [1, 3])))
        @test _doctree_is_open(tree, root, root.notes[1])
    end

    @testset "a node whose children are a lazy list makes the entries that the rows reach" begin
        made = Ref(0)
        runs = make_index_list(1_000_000, 1, k -> (made[] += 1; _doctree_node("run $k")))
        lazy = _DocTreeLazy("runs", runs)
        root = _doctree_node("root", lazy)
        tree = DocumentTree(root)
        iomap = print_document(projection, nothing, tree, nothing)
        widget = iomap.output
        @test has_tree_children(lazy)
        # The open of the lazy node makes no child.
        evaluate_operation(nothing, read_intent(projection, iomap, _doctree_chevron(widget, [1], [1, 1])))
        @test _doctree_is_open(tree, root, lazy) && made[] <= 1
        # The children of its node are a lazy list: a walk of twenty rows makes
        # twenty children.
        children = widget.roots[1].children[1].children
        @test children isa ListNode
        link = children
        for _ in 1:19
            link = link.next
        end
        @test link.value.label == "run 20" && made[] <= 21
        # A path maps both ways, counted from the head of the list.
        @test _nav_is(map_reference_backward(projection, iomap, _doctree_node_path(1, 1, 5)),
                      _doctree_path(root_step, FieldReferenceStep("children"), ElementReferenceStep(1),
                                    FieldReferenceStep("children"), ElementReferenceStep(5)))
        run_five = _doctree_path(root_step, FieldReferenceStep("children"), ElementReferenceStep(1),
                                 FieldReferenceStep("children"), ElementReferenceStep(5))
        @test _nav_is(map_reference_forward(projection, iomap, run_five), _doctree_node_path(1, 1, 5))
        # A chevron on a child that a walk made opens it and holds its document.
        write = read_intent(projection, iomap, _doctree_chevron(widget, [1], [1, 1], [1, 1, 3]))
        @test last(get_wrapped_operation(write).operations).acquired == Any[runs[3]]
        evaluate_operation(nothing, write)
        @test widget.expanded == Set([[1], [1, 1], [1, 1, 3]])
        @test made[] <= 21
        # A second print finds the open child, which the walks of the list reached.
        again = print_document(projection, nothing, tree, nothing).output
        @test again.expanded == Set([[1], [1, 1], [1, 1, 3]])
        # A path past the end of the list reaches no document.
        @test map_reference_backward(projection, iomap, _doctree_node_path(1, 1, 2_000_000)) === nothing
        @test made[] <= 21
    end

    @testset "a node draws a chevron only when its document is known to have children" begin
        root = _doctree_node("root", _DocTreeKnown(true, CellVector()),
                             _DocTreeKnown(false, CellVector(Any[_doctree_node("x")])),
                             _DocTreeKnown(nothing, CellVector(Any[_doctree_node("y")])))
        widget = print_document(projection, nothing, DocumentTree(root), nothing).output
        has_chevron(node) = WidgetModule._wtree_has_children(node)
        nodes = widget.roots[1].children
        @test has_chevron(nodes[1]) && !has_chevron(nodes[2]) && !has_chevron(nodes[3])
        # A plain document has children when a collection of them has an element.
        @test has_chevron(widget.roots[1])
        @test has_tree_children(root) && !has_tree_children(_doctree_node("leaf"))
    end

    @testset "a tree holds the documents of its open nodes while a tab holds the tree" begin
        empty!(_DOCTREE_HOLD_EVENTS)
        root = _doctree_held("root", _doctree_held("a", _doctree_held("a1")), _doctree_held("b"))
        tree = DocumentTree(root)
        iomap = print_document(projection, nothing, tree, nothing)
        widget = iomap.output
        editor = _doctree_hold_editor(PrimitiveString("x"))
        chevron!(paths...) = evaluate_operation(editor, read_intent(projection, iomap, _doctree_chevron(widget, paths...)))
        # A tree that nothing holds passes nothing on.
        chevron!([1], [1, 1])
        @test isempty(_DOCTREE_HOLD_EVENTS)
        # A tab that shows the tree holds it, and the tree holds its open nodes.
        tab = PaneTab("tree", tree)
        evaluate_operation(editor, AcquireDocumentOperation(tab))
        @test sort(_DOCTREE_HOLD_EVENTS) == [(:acquire, "a"), (:acquire, "root")]
        # A node that opens is acquired, and a node that closes is released.
        empty!(_DOCTREE_HOLD_EVENTS)
        chevron!([1], [1, 1], [1, 1, 1])
        @test _DOCTREE_HOLD_EVENTS == [(:acquire, "a1")]
        chevron!([1])
        @test sort(_DOCTREE_HOLD_EVENTS) == [(:acquire, "a1"), (:release, "a"), (:release, "a1")]
        # A document that two holders show is released at its last holder.
        empty!(_DOCTREE_HOLD_EVENTS)
        other = PaneTab("root", root)
        evaluate_operation(editor, AcquireDocumentOperation(other))
        evaluate_operation(editor, ReleaseDocumentOperation(tab))
        @test isempty(_DOCTREE_HOLD_EVENTS)
        evaluate_operation(editor, ReleaseDocumentOperation(other))
        @test _DOCTREE_HOLD_EVENTS == [(:release, "root")]
        # A release of a document that nothing holds releases nothing.
        evaluate_operation(editor, ReleaseDocumentOperation(other))
        @test _DOCTREE_HOLD_EVENTS == [(:release, "root")]
    end

    @testset "a tree holds the documents of the rows that its view shows" begin
        empty!(_DOCTREE_HOLD_EVENTS)
        runs = make_index_list(1_000_000, 1, k -> _doctree_held("run $k"))
        tree = DocumentTree(_DocTreeLazy("runs", runs))
        widgets = RecursiveProjection(WidgetToGraphics(StyleFont("Ubuntu", 20); measure = FixedMeasure(8, 12, 4, 0)))
        chain = ChainingProjection(projection, widgets)
        context = with_exact_size(PrinterContext(); width = Cell(Int32(300)), height = Cell(Int32(200)))
        iomap = print_document(chain, nothing, tree, context)
        editor = _doctree_hold_editor(PrimitiveString("x"))
        # The runs that the tree holds, from the acquires and the releases that they note.
        held = Set{String}()
        function follow!()
            for (kind, name) in _DOCTREE_HOLD_EVENTS
                kind === :acquire ? push!(held, name) : delete!(held, name)
            end
            empty!(_DOCTREE_HOLD_EVENTS)
            held
        end
        # No view told the tree its rows yet: a tab that shows it makes it hold the
        # first fifty runs of its open lazy list.
        tab = PaneTab("tree", tree)
        evaluate_operation(editor, AcquireDocumentOperation(tab))
        @test length(follow!()) == 50 && "run 1" in held && "run 50" in held
        # A wheel turn down: the tree holds the runs that its view shows, and lets
        # go of the others, as view state.
        turn = read_intent(chain, iomap, MouseScroll(0, -3, 20, 60; time = 0.0))
        is_view_state(operation) = operation isa ReplaceViewStateOperation ||
            (operation isa CompoundOperation && all(is_view_state, operation.operations))
        @test turn isa CompoundOperation && is_view_state(turn)
        evaluate_operation(editor, turn)
        @test held == Set(document.name for document in keys(tree.shown) if document isa _DocTreeHeld) ==
              follow!()
        @test 9 <= length(held) <= 11 && !("run 50" in held)
        # More turns move the holds down the list, and the count stays the rows of the view.
        for time in 1.0:1.0:40.0
            evaluate_operation(editor, read_intent(chain, iomap, MouseScroll(0, -3, 20, 60; time)))
        end
        follow!()
        @test 9 <= length(held) <= 11 && !("run 1" in held)
        # The release of the tab lets go of every run.
        evaluate_operation(editor, ReleaseDocumentOperation(tab))
        @test isempty(follow!())
    end

    @testset "a navigator holds its page, and a visit moves the hold" begin
        empty!(_DOCTREE_HOLD_EVENTS)
        root = _doctree_held("root", _doctree_held("a"))
        navigator = Navigator(root)
        editor = _doctree_hold_editor(navigator)
        tab = PaneTab("page", navigator)
        # The tab holds the navigator and its content, and the navigator holds its
        # page, the content, which is acquired once.
        evaluate_operation(editor, AcquireDocumentOperation(tab))
        @test _DOCTREE_HOLD_EVENTS == [(:acquire, "root")]
        child = _doctree_path(FieldReferenceStep("children"), ElementReferenceStep(1))
        evaluate_operation(editor, make_navigator_open_operation(navigator, root, child))
        @test get_navigator_page(navigator) === root.children[1]
        # The content stays held by the tab when the navigator leaves it.
        @test _DOCTREE_HOLD_EVENTS == [(:acquire, "root"), (:acquire, "a")]
        evaluate_operation(editor, make_navigator_back_operation(navigator))
        @test _DOCTREE_HOLD_EVENTS == [(:acquire, "root"), (:acquire, "a"), (:release, "a")]
        # The close of the tab releases the page of the navigator and its content.
        empty!(_DOCTREE_HOLD_EVENTS)
        evaluate_operation(editor, make_navigator_open_operation(navigator, root, child))
        evaluate_operation(editor, ReleaseDocumentOperation(tab))
        @test sort(_DOCTREE_HOLD_EVENTS) == [(:acquire, "a"), (:release, "a"), (:release, "root")]
    end

    @testset "a change of one document computes its own node again, and no other" begin
        root = _doctree_make()
        tree = DocumentTree(root)
        tree.expanded = IdDict{Any,Nothing}(root => nothing, root.parts[1] => nothing)
        widget = print_document(projection, nothing, tree, nothing).output
        read_labels() = (node = widget.roots[1];
                         vcat([child.label for child in node.children],
                              [child.label for child in node.children[1].children]))
        alpha = root.parts[1]
        nodes = Any[alpha, root.parts[2], root.notes[1], alpha.children[1], alpha.children[2]]
        @test read_labels() == ["alpha", "beta", "gamma", "alpha one", "alpha two"]
        before = Dict(n => _DOCTREE_LABEL_COUNTS[node] for (n, node) in enumerate(nodes))
        under = widget.roots[1].children[1].children
        alpha.name = "alpha*"
        @test read_labels() == ["alpha*", "beta", "gamma", "alpha one", "alpha two"]
        @test _DOCTREE_LABEL_COUNTS[alpha] == before[1] + 1
        @test all(_DOCTREE_LABEL_COUNTS[nodes[n]] == before[n] for n in 2:5)
        # The nodes under it are the same nodes.
        @test widget.roots[1].children[1].children === under
    end

    @testset "the verb shows a tree in a tab" begin
        root = _doctree_make()
        editor, backend = _nav_editor(PrimitiveString("start"); tabs = true)
        shown = show_document_tree!(root; editor)
        drain_operations!(editor)
        run_frame!(editor)
        @test shown isa ReferencedDocument
        tree = get_document(shown)
        @test tree isa DocumentTree && tree.root === root && tree.title == "root"
        @test try_evaluate_reference(editor.document, get_reference(shown), nothing) === tree
        @test _nav_has_text(backend, "alpha") && _nav_has_text(backend, "gamma")
    end

    @testset "a double click on a node opens its document in a navigator, and Back returns" begin
        root = _doctree_make()
        tree = DocumentTree(root)
        navigator = Navigator(tree)
        editor, backend = _nav_editor(navigator)
        click = _nav_click(backend, "gamma")
        @test click !== nothing
        _nav_press!(editor, backend, click, _doctree_double(click))
        @test get_navigator_page(navigator) === root.notes[1]
        @test _nav_is(navigator.address, _doctree_path(root_step, FieldReferenceStep("notes"), ElementReferenceStep(1)))
        back = _nav_click(backend, _NAV_BACK)
        @test back !== nothing
        _nav_press!(editor, backend, back)
        @test get_navigator_page(navigator) === tree
        @test navigator.address isa EmptyReference
        @test _nav_has_text(backend, "gamma")
    end

    @testset "a double click on a row of a roster opens its item in a navigator, and Back returns" begin
        items = CellVector(Any[_doctree_node("first"), _doctree_node("second")])
        roster = link_roster!(Roster(CollectionItems(items); columns = ["name"], title = "Nodes"), items)
        navigator = Navigator(roster)
        editor, backend = _nav_editor(navigator)
        click = _nav_click(backend, "second")
        @test click !== nothing
        _nav_press!(editor, backend, click, _doctree_double(click))
        @test get_navigator_page(navigator) === items[2]
        @test _nav_is(navigator.address, _doctree_path(FieldReferenceStep("rows"), ElementReferenceStep(2),
                                                       FieldReferenceStep("item")))
        back = _nav_click(backend, _NAV_BACK)
        @test back !== nothing
        _nav_press!(editor, backend, back)
        @test get_navigator_page(navigator) === roster
        @test _nav_has_text(backend, "second")
    end
end
end
