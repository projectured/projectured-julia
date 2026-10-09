# Fragment of `ToolModule` — `execute_julia_code!` and `execute_julia_expression!`,
# which run the code of the `execute_julia_code` tool, and the persistent namespace
# they evaluate into.

# The packages of the whole surface: every loaded ProjecturEd package that is not
# a test or an example package. The umbrella loads only the packages that a user
# installed, so the surface is what the session loaded, and not a list written
# down. A package that only re-exports others, such as the umbrella, adds nothing,
# because each module counts once, under the package that defines it.
function _collect_surface_packages()
    loaded = Dict(String(id.name) => mod for (id, mod) in Base.loaded_modules)
    packages = sort([n for n in keys(loaded) if startswith(n, "Projectured") &&
                                                !endswith(n, "Test") && !endswith(n, "Example")])
    isempty(packages) && return Module[parentmodule(@__MODULE__)]
    Module[loaded[n] for n in packages]
end

# A module that exports names and defines none of them. A module that it exports
# is left out of the test: the name of a gathered module reaches the aggregate
# through two imports, and `which` refuses such a name.
function _is_aggregate_module(m::Module)
    exported = [name for name in names(m)
                if isdefined(m, name) && !(getfield(m, name) isa Module)]
    !isempty(exported) && all(name -> which(m, name) !== m, exported)
end

# The submodules of `package` on the whole surface, each under the name that the
# package binds it by: a submodule the package defines, or a submodule of a
# package it reaches but `packages` does not name. A submodule whose parent IS in
# `packages` is skipped, so a kernel module that three packages alias is there
# once. A package module itself (parent `Main`) is not a submodule. An aggregate,
# such as `KernelModule`, is left out: it defines none of the names it exports,
# so each of them counts under the module that defines it.
function _collect_package_submodules(package::Module, packages)
    found = Pair{Symbol,Module}[]
    for name in sort!(names(package; all = true))
        isdefined(package, name) || continue
        sub = getfield(package, name)
        (sub isa Module && sub !== package) || continue
        parent = parentmodule(sub)
        (parent === package || (parent !== Main && !(parent in packages))) || continue
        _is_aggregate_module(sub) && continue
        push!(found, name => sub)
    end
    found
end

# The modules of the whole surface, each under the name its package binds it by.
# An empty declaration is the whole surface: the scratch module binds the names
# of these modules, and the documentation tools read these modules, so what a
# model finds and what it can write do not differ.
function _collect_surface_modules()
    packages = _collect_surface_packages()
    Pair{Symbol,Module}[pair for package in packages
                        for pair in _collect_package_submodules(package, packages)]
end

# The whole surface as a declaration: each of its modules with every name that
# it exports, which are the names the scratch module binds.
_collect_surface_api() =
    ApiEntry[ApiEntry(mod, nothing) for (_, mod) in _collect_surface_modules()]

function _scratch_sources(set::ToolSet)
    # A declared API is the whole of it. The names a `ToolSet` declares are the
    # names a model may write, and nothing else arrives — not the umbrella, and
    # not a package that happens to be loaded.
    isempty(set.api) || return copy(set.api)
    ApiEntry[ApiEntry(mod, nothing) for mod in _collect_surface_packages()]
end

function _flat_reexport!(m::Module, source::Module, sources)
    srcname = nameof(source)
    for (n, sub) in _collect_package_submodules(source, sources)
        syms = get_api_entry_names(ApiEntry(sub, nothing))
        isempty(syms) && continue
        # A *relative* path (`using .Source.Module: …`) resolves `Source` in the
        # scratch module, where the caller bound it. An absolute path would ask
        # the package loader instead, and fail for every package the active
        # project does not declare.
        Core.eval(m, Expr(:using, Expr(:(:),
            Expr(:., :., srcname, n), (Expr(:., s) for s in syms)...)))
    end
end

# The names a model looks the API up with. A scratch module built from a
# declaration defines each of them itself, with the declaration applied, so a
# declared module that exports one of these functions does not bind it again.
const _SCRATCH_HELPER_NAMES = (:read_function_documentation, :search_api, :list_modules,
                               :list_types, :list_functions)

# The scratch module for one `ToolSet`, built on first use. Each top-level
# statement of an `execute_julia_code!` call is evaluated here, so an assignment
# (`paths = …`) becomes a module global that survives into the next call — an
# agent can build state up incrementally instead of cramming everything into one
# block, which is a major source of wasted rounds.
function _scratch_module(set::ToolSet)
    set.scratch === nothing || return set.scratch
    m = Module(:ToolScratch)
    srcs = _scratch_sources(set)
    mods = Module[entry.module_ for entry in srcs]
    # Bind each source under its own name, so qualified access still works. The
    # umbrella is the exception: `Projectured` names the scratch module below.
    for mod in mods
        nameof(mod) === :Projectured && continue
        Core.eval(m, :(const $(nameof(mod)) = $mod))
    end
    if isempty(set.api)
        for mod in mods
            _flat_reexport!(m, mod, mods)
        end
        # `Projectured` names the scratch module itself: after the re-export it holds
        # the flat namespace of the whole surface, so `Projectured.CellVector` and
        # `Projectured.JsonObject` resolve whatever the umbrella depends on.
        Core.eval(m, :(const Projectured = $m))
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
        #
        # A helper name is left to the helpers below. The refusal makes sure that
        # a declared helper name is that very function, so nothing is lost.
        _refuse_helper_names(srcs)
        for entry in srcs
            bindings = [binding for binding in get_api_entry_bindings(entry)
                        if !(last(binding) in _SCRATCH_HELPER_NAMES)]
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
        _bind_lookup_functions!(m, set, copy(srcs))
    end
    set.scratch = m
end

# **How to look is always in scope.** The declaration says what a model may DO;
# finding out what that is, is not one of the things it does. Without these the
# locator `search_api` prints for every function — a
# `read_function_documentation(…)` call — names something the model cannot reach,
# and a model that lists a module it was told about learns only that the name is
# not defined. Each such answer costs it a round.
#
# They arrive with the declaration already applied, so what they answer and what
# the code can call are the same set, and a model cannot widen its own view by
# passing a different one. The declaration is written after the splat, because of
# two equal keywords the later one wins. The meaning model and the relevance model
# are read from the set when the search runs, so a model bound after this module
# was built still ranks it.
function _bind_lookup_functions!(m::Module, set::ToolSet, declared::Vector{ApiEntry})
    Core.eval(m, :(const read_function_documentation =
        (mod, name, type_name = nothing) ->
            $(read_function_documentation)(mod, name, type_name; api = $declared)))
    Core.eval(m, :(const search_api =
        (query; kwargs...) -> $(search_api)(query; meaning_model = $(set).meaning_model,
                                            relevance_model = $(set).relevance_model,
                                            kwargs..., api = $declared)))
    Core.eval(m, :(const list_modules = () -> $(list_modules)(; api = $declared)))
    Core.eval(m, :(const list_types =
        module_name -> $(list_types)(module_name; api = $declared)))
    Core.eval(m, :(const list_functions =
        (module_name, type_name = nothing) ->
            $(list_functions)(module_name, type_name; api = $declared)))
    m
end

"""
    get_last_evaluated_value(set) -> Any

The value the most recent `execute_julia_code!` call on `set` produced (`nothing`
if it errored or returned `nothing`). A caller uses this to embed a returned
`Document` as a *live* result — rendering it in place — instead of settling for
its text repr.
"""
get_last_evaluated_value(set::ToolSet) = set.last_value

# How many values of calls `set` keeps; the oldest goes first.
const TOOL_CALL_VALUE_CAPACITY = 32

"""
    keep_tool_call_value!(set, call_id, value) -> value

Keep `value`, the value of the call that has the id `call_id`, in `set` until a
caller takes it with [`take_tool_call_value!`](@ref). A value kept again under
the same id replaces the first. When `TOOL_CALL_VALUE_CAPACITY` values wait, the
oldest goes, so a value that nobody takes does not stay.

Use it when the caller that runs a tool and the caller that shows its result are
not the same, such as the MCP server that runs a tool for an agent and the turn
of the agent that draws the call: the id of the call ties the two.
"""
function keep_tool_call_value!(set::ToolSet, call_id::AbstractString, value)
    filter!(pair -> first(pair) != call_id, set.call_values)
    push!(set.call_values, String(call_id) => value)
    length(set.call_values) > TOOL_CALL_VALUE_CAPACITY && popfirst!(set.call_values)
    value
end

"""
    take_tool_call_value!(set, call_id) -> value or nothing

The value that [`keep_tool_call_value!`](@ref) kept under `call_id`, which then
leaves `set`; `nothing` when none waits.
"""
function take_tool_call_value!(set::ToolSet, call_id::AbstractString)
    index = findfirst(pair -> first(pair) == call_id, set.call_values)
    index === nothing && return nothing
    last(popat!(set.call_values, index))
end

"""
    get_last_evaluation_exception(set) -> exception or nothing

The exception that the code of the most recent `execute_julia_code!` call on
`set` threw, or `nothing` when it threw none. The answer of that call is the
message of the exception, as at the Julia REPL; this is how a caller tells the
two apart.
"""
get_last_evaluation_exception(set::ToolSet) = set.last_exception

"""
    get_evaluation_exception_count(set) -> Int

The number of `execute_julia_code!` and `execute_julia_expression!` calls on
`set` whose code threw. A caller tells whether one call threw by the count before
and after it. The last exception can not tell it, because two exceptions can be
equal: two `ErrorException`s with one message are `===`.
"""
get_evaluation_exception_count(set::ToolSet) = set.exception_count

# The editor that runs the code of the current evaluation, or `nothing` outside one.
const _EVALUATION_EDITOR = ScopedValue{Any}(nothing)

"""
    MissingEvaluationEditorException()

What [`get_evaluation_editor`](@ref) throws outside an evaluation: a verb was
called with no editor, and no code of the evaluator, of the assistant or of the
`execute_julia_code` tool runs. The caller passes the editor as `editor = …`.
"""
struct MissingEvaluationEditorException <: Exception end

Base.showerror(io::IO, ::MissingEvaluationEditorException) =
    print(io, "MissingEvaluationEditorException: no editor runs this code, so the ",
          "verb has no editor. Pass the editor as the keyword `editor = …`.")

"""
    get_evaluation_editor() -> editor

The editor that runs the code of the current evaluation: the code of the
evaluator, of the assistant, or of the `execute_julia_code` tool. A verb takes it
as the default of its `editor` keyword, so the code that calls the verb names no
editor:

    focus_pane!(reference::Reference; editor = get_evaluation_editor())

A task that the code starts gets the same editor. Code that runs after the
evaluation, such as a callback or a timer, gets none, and passes its editor.

Throws [`MissingEvaluationEditorException`](@ref) outside an evaluation.
"""
function get_evaluation_editor()
    editor = _EVALUATION_EDITOR[]
    editor === nothing && throw(MissingEvaluationEditorException())
    editor
end

"""
    execute_julia_code!(set, target, code; describe_value = _describe_value_for_model) -> String

Evaluate `code` in the editor process, with `target` bound as `editor` and the
Projectured names in scope. `target` is also the editor of the evaluation, which
[`get_evaluation_editor`](@ref) answers to each verb that the code calls with no
editor. Statements run at the top level of `set`'s persistent
scratch module, so top-level assignments stay bound for later calls.

**A variable is how a caller keeps what it found.** The description the model
reads tells it to keep each object it finds or makes in its own variable, named by
what it holds and numbered (`items_tab_1`, `rows_1`, then `rows_2`), and to use
the variable in a later call instead of finding the object again.

**The answer is what the code printed, whole, then the value of the last
statement on its own.** What the code prints is what the caller asked for, so
it is never cut. The value of the last statement comes unasked, and it is what
floods a window — a `DataFrame` of thousands of rows, the `Text` a side-effect
verb answers — so `describe_value` renders it instead of the value itself. Its
default, `_describe_value_for_model`, keeps a short value whole, limits a
longer one as the Julia REPL would, and trims one still longer than that to its
start and its end with a note of how to read a part; [`describe_value_for_person`](@ref)
is the other description this editor calls it with, the value exactly as the
REPL shows it, with no note. `nothing`, with nothing printed, answers "Done.",
because an empty answer reads as a broken tool.

**A name that is not defined answers the nearest names that are.** A caller
guesses `plot_results`, and the error names `make_result_plot`: the search that
starts from a guess, done where the guess fails, so it costs no round.

Never throws: an error comes back as its formatted message, after what the code
printed before it, because the caller is usually an agent that must be able to
read the failure and try again.

**A call with no code answers that, rather than answering nothing.** Empty source
evaluates to nothing and prints nothing, and a model reads an empty answer as a
broken tool rather than as its own mistake, and then stops writing code at all. A
local model asked to run a set of simulations wrote an empty call, got a blank
back, said "the tool seems to not be returning the output", and spent every
remaining round searching instead of running anything. The one line back is what
lets it correct itself.
"""
function execute_julia_code!(set::ToolSet, target, code;
                             describe_value::Function = _describe_value_for_model)
    @info "[tool] execute_julia_code! call" code
    set.last_value = nothing
    set.last_exception = nothing
    if code === nothing || isempty(strip(String(code)))
        answer = "No code was given. Put the Julia source in the `code` argument."
        @info "[tool] execute_julia_code! result" answer
        return answer
    end
    # parseall handles code of several lines
    output = _run_expression(set, target, () -> Meta.parseall(code); describe_value)
    @info "[tool] execute_julia_code! result" output
    output
end

"""
    execute_julia_expression!(set, target, expression; describe_value = _describe_value_for_model) -> String

[`execute_julia_code!`](@ref) for code that is already an `Expr`, such as
`Meta.parseall` or `make_julia_expression` gives: the same scratch module, the
same `editor` binding, the same answer, and the same notice to the observers. An
object that the expression holds in a `QuoteNode` is used as that very object.
"""
function execute_julia_expression!(set::ToolSet, target, expression;
                                   describe_value::Function = _describe_value_for_model)
    @info "[tool] execute_julia_expression! call" expression
    set.last_value = nothing
    set.last_exception = nothing
    output = _run_expression(set, target, () -> expression; describe_value)
    @info "[tool] execute_julia_expression! result" output
    output
end

# A statement of a call runs with the scope rule of the Julia REPL: an assignment
# in a loop at the top level assigns the global of that name, as it does at the
# prompt. Evaluated as it is, the loop makes a new local variable instead and
# leaves the global as it was, which a caller reads as data that changed under
# it. The mark in front of the statement is the one `REPL.softscope` puts there,
# and the lowering of Julia reads it.
function _make_soft_scope(statement)
    statement isa Expr || return statement
    statement.head in (:meta, :import, :using, :export, :module, :error, :incomplete, :thunk) &&
        return statement
    statement.head === :global && all(argument -> argument isa Symbol, statement.args) &&
        return statement
    Expr(:block, Expr(:softscope, true), statement)
end

# An exception of model code is the answer of the call, as at the Julia REPL: an
# interrupt ends the evaluation and the session goes on, and a stack overflow is an
# error message. The other exceptions that mean stop, a quit and a heap that ran
# out, go on to the caller. It is the one catch of the kernel that answers an
# exception that means stop (PAR-REPORT-NEVER-THROWS).
_is_passthrough_for_model_code(exception) =
    is_passthrough_exception(exception) &&
    !(exception isa InterruptException || exception isa StackOverflowError)

# Everything an evaluation does after the parse. `make_expression` runs inside
# the guard, so a failure to make the expression is answered like any other.
# `describe_value` renders the last value once the capture is closed, so its
# text never lands inside the same pipe as the code's own `println`s. What the
# code printed comes first in the answer, also before an error.
function _run_expression(set::ToolSet, target, make_expression::Function;
                          describe_value::Function = _describe_value_for_model)
    pipes = (Pipe(), Pipe())
    readers = Task[]
    printed = ""
    described = try
        m = _scratch_module(set)
        # (Re)bind `editor` each call, so user code can reference it and so it
        # always tracks the current target.
        Core.eval(m, :(editor = $(QuoteNode(target))))
        expr = make_expression()

        result = nothing
        # A verb that the code calls with no editor takes `target`, and so does a
        # verb in a task that the code starts.
        with(_EVALUATION_EDITOR => target) do
            redirect_stdio(stdout = pipes[1], stderr = pipes[2]) do
                # A write into a full pipe waits for a reader, so one task reads each
                # pipe while the code runs. `redirect_stdio` opens the pipes.
                append!(readers, [@async(read(pipe.out, String)) for pipe in pipes])
                # Evaluate each top-level statement in order and keep the last value
                # (REPL semantics); top-level assignments persist as module globals.
                if expr isa Expr && expr.head == :toplevel
                    for e in expr.args
                        e isa LineNumberNode && continue
                        result = Core.eval(m, _make_soft_scope(e))
                    end
                else
                    result = Core.eval(m, _make_soft_scope(expr))
                end
            end
        end
        set.last_value = result
        describe_value(result)
    catch e
        _is_passthrough_for_model_code(e) && rethrow()
        set.last_exception = e
        set.exception_count += 1
        sprint(showerror, e, catch_backtrace()) * _suggest_nearest_names(e, set)
    finally
        # A reader reads to the end of its pipe, which comes when its write end closes.
        foreach(pipe -> close(pipe.in), pipes)
        printed = join(fetch(reader) for reader in readers)
        foreach(pipe -> close(pipe.out), pipes)
    end
    answer = printed * described
    output = isempty(strip(answer)) ? "Done." : answer
    _notify_evaluation(set)
    output
end

# The longest value that is shown as it is. Beyond it, the value is limited.
const _SHOWN_VALUE_CHARACTERS = 200

# The longest REPL-limited display a model is shown whole. Beyond it, the
# display is trimmed to its start and its end around one mark line.
const _MODEL_VALUE_CHARACTERS = 600

"""
    describe_value_for_person(value) -> String

The value of the last statement, exactly as the Julia REPL shows it: `show`
with `MIME"text/plain"()`, `:limit => true`, and the size of a default terminal
(24 rows × 80 columns) — a string keeps its quotes, and a long collection keeps
the REPL's own `⋮`. `nothing` describes as nothing, the REPL's own answer to it.

Passed as `describe_value` to [`execute_julia_code!`](@ref) wherever the answer
goes to a person rather than to a model: the evaluator and the chat composer.
"""
function describe_value_for_person(value)
    value === nothing && return ""
    Base.invokelatest(sprint, show, MIME"text/plain"(), value;
        context = (:limit => true, :displaysize => (24, 80))) * "\n"
end

# The value of the last statement, as a model is shown it: a short one as it
# is, a longer one limited as the Julia REPL would limit it, and one still long
# even limited trimmed to its start and its end, with a note of how to read a
# part. Prose a verb answers on purpose is shown whole, however long: a `Text`
# as it is, and a long `String` without its quotes. A verb that answers
# `show_layout`'s layout or a search's hits answers it to be read. A function is
# shown as the Julia REPL shows it, by its name and its number of methods; its
# plain `repr` in the scratch module is the name of its type. The code can make a
# function, a type or a `show` method in a newer world than this one, so each
# display runs in the newest world.
function _describe_value_for_model(value)
    value === nothing && return ""
    value isa Base.Text && return string(value) * "\n"
    value isa Function && return Base.invokelatest(sprint, show, MIME"text/plain"(), value) * "\n"
    text = Base.invokelatest(repr, value; context = :limit => true)
    (length(text) <= _SHOWN_VALUE_CHARACTERS && !occursin('\n', text)) && return text * "\n"
    value isa AbstractString && return String(value) * "\n"
    limited = Base.invokelatest(sprint, show, MIME"text/plain"(), value;
        context = (:limit => true, :displaysize => (20, 100)))
    length(limited) <= _MODEL_VALUE_CHARACTERS && return limited * "\n"
    # Never a print of the whole value — a huge collection would cost too much
    # to render even to measure. Only the already-limited display is trimmed.
    half = _MODEL_VALUE_CHARACTERS ÷ 2
    left_out = length(limited) - 2 * half
    first(limited, half) * "\n⋯ " * string(left_out) * " characters left out ⋯\n" *
        last(limited, half) * "\nThe value is trimmed: " * _summarize_value(value) *
        ". Print a part, as `println(first(x, 10))` or `println(names(x))`.\n"
end

function _summarize_value(value)
    text = try
        Base.invokelatest(summary, value)
    catch exception
        _is_passthrough_for_model_code(exception) && rethrow()
        string(typeof(value))
    end
    length(text) > _SHOWN_VALUE_CHARACTERS ? first(text, _SHOWN_VALUE_CHARACTERS - 1) * "…" : text
end

# The names the code may write: the declared ones, or every name of the surface.
_get_writable_names(set::ToolSet) =
    String[String(name) for entry in (isempty(set.api) ? _collect_surface_api() : set.api)
           for name in get_api_entry_names(entry)]

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
            is_passthrough_exception(err) && rethrow()
            @warn "an evaluation observer failed" reason =
                first(split(sprint(showerror, err), "\n"))
        end
    end
    nothing
end
