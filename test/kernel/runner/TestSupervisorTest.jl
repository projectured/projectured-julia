"""
    test_supervised_runs()

The supervisor of `tool/run-tests.jl`, with real worker processes: each part of a
suite gets a result, a part that passes its time limit gets `timeout` and the
parts after it still run, the record file holds one line for each part, two
workers run parts at the same time, a part alone runs beside no other part, a part
over the memory runs once more before it gets the result `memory`, and
the record of a commit of main is stored and compared with a run of a branch, and
a session keeps its worker and runs each request with the changes of the files.
"""
function test_supervised_runs()
    @testset "a supervised run gives each part a result, and a part that hangs stops no other" begin
        folder = mktempdir()
        fixture = joinpath(folder, "SupervisedFixture.jl")
        write(fixture, """
            module SupervisedFixture
            using Test
            using Main.ProjecturedKernelTest: TestPart, TestSuite
            plain_test() = @test true
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
                                    fixture, "fixture_suite", fixture, "plain_test"]; output)
        text = String(take!(output))
        @test code == 1
        records = read_part_records(record)
        @test [(r.part, r.result) for r in records] ==
              [("passes", "done"), ("fails", "done"), ("hangs", "timeout"), ("after", "done"),
               ("plain_test", "done")]
        @test [(r.pass, r.fail) for r in records] == [(1, 0), (0, 1), (0, 0), (2, 0), (1, 0)]
        @test [r.suite for r in records] ==
              ["fixture", "fixture", "fixture", "fixture", "plain_test"]
        @test occursin("The part fixture/hangs takes more than 3 s", text)
        @test occursin(
            "Summary: 5 parts (4 done, 1 timeout); 4 pass, 1 fail, 0 error, 0 broken.", text)
    end

    @testset "two workers run two parts at the same time, and a part alone runs beside none" begin
        folder = mktempdir()
        log = joinpath(folder, "times.txt")
        fixture = joinpath(folder, "ParallelFixture.jl")
        write(fixture, """
            module ParallelFixture
            using Test
            using Main.ProjecturedKernelTest: TestPart, TestSuite
            const LOG = $(repr(log))
            mark(what, name) = open(io -> println(io, what, " ", name, " ", time()), LOG, "a")
            has_started(name) =
                isfile(LOG) && any(line -> startswith(line, "start \$name "), readlines(LOG))
            # A part that waits until `other` started, at most a minute.
            function waits_for(name, other)
                mark("start", name)
                timedwait(() -> has_started(other), 60.0)
                mark("end", name)
                @test true
            end
            timed(name; is_alone = false) =
                TestPart(() -> (mark("start", name); sleep(0.5); mark("end", name); @test true);
                         name, is_alone)
            const parallel_suite = TestSuite("parallel", [
                TestPart(() -> waits_for("a", "b"); name = "a"), timed("b"),
                timed("alone"; is_alone = true), timed("d"),
            ])
            end
            """)
        output = IOBuffer()
        code = run_test_supervisor(["--workers", "2", "--threads", "1", "--memory", "1G",
                                    fixture, "parallel_suite"]; output)
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

    @testset "a part over the memory runs once more in a new worker, then gets memory" begin
        folder = mktempdir()
        fixture = joinpath(folder, "MemoryFixture.jl")
        write(fixture, """
            module MemoryFixture
            using Test
            using Main.ProjecturedKernelTest: TestPart, TestSuite
            const held = Any[]
            function grows()
                push!(held, ones(UInt8, 1500 * 2^20))    # 1.5 GiB, held
                sleep(60)
                @test true
            end
            const memory_suite = TestSuite("memory", [TestPart(grows; name = "grows"),
                                                      TestPart(() -> (@test true); name = "after")])
            end
            """)
        record = joinpath(folder, "record.tsv")
        output = IOBuffer()
        code = run_test_supervisor(["--memory", "1G", "--limit", "120", "--record", record,
                                    fixture, "memory_suite"]; output)
        text = String(take!(output))
        @test code == 1
        @test occursin("memory; the part runs again in a new worker", text)
        @test [(r.part, r.result) for r in read_part_records(record)] ==
              [("grows", "memory"), ("after", "done")]
    end

    @testset "the record of a commit of main is stored, and a branch run is compared with it" begin
        root = mktempdir()
        settings = ["-c", "user.name=test", "-c", "user.email=test@example.com",
                    "-c", "commit.gpgsign=false"]
        git(arguments...) =
            run(pipeline(`git -C $root $settings $arguments`; stdout = devnull, stderr = devnull))
        commit() = readchomp(`git -C $root rev-parse --short=12 HEAD`)
        git("init", "-q", "-b", "main")
        git("commit", "-q", "--allow-empty", "-m", "first")
        first_commit = commit()
        columns = ["repository", "commit", "suite", "part", "pass", "fail", "error", "broken",
                   "result", "seconds"]
        row(at, part, pass, fail) =
            Dict("repository" => "", "commit" => at, "suite" => "s", "part" => part,
                 "pass" => string(pass), "fail" => string(fail), "error" => "0", "broken" => "0",
                 "result" => "done", "seconds" => "1.0")
        withenv("PROJECTURED_TEST_RECORDS" => mktempdir()) do
            output = IOBuffer()
            first_rows = [row(first_commit, "a", 2, 0), row(first_commit, "b", 1, 1)]
            store_and_compare_records(first_rows, columns, root; output)
            text = String(take!(output))
            @test occursin("Stored the record of commit $first_commit of main", text)
            stored = joinpath(test_record_store(), repository_name(root), first_commit * ".tsv")
            @test isfile(stored)
            git("checkout", "-q", "-b", "topic")
            git("commit", "-q", "--allow-empty", "-m", "second")
            second = commit()
            store_and_compare_records([row(second, "a", 2, 0), row(second, "b", 2, 0),
                                       row(second, "c", 1, 0)], columns, root; output)
            text = String(take!(output))
            @test !occursin("Stored", text)
            @test occursin("Compared with the stored record of main at $first_commit", text)
            @test occursin("changed  s/b: done: 1 pass, 1 fail", text)
            @test occursin("new      s/c", text)
            @test !occursin("s/a", text)
        end
    end

    @testset "a session keeps its worker, and a request runs the files in their new form" begin
        folder = mktempdir()
        fixture = joinpath(folder, "StayFixture.jl")
        write_fixture(answer) = write(fixture, """
            module StayFixture
            using Test
            using Main.ProjecturedKernelTest: TestPart, TestSuite
            answer() = $answer
            checked() = @test answer() == 1
            const stay_suite = TestSuite("stay", [checked])
            end
            """)
        write_fixture("1")
        session_output = IOBuffer()
        options = TestRunOptions(stay = joinpath(folder, "session"), limit = 120.0)
        session = errormonitor(@async run_test_session(options; output = session_output))
        request(arguments...) = begin
            output = IOBuffer()
            code = send_test_request(joinpath(folder, "session"), [arguments...];
                                     output, wait_seconds = 300)
            (code, String(take!(output)))
        end
        code, text = request(fixture, "stay_suite")
        @test code == 0
        write_fixture("2")
        code, text = request(fixture, "stay_suite")
        # The open worker says whether it has Revise. With Revise, the changed file
        # runs in its new form, in the same worker.
        has_revise = occursin("applied the changes of the files with Revise", text)
        @test has_revise || occursin("The workers have no Revise", text)
        @test code == (has_revise ? 1 : 0)
        if has_revise
            write_fixture("1 +")                         # Revise can not apply this
            code, text = request(fixture, "stay_suite")
            @test occursin("Revise could not apply the changes of the files", text)
            @test code == 2
        end
        write_fixture("1")
        code, text = request("--restart", fixture, "stay_suite")
        @test code == 0
        @test request("--stop") == (0, "")
        @test timedwait(() -> istaskdone(session), 60.0) == :ok && fetch(session) == 0
    end

    @testset "a worker loads only the home of its part, and another home gets a new worker" begin
        folder = mktempdir()
        leaf = joinpath(folder, "LeafFixture.jl")
        write(leaf, """
            module LeafFixture
            using Test
            # The worker of this part has loaded this file and no other fixture.
            leaf_alone() = @test !isdefined(Main, :UmbrellaFixture)
            end
            """)
        umbrella = joinpath(folder, "UmbrellaFixture.jl")
        write(umbrella, """
            isdefined(Main, :LeafFixture) || Base.include(Main, $(repr(leaf)))
            module UmbrellaFixture
            using Test
            using Main.ProjecturedKernelTest: TestPart, TestSuite
            using Main.LeafFixture: leaf_alone
            umbrella_part() = @test isdefined(Main, :UmbrellaFixture)
            const umbrella_suite = TestSuite("umbrella", [
                TestPart(leaf_alone), TestPart(umbrella_part),
                TestPart(() -> (@test isdefined(Main, :UmbrellaFixture)); name = "closure"),
            ])
            end
            """)
        record = joinpath(folder, "record.tsv")
        output = IOBuffer()
        code = run_test_supervisor(["--record", record, leaf, "leaf_alone", umbrella, "umbrella_suite"];
                                   output)
        @test code == 0
        # The order of the record follows the run: a worker takes the parts of its package first.
        @test sort([(r.suite, r.part, r.pass) for r in read_part_records(record)]) ==
              sort([("leaf_alone", "leaf_alone", 1), ("umbrella", "leaf_alone", 1),
                    ("umbrella", "umbrella_part", 1), ("umbrella", "closure", 1)])
    end

    @testset "a worker starts when its memory from the record fits beside the others" begin
        folder = mktempdir()
        log = joinpath(folder, "times.txt")
        files = map(("A", "B")) do letter
            file = joinpath(folder, "Memory$(letter)Fixture.jl")
            write(file, """
                module Memory$(letter)Fixture
                using Test
                using Main.ProjecturedKernelTest: TestPart, TestSuite
                function part_$(letter)()
                    open(io -> println(io, "start $(letter) ", time()), $(repr(log)), "a")
                    sleep(1.0)
                    open(io -> println(io, "end $(letter) ", time()), $(repr(log)), "a")
                    @test true
                end
                const suite_$(letter) = TestSuite("$(letter)", [TestPart(part_$(letter))])
                end
                """)
            file
        end
        # A peak of 2.4 GiB asks for 3 GiB, so two such workers do not fit in 4 GiB.
        earlier = joinpath(folder, "earlier.tsv")
        write(earlier, "suite\tpart\tpeak_bytes\nA\tpart_A\t$(round(Int, 2.4 * 2^30))\n" *
                       "B\tpart_B\t$(round(Int, 2.4 * 2^30))\n")
        output = IOBuffer()
        code = run_test_supervisor(["--workers", "2", "--threads", "1", "--memory", "4G",
                                    "--memory-total", "4G", "--memory-from", earlier,
                                    files[1], "suite_A", files[2], "suite_B"]; output)
        @test code == 0
        times = Dict(Tuple(split(line)[1:2]) => parse(Float64, split(line)[3]) for line in readlines(log))
        first_end = min(times[("end", "A")], times[("end", "B")])
        second_start = max(times[("start", "A")], times[("start", "B")])
        @test first_end <= second_start
    end

    @testset "the command line of the supervisor" begin
        options = read_test_run_options(["--memory", "800M", "--limit", "30", "--only", "r\"^a\"",
                                         "--workers", "3", "P", "test_p", "Q", "test_q"])
        @test options.workers == 3
        @test read_test_run_options(["--workers", "auto", "--memory-total", "10G", "--memory-from",
                                     "r.tsv", "P", "test_p"]) isa TestRunOptions
        @test read_test_run_options(["--workers", "auto", "P", "test_p"]).workers == 0
        @test read_test_run_options(["--memory-total", "10G", "P", "test_p"]).memory_total == 10 * 2^30
        @test options.memory_bytes == 800 * 2^20
        @test options.limit == 30.0
        @test read_name_filter(options.only) == r"^a"
        @test read_name_filter("text") == "text" && read_name_filter("") === nothing
        @test options.suites == [("P", "test_p"), ("Q", "test_q")]
        @test run_test_supervisor(["P"]; output = IOBuffer()) == 2
        @test run_test_supervisor(["--help"]; output = IOBuffer()) == 0
    end
end
