"""
S4 tests — `LoaderContext`, `resolve!`, shared identity across
file boundaries, and cycles between file documents.

Every one of these tests spends a real filesystem: mktempdir, save,
reload, resolve, assert. The point of S4 is that the loader's intern
table dedups targets and that a mutually-referential file graph
terminates.
"""

using Test
using ProjecturedSerialization.FileProjectModule
using ProjecturedJson.JsonFileModule
using ProjecturedJson.JsonModule

_stub_at(obj::JsonObject, key::AbstractString) = begin
    for e in getfield(obj, :entries)[]
        e.key == key && return getfield(e, :value)[]
    end
    error("no entry with key ", repr(key))
end

function test_file_project_s4()
@testset "S4: LoaderContext + resolve! + shared identity + cycles" begin

    # ── LoaderContext basics ────────────────────────────────────────────

    @testset "LoaderContext holds base_dir + empty intern" begin
        ctx = LoaderContext("/tmp/example")
        @test ctx.base_dir == "/tmp/example"
        @test isempty(ctx.intern)
    end

    # ── register / lookup FileDocument type by extension ────────────────

    @testset "file_document_type dispatches by extension" begin
        @test file_document_type("root.json") == JsonFile
        # ".txt" is claimed by TextFile
        @test file_document_type("readme.txt") <: FileDocument
        # An unknown extension routes to the "" fallback (TextFile)
        @test file_document_type("Makefile") <: FileDocument
    end

    # ── ReferenceStub state ─────────────────────────────────────────────

    @testset "unhosted ReferenceStub is not resolvable" begin
        stub = ReferenceStub("file(\"x.json\")")
        @test !is_resolved(stub)
        @test_throws ErrorException resolve!(stub)
    end

    # ── Shared identity: two markers to the same child are `===` ───────

    @testset "two markers to the same file resolve to === objects" begin
        d = mktempdir()
        try
            child = JsonFile("child.json", JsonString("shared"))
            root  = JsonFile("root.json", JsonObject("a" => child, "b" => child))
            save_project!(root, d)
            reloaded = load_project(JsonFile, "root.json", d)
            obj = content(reloaded)::JsonObject
            stub_a = _stub_at(obj, "a")
            stub_b = _stub_at(obj, "b")
            @test stub_a isa ReferenceStub
            @test stub_b isa ReferenceStub
            @test stub_a !== stub_b     # separate stub objects
            ra = resolve!(stub_a)
            rb = resolve!(stub_b)
            @test ra isa JsonFile
            @test filename(ra) == "child.json"
            @test ra === rb             # shared identity via intern table
        finally
            rm(d; recursive=true, force=true)
        end
    end

    # ── Idempotence: resolve! caches after first call ───────────────────

    @testset "resolve! is idempotent (cached in stub.resolved)" begin
        d = mktempdir()
        try
            child = JsonFile("child.json", JsonNull())
            root  = JsonFile("root.json",  JsonObject("c" => child))
            save_project!(root, d)
            reloaded = load_project(JsonFile, "root.json", d)
            obj = content(reloaded)::JsonObject
            stub = _stub_at(obj, "c")
            @test !is_resolved(stub)
            r1 = resolve!(stub)
            @test is_resolved(stub)
            r2 = resolve!(stub)
            @test r1 === r2             # second call hits the stub cache
        finally
            rm(d; recursive=true, force=true)
        end
    end

    # ── Cycle: A refers into B refers into A ───────────────────────────

    @testset "cycle A ↔ B resolves without looping and preserves identity" begin
        d = mktempdir()
        try
            a = JsonFile("a.json", JsonNothing())
            b = JsonFile("b.json", JsonNothing())
            getfield(a, :content)[] = JsonObject("to_b" => b)
            getfield(b, :content)[] = JsonObject("to_a" => a)
            save_project!(a, d)
            @test isfile(joinpath(d, "a.json"))
            @test isfile(joinpath(d, "b.json"))

            loaded_a = load_project(JsonFile, "a.json", d)
            @test loaded_a isa JsonFile
            @test filename(loaded_a) == "a.json"

            stub_ab = _stub_at(content(loaded_a)::JsonObject, "to_b")
            resolved_b = resolve!(stub_ab)
            @test resolved_b isa JsonFile
            @test filename(resolved_b) == "b.json"

            stub_ba = _stub_at(content(resolved_b)::JsonObject, "to_a")
            resolved_a = resolve!(stub_ba)
            @test resolved_a === loaded_a   # cycle closes on the original A
        finally
            rm(d; recursive=true, force=true)
        end
    end

    # ── A marker naming no registered function fails loudly ──────────────

    @testset "unknown vocabulary function errors at resolve time" begin
        d = mktempdir()
        try
            stub = ReferenceStub("nosuchfunction(\"x.json\")", LoaderContext(d))
            @test_throws ErrorException resolve!(stub)
        finally
            rm(d; recursive=true, force=true)
        end
    end

end
end
