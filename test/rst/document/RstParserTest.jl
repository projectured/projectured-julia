# Tests for the reStructuredText parser (`rstparse`) and the `:source`
# projection's emit path.
#
# Two levels of check:
#
# - unit tests on small strings, one construct at a time;
# - a fixture round-trip on five real files copied from the INET
#   documentation (`test/rst/fixture/rst/`).
#
# The round-trip criterion is **AST idempotence**, not byte equality:
#
#     rstparse(print_natural_text(rstparse(text))) == rstparse(text)
#
# Byte equality is out of reach because the corpus writes adornment lines
# longer than their titles and mixes indent widths. `test_rst_corpus`
# reports the byte-exact count as a quality figure without asserting it.

const RST_FIXTURE_DIR = joinpath(@__DIR__, "..", "fixture", "rst")

rst_fixture_files() = sort(filter(f -> endswith(f, ".rst"), readdir(RST_FIXTURE_DIR; join = true)))

# ── Structural comparison ─────────────────────────────────────────────────────
# `==` on a document is identity, so the round-trip needs its own deep compare.
# `selection` is skipped: it is editor state, not content.

rst_ast_equal(a, b) = a == b

function rst_ast_equal(a::RstDocument, b::RstDocument)
    typeof(a).name === typeof(b).name || return false
    for name in fieldnames(typeof(a))
        name === :selection && continue
        rst_ast_equal(getproperty(a, name), getproperty(b, name)) || return false
    end
    true
end

function rst_ast_equal(a::CellVector, b::CellVector)
    length(a) == length(b) || return false
    all(rst_ast_equal(x, y) for (x, y) in zip(a, b))
end

# The first place the two trees differ, as a path like
# `RstRoot.elements[1].RstSection.title[2]`. Used to report a round-trip
# failure as something a reader can act on.
function rst_first_difference(a, b, path::String = "")
    a isa RstDocument && b isa RstDocument || return rst_ast_equal(a, b) ? nothing : path
    typeof(a).name === typeof(b).name || return path * " (" * string(nameof(typeof(a))) * " vs " * string(nameof(typeof(b))) * ")"
    for name in fieldnames(typeof(a))
        name === :selection && continue
        x, y = getproperty(a, name), getproperty(b, name)
        here = path * "." * string(name)
        if x isa CellVector && y isa CellVector
            length(x) == length(y) || return here * " (length $(length(x)) vs $(length(y)))"
            for k in eachindex(x)
                d = rst_first_difference(x[k], y[k], here * "[$k]")
                d === nothing || return d
            end
        elseif !rst_ast_equal(x, y)
            return here * " (" * repr(first(string(x), 60)) * " vs " * repr(first(string(y), 60)) * ")"
        end
    end
    nothing
end

# ── Unit tests ────────────────────────────────────────────────────────────────

function test_rst_parser()
    @testset "rstparse" begin
        @testset "sections nest by adornment order" begin
            doc = rstparse("Alpha\n=====\n\ntext\n\nBeta\n----\n\nmore\n\nGamma\n=====\n")
            @test length(doc.elements) == 2
            a = doc.elements[1]
            @test a isa RstSection && a.level == 1 && a.adornment == "="
            @test rst_title_text(a) == "Alpha"
            # `-` is met second, so it opens depth 2 and Beta sits inside Alpha.
            b = a.elements[2]
            @test b isa RstSection && b.level == 2 && b.adornment == "-"
            # `=` reopens depth 1, so Gamma is a sibling of Alpha.
            @test doc.elements[2] isa RstSection && doc.elements[2].level == 1
            @test rst_title_text(doc.elements[2]) == "Gamma"
        end

        @testset "inline markup" begin
            run(text) = rstparse(text).elements[1].content
            @test run("plain")[1] isa RstText
            @test run("a ``lit`` b")[2] isa RstLiteral
            @test run("a ``lit`` b")[2].content == "lit"
            r = run("use :ned:`Foo` now")[2]
            @test r isa RstRole && r.name == "ned" && r.content == "Foo"
            @test run("a **b** c")[2] isa RstStrong
            @test run("a *b* c")[2] isa RstEmphasis
            ref = run("`INET <https://x>`__")[1]
            @test ref isa RstReference && ref.text == "INET" && ref.target == "https://x" && ref.anonymous
            @test run("`name`_")[1].target == ""
            @test run("a |v| b")[2] isa RstSubstitutionReference
            @test run("a [1]_ b")[2] isa RstFootnoteReference
        end

        @testset "a wildcard is not emphasis" begin
            # The corpus writes ini wildcards in running prose. Both of these
            # must stay plain text: the start-string rule needs a non-blank
            # after it, the end-string rule a non-blank before it.
            for text in ("*.host.numApps = 1",
                         "*.source.numApps = 1 and *.sink.numApps = 2")
                content = rstparse(text).elements[1].content
                @test length(content) == 1
                @test content[1] isa RstText
                @test content[1].content == text
            end
        end

        @testset "lists" begin
            b = rstparse("-  one\n-  two\n").elements[1]
            @test b isa RstBulletList && b.marker == "-" && length(b.items) == 2
            e = rstparse("1. one\n2. two\n").elements[1]
            @test e isa RstEnumeratedList && e.style == "1." && length(e.items) == 2
            # A continuation line belongs to its item, and does not become a
            # definition list.
            c = rstparse("-  one\n   still one\n").elements[1]
            @test length(c.items) == 1
            @test c.items[1].elements[1] isa RstParagraph
            @test length(c.items[1].elements) == 1
        end

        @testset "directives" begin
            f = rstparse(".. figure:: media/N.png\n   :align: center\n\n   The caption\n").elements[1]
            @test f isa RstFigure && f.path == "media/N.png" && f.align == "center"
            @test length(f.caption) == 1
            l = rstparse(".. literalinclude:: ../omnetpp.ini\n   :language: ini\n   :start-at: *.a\n").elements[1]
            @test l isa RstLiteralInclude && l.language == "ini" && l.start_at == "*.a"
            @test rstparse(".. note::\n\n   Careful.\n").elements[1] isa RstAdmonition
            @test rstparse(".. video_noloop:: a.mp4\n").elements[1].loop == false
            @test rstparse(".. video:: a.mp4\n").elements[1].loop == true
            t = rstparse(".. toctree::\n   :maxdepth: 3\n   :titlesonly:\n\n   a/index\n   b/index\n").elements[1]
            @test t isa RstToctree && t.maxdepth == 3 && t.titlesonly && length(t.entries) == 2
            # A directive with no struct of its own keeps its name and body.
            g = rstparse(".. only:: html\n\n   web only\n").elements[1]
            @test g isa RstDirective && g.name == "only" && g.argument == "html"
        end

        @testset "explicit markup" begin
            @test rstparse(".. _ug:cha:queueing:\n").elements[1] isa RstTarget
            @test rstparse(".. _ug:cha:queueing:\n").elements[1].name == "ug:cha:queueing"
            @test rstparse(".. this is a comment\n").elements[1] isa RstComment
            @test rstparse(".. role:: par(code)\n").elements[1].base == "code"
        end

        @testset "grid table" begin
            text = "+----+----+\n| a  | b  |\n+====+====+\n| c  | d  |\n+----+----+\n"
            t = rstparse(text).elements[1]
            @test t isa RstGridTable
            @test length(t.rows) == 2
            @test length(t.rows[1].cells) == 2
            @test t.header_rows == 1
            @test t.widths == [4, 4]
        end

        @testset "a paragraph is one line" begin
            # The parser joins a paragraph's source lines with a space, so the
            # emitted paragraph never starts a line at column zero inside a
            # list item or a directive body.
            p = rstparse("one\ntwo\nthree\n").elements[1]
            @test p.content[1].content == "one two three"
        end
    end
end

# ── Fixture round-trip ────────────────────────────────────────────────────────

function test_rst_round_trip()
    @testset "rst round-trip (AST idempotence)" begin
        for path in rst_fixture_files()
            name = basename(path)
            @testset "$name" begin
                text = read(path, String)
                doc = rstparse(text)
                emitted = print_natural_text(doc)
                again = rstparse(emitted)
                difference = rst_first_difference(again, doc)
                @test difference === nothing
                difference === nothing || @info "round-trip differs" file = name at = difference
            end
        end
    end
end

"""
    test_rst_corpus(dir) -> NamedTuple

Parse every `.rst` file under `dir`, re-emit it through the `:source`
projection, and re-parse the result. Returns a summary of the files that
parsed, that round-tripped at the AST level, and that round-tripped byte
for byte.

Not wired into `test_domain()`: point it at a documentation tree to sweep
it, for example

    test_rst_corpus("/home/projectured/workspace/inet-cpp")
"""
function test_rst_corpus(dir::AbstractString; verbose::Bool = true, limit::Int = typemax(Int))
    files = String[]
    for (root, _, names) in walkdir(dir)
        for n in names
            endswith(n, ".rst") && push!(files, joinpath(root, n))
        end
    end
    sort!(files)
    length(files) > limit && (files = files[1:limit])
    parsed = 0
    idempotent = 0
    exact = 0
    failures = String[]
    for f in files
        text = read(f, String)
        local doc
        try
            doc = rstparse(text)
            parsed += 1
        catch e
            push!(failures, "parse: $f: $(sprint(showerror, e))")
            continue
        end
        local emitted
        try
            emitted = print_natural_text(doc)
        catch e
            push!(failures, "emit: $f: $(sprint(showerror, e))")
            continue
        end
        emitted == text && (exact += 1)
        try
            if rst_ast_equal(rstparse(emitted), doc)
                idempotent += 1
            else
                push!(failures, "idempotence: $f")
            end
        catch e
            push!(failures, "reparse: $f: $(sprint(showerror, e))")
        end
    end
    if verbose
        println("rst corpus $dir")
        println("  files       $(length(files))")
        println("  parsed      $parsed")
        println("  idempotent  $idempotent")
        println("  byte-exact  $exact")
        for f in first(failures, 40)
            println("  ! $f")
        end
        length(failures) > 40 && println("  … $(length(failures) - 40) more")
    end
    (files = length(files), parsed = parsed, idempotent = idempotent,
     exact = exact, failures = failures)
end
