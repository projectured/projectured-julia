# The parser reads the Markdown that the documentation tools write. Each input
# below is an excerpt of a real answer of a tool.

# The text of a node: its inline text, joined, with a code span in backticks.
_join_markdown_inline_text(node::MarkdownText) = node.content
_join_markdown_inline_text(node::MarkdownCode) = "`" * node.content * "`"
_join_markdown_inline_text(node) = join(_join_markdown_inline_text(child) for child in node.content)

_collect_parsed_markdown_blocks(source) = collect(parse_markdown(source).elements)

# A tree as a string of its types and its values, to compare two parses.
function _describe_markdown_tree(node)
    node isa MarkdownDocument || return repr(node)
    parts = String[]
    for name in fieldnames(typeof(node))
        is_view_state_field(name) && continue
        value = getproperty(node, name)
        described = value isa CellVector ?
            "[" * join((_describe_markdown_tree(child) for child in value), ", ") * "]" :
            _describe_markdown_tree(value)
        push!(parts, string(name, "=", described))
    end
    string(nameof(typeof(node)), "(", join(parts, "; "), ")")
end

# The table of `kernel/selection.md`, as `read_resource` gives a section of it.
const _MARKDOWN_SELECTION_TABLE = """
| Type | `selection` meaning |
|---|---|
| `JsonNull` / `JsonBool` / `JsonNumber` / `JsonString` | Path within this primitive — typically `.value + {k}` for cursor at offset `k` in the value |
| `JsonArray` | `[i] + <child path>` — into element `i` (1-based) |
| `JsonObjectEntry` | `.key + {k}` (cursor in key) or `.value + <child path>` |
| `TextBlock` | `{k}` — flat cursor at offset `k` in the concatenated spans |
"""

function test_markdown_parser()
@testset "the markdown parser reads what the documentation tools write" begin

    @testset "a list item takes the indented line below it" begin
        # `search_api` at the default detail: a signature, then one sentence.
        source = """
        # API matches for "reference"

        - `extend_reference(base::Reference, steps::ReferenceStep...) -> Reference` — function in ReferenceModule
          Return a new `Reference` formed by appending `steps` to the end of `base`.
        - `ReferenceRules(rules)` — type in ReferenceModule
          An ordered set of rules.
        """
        blocks = _collect_parsed_markdown_blocks(source)
        @test length(blocks) == 2
        @test blocks[2] isa MarkdownList
        items = collect(blocks[2].items)
        @test length(items) == 2
        @test _join_markdown_inline_text(items[1].elements[1]) ==
              "`extend_reference(base::Reference, steps::ReferenceStep...) -> Reference` — " *
              "function in ReferenceModule Return a new `Reference` formed by appending " *
              "`steps` to the end of `base`."
        @test _join_markdown_inline_text(items[2].elements[1]) ==
              "`ReferenceRules(rules)` — type in ReferenceModule An ordered set of rules."
    end

    @testset "a line with no indent continues a list item too" begin
        blocks = _collect_parsed_markdown_blocks("- one\ntwo\n- three\n")
        @test length(blocks) == 1
        @test [_join_markdown_inline_text(item.elements[1]) for item in blocks[1].items] == ["one two", "three"]
    end

    @testset "an indented code block keeps its lines and their indent" begin
        # The `# Example` of the docstring of `ConcreteReference`.
        source = """
        The boundary type is stored once.

        # Example

            path = ConcreteReference(FieldReferenceStep("address"),
                       ConcreteReference(FieldReferenceStep("city"),

                           EmptyReference()))

        After the code.
        """
        blocks = _collect_parsed_markdown_blocks(source)
        @test [nameof(typeof(block)) for block in blocks] ==
              [:MarkdownParagraph, :MarkdownHeading, :MarkdownCodeBlock, :MarkdownParagraph]
        @test blocks[3].language == ""
        @test blocks[3].code ==
              "path = ConcreteReference(FieldReferenceStep(\"address\"),\n" *
              "           ConcreteReference(FieldReferenceStep(\"city\"),\n" *
              "\n" *
              "               EmptyReference()))"
        @test _join_markdown_inline_text(blocks[4]) == "After the code."
    end

    @testset "an indented line inside a paragraph stays in the paragraph" begin
        blocks = _collect_parsed_markdown_blocks("one\n    two\n")
        @test length(blocks) == 1
        @test _join_markdown_inline_text(blocks[1]) == "one two"
    end

    @testset "an indented list line stays a list" begin
        blocks = _collect_parsed_markdown_blocks("text\n\n    - item\n")
        @test blocks[2] isa MarkdownList
    end

    @testset "an admonition is a quote with its title in bold" begin
        # The docstring of `make_child_context`.
        source = """
        Return a context for a child position.

        !!! warning "The properties Dict is shared, not copied"
            `make_child_context` passes the parent's `properties` Dict to the child **by
            reference**. Mutating it in place leaks into the parent.

                ctx.properties[k] = v

        After the admonition.
        """
        blocks = _collect_parsed_markdown_blocks(source)
        @test [nameof(typeof(block)) for block in blocks] ==
              [:MarkdownParagraph, :MarkdownQuote, :MarkdownParagraph]
        inner = collect(blocks[2].elements)
        @test [nameof(typeof(block)) for block in inner] ==
              [:MarkdownParagraph, :MarkdownParagraph, :MarkdownCodeBlock]
        @test inner[1].content[1] isa MarkdownStrong
        @test _join_markdown_inline_text(inner[1]) == "The properties Dict is shared, not copied"
        @test _join_markdown_inline_text(inner[2]) ==
              "`make_child_context` passes the parent's `properties` Dict to the child " *
              "by reference. Mutating it in place leaks into the parent."
        @test inner[3].code == "ctx.properties[k] = v"
        @test _join_markdown_inline_text(blocks[3]) == "After the admonition."
    end

    @testset "an admonition with no title takes its kind as the title" begin
        blocks = _collect_parsed_markdown_blocks("!!! note\n    Read this.\n")
        @test _join_markdown_inline_text(blocks[1].elements[1]) == "Note"
        @test _join_markdown_inline_text(blocks[1].elements[2]) == "Read this."
    end

    @testset "a line that looks like a fence but is none still moves on" begin
        blocks = _collect_parsed_markdown_blocks("```a`b\n")
        @test length(blocks) == 1
        @test blocks[1] isa MarkdownParagraph
    end

    @testset "a table is a header, the alignments and the rows" begin
        source = "A paragraph that a table interrupts.\n" * _MARKDOWN_SELECTION_TABLE * "\nAfter.\n"
        blocks = _collect_parsed_markdown_blocks(source)
        @test [nameof(typeof(block)) for block in blocks] ==
              [:MarkdownParagraph, :MarkdownTable, :MarkdownParagraph]
        table = blocks[2]
        @test table.alignments == [:default, :default]
        @test [_join_markdown_inline_text(entry) for entry in table.header.elements] ==
              ["Type", "`selection` meaning"]
        @test length(table.rows) == 4
        @test [_join_markdown_inline_text(entry) for entry in table.rows[2].elements] ==
              ["`JsonArray`", "`[i] + <child path>` — into element `i` (1-based)"]
    end

    @testset "a delimiter row says the alignment of each column" begin
        table = _collect_parsed_markdown_blocks("| a | b | c | d |\n|---|:--|:-:|--:|\n")[1]
        @test table.alignments == [:default, :left, :center, :right]
        @test isempty(table.rows)
    end

    @testset "an escaped pipe is a pipe in its entry, and a short row gets empty entries" begin
        table = _collect_parsed_markdown_blocks("| a | b |\n|---|---|\n| x \\| y |\n")[1]
        @test [_join_markdown_inline_text(entry) for entry in table.rows[1].elements] == ["x | y", ""]
    end

    @testset "a pipe with no delimiter row below it is prose" begin
        blocks = _collect_parsed_markdown_blocks("a | b\n---\n")
        @test !any(block -> block isa MarkdownTable, blocks)
    end

    @testset "a table printed and parsed again is the same table" begin
        table = parse_markdown(_MARKDOWN_SELECTION_TABLE * "\n| a | b |\n|:--|--:|\n| x | y |\n")
        printed = print_natural_text(table)
        @test occursin("| Type | `selection` meaning |\n| --- | --- |\n| `JsonNull`", printed)
        @test occursin("| a | b |\n| :--- | ---: |\n| x | y |", printed)
        @test _describe_markdown_tree(parse_markdown(printed)) == _describe_markdown_tree(table)
    end

    @testset "no guide keeps a table as a paragraph of pipes" begin
        # The guides of the kernel: `documentation/` of this repository, or the copy
        # in an installed kernel.
        root = ProjecturedKernel.ToolModule._get_documentation_directory()
        guides = String[]
        for (directory, _, files) in walkdir(root), file in files
            endswith(file, ".md") && push!(guides, joinpath(directory, file))
        end
        @test length(guides) > 100
        pipe_paragraphs = String[]
        table_count = 0
        for guide in guides, block in _collect_parsed_markdown_blocks(read(guide, String))
            block isa MarkdownTable && (table_count += 1)
            block isa MarkdownParagraph && startswith(_join_markdown_inline_text(block), "|") &&
                push!(pipe_paragraphs, relpath(guide, root))
        end
        @test isempty(pipe_paragraphs)
        @test table_count > 90
    end

end
end # test_markdown_parser
