"""
Tests for `JsonFile` and the S3 cross-file marker round-trip: a JSON
file whose content contains an embedded child JsonFile saves as two
files, with the parent's slot for the child holding a marker string
(`"<<file(\"child.json\")>>"`); reloading the parent lifts that
marker into a `ReferenceStub` in the same slot.
"""

using Test
using ProjecturedDomain.FileProjectModule
using ProjecturedDomain.JsonFileModule
using ProjecturedDomain.JsonModule
using ProjecturedDomain.ReferenceModule: FileReferenceStep, EmptyReference, ConcreteReference

# Access the underlying cell of a @document field so we can inspect a
# slot without going through the auto-generated property getter (which
# would unwrap the cell and hide whether a stub is what's stored).
_slot(node, name) = getfield(node, name)[]

function test_json_file()
@testset "JsonFile: two-file round-trip via marker" begin

    @testset "single-file round-trip: save then load matches" begin
        d = mktempdir()
        try
            root = JsonFile("root.json",
                            JsonObject("name" => JsonString("aloha"),
                                       "count" => JsonNumber(3)))
            save_project!(root, d)
            @test isfile(joinpath(d, "root.json"))
            reloaded = load_project(JsonFile, "root.json", d)
            @test reloaded isa JsonFile
            @test filename(reloaded) == "root.json"
            @test content(reloaded) isa JsonObject
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "two-file save writes both files" begin
        d = mktempdir()
        try
            child = JsonFile("child.json", JsonObject("nested" => JsonString("data")))
            root  = JsonFile("root.json",  JsonObject("child" => child))
            save_project!(root, d)
            @test isfile(joinpath(d, "root.json"))
            @test isfile(joinpath(d, "child.json"))
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "parent's slot for the child renders as a marker string" begin
        d = mktempdir()
        try
            child = JsonFile("child.json", JsonNull())
            root  = JsonFile("root.json",  JsonObject("child" => child))
            save_project!(root, d)
            root_text = read(joinpath(d, "root.json"), String)
            @test occursin("<<file(\\\"child.json\\\")>>", root_text)
            # The child's file has its own content, not a marker.
            child_text = read(joinpath(d, "child.json"), String)
            @test child_text == "null"
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "load lifts the marker into a ReferenceStub in the slot" begin
        d = mktempdir()
        try
            child = JsonFile("child.json", JsonString("hi"))
            root  = JsonFile("root.json",  JsonObject("child" => child))
            save_project!(root, d)
            reloaded = load_project(JsonFile, "root.json", d)
            obj = content(reloaded)::JsonObject
            entry = getfield(obj, :entries)[][1]
            slot = _slot(entry, :value)
            @test slot isa ReferenceStub
            @test slot.reference == ConcreteReference(FileReferenceStep("child.json"),
                                                       EmptyReference())
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "round-trip: reload then re-save produces identical bytes" begin
        d = mktempdir()
        try
            child = JsonFile("child.json", JsonObject("k" => JsonString("v")))
            root  = JsonFile("root.json",  JsonObject("child" => child))
            save_project!(root, d)
            root_before  = read(joinpath(d, "root.json"), String)
            child_before = read(joinpath(d, "child.json"), String)
            reloaded_root  = load_project(JsonFile, "root.json", d)
            reloaded_child = load_project(JsonFile, "child.json", d)
            # Bytes may differ only if the emit reshapes the AST; the
            # marker-carrying root re-emits as the same marker string,
            # so the file is byte-identical.
            save_project!(reloaded_root, d)
            save_project!(reloaded_child, d)
            @test read(joinpath(d, "root.json"), String) == root_before
            @test read(joinpath(d, "child.json"), String) == child_before
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "marker walk leaves ordinary strings alone" begin
        d = mktempdir()
        try
            root = JsonFile("root.json",
                            JsonObject("plain" => JsonString("ordinary text"),
                                       "special" => JsonString("<<not a marker")))
            save_project!(root, d)
            reloaded = load_project(JsonFile, "root.json", d)
            obj = content(reloaded)::JsonObject
            entries = getfield(obj, :entries)[]
            @test _slot(entries[1], :value) isa JsonString
            @test _slot(entries[2], :value) isa JsonString
        finally
            rm(d; recursive=true, force=true)
        end
    end

    @testset "save deduplicates when the same child appears twice" begin
        d = mktempdir()
        try
            child = JsonFile("shared.json", JsonString("shared"))
            root  = JsonFile("root.json",
                             JsonObject("a" => child, "b" => child))
            save_project!(root, d)
            # Shared file written once; the two slots each get a marker.
            @test isfile(joinpath(d, "shared.json"))
            root_text = read(joinpath(d, "root.json"), String)
            n = 0
            i = 1
            while true
                r = findnext("<<file(\\\"shared.json\\\")>>", root_text, i)
                r === nothing && break
                n += 1
                i = last(r) + 1
            end
            @test n == 2
        finally
            rm(d; recursive=true, force=true)
        end
    end

end
end
