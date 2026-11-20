"""
    test_supervised_runs()

The supervisor of `tool/run-tests.jl`, with real worker processes: each part of a
suite gets a result, a part that passes its time limit gets `timeout` and the
parts after it still run, the record file holds one line for each part, two
workers run parts at the same time, and a part alone runs beside no other part.
"""
function test_supervised_runs()
    @testset "a supervised run gives each part a result, and a part that hangs stops no other" begin
        folder = mktempdir()
        fixture = joinpath(folder, "SupervisedFixture.jl")
        write(fixture, """
            module SupervisedFixture
            using Test
            using Main.ProjecturedKernelTest: TestPart, TestSuite
            const fixture_suite = TestSuite("fixture", [
                TestPart(() -> (@test true); name = "passes"),
                TestPart(() -> (@test 1 == 2); name = "fails"),
                TestPart(() -> sleep(120); name = "hangs", limit = 3),
                TestPart(() -> (@test true; @test true); name = "after"),
            ])
            end
            """)
        record = joinpath(folder, "record.tsv")
        output = IOBuffer()
        code = run_test_supervisor(["--limit", "120", "--memory", "4G", "--record", record,
                                    fixture, "fixture_suite"]; output)
        text = String(take!(output))
        @test code == 1
        records = read_part_records(record)
        @test [(r.part, r.result) for r in records] ==
              [("passes", "done"), ("fails", "done"), ("hangs", "timeout"), ("after", "done")]
        @test [(r.pass, r.fail) for r in records] == [(1, 0), (0, 1), (0, 0), (2, 0)]
        @test all(r -> r.suite == "fixture", records)
        @test occursin("The part fixture/hangs takes more than 3 s", text)
        @test occursin("Summary: 4 parts (3 done, 1 timeout); 3 pass, 1 fail, 0 error, 0 broken.",
                       text)
    end

    @testset "two workers run two parts at the same time, and a part alone runs beside none" begin
        folder = mktempdir()
        log = joinpath(folder, "times.txt")
        fixture = joinpath(folder, "ParallelFixture.jl")
        write(fixture, """
            module ParallelFixture
            using Test
            using Main.ProjecturedKernelTest: TestPart, TestSuite
            mark(what, name) = open(io -> println(io, what, " ", name, " ", time()), $(repr(log)), "a")
            timed(name, seconds; is_alone = false) =
                TestPart(() -> (mark("start", name); sleep(seconds); mark("end", name); @test true);
                         name, is_alone)
            const parallel_suite = TestSuite("parallel", [
                timed("a", 3), timed("b", 3), timed("alone", 1; is_alone = true), timed("d", 1),
            ])
            end
            """)
        output = IOBuffer()
        code = run_test_supervisor(["--workers", "2", "--threads", "1", fixture, "parallel_suite"];
                                   output)
        @test code == 0
        times = Dict{Tuple{String, String}, Float64}()
        for line in readlines(log)
            what, name, at = split(line)
            times[(what, name)] = parse(Float64, at)
        end
        start(name) = times[("start", name)]
        stop(name) = times[("end", name)]
        if _usable_cpus() >= 2
            @test start("b") < stop("a") && start("a") < stop("b")
        end
        @test start("alone") >= max(stop("a"), stop("b"))
        @test start("d") >= stop("alone")
        @test occursin("[w2] ", String(take!(output)))
    end

    @testset "the command line of the supervisor" begin
        options = read_test_run_options(["--memory", "800M", "--limit", "30", "--only", "r\"^a\"",
                                         "--workers", "3", "P", "test_p", "Q", "test_q"])
        @test options.workers == 3
        @test options.memory_bytes == 800 * 2^20
        @test options.limit == 30.0
        @test read_name_filter(options.only) == r"^a"
        @test read_name_filter("text") == "text" && read_name_filter("") === nothing
        @test options.suites == [("P", "test_p"), ("Q", "test_q")]
        @test run_test_supervisor(["P"]; output = IOBuffer()) == 2
        @test run_test_supervisor(["--help"]; output = IOBuffer()) == 0
    end
end
