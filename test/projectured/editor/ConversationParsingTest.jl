# Stage 5 — LLM response → documents.
# parse_markdown_blocks splits a finished assistant text block into ConversationParts:
# julia/json/xml fenced blocks become real parsed documents; every run of prose is
# parsed by the project's own parse_markdown into a real MarkdownRoot (headings /
# **bold** / inline `code` become structure, not flat text); unknown/malformed fenced
# blocks fall back to fenced text.


# The inline/block children of a container Markdown node (root, paragraph, …),
# which forward the vector protocol over their children (@forward_vector_protocol).
_md_kids(d) = [d[i] for i in 1:length(d)]

function test_parse_markdown_blocks()
    @testset "parse_markdown_blocks (Stage 5)" begin
        md = """
        Here is some prose.

        ```julia
        2 + 2
        ```

        ```json
        {"a": 1}
        ```

        ```xml
        <a/>
        ```

        ```unknownlang
        raw stuff
        ```
        """
        contents = [p.content for p in parse_markdown_blocks(md)]
        @test contents[1] isa MarkdownDocument                # prose → real Markdown
        @test any(c -> c isa JuliaDocument, contents)         # ```julia parsed
        @test any(c -> c isa JsonDocument, contents)          # ```json parsed
        @test any(c -> c isa XmlDocument, contents)           # ```xml parsed
        # Unknown language → a Markdown code block, which keeps its fence.
        @test any(c -> c isa MarkdownDocument && occursin("```unknownlang", print_natural_text(c)), contents)

        # Prose markdown is parsed into a *structured* document, not flat text:
        # a heading becomes a MarkdownHeading node.
        head = parse_markdown_blocks("# Hello world")[1].content
        @test head isa MarkdownDocument
        @test any(n -> n isa MarkdownHeading, _md_kids(head))

        # Inline **bold** becomes a MarkdownStrong node inside the paragraph.
        para = parse_markdown_blocks("Some **bold** words")[1].content[1]
        @test para isa MarkdownParagraph
        @test any(n -> n isa MarkdownStrong, _md_kids(para))

        # Inline code spans become MarkdownCode nodes carrying the verbatim code.
        inline = parse_markdown_blocks("Nice `factorial(6) = 720` done")[1].content
        @test inline isa MarkdownDocument
        codes = filter(n -> n isa MarkdownCode, _md_kids(inline[1]))
        @test any(c -> occursin("factorial(6) = 720", c.content), codes)

        # Malformed code must not break the turn — falls back to a Markdown code block.
        bad = parse_markdown_blocks("```julia\n(((\n```")
        @test bad[1].content isa MarkdownDocument
        @test occursin("(((", print_natural_text(bad[1].content))

        # Plain prose only → a single Markdown part.
        plain = parse_markdown_blocks("just words")
        @test length(plain) == 1 && plain[1].content isa MarkdownDocument
    end

    @testset "a plain text part reaches the model as its value" begin
        # The breaks, the indent and the marks stay as the person typed them.
        text = "line one\n    indented *not emphasis*\n1. not a list"
        part = ConversationPart(PrimitiveString(text))
        @test AssistantModule._part_text(part) == text
        @test AssistantModule._block_text(part.content) == text
        # A message that the composer sends is that same plain text.
        draft = ConversationDraft([ConversationPart(PrimitiveString(text))])
        @test finalize_draft!(draft)
        sent = only(collect(draft.parts))
        @test sent.content isa PrimitiveString
        @test AssistantModule._part_text(sent) == text
    end
end
