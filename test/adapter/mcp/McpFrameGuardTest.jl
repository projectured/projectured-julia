# The frame guard of the door of MCP tools: many tool calls that clients make at
# once drain in frames that stay flat at any count of calls. Each call goes through
# the handler that `render_mcp_tools` gives a server, posts its call to the inbox of
# the editor, and waits for the answer; the inbox takes at most 64 calls in a drain,
# so each size is above that bound. The tool has an empty body, so a frame measures
# the door and not the work of a tool. The harness is `FrameGuard.jl` of the kernel
# tests.

# A scene of `size` calls of an empty tool, each from a task of its own, and done
# when every call has its answer.
function _make_mcp_frame_guard_scene()
    answered = Threads.Atomic{Int}(0)
    target = Ref(0)
    handler = Ref{Any}(nothing)
    probe = Tool("frame_guard_probe"; description = "Answers at once.",
                 parameters = NamedTuple[], handler = (target, arguments) -> "done")
    FrameScene("tool calls that clients make at once"; sizes = [100, 1_000, 10_000],
               is_burst = true,
               make_editor = function (size)
                   answered[] = 0
                   target[] = 0
                   editor = _mcp_editor()
                   handler[] = only(tool.handler for tool in render_mcp_tools(editor, [probe])
                                    if tool.name == "frame_guard_probe")
                   editor
               end,
               give_input! = (editor, size) -> _call_mcp_frame_guard_probe(handler[], size, target, answered),
               is_input_done = editor -> answered[] >= target[])
end

# `size` clients call the tool through `handler`, each on a task of its own.
function _call_mcp_frame_guard_probe(handler, size, target, answered)
    target[] += size
    for _ in 1:size
        Threads.@spawn (handler(Dict{String,Any}()); Threads.atomic_add!(answered, 1))
    end
    nothing
end

function test_mcp_frame_guards()
    @testset "the frame guard of the door of MCP tools" begin
        @testset "tool calls that clients make at once drain in flat frames" begin
            scene = _make_mcp_frame_guard_scene()
            # The record counts the bytes of the process, and the clients start on
            # other threads while the first frames run, so the guard asserts the
            # time and the frames, and not the bytes.
            check_frame_growth(scene; allocation_bound = Inf)
            works = measure_frame_work(scene; repetitions = 1)
            # A drain takes at most 64 calls, so the largest burst takes as many
            # frames as 64 calls go into it, and a few more while the clients start.
            largest = works[end]
            @test largest.frame_count <= cld(largest.size, 64) + 5
        end
    end
end
