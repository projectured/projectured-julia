# Run `suite` with `keywords` inside a quiet testset, with no printed line.
function _run_quietly(suite::TestSuite; keywords...)
    Base.ScopedValues.@with Test.TESTSET_PRINT_ENABLE => false begin
        redirect_stdout(devnull) do
            @testset HeldTestSet "a suite under test" begin
                suite(; keywords...)
            end
        end
    end
end

"""
    test_suite_runner()

The runner of a suite: it runs the parts in the order of the table, a part that
throws records an error and the parts after it still run, a suite inside a suite
runs as a testset of its own, the record file holds one line for each part with
its counts, and `only` and `skip` choose the parts and the items of a walk by
name.
"""
function test_suite_runner()
    @testset "a suite runs its parts in their order, and a part that throws stops no other" begin
        ran = String[]
        inner = TestSuite("inner", [
            TestPart(() -> (push!(ran, "second"); @test 1 == 1); name = "second"),
        ])
        suite = TestSuite("outer", [
            TestPart(() -> (push!(ran, "first"); @test true; @test true); name = "first"),
            TestPart(() -> (push!(ran, "throws"); error("a fault of the part")); name = "throws"),
            inner,
            TestPart(() -> (push!(ran, "last"); @test_broken false); name = "last"),
        ])
        path = joinpath(mktempdir(), "record.tsv")
        _run_quietly(suite; record = path)
        @test ran == ["first", "throws", "second", "last"]
        records = read_part_records(path)
        @test [r.part for r in records] == ["first", "throws", "second", "last"]
        @test [r.suite for r in records] == ["outer", "outer", "outer/inner", "outer"]
        @test [(r.pass, r.fail, r.error, r.broken) for r in records] ==
              [(2, 0, 0, 0), (0, 0, 1, 0), (1, 0, 0, 0), (0, 0, 0, 1)]
        @test all(r -> r.result == "done" && r.seconds >= 0 && r.peak_bytes > 0, records)
        @test first(readlines(path)) == join(PART_RECORD_COLUMNS, '\t')
    end

    @testset "a plain function in the table is a part with the name of the function" begin
        suite = TestSuite("named", [_runner_fixture_part])
        @test only(suite.entries).name == "_runner_fixture_part"
        path = joinpath(mktempdir(), "record.tsv")
        _run_quietly(suite; record = path)
        @test only(read_part_records(path)).pass == 1
    end

    @testset "only and skip choose the parts by their names and the names of their suites" begin
        noop() = nothing
        suite = TestSuite("all", [
            TestPart(noop; name = "test_widget_table"),
            TestPart(noop; name = "test_text"),
            TestSuite("ProjecturedJSON", [TestPart(noop; name = "test_json_parser")]),
        ])
        names(chosen) = chosen === nothing ? String[] :
            [entry isa TestSuite ? entry.name * "/" * join(names(entry), ",") : entry.name
             for entry in chosen.entries]
        @test names(select_parts(suite)) == ["test_widget_table", "test_text",
                                             "ProjecturedJSON/test_json_parser"]
        @test names(select_parts(suite; only = "widget")) == ["test_widget_table"]
        @test names(select_parts(suite; only = "ProjecturedJSON")) ==
              ["ProjecturedJSON/test_json_parser"]
        @test names(select_parts(suite; only = r"^test_t")) == ["test_text"]
        @test names(select_parts(suite; skip = "JSON")) == ["test_widget_table", "test_text"]
        @test names(select_parts(suite; only = "test_", skip = "text")) ==
              ["test_widget_table", "ProjecturedJSON/test_json_parser"]
        @test select_parts(suite; only = "nothing like it") === nothing
        ran = String[]
        counted = TestSuite("counted", [
            TestPart(() -> (push!(ran, "a"); @test true); name = "a"),
            TestPart(() -> (push!(ran, "b"); @test true); name = "b"),
        ])
        _run_quietly(counted; skip = "a")
        @test ran == ["b"]
    end

    @testset "a walk chooses its items by name" begin
        items = [(name = "json",), (name = "json_widget",), (name = "xml",)]
        @test select_by_name(items) == items
        @test [item.name for item in select_by_name(items; only = "json")] == ["json", "json_widget"]
        @test [item.name for item in select_by_name(items; skip = r"_widget$")] == ["json", "xml"]
        @test select_by_name(("json", "text", "xml"); only = "x") == ["text", "xml"]
    end
end

"A part for the test of the runner: one test that passes."
_runner_fixture_part() = @test true
