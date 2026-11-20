# A testset that keeps the results of its children and gives them to no parent,
# so a suite under test can fail on purpose without a failure of the real run.
mutable struct _QuietTestSet <: Test.AbstractTestSet
    description::String
    results::Vector{Any}
end

_QuietTestSet(description::AbstractString; _...) = _QuietTestSet(String(description), Any[])
Test.record(ts::_QuietTestSet, result) = (push!(ts.results, result); result)
Test.finish(ts::_QuietTestSet) = ts

# Run `suite` with `keywords` inside a quiet testset, with no printed line.
function _run_quietly(suite::TestSuite; keywords...)
    Base.ScopedValues.@with Test.TESTSET_PRINT_ENABLE => false begin
        redirect_stdout(devnull) do
            @testset _QuietTestSet "a suite under test" begin
                suite(; keywords...)
            end
        end
    end
end

"""
    test_suite_runner()

The runner of a suite: it runs the parts in the order of the table, a part that
throws records an error and the parts after it still run, a suite inside a suite
runs as a testset of its own, and the record file holds one line for each part
with its counts.
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
end

"A part for the test of the runner: one test that passes."
_runner_fixture_part() = @test true
