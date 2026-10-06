# The steps of a build, with `cp` and `sh` as the commands: a step runs, a step
# whose outputs are newer than its inputs answers SKIP, a dependency file names
# the inputs, a failed step says its error, and a copy accepts a hard link. Each
# case works in a folder of its own, and sets the times of its files.

# Set the time of a file, in seconds from now, so a test does not wait.
function _set_build_file_time(path, seconds)
    when = time() + seconds
    run(`touch -d @$(round(Int, when)) $path`)
    path
end

_run_build_step(step) = only(collect_task_group_results(run_task_group(TaskGroup([step]))))

function test_build_step()
    @testset "build step" begin
        @testset "a step runs, and then it is up to date" begin
            folder = mktempdir()
            write(joinpath(folder, "in.txt"), "one")
            _set_build_file_time(joinpath(folder, "in.txt"), -100)
            step = BuildCommandTask(; action = "Copying", subject = "in.txt",
                working_directory = folder, arguments = ["cp", "in.txt", "out/out.txt"],
                input_files = ["in.txt"], output_files = ["out/out.txt"])
            @test !is_build_step_up_to_date(step)
            result = _run_build_step(step)
            @test result.result == "DONE" && result.exit_code == 0
            @test read(joinpath(folder, "out", "out.txt"), String) == "one"
            again = _run_build_step(step)
            @test again.result == "SKIP" && again.reason == "Up-to-date" && is_expected(again)
            # An input newer than the output makes the step run again.
            _set_build_file_time(joinpath(folder, "in.txt"), 100)
            @test !is_build_step_up_to_date(step)
            @test format_task_parameters(step) == "in.txt"
            @test format_task_column(step, "step") == "Copying"
            @test format_task_details(step, again) == ["command: cp in.txt out/out.txt"]
        end

        @testset "a dependency file names the inputs of an output" begin
            folder = mktempdir()
            for name in ("in.txt", "extra.h", "out.txt")
                write(joinpath(folder, name), "")
            end
            _set_build_file_time(joinpath(folder, "in.txt"), -100)
            _set_build_file_time(joinpath(folder, "extra.h"), -100)
            _set_build_file_time(joinpath(folder, "out.txt"), -50)
            write(joinpath(folder, "out.d"), "out.txt: in.txt \\\n extra.h\n\nextra.h:\n")
            @test read_dependency_file(joinpath(folder, "out.d"))["out.txt"] == ["in.txt", "extra.h"]
            step = BuildCommandTask(; action = "Compiling", subject = "in.txt",
                working_directory = folder, arguments = ["true"], input_files = ["in.txt"],
                output_files = ["out.txt"], dependency_file = "out.d")
            @test find_build_step_input_files(step) == ["in.txt", "extra.h"]
            @test is_build_step_up_to_date(step)
            _set_build_file_time(joinpath(folder, "extra.h"), 100)
            @test !is_build_step_up_to_date(step)
        end

        @testset "a dependency file can name its paths relative to a folder" begin
            folder = mktempdir()
            for path in ("src/a.msg", "src/a_m.cc", "src/a_m.h", "src/b.msg")
                mkpath(dirname(joinpath(folder, path)))
                write(joinpath(folder, path), "")
            end
            write(joinpath(folder, "a_m.h.d"), "a_m.cc a_m.h: a.msg b.msg\n")
            step = BuildCommandTask(; action = "Generating", subject = "src/a_m.cc",
                working_directory = folder, arguments = ["true"], input_files = ["src/a.msg"],
                output_files = ["src/a_m.cc", "src/a_m.h"], dependency_file = "a_m.h.d",
                dependency_root = "src")
            @test find_build_step_input_files(step) == ["src/a.msg", "src/b.msg"]
        end

        @testset "a step that ends DONE touches its outputs" begin
            folder = mktempdir()
            write(joinpath(folder, "in.txt"), "")
            write(joinpath(folder, "out.txt"), "")
            _set_build_file_time(joinpath(folder, "out.txt"), -200)
            _set_build_file_time(joinpath(folder, "in.txt"), -100)
            # The command leaves its output as it was, as opp_msgc does.
            step = BuildCommandTask(; action = "Generating", subject = "in.txt",
                working_directory = folder, arguments = ["true"], input_files = ["in.txt"],
                output_files = ["out.txt"])
            @test _run_build_step(step).result == "DONE"
            @test is_build_step_up_to_date(step)
        end

        @testset "a removal removes once" begin
            folder = mktempdir()
            mkpath(joinpath(folder, "out", "debug"))
            write(joinpath(folder, "out", "debug", "a.o"), "")
            step = BuildRemoveTask(; working_directory = folder, path = "out")
            @test _run_build_step(step).result == "DONE" && !ispath(joinpath(folder, "out"))
            @test _run_build_step(step).result == "SKIP"
        end

        @testset "a failed step says its error" begin
            folder = mktempdir()
            write(joinpath(folder, "in.cc"), "")
            step = BuildCommandTask(; action = "Compiling", subject = "in.cc",
                working_directory = folder,
                arguments = ["sh", "-c", "echo 'warning: a' >&2; echo 'in.cc:3:1: error: bad' >&2; exit 1"],
                input_files = ["in.cc"], output_files = ["in.o"])
            result = _run_build_step(step)
            @test result.result == "ERROR" && result.reason == "Non-zero exit code: 1"
            @test result.exit_code == 1 && !is_expected(result)
            @test format_task_details(step, result)[2:3] == ["exit code: 1", "error: in.cc:3:1: error: bad"]
        end

        @testset "a copy copies once, and accepts a hard link" begin
            folder = mktempdir()
            write(joinpath(folder, "lib.so"), "binary")
            _set_build_file_time(joinpath(folder, "lib.so"), -100)
            step = BuildCopyTask(; working_directory = folder, source_file = "lib.so",
                                 target_file = "bin/lib.so")
            @test _run_build_step(step).result == "DONE"
            @test read(joinpath(folder, "bin", "lib.so"), String) == "binary"
            @test _run_build_step(step).result == "SKIP"
            linked = BuildCopyTask(; working_directory = folder, source_file = "lib.so",
                                   target_file = "linked.so")
            hardlink(joinpath(folder, "lib.so"), joinpath(folder, "linked.so"))
            @test is_build_step_up_to_date(linked)
        end
    end
end
