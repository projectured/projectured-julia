# The pages of the help: the table of a tree and of a group, the open of a row at
# the place of its node in the tree, and the page of a type.

# The text of each label of a page, from the top.
function _collect_help_label_texts(node, found = String[])
    node isa Cell && (node = node[])
    if node isa WidgetLabel
        push!(found, String(node.content))
    elseif node isa LayoutConstraint
        _collect_help_label_texts(node.child, found)
    elseif node isa WidgetScrollPane
        _collect_help_label_texts(node.content, found)
    elseif node isa VerticalLayout || node isa GridLayout
        foreach(child -> _collect_help_label_texts(child, found), node.children)
    end
    found
end

_help_double(click) = MouseClick(click.button, click.x, click.y, 2, ModifierKeys(); time = 0.0)

_get_help_columns(holder) = collect(String, holder.table.columns)

# A double click on the first text `text` that the frame draws.
function _open_help_row!(editor, backend, text)
    click = _nav_click(backend, text)
    click === nothing && return false
    _nav_press!(editor, backend, click, _help_double(click))
    true
end

function test_help_pages()
@testset "the pages of the help" begin

@testset "the page of a tree is a line over the table of its groups" begin
    list = update_help_groups!(DocumentTypeList())
    output = print_document(make_help_group_projection(), nothing, list, nothing).output
    @test output isa GridLayout
    count = sum(group -> group.count, list.children)
    @test startswith(only(_collect_help_label_texts(output.children[1])), "$count document types in ")
    @test output.children[2] === list.table
    @test _get_help_columns(list) == ["name", "count", "description"]
    @test [row.item for row in list.table.rows] == collect(list.children)
    platform = _find_help_child(list, "Platform")
    @test [row.item for row in platform.table.rows] == collect(platform.children)
    @test _get_help_columns(_find_help_child(platform, "Widget")) == ["name", "typed", "description"]
    projections = update_help_groups!(ProjectionList())
    @test _get_help_columns(_find_help_child(_find_help_child(projections, "Platform"), "Widget")) ==
          ["name", "description"]
    # A tree that no acquire built has no table, and its page shows the line alone.
    @test length(print_document(make_help_group_projection(), nothing, DocumentTypeList(), nothing).output.children) == 1
end

@testset "the open of a row opens the node at its place in the tree" begin
    list = update_help_groups!(DocumentTypeList())
    k = findfirst(group -> group.name == "Platform", collect(list.children))
    row = _help_tree_path(FieldReferenceStep("table"), FieldReferenceStep("rows"), ElementReferenceStep(k),
                          FieldReferenceStep("item"), FieldReferenceStep("name"))
    @test _help_tree_steps(HelpModule._find_help_node_path(list, row)) ==
          _help_tree_steps(_help_tree_path(FieldReferenceStep("children"), ElementReferenceStep(k),
                                           FieldReferenceStep("name")))
    @test HelpModule._find_help_node_path(list, _help_tree_path(FieldReferenceStep("children"))) === nothing
end

@testset "the page of a type shows its name, its module, the names to type and its whole docstring" begin
    list = update_help_groups!(DocumentTypeList())
    about = _find_help_child(_find_help_child(_find_help_child(list, "Platform"), "Help"), "AboutPage")
    texts = _collect_help_label_texts(print_document(make_help_entry_projection(), nothing, about, nothing).output)
    @test texts[1:3] == ["AboutPage", "ProjecturedPlatform.HelpModule", "Names to type in an empty tab: " * about.typed]
    @test texts[4:end] == split(about.text, '\n')
    @test texts[4] == "    AboutPage(; name, summary, version, homepage)"
    bare = HelpEntry("Bare", Int, "", "", "")
    @test _collect_help_label_texts(print_document(make_help_entry_projection(), nothing, bare, nothing).output) ==
          ["Bare", "Core", "No description."]
end

@testset "in a navigator, a double click on a row opens its page, and Parent and Back return" begin
    list = DocumentTypeList()
    navigator = Navigator(list)
    editor, backend = _nav_editor(navigator)
    # A tab acquires its navigator, as this does, and the navigator its page,
    # whose acquire builds the groups.
    @test isempty(list.children)
    evaluate_operation(editor, AcquireDocumentOperation(navigator))
    @test !isempty(list.children)
    run_frame!(editor)
    @test _open_help_row!(editor, backend, "Platform")
    platform = _find_help_child(list, "Platform")
    @test get_navigator_page(navigator) === platform
    k = findfirst(group -> group === platform, collect(list.children))
    @test _help_tree_steps(navigator.address) ==
          _help_tree_steps(_help_tree_path(FieldReferenceStep("children"), ElementReferenceStep(k)))
    @test _open_help_row!(editor, backend, "Help")
    help = _find_help_child(platform, "Help")
    @test get_navigator_page(navigator) === help
    @test _open_help_row!(editor, backend, "AboutPage")
    about = _find_help_child(help, "AboutPage")
    @test get_navigator_page(navigator) === about
    @test _nav_has_text(backend, "ProjecturedPlatform.HelpModule")
    @test _nav_has_text(backend, "What a program says about itself")
    # Parent goes to the group of the type, and Back returns to the type.
    parent = _nav_click(backend, _NAV_PARENT)
    @test parent !== nothing
    _nav_press!(editor, backend, parent)
    @test get_navigator_page(navigator) === help
    back = _nav_click(backend, _NAV_BACK)
    @test back !== nothing
    _nav_press!(editor, backend, back)
    @test get_navigator_page(navigator) === about
end

end
end
