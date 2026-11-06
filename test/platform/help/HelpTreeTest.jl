# The trees of the help: the groups of the packages and of the modules, the
# entries of the types, what a second build keeps, and the nodes of the tree
# slice.

_help_tree_path(steps...) = extend_reference(EmptyReference(), steps...)
_help_tree_steps(reference) = get_reference_steps(strip_reference_types(reference))
_find_help_child(holder, name) = only(child for child in holder.children if child.name == name)

# The entries below a group, at any depth.
_collect_help_entries(holder) =
    Any[(child isa HelpEntry ? Any[child] : _collect_help_entries(child)) for child in holder.children] |>
    parts -> reduce(vcat, parts; init = Any[])

function test_help_tree()
@testset "the trees of the help" begin

@testset "a new tree holds no group, and its build groups the types by package and by module" begin
    list = DocumentTypeList()
    @test isempty(list.children)
    @test update_help_groups!(list) === list
    names = [group.name for group in list.children]
    # The kernel and the platform come first, then the other packages by name.
    first_names = [name for name in names if name in ("Kernel", "Platform")]
    @test "Platform" in first_names && names[1:length(first_names)] == first_names
    rest = names[(length(first_names) + 1):end]
    @test sort(rest; by = lowercase) == rest
    entries = _collect_help_entries(list)
    @test length(entries) == sum(group -> group.count, list.children)
    # Every document type is in the tree, one for each schema, and an entry says
    # whether an empty tab creates it.
    types = compute_document_types(Document)
    @test issetequal([entry.type for entry in entries], types)
    # A layout variant of a schema, such as `MHelpGroup`, is no type of its own.
    @test HelpGroup in types && !any(T -> nameof(T) in (:MHelpGroup, :IHelpGroup), types)
    @test issubset(get_insertion_candidates(Document), types)
    @test issetequal([entry.type for entry in entries if entry.creatable], get_insertion_candidates(Document))
    @test all(entry -> entry.creatable || isempty(entry.typed), entries)
    # A package of many modules holds a group for each module, by name.
    platform = _find_help_child(list, "Platform")
    @test all(child -> child isa HelpGroup, platform.children)
    modules = [group.name for group in platform.children]
    @test sort(modules; by = lowercase) == modules
    @test "Widget" in modules && "Help" in modules
    @test platform.count == sum(group -> group.count, platform.children)
    @test startswith(platform.description, "The platform")
    # A module holds the entries of its types, by name, with what a person types.
    help = _find_help_child(platform, "Help")
    @test [entry.name for entry in help.children] ==
          ["AboutPage", "DocumentTypeList", "HelpEntry", "HelpGroup", "HelpTheme", "ProjectionList"]
    @test startswith(help.description, "What the Help menu of a window opens")
    documents = _find_help_child(help, "DocumentTypeList")
    @test documents.type === DocumentTypeList
    @test documents.creatable && occursin("documents", documents.typed)
    @test startswith(documents.description, "The tree of every document type")
    @test startswith(documents.text, "    DocumentTypeList()")
    # A group and an entry are documents that an empty tab does not create.
    group = _find_help_child(help, "HelpGroup")
    @test !group.creatable && group.typed == ""
end

@testset "the tree of the projections names no typed name" begin
    list = update_help_groups!(ProjectionList())
    entries = _collect_help_entries(list)
    @test issetequal([entry.type for entry in entries], compute_concrete_subtypes(Projection))
    @test all(entry -> entry.typed == "", entries)
    chaining = only(entry for entry in entries if entry.name == "ChainingProjection")
    @test startswith(chaining.description, "A compound higher-order projection")
    @test get_document_decoration(chaining).icon === :lambda
end

@testset "an entry holds the shape of its type: its supertypes and the fields that a person sets" begin
    list = update_help_groups!(DocumentTypeList())
    help = _find_help_child(_find_help_child(list, "Platform"), "Help")
    documents = _find_help_child(help, "DocumentTypeList")
    # The family type `ADocumentTypeList` and the view state of every document
    # are left out.
    @test documents.supertypes == "Document"
    @test [(field.name, field.type) for field in documents.fields] == [("children", "CellVector"), ("world", "UInt64")]
    theme = _find_help_child(help, "HelpTheme")
    @test !occursin("AHelpTheme", theme.supertypes) && endswith(theme.supertypes, "Document")
    heading = only(field for field in theme.fields if field.name == "heading_text")
    @test heading.type == "ThemeText"
    @test startswith(heading.description, "The line that says what a tree or a group holds")
    # A projection keeps each field in a cell, and the type is the type of the
    # value.
    projections = update_help_groups!(ProjectionList())
    entry = only(entry for entry in _collect_help_entries(projections) if entry.name == "HelpGroupToWidget")
    @test entry.supertypes == "Projection"
    @test [(field.name, field.type) for field in entry.fields] == [("gap", "Int64"), ("line", "StyleText")]
end

@testset "a second build keeps the objects, and writes no collection that stays" begin
    list = update_help_groups!(DocumentTypeList())
    children = list.children
    platform = _find_help_child(list, "Platform")
    help = _find_help_child(platform, "Help")
    about = _find_help_child(help, "AboutPage")
    update_help_groups!(list)
    @test list.children === children
    @test _find_help_child(list, "Platform") === platform
    @test _find_help_child(platform, "Help") === help
    @test _find_help_child(help, "AboutPage") === about
end

@testset "the acquire builds the groups once for each change of the program" begin
    list = DocumentTypeList()
    acquire_document!(nothing, list)
    @test !isempty(list.children)
    @test list.world == Base.get_world_counter()
    children = list.children
    acquire_document!(nothing, list)
    @test list.children === children
    # A save writes the type name only, and a load builds again at its acquire.
    @test pred_arguments(list) == ((), Pair{Symbol,Any}[])
end

@testset "a tree of the tree slice shows the groups and maps a path both ways" begin
    list = update_help_groups!(DocumentTypeList())
    @test has_tree_children(DocumentTypeList())
    @test format_tree_node_label(list) == "Documents"
    platform = _find_help_child(list, "Platform")
    @test format_tree_node_label(platform) == "Platform"
    @test get_document_decoration(platform).detail == string(platform.count)
    k = findfirst(group -> group === platform, collect(list.children))
    h = findfirst(group -> group.name == "Help", collect(platform.children))
    projection = DocumentTreeToWidgetTree()
    iomap = print_document(projection, nothing, DocumentTree(list), nothing)
    about = _help_tree_path(FieldReferenceStep("root"), FieldReferenceStep("children"), ElementReferenceStep(k),
                            FieldReferenceStep("children"), ElementReferenceStep(h),
                            FieldReferenceStep("children"), ElementReferenceStep(1))
    row = _help_tree_path(FieldReferenceStep("roots"), ElementReferenceStep(1),
                          FieldReferenceStep("children"), ElementReferenceStep(k),
                          FieldReferenceStep("children"), ElementReferenceStep(h),
                          FieldReferenceStep("children"), ElementReferenceStep(1))
    @test _help_tree_steps(map_reference_forward(projection, iomap, about)) == _help_tree_steps(row)
    @test _help_tree_steps(map_reference_backward(projection, iomap, row)) == _help_tree_steps(about)
    @test evaluate_reference(list, strip_reference_types(_help_tree_path(_help_tree_steps(about)[2:end]...))).name ==
          "AboutPage"
end

end
end
