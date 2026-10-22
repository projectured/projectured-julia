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
    elseif node isa CellVector || node isa AbstractVector
        foreach(child -> _collect_help_label_texts(child, found), node)
    end
    found
end

_help_double(click) = MouseClick(click.button, click.x, click.y, 2, ModifierKeys(); time = 0.0)

# The table of the page of `holder`, its headers, the first cell of each row, and
# the width policy of each column.
function _draw_help_table(holder)
    table = print_document(make_help_group_projection(), nothing, holder, nothing).output.children[2]
    (table, _collect_help_label_texts(table.column_headers),
     [first(_collect_help_label_texts(row)) for row in table.cells],
     [column.policy for column in table.columns])
end

# A double click on the first text `text` that the frame draws.
function _open_help_row!(editor, backend, text)
    click = _nav_click(backend, text)
    click === nothing && return false
    _nav_press!(editor, backend, click, _help_double(click))
    true
end

function test_help_pages()
@testset "the pages of the help" begin

@testset "the page of a tree is a line over a table of its groups, which fits its content" begin
    list = update_help_groups!(DocumentTypeList())
    output = print_document(make_help_group_projection(), nothing, list, nothing).output
    @test output isa GridLayout
    count = sum(group -> group.count, list.children)
    @test startswith(only(_collect_help_label_texts(output.children[1])), "$count document types in ")
    (table, headers, names, policies) = _draw_help_table(list)
    @test table isa WidgetTable
    @test headers == ["name", "types", "description"]
    @test names == [group.name for group in list.children]
    # The name and the count are as wide as their widest cell, and the
    # description takes the rest.
    @test policies == [Content, Content, Fill]
    platform = _find_help_child(list, "Platform")
    (_, headers, names, policies) = _draw_help_table(_find_help_child(platform, "Widget"))
    @test headers == ["name", "names to type", "description"]
    @test names == [entry.name for entry in _find_help_child(platform, "Widget").children]
    @test policies == [Content, Content, Fill]
    projections = update_help_groups!(ProjectionList())
    (_, headers, _, policies) = _draw_help_table(_find_help_child(_find_help_child(projections, "Platform"), "Widget"))
    @test headers == ["name", "description"]
    @test policies == [Content, Fill]
    # A tree that no acquire built has no group, and its page shows the line alone.
    @test length(print_document(make_help_group_projection(), nothing, DocumentTypeList(), nothing).output.children) == 1
end

@testset "a node maps to its row, and the row back to the node" begin
    list = update_help_groups!(DocumentTypeList())
    p = make_help_group_projection()
    iomap = print_document(p, nothing, list, nothing)
    k = findfirst(group -> group.name == "Platform", collect(list.children))
    node = _help_tree_path(FieldReferenceStep("children"), ElementReferenceStep(k))
    row = _help_tree_path(FieldReferenceStep("children"), RangeReferenceStep(1, 2), FieldReferenceStep("rows"),
                          RangeReferenceStep(k - 1, k))
    @test _help_tree_steps(map_reference_forward(p, iomap, node)) == _help_tree_steps(row)
    @test _help_tree_steps(map_reference_forward(p, iomap, extend_reference(node, FieldReferenceStep("name")))) ==
          _help_tree_steps(row)
    @test _help_tree_steps(map_reference_backward(p, iomap, row)) == _help_tree_steps(node)
    # A press on the line leaves the selection where it is.
    @test map_reference_backward(p, iomap, _help_tree_path(FieldReferenceStep("children"), RangeReferenceStep(0, 1))) ===
          nothing
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
