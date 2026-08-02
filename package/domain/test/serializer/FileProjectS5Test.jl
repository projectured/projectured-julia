"""
S5 tests — save discipline. `save_project!` iterates **loaded** file
documents only (the graph rooted at `root`, plus anything reachable
through a resolved `ReferenceStub`) and writes each with the S2
byte-equality guard so `mtime` and git's clean status are preserved
when the emitted text is unchanged.

Four cases:
- Unloaded stub (never `resolve!`d) → target file on disk is untouched.
- Resolved stub, unmodified → target's `mtime` is preserved.
- Resolved stub, modified → target is rewritten.
- Recreate-on-deleted was already covered in S2's TextFile suite; we
  add a JsonFile variant here.
"""

using Test
using ProjecturedDomain.FileProjectModule
using ProjecturedDomain.JsonFileModule
using ProjecturedDomain.JsonModule

_s5_stub_at(obj::JsonObject, key::AbstractString) = begin
    for e in getfield(obj, :entries)[]
        e.key == key && return getfield(e, :value)[]
    end
    error("no entry with key ", repr(key))
end

function test_file_project_s5()
@testset "S5: save discipline (loaded-only + write-gating)" begin

    @testset "unloaded stub target's mtime is preserved by save" begin
        d = mktempdir()
        try
            child = JsonFile("child.json", JsonString("original"))
            root  = JsonFile("root.json",  JsonObject("c" => child))
            save_project!(root, d)
            child_mt = mtime(joinpath(d, "child.json"))
            # Reload root — child stays unresolved.
            reloaded = load_project(JsonFile, "root.json", d)
            @test !is_resolved(_s5_stub_at(content(reloaded), "c"))
            sleep(0.05)
            save_project!(reloaded, d)
            # Child was not in the loaded graph → not written.
            @test mtime(joinpath(d, "child.json")) == child_mt
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "resolved but unmodified target's mtime is preserved" begin
        d = mktempdir()
        try
            child = JsonFile("child.json", JsonString("original"))
            root  = JsonFile("root.json",  JsonObject("c" => child))
            save_project!(root, d)
            reloaded = load_project(JsonFile, "root.json", d)
            stub = _s5_stub_at(content(reloaded), "c")
            resolve!(stub)   # child now in the loaded graph
            child_mt = mtime(joinpath(d, "child.json"))
            sleep(0.05)
            save_project!(reloaded, d)
            @test mtime(joinpath(d, "child.json")) == child_mt
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "resolved and modified target is rewritten" begin
        d = mktempdir()
        try
            child = JsonFile("child.json", JsonString("original"))
            root  = JsonFile("root.json",  JsonObject("c" => child))
            save_project!(root, d)
            reloaded = load_project(JsonFile, "root.json", d)
            stub = _s5_stub_at(content(reloaded), "c")
            resolved_child = resolve!(stub)
            # Mutate the child's content field.
            getfield(resolved_child, :content)[] = JsonString("updated")
            save_project!(reloaded, d)
            @test occursin("updated", read(joinpath(d, "child.json"), String))
            @test !occursin("original", read(joinpath(d, "child.json"), String))
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "root's own mtime preserved when unchanged" begin
        d = mktempdir()
        try
            root = JsonFile("root.json", JsonObject("k" => JsonString("v")))
            save_project!(root, d)
            root_mt = mtime(joinpath(d, "root.json"))
            sleep(0.05)
            save_project!(root, d)
            @test mtime(joinpath(d, "root.json")) == root_mt
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "recreate after external deletion (JsonFile)" begin
        d = mktempdir()
        try
            root = JsonFile("root.json", JsonObject("k" => JsonString("v")))
            save_project!(root, d)
            rm(joinpath(d, "root.json"))
            @test !isfile(joinpath(d, "root.json"))
            save_project!(root, d)
            @test isfile(joinpath(d, "root.json"))
            @test occursin("\"v\"", read(joinpath(d, "root.json"), String))
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "unresolved stub's peer file untouched even if root is rewritten" begin
        # Loading root, mutating only root, then saving must not scan
        # into the referenced child.json's disk contents.
        d = mktempdir()
        try
            child = JsonFile("child.json", JsonString("child original"))
            root  = JsonFile("root.json",
                             JsonObject("c" => child,
                                        "k" => JsonString("v0")))
            save_project!(root, d)
            child_mt = mtime(joinpath(d, "child.json"))
            reloaded = load_project(JsonFile, "root.json", d)
            # Modify a plain string entry so root's text changes.
            entries = getfield(content(reloaded), :entries)[]
            k_slot = getfield(entries[2], :value)[]
            getfield(k_slot, :value)[] = "v1"
            sleep(0.05)
            save_project!(reloaded, d)
            @test occursin("v1", read(joinpath(d, "root.json"), String))
            @test mtime(joinpath(d, "child.json")) == child_mt
        finally
            rm(d; recursive=true, force=true)
        end
    end

end
end
