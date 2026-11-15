# A program as a task, with `sh` as the program: the exit code and its reason, the
# variables that the program adds to the environment of the editor, its folder, a
# stop, the time limit, the marks of its lines, and the refusals of its
# constructor. Each program runs in a group of one task, as a group starts it.

# Run `task` in a group of one, and answer its execution.
_run_program(task) = only(run_task_group(TaskGroup([task])).runs)

_make_program(command; folder = mktempdir(), keywords...) =
    ProgramTask(command; working_directory = folder, keywords...)

function test_program_task()
    @testset "program task" begin
        @testset "a program ends DONE or ERROR with its exit code" begin
            result = _run_program(_make_program(`sh -c "exit 0"`)).result
            @test result isa ProgramResult
            @test result.result == "DONE" && result.exit_code == 0 && result.reason === nothing
            @test is_expected(result)
            result = _run_program(_make_program(`sh -c "exit 3"`)).result
            @test result.result == "ERROR" && result.exit_code == 3
            @test result.reason == "Non-zero exit code: 3"
            @test !is_expected(result)
        end

        @testset "a program adds its variables to the environment of the editor" begin
            execution = _run_program(_make_program(`sh -c 'echo $WALK:$HOME'`;
                                                   environment = Dict("WALK" => "1")))
            @test collect_output_lines(execution.output) == ["1:" * ENV["HOME"]]
        end

        @testset "a program runs in its folder" begin
            folder = realpath(mktempdir())
            execution = _run_program(_make_program(`pwd`; folder))
            @test collect_output_lines(execution.output) == [folder]
        end

        @testset "a stop ends the program CANCEL" begin
            group = TaskGroup([_make_program(`sh -c "sleep 30"`)])
            start_task_group!(group)
            deadline = time() + 10
            while (group.runs[1] === nothing || !is_task_running(group.runs[1])) && time() < deadline
                sleep(0.02)
            end
            stopped_at = time()
            stop_task_execution!(group.runs[1])
            wait_task_group(group)
            @test time() - stopped_at < 5
            @test group.runs[1].result.result == "CANCEL"
        end

        @testset "the time limit stops the program and ends it ERROR" begin
            started = time()
            execution = _run_program(_make_program(`sh -c "sleep 30"`; time_limit = 1))
            @test time() - started < 5
            @test execution.result.result == "ERROR"
            @test execution.result.reason == "Time limit of 1 s"
            # A program that ends before its limit is not stopped by it.
            execution = _run_program(_make_program(`sh -c "exit 0"`; time_limit = 30))
            @test execution.result.result == "DONE"
        end

        @testset "a line marks as an error or a warning" begin
            task = _make_program(`sh -c "echo fatal: bad revision; echo Warning: x; echo plain"`)
            @test find_task_output_mark(task, :output, "fatal: bad revision") === :error
            @test find_task_output_mark(task, :output, "src/a.cc:3: Error: x") === :error
            @test find_task_output_mark(task, :output, "warning: unused") === :warning
            @test find_task_output_mark(task, :output, "plain") === nothing
            output = _run_program(task).output
            @test output.mark_counts == Dict(:error => 1, :warning => 1)
            @test output.first_mark_lines == Dict(:error => 1, :warning => 2)
        end

        @testset "a program says its name, its command and its facts" begin
            task = _make_program(`git checkout --detach 3fa2c1d`; folder = "/work",
                                 environment = Dict("B" => "2", "A" => "1"), name = "checkout")
            @test format_task_parameters(task) == "checkout"
            @test get_task_columns(task) == ["name" => 2, "command" => 4]
            @test format_task_column(task, "name") == "checkout"
            @test format_task_column(task, "command") == "git checkout --detach 3fa2c1d"
            facts(task, result) = [fact.label => fact.value for fact in collect(make_task_kind_document(task, result).facts)]
            @test facts(task, nothing) ==
                  ["command" => "git checkout --detach 3fa2c1d", "folder" => "/work", "environment" => "A=1 B=2"]
            @test _make_program(`make`).name == "make"
            result = _run_program(_make_program(`sh -c "exit 2"`)).result
            @test last(facts(result.task, result)) == ("exit code" => "2")
        end

        @testset "the constructor refuses what it does not run" begin
            @test_throws ArgumentError _make_program(Cmd(`ls`; dir = "/tmp"))
            @test_throws ArgumentError _make_program(setenv(`ls`, "A" => "1"))
            @test_throws ArgumentError _make_program(String[])
            @test _make_program(["sh", "-c", "exit 0"]).arguments == ["sh", "-c", "exit 0"]
        end

        @testset "a folder that does not exist ends the task ERROR" begin
            execution = _run_program(ProgramTask(`ls`; working_directory = "/no/such/folder"))
            @test execution.result isa TaskStartFailure
            @test execution.result.result == "ERROR"
        end
    end
end
