# The two lists of the Help menu: which types each one holds, in which order, and
# what it draws.

# What a printer draws, as text.
function _draw_help_text(projection, document)
    text = ChainingProjection(projection,
                              RecursiveProjection(SyntaxToText()),
                              RecursiveProjection(TextToString()))
    output = print_document(text, document).output
    output isa Cell ? output[] : output
end

function test_help_list_to_syntax()
@testset "the Help lists" begin

@testset "the document types are the ones an empty tab can make, by name" begin
    entries = compute_help_entries(DocumentTypeList())
    names = [entry.name for entry in entries]
    @test sort(names; by = lowercase) == names
    @test issetequal(names, [String(nameof(T)) for T in get_insertion_candidates(Document)])
    # A list is a document type too, and a person reaches it by its alias.
    list = only(entry for entry in entries if entry.name == "DocumentTypeList")
    @test "documents" in list.typed
    @test list.package == "ProjecturedHelp"
    about = only(entry for entry in entries if entry.name == "AboutPage")
    @test startswith(about.summary, "What a program says about itself")
end

@testset "the projections are every concrete projection, by name" begin
    entries = compute_help_entries(ProjectionList())
    names = [entry.name for entry in entries]
    @test sort(names; by = lowercase) == names
    @test issetequal(names, [String(nameof(T)) for T in compute_concrete_subtypes(Projection)])
    chaining = only(entry for entry in entries if entry.name == "ChainingProjection")
    @test chaining.package == "ProjecturedProjection"
    @test isempty(chaining.typed)
    @test startswith(chaining.summary, "A compound higher-order projection")
    # A projection with no docstring has no description.
    @test only(entry for entry in entries if entry.name == "HelpListToSyntax").summary == ""
end

@testset "a list draws a heading, then the name and the description of each type" begin
    lines = split(_draw_help_text(HelpListToSyntax(), DocumentTypeList()), "\n")
    count = length(get_insertion_candidates(Document))
    @test lines[1] == "$count document types. Type one of the names in an empty tab to make a document of that type."
    # An entry is a blank line, the name line and the description line.
    @test length(lines) == 1 + 3count
    at = findfirst(==("AboutPage   ProjecturedHelp   type: about page, about"), lines)
    @test at !== nothing
    @test startswith(lines[at + 1], "    What a program says about itself")
    lines = split(_draw_help_text(HelpListToSyntax(), ProjectionList()), "\n")
    at = findfirst(==("HelpListToSyntax   ProjecturedHelp"), lines)
    @test at !== nothing
    @test lines[at + 1] == "    no description"
end

end
end
