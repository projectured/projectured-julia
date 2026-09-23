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
        # view by passing a different one. The declaration is written after the
        # splat, because of two equal keywords the later one wins. The meaning
        # model is read from the set when the search runs, so a model bound after
        # this module was built still ranks it.
        declared = copy(srcs)
        Core.eval(m, :(const read_function_documentation =
            (mod, name, type_name = nothing) ->
                $(read_function_documentation)(mod, name, type_name; api = $declared)))
        Core.eval(m, :(const search_api =
            (query; kwargs...) -> $(search_api)(query; meaning_model = $(set).meaning_model,
                                                kwargs..., api = $declared)))
    end
    set.scratch = m
end

"""
    get_last_evaluated_value(set) -> Any

The value the most recent `execute_julia_code` call on `set` produced (`nothing`
if it errored or returned `nothing`). A caller uses this to embed a returned
`Document` as a *live* result — rendering it in place — instead of settling for
its text repr.
"""
get_last_evaluated_value(set::ToolSet) = set.last_value

"""
    execute_julia_code(set, target, code) -> String

Evaluate `code` in the editor process, with `target` bound as `editor` and the
Projectured names in scope. Statements run at the top level of `set`'s persistent
scratch module, so top-level assignments stay bound for later calls.

**The answer is what the code printed, whole, and the last value in one line.**
What the code prints is what the caller asked for, so it is never cut. The
value of the last expression comes unasked, and it is what floods a window — a
`DataFrame` of thousands of rows, the `Text` a side-effect verb answers — so a
short one is shown as it is and a long one is described by its `summary`; the
caller then prints the part it wants. A value is whole or described, never cut
in the middle. `nothing`, with nothing printed, answers "Done.", because an
empty answer reads as a broken tool.

**A name that is not defined answers the nearest names that are.** A caller
guesses `plot_results`, and the error names `make_result_plot`: the search that
starts from a guess, done where the guess fails, so it costs no round.

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
    # parseall handles code of several lines
    output = _run_expression(set, target, () -> Meta.parseall(code))
    @info "[tool] execute_julia_code result" output
    output
end

"""
    execute_julia_expression(set, target, expression) -> String

[`execute_julia_code`](@ref) for code that is already an `Expr`, such as
`Meta.parseall` or `make_julia_expression` gives: the same scratch module, the
same `editor` binding, the same answer, and the same notice to the observers. An
object that the expression holds in a `QuoteNode` is used as that very object.
"""
function execute_julia_expression(set::ToolSet, target, expression)
    @info "[tool] execute_julia_expression call" expression
    set.last_value = nothing
    output = _run_expression(set, target, () -> expression)
    @info "[tool] execute_julia_expression result" output
    output
end

# Everything an evaluation does after the parse. `make_expression` runs inside
# the guard, so a failure to make the expression is answered like any other.
function _run_expression(set::ToolSet, target, make_expression::Function)
    output = try
        m = _scratch_module(set)
        # (Re)bind `editor` each call, so user code can reference it and so it
        # always tracks the current target.
        Core.eval(m, :(editor = $(QuoteNode(target))))
        expr = make_expression()

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
            print(_describe_last_value(result))
        end

        close(stdout_pipe.in)
        close(stderr_pipe.in)
        stdout_output = String(read(stdout_pipe.out))
        stderr_output = String(read(stderr_pipe.out))
        close(stdout_pipe.out)
        close(stderr_pipe.out)

        answer = stdout_output * stderr_output
        isempty(strip(answer)) ? "Done." : answer
    catch e
        sprint(showerror, e, catch_backtrace()) * _suggest_nearest_names(e, set)
    end
    _notify_evaluation(set)
    output
end

# The longest value that is shown as it is. Beyond it, the value is described.
const _SHOWN_VALUE_CHARACTERS = 200

# The value of the last expression, as the answer shows it: a short one as it
# is, a long one by its `summary` and how to read a part of it, and `nothing` as
# nothing at all. Prose a verb answers on purpose is shown whole, however long:
# a `Text` as it is, and a long `String` without its quotes. A verb that answers
# `show_layout`'s program or a search's hits answers it to be read.
function _describe_last_value(value)
    value === nothing && return ""
    value isa Base.Text && return string(value) * "\n"
    text = repr(value; context = :limit => true)
    (length(text) <= _SHOWN_VALUE_CHARACTERS && !occursin('\n', text)) && return text * "\n"
    value isa AbstractString && return String(value) * "\n"
    "The last value is " * _summarize_value(value) * ". Print the part you want to read, " *
        "as `println(first(x, 10))` or `println(names(x))`.\n"
end

function _summarize_value(value)
    text = try
        summary(value)
    catch
        string(typeof(value))
    end
    length(text) > _SHOWN_VALUE_CHARACTERS ? first(text, _SHOWN_VALUE_CHARACTERS - 1) * "…" : text
end

# The names the code may write: the declared ones, or every name of the surface.
_get_writable_names(set::ToolSet) =
    isempty(set.api) ? String[String(last(split(entry.qualname, '.'))) for entry in _api_index()] :
                       String[String(name) for entry in set.api for name in get_api_entry_names(entry)]

_suggest_nearest_names(error, set::ToolSet) = ""

function _suggest_nearest_names(error::UndefVarError, set::ToolSet)
    nearest = _find_nearest_names(String(error.var), _get_writable_names(set))
    isempty(nearest) && return ""
    "\nDid you mean: " * join(("`" * name * "`" for name in nearest), ", ") * "?\n"
end

# The names closest to a guess, at most `count`: first by the words the guess
# shares with a name — `plot_results` shares two of three with
# `make_result_plot` — and then by edit distance, which is what finds a typo.
function _find_nearest_names(guess::AbstractString, candidates; count::Integer = 3)
    guessed = lowercase(guess)
    guessed_words = _split_name_words(guessed)
    scored = Tuple{Float64,Int,String}[]
    for candidate in unique(candidates)
        lowered = lowercase(candidate)
        lowered == guessed && continue
        shared = length(intersect(guessed_words, _split_name_words(lowered)))
        distance = _compute_edit_distance(guessed, lowered)
        (shared > 0 || distance <= 2) || continue
        push!(scored, (-shared / max(length(guessed_words), 1), distance, candidate))
    end
    sort!(scored)
    [name for (_, _, name) in first(scored, count)]
end

_split_name_words(name::AbstractString) =
    Set(word for word in split(rstrip(name, '!'), r"[^a-z0-9]+") if length(word) >= 2)

function _compute_edit_distance(a::AbstractString, b::AbstractString)
    x = collect(a)
    y = collect(b)
    previous = collect(0:length(y))
    for (i, character) in enumerate(x)
        current = Vector{Int}(undef, length(y) + 1)
        current[1] = i
        for (j, other) in enumerate(y)
            current[j + 1] = min(previous[j + 1] + 1, current[j] + 1,
                                 previous[j] + (character == other ? 0 : 1))
        end
        previous = current
    end
    previous[end]
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
