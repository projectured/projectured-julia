# Fragment of `ToolModule` — the `execute_julia_code` tool and the persistent
# namespace it evaluates into.

# The umbrella `Projectured` package (loaded, but not a dependency of the kernel —
# that would be circular) re-exports every kernel/base/visual/domain submodule.
# Prefer it, so scratch code can reach any loaded domain type. In a per-package
# test environment the
# umbrella is absent, so fall back to whichever source packages ARE loaded and
# flat-re-export each of their submodules ourselves — the same names then resolve.
const _SOURCE_PREFERENCE = ("Projectured", "ProjecturedDomain", "ProjecturedVisual",
                            "ProjecturedBase", "ProjecturedKernel")

function _flat_reexport!(m::Module, source::Module, sources)
    srcname = nameof(source)
    for n in names(source; all = true)
        isdefined(source, n) || continue
        sub = getfield(source, n)
        sub isa Module && sub !== source || continue
        # A submodule this source defines, or a submodule of a package the source
        # reaches but `sources` does not name. The second case is a concrete
        # domain in its own package: the umbrella binds it, so it arrives here
        # through that binding. A submodule whose parent IS in `sources` is
        # skipped, so a kernel module aliased by three sources is not bound three
        # times. A package module itself (parent `Main`) is not a submodule.
        parent = parentmodule(sub)
        (parent === source || (parent !== Main && !(parent in sources))) || continue
        syms = [s for s in names(sub) if s !== nameof(sub) && isdefined(sub, s)]
        isempty(syms) && continue
        Core.eval(m, Expr(:using, Expr(:(:),
            Expr(:., srcname, n), (Expr(:., s) for s in syms)...)))
    end
end

# The scratch module for one `ToolSet`, built on first use. Each top-level
# statement of an `execute_julia_code` call is evaluated here, so an assignment
# (`paths = …`) becomes a module global that survives into the next call — an
# agent can build state up incrementally instead of cramming everything into one
# block, which is a major source of wasted rounds.
function _scratch_module(set::ToolSet)
    set.scratch === nothing || return set.scratch
    m = Module(:ToolScratch)
    loaded = Dict(String(id.name) => mod for (id, mod) in Base.loaded_modules)
    srcs = Module[loaded[n] for n in _SOURCE_PREFERENCE if haskey(loaded, n)]
    isempty(srcs) && push!(srcs, parentmodule(@__MODULE__))
    # Bind each source under its own name, so qualified access still works, and
    # alias the highest-preference one as `Projectured`.
    for src in srcs
        Core.eval(m, :(const $(nameof(src)) = $src))
    end
    Core.eval(m, :(const Projectured = $(srcs[1])))
    for src in srcs
        _flat_reexport!(m, src, srcs)
    end
    set.scratch = m
end

"""
    last_evaluated_value(set) -> Any

The value the most recent `execute_julia_code` call on `set` produced (`nothing`
if it errored or returned `nothing`). A caller uses this to embed a returned
`Document` as a *live* result — rendering it in place — instead of settling for
its text repr.
"""
last_evaluated_value(set::ToolSet) = set.last_value

"""
    execute_julia_code(set, target, code) -> String

Evaluate `code` in the editor process, with `target` bound as `editor` and the
Projectured names in scope. Statements run at the top level of `set`'s persistent
scratch module, so top-level assignments stay bound for later calls. Returns the
repr of the last value together with anything the code printed.

Never throws: an error comes back as its formatted message, because the caller is
usually an agent that must be able to read the failure and try again.
"""
function execute_julia_code(set::ToolSet, target, code)
    @info "[tool] execute_julia_code call" code
    set.last_value = nothing
    output = try
        m = _scratch_module(set)
        # (Re)bind `editor` each call, so user code can reference it and so it
        # always tracks the current target.
        Core.eval(m, :(editor = $(QuoteNode(target))))
        expr = Meta.parseall(code)          # parseall handles multi-line code

        stdout_pipe = Pipe()
        stderr_pipe = Pipe()

        redirect_stdio(stdout = stdout_pipe, stderr = stderr_pipe) do
            # Evaluate each top-level statement in order and keep the last value
            # (REPL semantics); top-level assignments persist as module globals.
            result = nothing
            if expr isa Expr && expr.head == :toplevel
                for e in expr.args
                    e isa LineNumberNode && continue
                    result = Core.eval(m, e)
                end
            else
                result = Core.eval(m, expr)
            end
            set.last_value = result
            result === nothing || println(repr(result))
        end

        close(stdout_pipe.in)
        close(stderr_pipe.in)
        stdout_output = String(read(stdout_pipe.out))
        stderr_output = String(read(stderr_pipe.out))
        close(stdout_pipe.out)
        close(stderr_pipe.out)

        stdout_output * stderr_output
    catch e
        sprint(showerror, e, catch_backtrace())
    end
    @info "[tool] execute_julia_code result" output
    output
end
