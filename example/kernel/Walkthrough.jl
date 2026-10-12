# A walkthrough of a kernel layer: the lines that a person types in a REPL to try the
# layer, each with the value that it gives.

"""
    _print_walkthrough(io::IO, layer::Module, lines)

Run `lines` in a new module that uses `layer`, and print them as a REPL session.

A line that starts with `#` prints as it is. Every other line is parsed and run,
and prints after a `julia> ` prompt, with the value that it gives under it. All
lines run in one module, so a name that one line binds is there for the lines
after it. The printed code is the code that runs, so a value under a line is
always the value that the line gives.
"""
function _print_walkthrough(io::IO, layer::Module, lines::AbstractVector{<:AbstractString})
    session = Module(:Walkthrough)
    Core.eval(session, :(const Layer = $layer))
    Core.eval(session, :(using .Layer))
    println(io, "# Type each line in a REPL after `using ", join(fullname(layer), "."), "`.")
    println(io)
    for line in lines
        if startswith(line, "#")
            println(io, line)
            continue
        end
        println(io, "julia> ", line)
        value = Core.eval(session, Meta.parse(line))
        if value !== nothing
            # The line can define a name that the value shows, and this function
            # runs in the world from before the line ran. The session is the module
            # that names its types, as `Main` is in a REPL.
            Base.invokelatest(show, IOContext(io, :limit => true, :module => session),
                              MIME"text/plain"(), value)
            println(io)
        end
        println(io)
    end
    return nothing
end
