# The decoration of a document: the tint and the corner marks that its conditions
# give, in the order of the list of the conditions; a fact of a kind after the
# name; the conditions in words; the default that answers the document a layer
# holds; the icon with its marks and the pills of its counts; a row of a tree that
# draws them; and the default title of a tab, which reads the decoration of its
# content. The editor is the one of `NavigatorToWidgetTest.jl`.

@document struct _DecoratedNode
    name::String
    state::Symbol
end

# A layer that holds a document for a person to edit.
@document struct _DecoratedLayer
    content::Any
end

DocumentModule.get_edited_field(::_DecoratedLayer) = :content
TreeModule.format_tree_node_label(node::_DecoratedNode) = node.name

function DomainModule.get_document_decoration(node::_DecoratedNode)
    conditions = node.state === :running ? [DocumentCondition(:running), DocumentCondition(:waiting; count = 2)] :
                 node.state === :unsaved ? [DocumentCondition(:unsaved)] : DocumentCondition[]
    DocumentDecoration(; icon = :file, conditions, counts = [DocumentCount("2/4"; role = :accent)],
                       detail = "since 12:03")
end

# A fact of a kind, as a package declares one.
DomainModule.get_condition_look(::Val{:_decorated_fact}) = ConditionLook(:after_name, :lock, nothing, "a fact")

_decorated(conditions...; kwargs...) = DocumentDecoration(; icon = :file, conditions = DocumentCondition[conditions...],
                                                          kwargs...)

function test_document_decoration()
@testset "the decoration of a document" begin

    @testset "the tint and the marks follow the order of the conditions" begin
        file = _decorated(DocumentCondition(:unsaved), DocumentCondition(:changed_on_disk))
        @test find_decoration_tint(file) === :info
        marks = collect_decoration_marks(file)
        @test marks.bottom_right.glyph === :refresh
        @test marks.top_left === nothing && marks.top_right === nothing && marks.bottom_left === nothing
        @test format_decoration_words(file) == "changed on disk\nunsaved edits"
        # A failure tints before a wait, and each corner holds its own condition.
        busy = _decorated(DocumentCondition(:running), DocumentCondition(:waiting; count = 2),
                          DocumentCondition(:failed; count = 3), DocumentCondition(:read_only))
        @test find_decoration_tint(busy) === :error
        marks = collect_decoration_marks(busy)
        @test marks.top_left.glyph === :loader && marks.top_right.count == 2 && marks.top_right.glyph === nothing
        @test marks.bottom_left.count == 3 && marks.bottom_right.glyph === :lock
        @test format_decoration_words(busy) == "failed: 3\nwaits for you: 2\nrunning\nread only"
        # A condition takes the role of its result code.
        @test find_decoration_tint(_decorated(DocumentCondition(:unexpected; role = :error))) === :error
        # A condition with no tint gives none.
        @test find_decoration_tint(_decorated(DocumentCondition(:unsaved))) === nothing
        @test find_decoration_tint(_decorated()) === nothing
    end

    @testset "a fact of a kind shows after the name, and an unknown condition shows nothing" begin
        fact = _decorated(DocumentCondition(:_decorated_fact), DocumentCondition(:_no_such_condition))
        marks = collect_decoration_marks(fact)
        @test length(marks.after_name) == 1 && marks.after_name[1].glyph === :lock
        @test format_decoration_words(fact) == "a fact"
        @test find_decoration_tint(fact) === nothing
    end

    @testset "the default answers the document that a layer holds" begin
        node = _DecoratedNode("a", :unsaved)
        @test get_document_decoration(_DecoratedLayer(node)).detail == "since 12:03"
        @test get_document_decoration(PrimitiveString("plain")).icon === nothing
    end

    @testset "the icon has its tint and its marks, and the counts are pills" begin
        @test make_decoration_icon(_decorated()) === :file
        @test make_decoration_icon(DocumentDecoration()) === nothing
        icon = make_decoration_icon(get_document_decoration(_DecoratedNode("a", :running)))
        @test icon isa WidgetIcon && icon.name === :file && icon.role === :warning
        @test icon.top_left.content === :loader && icon.top_left.role === :accent
        @test icon.top_right.content == 2 && icon.bottom_right === nothing
        parts = make_decoration_badges(_decorated(DocumentCondition(:_decorated_fact);
                                                  counts = [DocumentCount("2/4"; role = :accent), DocumentCount("12")]))
        @test parts[1] isa WidgetIcon && parts[1].name === :lock
        @test parts[2] isa WidgetBadge && parts[2].content == "2/4" && parts[2].role === :accent
        @test parts[3] isa WidgetBadge && parts[3].role === nothing && parts[3].variant === :secondary
        # The drawing: the glyph, then a disc and a glyph for a glyph mark, and a pill
        # and a text for a count.
        badge = WidgetBadgeToGraphicsCanvas(WidgetTheme(); measure = FixedMeasure(8, 12, 4, 0))
        elements = Any[]
        @test WidgetModule._push_decorated_icon!(elements, badge, icon, 10, 10, 16, color_black, color_white)
        @test count(element -> element isa GraphicsText, elements) == 3
        @test count(element -> element isa GraphicsRect, elements) == 2
        @test WidgetModule.icon_width(icon, 16) == 16
    end

    @testset "a row of a tree draws the marks, the detail and the pills" begin
        root = _doctree_node("root", _DecoratedNode("busy", :running))
        tree = DocumentTree(root)
        editor, backend = _nav_editor(tree)
        @test _nav_has_text(backend, "busy") && _nav_has_text(backend, "since 12:03")
        @test _nav_has_text(backend, "2/4") && _nav_has_text(backend, "2")
        # The glyph of the loader mark at the top left.
        @test _nav_has_text(backend, string(find_icon_character(:loader)))
    end

    @testset "the kinds of the platform say their state" begin
        # A folder reads, then fails, with the failure in words.
        folder = make_filesystem_pathname(mktempdir())
        @test get_document_decoration(folder).icon === :folder
        folder.state = :reading
        @test find_decoration_tint(get_document_decoration(folder)) === :accent
        folder.failure = ErrorException("no access")
        folder.state = :failed
        decoration = get_document_decoration(folder)
        @test find_decoration_tint(decoration) === :error && occursin("no access", format_decoration_words(decoration))
        @test get_file_icon("notes.md") === :pilcrow && get_file_icon("model.jl") === :lambda && get_file_icon("x.bin") === :file
        # The logs count what they hold.
        log = MessageLog()
        push!(log.entries, MessageLogEntry("Error", "broken"), MessageLogEntry("Warn", "odd"), MessageLogEntry("Info", "fine"))
        @test [count.text for count in get_document_decoration(log).counts] == ["1 error", "1 warning"]
        @test isempty(get_document_decoration(FaultLog()).conditions)
        # A navigator says what its page says.
        node = _DecoratedNode("busy", :running)
        @test get_document_decoration(Navigator(node)).detail == "since 12:03"
        # A file page whose band shows says that the file changed on disk.
        path = joinpath(mktempdir(), "notes.txt")
        write(path, "hello")
        page = make_file_page(WidgetScrollPane(make_file_tab(path)))
        @test get_document_decoration(page).icon === :pilcrow
        @test isempty(get_document_decoration(page).conditions)
        page.band = FileBand(; message = "notes.txt changed on disk.")
        @test [condition.name for condition in get_document_decoration(page).conditions] == [:changed_on_disk]
    end

    @testset "a log that counts its faults has a command that clears them" begin
        log = FaultLog()
        push!(log.entries, FaultLogEntry(1, UInt64(1), :print, :Test, "broken", 1))
        @test only(get_document_decoration(log).conditions).count == 1
        collected = read_gesture(log, CollectIntents())
        clear = only(intent for intent in collected.intents if intent.description == "Clear the fault log")
        evaluate_operation(nothing, clear.operation)
        @test isempty(log.entries) && isempty(get_document_decoration(log).conditions)
        calls = McpLog()
        calls.faults = 2
        @test [count.text for count in get_document_decoration(calls).counts] == ["2 faults"]
        collected = read_gesture(calls, CollectIntents())
        clear = only(intent for intent in collected.intents if intent.description == "Clear the MCP log")
        evaluate_operation(nothing, clear.operation)
        @test calls.faults == 0 && isempty(get_document_decoration(calls).counts)
    end

    @testset "the default title of a tab reads the decoration of its content" begin
        node = _DecoratedNode("busy", :running)
        title = make_pane_tab_title(node, "busy")
        @test title.icon isa WidgetIcon && title.icon_role === :warning
        @test length(title.badges) == 1 && title.badges[1].content == "2/4"
        @test title.tooltip == "waits for you: 2\nrunning"
        # A plain document gives a tab with no icon, as before.
        plain = make_pane_tab_title(PrimitiveString("plain"), "plain")
        @test plain.icon === nothing && plain.icon_role === nothing && isempty(plain.badges) && plain.tooltip === nothing
    end
end
end
