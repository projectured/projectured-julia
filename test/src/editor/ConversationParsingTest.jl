# Stage 5 — LLM response → documents.
# parse_markdown_blocks turns a finished assistant text block into ConversationParts
# whose content is the right document: julia/json/xml fenced blocks become real
# parsed documents, unknown/malformed blocks fall back to fenced text.

using Projectured: parse_markdown_blocks, ConversationPart,
                   TextText, JuliaDocument, JsonDocument, XmlDocument

function _cp_flat(t::TextText)
    io = IOBuffer()
    for s in t.elements
        hasproperty(s, :content) && s.content isa AbstractString && print(io, s.content)
    end
    String(take!(io))
end

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
        @test contents[1] isa TextText                       # prose
        @test any(c -> c isa JuliaDocument, contents)         # ```julia parsed
        @test any(c -> c isa JsonDocument, contents)          # ```json parsed
        @test any(c -> c isa XmlDocument, contents)           # ```xml parsed
        # Unknown language → fenced text fallback.
        @test any(c -> c isa TextText && occursin("unknownlang", _cp_flat(c)), contents)

        # Malformed code must not break the turn — falls back to fenced text.
        bad = parse_markdown_blocks("```julia\n(((\n```")
        @test bad[1].content isa TextText

        # Plain prose only → a single text part.
        plain = parse_markdown_blocks("just words")
        @test length(plain) == 1 && plain[1].content isa TextText

        # Inline code spans render as text (not the `Markdown.Code(...)` repr).
        inline = parse_markdown_blocks("Nice `factorial(6) = 720` done")
        txt = _cp_flat(inline[1].content)
        @test occursin("factorial(6) = 720", txt)
        @test !occursin("Markdown.Code", txt)
    end
end
