# A repository of four packages under `root`: a kernel, a platform of three slices,
# a JSON domain on the platform, and a test package for each, where the platform
# tests use the JSON domain as a fixture. It gives the table of the slices.
function _changed_parts_fixture(root::AbstractString)
    write_file(path, text) =
        (mkpath(dirname(joinpath(root, path))); write(joinpath(root, path), text))
    package(name, deps, includes) = begin
        lines = ["name = \"$name\"", "uuid = \"$(string(hash(name); base = 16))\"", "", "[deps]"]
        append!(lines, ["$dep = \"0\"" for dep in deps])
        write_file("package/$name/Project.toml", join(lines, "\n") * "\n")
        write_file("package/$name/src/$name.jl",
                   join(("include(\"../../../$path\")" for path in includes), "\n") * "\n")
    end
    package("Kernel", String[], ["source/kernel/KernelModule.jl"])
    package("Platform", ["Kernel"], ["source/platform/text/TextModule.jl",
                                     "source/platform/widget/WidgetModule.jl",
                                     "source/platform/tree/TreeModule.jl"])
    package("Json", ["Kernel", "Platform"], ["source/domain/json/JsonModule.jl"])
    package("KernelTest", ["Kernel"], ["test/kernel/CellTest.jl"])
    package("PlatformTest", ["Kernel", "Platform", "Json"],
            ["test/platform/text/TextTest.jl", "test/platform/widget/WidgetTest.jl",
             "test/platform/tree/TreeTest.jl"])
    package("JsonTest", ["Json"], ["test/domain/json/JsonTest.jl"])
    Dict("source/platform" => Dict("text" => String[], "widget" => ["text"], "tree" => ["widget"]))
end

"""
    test_changed_parts()

The parts of what changed: a changed test file reaches itself, a changed file of
a package reaches its tests and those of each package that uses it, a changed
slice reaches its tests and those of the slices that use it, a change of the
kernel reaches every package, and the suite keeps the parts in what is reached.
"""
function test_changed_parts()
    @testset "a change reaches the tests of its code and of the code that uses it" begin
        root = mktempdir()
        edges = _changed_parts_fixture(root)
        reached(files...) =
            sort(collect(reached_test_paths(root, collect(files); slice_edges = edges)))
        @test reached("test/platform/widget/WidgetTest.jl") ==
              ["test/platform/widget/WidgetTest.jl"]
        @test reached("README.md") == String[]
        @test reached("source/platform/text/TextLine.jl") ==
              ["test/domain/json", "test/platform/text", "test/platform/tree",
               "test/platform/widget"]
        @test reached("source/platform/tree/TreeNode.jl") ==
              ["test/domain/json", "test/platform/tree"]
        @test reached("source/domain/json/JsonParse.jl") == ["test/domain/json", "test/platform"]
        @test reached("package/Json/Project.toml") == ["test/domain/json", "test/platform"]
        @test reached("source/kernel/Cell.jl") ==
              ["test/domain/json", "test/kernel", "test/platform"]
    end

    @testset "the suite keeps the parts whose file is reached" begin
        root = mktempdir()
        holder = Module(:ChangedPartsFixture)
        Core.eval(holder, :(using Test))
        for (path, name) in (("test/platform/text/TextTest.jl", :test_text),
                             ("test/platform/tree/TreeTest.jl", :test_tree),
                             ("test/domain/json/JsonTest.jl", :test_json))
            mkpath(dirname(joinpath(root, path)))
            Base.include_string(holder, "$name() = @test true", joinpath(root, path))
        end
        part(name) = Base.invokelatest(getglobal, holder, name)
        suite = TestSuite("all", [part(:test_text), TestSuite("json", [part(:test_json)]),
                                  part(:test_tree)])
        names(chosen) = chosen === nothing ? String[] :
            [entry isa TestSuite ? entry.name * "/" * join(names(entry), ",") : entry.name
             for entry in chosen.entries]
        @test names(select_changed_parts(suite, root, ["test/platform/tree"])) == ["test_tree"]
        chosen = select_changed_parts(suite, root, ["test/domain/json", "test/platform/text"])
        @test names(chosen) == ["test_text", "json/test_json"]
        @test select_changed_parts(suite, root, ["test/kernel"]) === nothing
    end
end
