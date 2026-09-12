# Fragment of `ToolModule` — the `execute_julia_code` tool and the persistent
# namespace it evaluates into.

# The umbrella `Projectured` package (loaded, but not a dependency of the kernel —
# that would be circular) re-exports every submodule of every package below it,
# so it alone is enough. In a per-package test environment the umbrella is
# absent, so fall back to every loaded Projectured package and flat-re-export
# each of their submodules — the same names then resolve. The set is read at
# run time rather than written down, because the packages below the umbrella
# are many and each test environment loads a different subset.
function _scratch_sources(set::ToolSet)
    # A declared API is the whole of it. The names a `ToolSet` declares are the
    # names a model may write, and nothing else arrives — not the umbrella, and
    # not a package that happens to be loaded.
    isempty(set.api) || return copy(set.api)
    whole(mods) = ApiEntry[ApiEntry(mod, nothing) for mod in mods]
    loaded = Dict(String(id.name) => mod for (id, mod) in Base.loaded_modules)
    haskey(loaded, "Projectured") && return whole([loaded["Projectured"]])
    packages = sort([n for n in keys(loaded) if startswith(n, "Projectured")])
    isempty(packages) && return whole([parentmodule(@__MODULE__)])
    whole([loaded[n] for n in packages])
end

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
        # A *relative* path (`using .Source.Module: …`) resolves `Source` in the
        # scratch module, where the caller bound it. An absolute path would ask
        # the package loader instead, and fail for every package the active
        # project does not declare.
        Core.eval(m, Expr(:using, Expr(:(:),
            Expr(:., :., srcname, n), (Expr(:., s) for s in syms)...)))
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
    srcs = _scratch_sources(set)
    mods = Module[entry.module_ for entry in srcs]
    # Bind each source under its own name, so qualified access still works.
    for mod in mods
        Core.eval(m, :(const $(nameof(mod)) = $mod))
    end
    if isempty(set.api)
        for mod in mods
            _flat_reexport!(m, mod, mods)
        end
        # `Projectured` names the umbrella when it is loaded, and the scratch module
        # itself otherwise: after the re-export the scratch module holds the same
        # flat namespace, so `Projectured.CellVector` resolves either way.
        Core.eval(m, :(const Projectured = $(nameof(mods[1]) === :Projectured ? mods[1] : m)))
    else
        # Each entry gives the names it declared, or every name its module
        # exports — and a declared name arrives **unqualified**, exactly as an
        # exported one does. That is what lets a declaration hand out `PaneSplit`
        # while `PaneSplit` goes on having one owning module.
        #
        # A declared module is taken as it stands: its own names, and not the
        # names of the submodules it reaches. A module that means to offer more
        # exports more — which is what makes the list a decision a person writes
        # down, rather than a consequence of what it happens to import.
        for entry in srcs
            bindings = api_entry_bindings(entry)
            isempty(bindings) && continue
            # `using M: name` for a plain one, `using M: name as alias` for a
            # renamed one — which is `Expr(:as, Expr(:., name), alias)`, the same
            # shape Julia parses that line into.
            clauses = (name === alias ? Expr(:., name) :
                       Expr(:as, Expr(:., name), alias)
                       for (name, alias) in bindings)
            Core.eval(m, Expr(:using, Expr(:(:), Expr(:., :., nameof(entry.module_)),
                                           clauses...)))
        end
        # **How to look is always in scope.** The declaration says what a model may
        # DO; finding out what that is, is not one of the things it does. Without
        # these two the locator `search_api` prints for every function — a
        # `read_function_documentation(…)` call — names something the model cannot
        # reach, and it spends a round learning that.
        #
        # They arrive with the declaration already applied, so what they answer and
        # what the code can call are the same set, and a model cannot widen its own
        # view by passing a different one.
        declared = copy(srcs)
        Core.eval(m, :(const read_function_documentation =
            (mod, name, type_name = nothing) ->
                $(read_function_documentation)(mod, name, type_name; api = $declared)))
        Core.eval(m, :(const search_api =
            (query; kwargs...) -> $(search_api)(query; api = $declared, kwargs...)))
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

**A call with no code answers that, rather than answering nothing.** Empty source
evaluates to nothing and printed nothing, so the tool used to return an empty
string — which a model reads as a broken tool rather than as its own mistake, and
then it stops writing code at all. Measured against a local model asked to run a
set of simulations: it wrote an empty call, got a blank back, said "the tool seems
to not be returning the output", and spent every remaining round searching instead
of running anything. The one line back is what lets it correct itself.
"""
function execute_julia_code(set::ToolSet, target, code)
    @info "[tool] execute_julia_code call" code
    set.last_value = nothing
    if code === nothing || isempty(strip(String(code)))
        answer = "No code was given. Put the Julia source in the `code` argument."
        @info "[tool] execute_julia_code result" answer
        return answer
    end
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
    _notify_evaluation(set)
    output
end

# Tell whoever asked what this call produced. After the output is built, so an
# observer that itself evaluates cannot interleave with the capture; and guarded,
# because an observer is a side effect on a result rather than a step of making
# one — a host that throws here must not turn a good evaluation into an error the
# reader has to read.
function _notify_evaluation(set::ToolSet)
    isempty(set.observers) && return nothing
    value = set.last_value
    for observe in set.observers
        try
            observe(value)
        catch err
            @warn "an evaluation observer failed" reason =
                first(split(sprint(showerror, err), "\n"))
        end
    end
    nothing
end
