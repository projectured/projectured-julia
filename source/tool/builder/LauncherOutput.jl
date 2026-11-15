# Fragment of `BuilderModule` — the output of the slow work of a launcher. A
# launcher also includes this file alone, before any package is installed, so it
# uses only Base.

"""
    run_with_slow_output(work; notice, after = 10.0) -> value

Run `work()` with its error output and its logs held back, and answer its value.
When `work` ends within `after` seconds, the held output is dropped, so a start
that has nothing to install or compile stays quiet. When it runs longer, the line
`notice` and the held output go to the error output, and the rest follows as it
comes, so a person sees which package installs or compiles. When `work` throws,
the held output goes there too, and the exception is thrown again.

Use it in a launcher around the preparation of a program: the resolve, the
install and the compile of its packages. A normal start of `bin/projectured`
spends about five seconds there, and the first start after an update some minutes.

# Example

    path = run_with_slow_output(; notice = "Preparing the packages of the program.") do
        Pkg.instantiate()
        "ready"
    end
"""
function run_with_slow_output(work; notice::AbstractString, after::Real = 10.0)
    terminal = stderr
    held = IOBuffer()
    gate = ReentrantLock()
    is_shown = Ref(false)
    # The notice and what was held, once, when the time is up or the work failed.
    function show_held!()
        lock(gate) do
            is_shown[] && return nothing
            is_shown[] = true
            println(terminal, notice)
            write(terminal, take!(held))
            flush(terminal)
            nothing
        end
    end
    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async = true, writer_supports_async = true)
    reader = @async while !eof(pipe)
        bytes = readavailable(pipe)
        lock(gate) do
            is_shown[] ? (write(terminal, bytes); flush(terminal)) : write(held, bytes)
        end
    end
    timer = Timer(_ -> show_held!(), after)
    # The end of the work: no more output comes, and the reader takes what is left.
    function end_output!()
        close(timer)
        close(pipe.in)
        wait(reader)
    end
    try
        value = redirect_stderr(pipe) do
            Base.CoreLogging.with_logger(work, Base.CoreLogging.SimpleLogger(stderr))
        end
        end_output!()
        value
    catch
        end_output!()
        show_held!()
        rethrow()
    end
end
