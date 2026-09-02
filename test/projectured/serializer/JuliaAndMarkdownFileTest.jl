"""
S6 tests — `JuliaFile` and `MarkdownFile` round-trip via the
existing projectured parsers (`juliaparse`, `markdownparse`) and the
`print_natural_text` projection pipeline. Cross-file markers use each
format's natural escape:

- Julia:   `pred_ref("<<file(\\"path\\")>>")` — a plain call the
  projectured Julia parser accepts (no macro syntax).
- Markdown: fenced block ` ```pred-ref` … ` ``` ` — a block-level
  marker; inline stubs aren't supported yet (the markdown parser
  stops URLs at the first `)`).
"""

using Test
using ProjecturedKernel.CellModule
using ProjecturedSerialization.FileProjectModule
using ProjecturedJulia.JuliaFileModule
using ProjecturedJulia.JuliaModule
using ProjecturedMarkdown.MarkdownFileModule
using ProjecturedMarkdown.MarkdownModule

_arg1(call::JuliaCall) = begin
    v = getfield(call, :arguments)[]
    a = v[1]
    a isa AbstractCell ? a[] : a
end

function test_julia_and_markdown_file()
@testset "S6: JuliaFile + MarkdownFile round-trip" begin

    # ── JuliaFile ────────────────────────────────────────────────────────

    @testset "JuliaFile: single-file round-trip" begin
        d = mktempdir()
        try
            root = JuliaFile("root.jl", JuliaCall(JuliaIdentifier("f"),
                                                   Any[JuliaInteger(1), JuliaInteger(2)]))
            save_project!(root, d)
            @test isfile(joinpath(d, "root.jl"))
            @test read(joinpath(d, "root.jl"), String) == "f(1, 2)"
            reloaded = load_project(JuliaFile, "root.jl", d)
            @test reloaded isa JuliaFile
            @test content(reloaded) isa JuliaCall
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "JuliaFile: embedded child renders as pred_ref call" begin
        d = mktempdir()
        try
            child = JuliaFile("child.jl", JuliaIdentifier("x"))
            root  = JuliaFile("root.jl", JuliaCall(JuliaIdentifier("f"), Any[child]))
            save_project!(root, d)
            @test isfile(joinpath(d, "child.jl"))
            root_text = read(joinpath(d, "root.jl"), String)
            @test occursin("pred_ref(\"<<file(\\\"child.jl\\\")>>\")", root_text)
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "JuliaFile: load lifts pred_ref into a ReferenceStub" begin
        d = mktempdir()
        try
            child = JuliaFile("child.jl", JuliaIdentifier("x"))
            root  = JuliaFile("root.jl", JuliaCall(JuliaIdentifier("f"), Any[child]))
            save_project!(root, d)
            reloaded = load_project(JuliaFile, "root.jl", d)
            call = content(reloaded)::JuliaCall
            arg = _arg1(call)
            @test arg isa ReferenceStub
            resolved = resolve!(arg)
            @test resolved isa JuliaFile
            @test filename(resolved) == "child.jl"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "JuliaFile: shared child yields === after resolve" begin
        d = mktempdir()
        try
            child = JuliaFile("child.jl", JuliaIdentifier("x"))
            root  = JuliaFile("root.jl", JuliaCall(JuliaIdentifier("f"), Any[child, child]))
            save_project!(root, d)
            reloaded = load_project(JuliaFile, "root.jl", d)
            call = content(reloaded)::JuliaCall
            v = getfield(call, :arguments)[]
            s1 = v[1] isa AbstractCell ? v[1][] : v[1]
            s2 = v[2] isa AbstractCell ? v[2][] : v[2]
            @test s1 isa ReferenceStub
            @test s2 isa ReferenceStub
            @test resolve!(s1) === resolve!(s2)
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "JuliaFile: non-pred_ref call passes through unchanged" begin
        # A call with the same shape but a *different* callee name is
        # not a marker — load must leave it as an ordinary JuliaCall.
        d = mktempdir()
        try
            root = JuliaFile("root.jl", JuliaCall(JuliaIdentifier("some_other_fn"),
                                                   Any[JuliaInteger(42)]))
            save_project!(root, d)
            reloaded = load_project(JuliaFile, "root.jl", d)
            @test content(reloaded) isa JuliaCall
            call = content(reloaded)::JuliaCall
            @test call.callee isa JuliaIdentifier
            @test call.callee.name == "some_other_fn"
            @test _arg1(call) isa JuliaInteger
        finally
            rm(d; recursive=true, force=true)
        end
    end

    # ── MarkdownFile ─────────────────────────────────────────────────────

    @testset "MarkdownFile: single-file round-trip" begin
        d = mktempdir()
        try
            root = MarkdownFile("root.md",
                                MarkdownRoot([MarkdownHeading(1, [MarkdownText("Hello")]),
                                              MarkdownParagraph([MarkdownText("world")])]))
            save_project!(root, d)
            text = read(joinpath(d, "root.md"), String)
            @test occursin("# Hello", text)
            @test occursin("world", text)
            reloaded = load_project(MarkdownFile, "root.md", d)
            @test reloaded isa MarkdownFile
            @test content(reloaded) isa MarkdownRoot
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "MarkdownFile: embedded child renders as pred-ref fenced block" begin
        d = mktempdir()
        try
            child = MarkdownFile("child.md",
                                 MarkdownRoot([MarkdownParagraph([MarkdownText("hi")])]))
            root  = MarkdownFile("root.md",
                                 MarkdownRoot([MarkdownHeading(1, [MarkdownText("T")]),
                                               child,
                                               MarkdownParagraph([MarkdownText("after")])]))
            save_project!(root, d)
            @test isfile(joinpath(d, "child.md"))
            text = read(joinpath(d, "root.md"), String)
            @test occursin("```pred-ref", text)
            @test occursin("<<file(\"child.md\")>>", text)
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "MarkdownFile: load lifts pred-ref block into a ReferenceStub" begin
        d = mktempdir()
        try
            child = MarkdownFile("child.md",
                                 MarkdownRoot([MarkdownParagraph([MarkdownText("hi")])]))
            root  = MarkdownFile("root.md",
                                 MarkdownRoot([MarkdownHeading(1, [MarkdownText("T")]),
                                               child]))
            save_project!(root, d)
            reloaded = load_project(MarkdownFile, "root.md", d)
            elems = getfield(content(reloaded)::MarkdownRoot, :elements)[]
            stubs = [e for e in elems if e isa ReferenceStub]
            @test length(stubs) == 1
            resolved = resolve!(stubs[1])
            @test resolved isa MarkdownFile
            @test filename(resolved) == "child.md"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "MarkdownFile: ordinary code block left alone" begin
        d = mktempdir()
        try
            root = MarkdownFile("root.md",
                                MarkdownRoot([MarkdownCodeBlock("julia", "f(1)")]))
            save_project!(root, d)
            reloaded = load_project(MarkdownFile, "root.md", d)
            elems = getfield(content(reloaded)::MarkdownRoot, :elements)[]
            @test length(elems) == 1
            @test elems[1] isa MarkdownCodeBlock
        finally
            rm(d; recursive=true, force=true)
        end
    end

end
end
