"""
Tests for the marker **vocabulary** at domain level — the Julia
domain's `definition(document, "name")` — and for the round-trip
property every host format owes a marker: a file that was loaded and
saved keeps its markers verbatim, and forcing an embed changes not one
byte of the file that names it.
"""

using Test
using ProjecturedBase.FileProjectModule
using ProjecturedJulia.JuliaFileModule
using ProjecturedJson.JsonFileModule
using ProjecturedMarkdown.MarkdownFileModule
using ProjecturedJulia.JuliaModule: JuliaFunction, JuliaConst, JuliaStruct, JuliaDocstring
using ProjecturedVisual.NaturalFormatModule: document_to_text

const _MV_SOURCE = """
using Foo

\"\"\"
Build the packet queue step.
\"\"\"
function packet_queue_step(x)
    y = x + 1
    return y
end

const LIMIT = 10

struct Marker
    a::Int
end
"""

function test_marker_vocabulary()
@testset "Marker vocabulary: definition(…) + host-format round-trip" begin

    @testset "definition(…) finds each shape of top-level definition" begin
        d = mktempdir()
        try
            write(joinpath(d, "steps.jl"), _MV_SOURCE)
            ctx = LoaderContext(d)
            # A documented function comes back *with* its docstring — the
            # fragment a reader should see is the whole definition.
            f = evaluate_marker("definition(file(\"steps.jl\"), \"packet_queue_step\")", ctx)
            @test f isa JuliaDocstring
            @test occursin("function packet_queue_step", document_to_text(f))
            @test occursin("Build the packet queue step", document_to_text(f))

            @test evaluate_marker("definition(file(\"steps.jl\"), \"LIMIT\")", ctx) isa JuliaConst
            @test evaluate_marker("definition(file(\"steps.jl\"), \"Marker\")", ctx) isa JuliaStruct
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "definition(…) shares the file with a plain file(…) marker" begin
        d = mktempdir()
        try
            write(joinpath(d, "steps.jl"), _MV_SOURCE)
            ctx = LoaderContext(d)
            whole = evaluate_marker("file(\"steps.jl\")", ctx)
            part  = evaluate_marker("definition(file(\"steps.jl\"), \"LIMIT\")", ctx)
            # The fragment is a node *of* the interned file, not of a re-parse.
            @test any(s -> s === part, getfield(content(whole), :statements)[])
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "a missing or ambiguous name fails loudly" begin
        d = mktempdir()
        try
            write(joinpath(d, "steps.jl"), _MV_SOURCE)
            write(joinpath(d, "twice.jl"), "f(x) = 1\nf(x, y) = 2\n")
            ctx = LoaderContext(d)
            @test_throws ErrorException evaluate_marker("definition(file(\"steps.jl\"), \"nope\")", ctx)
            @test_throws ErrorException evaluate_marker("definition(file(\"twice.jl\"), \"f\")", ctx)
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "section(…) names a heading, and takes what it heads" begin
        d = mktempdir()
        try
            write(joinpath(d, "page.md"),
                  "# Title\n\nIntro.\n\n## First\n\nOne.\n\n### Deeper\n\nDeep.\n\n## Second\n\nTwo.\n")
            ctx = LoaderContext(d)

            first_section = document_to_text(
                evaluate_marker("section(file(\"page.md\"), \"First\")", ctx))
            # The heading, its prose, and the subsection it contains …
            @test occursin("## First", first_section)
            @test occursin("One.", first_section)
            @test occursin("Deeper", first_section)
            # … but not the section that follows at the same level.
            @test !occursin("Second", first_section)

            last_section = document_to_text(
                evaluate_marker("section(file(\"page.md\"), \"Second\")", ctx))
            @test occursin("Two.", last_section)
            @test !occursin("One.", last_section)

            # The section IS the page's own elements, not a copy of them.
            page = evaluate_marker("file(\"page.md\")", ctx)
            elements = collect(getfield(content(page), :elements)[])
            section = evaluate_marker("section(file(\"page.md\"), \"Second\")", ctx)
            @test any(e -> e === collect(getfield(section, :elements)[])[1], elements)

            # A heading nobody wrote, and one written twice, both fail loudly.
            @test_throws ErrorException evaluate_marker("section(file(\"page.md\"), \"Nope\")", ctx)
            write(joinpath(d, "twice.md"), "## Same\n\nA.\n\n## Same\n\nB.\n")
            @test_throws ErrorException evaluate_marker("section(file(\"twice.md\"), \"Same\")", ctx)
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "a marker written in a line stays in that line" begin
        d = mktempdir()
        try
            write(joinpath(d, "steps.jl"), _MV_SOURCE)
            text = "The builder is <<definition(file(\"steps.jl\"), \"LIMIT\")>> and it runs.\n"
            write(joinpath(d, "page.md"), text)
            page = load_project(MarkdownFile, "page.md", d)
            resolve_stubs!(page)

            # Saving puts it back as it was written — inline, with no fence.
            saved = document_to_text(content(page))
            @test occursin("The builder is <<definition(file(\"steps.jl\"), \"LIMIT\")>> and it runs.",
                           saved)
            @test !occursin("```", saved)
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "text that only looks like a marker is left alone" begin
        d = mktempdir()
        try
            write(joinpath(d, "page.md"), "A plain <<not a marker>> stays text.\n")
            page = load_project(MarkdownFile, "page.md", d)
            saved = document_to_text(content(page))
            @test occursin("<<not a marker>>", saved)
        finally
            rm(d; recursive=true, force=true)
        end
    end

    # ── Round-trip: whatever a marker says, saving re-emits it ──────────

    @testset "markdown: a fenced marker round-trips verbatim" begin
        d = mktempdir()
        try
            text = """
            # Step

            Prose before.

            ```pred-ref
            <<definition(file("steps.jl"), "packet_queue_step")>>
            ```

            Prose after.
            """
            write(joinpath(d, "page.md"), text)
            write(joinpath(d, "steps.jl"), _MV_SOURCE)
            page = load_project(MarkdownFile, "page.md", d)
            save_project!(page, d)
            saved = read(joinpath(d, "page.md"), String)
            @test occursin("<<definition(file(\"steps.jl\"), \"packet_queue_step\")>>", saved)
            @test occursin("Prose after.", saved)
            # Forcing the embed must not change what the file says.
            resolve_stubs!(page)
            save_project!(page, d)
            @test read(joinpath(d, "page.md"), String) == saved
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "json: a marker in a string value round-trips verbatim" begin
        d = mktempdir()
        try
            write(joinpath(d, "steps.jl"), _MV_SOURCE)
            root = JsonFile("root.json", ProjecturedJson.JsonModule.JsonObject(
                "fragment" => ProjecturedJson.JsonModule.JsonString(
                    "<<definition(file(\"steps.jl\"), \"LIMIT\")>>")))
            save_project!(root, d)
            before = read(joinpath(d, "root.json"), String)
            reloaded = load_project(JsonFile, "root.json", d)
            resolve_stubs!(reloaded)
            save_project!(reloaded, d)
            @test read(joinpath(d, "root.json"), String) == before
            @test occursin("definition(", before)
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "a marker's spacing survives a load/save cycle" begin
        d = mktempdir()
        try
            text = "```pred-ref\n<<file( \"other.md\" )>>\n```\n"
            write(joinpath(d, "page.md"), text)
            write(joinpath(d, "other.md"), "# Other\n")
            page = load_project(MarkdownFile, "page.md", d)
            resolve_stubs!(page)
            save_project!(page, d)
            # Spacing inside the marker is the author's, and comes back as written.
            @test occursin("<<file( \"other.md\" )>>", read(joinpath(d, "page.md"), String))
        finally
            rm(d; recursive=true, force=true)
        end
    end

end
end
