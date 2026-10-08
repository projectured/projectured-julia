# The transport with a real process: a child agent that starts and ends with its
# input, one that ignores the end of its input and keeps a child of its own, and
# a command that does not exist.

# A child agent in plain Julia: it answers `initialize` with the line in
# `CHILD_AGENT_ANSWER`, with the id of the request in place of `ANSWER_ID`, and
# reads on until its input ends. The id is the first `id` of the request,
# because the parameters of `initialize` hold no other.
const _CHILD_AGENT = raw"""
for line in eachline(stdin)
    m = match(r"id.:(\d+)", line)
    m === nothing && continue
    occursin("initialize", line) || continue
    println(replace(ENV["CHILD_AGENT_ANSWER"], "ANSWER_ID" => m[1]))
    flush(stdout)
    if get(ENV, "CHILD_AGENT_STAYS", "") in ("yes", "leaves")
        grandchild = run(`sleep 3600`; wait = false)
        write(ENV["CHILD_AGENT_PID_FILE"], string(getpid(grandchild)))
        ENV["CHILD_AGENT_STAYS"] == "leaves" && exit(0)
        sleep(3600)
    end
end
"""

const _CHILD_ANSWER = replace(JSON3.write(Dict(
    "jsonrpc" => "2.0", "id" => "ANSWER_ID",
    "result" => Dict("protocolVersion" => 1, "agentCapabilities" => Dict(),
                     "agentInfo" => Dict("name" => "child", "title" => "Child Agent"),
                     "authMethods" => []))), "\"ANSWER_ID\"" => "ANSWER_ID")

_make_child_command() = String[Base.julia_cmd().exec..., "--startup-file=no", "-e", _CHILD_AGENT]

_is_process_alive(pid::Integer) = ccall(:kill, Cint, (Cint, Cint), pid, 0) == 0

function test_acp_transport()
    @testset "an ACP agent in a process" begin
        @testset "an agent starts, and ends with its input" begin
            connection = make_agent_connection(:acp; command = _make_child_command(),
                                               environment = Dict("CHILD_AGENT_ANSWER" => _CHILD_ANSWER))
            start_agent_connection!(connection)
            @test connection.agent_info.title == "Child Agent"
            process = connection.transport.process
            stop_agent_connection!(connection)
            @test process_exited(process)
        end

        @testset "an agent that stays ends with its children" begin
            mktempdir() do directory
                pid_file = joinpath(directory, "grandchild.pid")
                connection = make_agent_connection(:acp; command = _make_child_command(),
                    environment = Dict("CHILD_AGENT_ANSWER" => _CHILD_ANSWER, "CHILD_AGENT_STAYS" => "yes",
                                       "CHILD_AGENT_PID_FILE" => pid_file))
                start_agent_connection!(connection)
                @test timedwait(() -> isfile(pid_file) && !isempty(read(pid_file, String)), 30.0) === :ok
                grandchild = parse(Int, read(pid_file, String))
                @test _is_process_alive(grandchild)
                process = connection.transport.process
                started = time()
                stop_agent_connection!(connection)
                @test process_exited(process)
                @test time() - started < 10
                @test timedwait(() -> !_is_process_alive(grandchild), 5.0) === :ok
            end
        end

        @testset "an agent that ends closes its transport, and a start starts it again" begin
            mktempdir() do directory
                pid_file = joinpath(directory, "grandchild.pid")
                connection = make_agent_connection(:acp; command = _make_child_command(),
                    environment = Dict("CHILD_AGENT_ANSWER" => _CHILD_ANSWER, "CHILD_AGENT_STAYS" => "leaves",
                                       "CHILD_AGENT_PID_FILE" => pid_file))
                start_agent_connection!(connection)
                first_process = connection.transport.process
                # The agent ends and leaves a child that holds its output open.
                @test timedwait(() -> process_exited(first_process), 30.0) === :ok
                @test timedwait(() -> connection.transport.is_closed, 10.0) === :ok
                grandchild = parse(Int, read(pid_file, String))
                @test timedwait(() -> !_is_process_alive(grandchild), 10.0) === :ok
                @test_throws Exception open_agent_session!(connection)
                rm(pid_file)
                start_agent_connection!(connection)
                @test connection.transport.process !== first_process
                @test connection.agent_info.title == "Child Agent"
                stop_agent_connection!(connection)
            end
        end

        @testset "a command that does not exist says so" begin
            connection = make_agent_connection(:acp; command = ["projectured-no-such-agent"])
            message = try
                start_agent_connection!(connection)
                ""
            catch exception
                sprint(showerror, exception)
            end
            @test occursin("The agent command `projectured-no-such-agent` can not start", message)
            @test connection.transport === nothing
        end
    end
end
