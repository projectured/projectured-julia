# Fragment of `ReplModule` — the workload of the leaf: the level it compiles
# ahead of time, and the recording of precompile statements that it replays.

"""
    WORKLOAD

How this build compiled ahead of time: `:none`, `:recorded` or `:live`. Read as a
preference at module scope, so the precompile cache depends on it and changing it
rebuilds. An environment variable would not — the stale image would be reused and
the setting would quietly do nothing.
"""
const WORKLOAD = Symbol(@load_preference("workload", "recorded"))

const WORKLOAD_LEVELS = (:none, :recorded, :live)

"""
    set_workload!(level::Symbol) -> level

Choose how the next build compiles, then restart Julia. The next `using
ProjecturedREPL` pays the build once.

| level | what the build does |
| --- | --- |
| `:none` | nothing; for a day spent editing the kernel |
| `:recorded` | replays [`PRECOMPILE_STATEMENTS`](@ref) — the default |
| `:live` | runs `ProjecturedExample.precompile_workload()` |

`:recorded` is the default. A recording covers what a person actually did rather
than what somebody thought to write down, which is why it is the only one of the
three that compiles the *reader*: measured downstream, the read half of a
first click is 4.4 ms under `:recorded` and 528 ms under `:live`, the same as
under no workload at all.

It costs a checked-in list that has to be re-recorded as the code moves — see
[`record_precompile_statements`](@ref). The list goes stale gracefully, and
`:live` is what to choose when a build must not depend on a file.
"""
function set_workload!(level::Symbol)
    level in WORKLOAD_LEVELS ||
        error("set_workload!: level must be one of ", WORKLOAD_LEVELS, ", got ",
              repr(level))
    set_preferences!(@__MODULE__, "workload" => String(level); force = true)
    @info "workload level set — restart Julia for it to take effect" level
    level
end

"""
    get_workload() -> Symbol

The level **this session was built with** — the same value as [`WORKLOAD`](@ref),
as a function, so it pairs with [`set_workload!`](@ref).

It also answers the question `WORKLOAD` cannot: whether the level stored for the
next build still matches the one in this image. `set_workload!` writes a
preference and a preference only takes effect on a rebuild, so a session where
the two differ is a session that has not been restarted yet, and this says so.
"""
function get_workload()
    stored = Symbol(@load_preference("workload", "recorded"))
    if stored !== WORKLOAD
        @warn "this session was built with another level; restart to pick the stored one up" built=WORKLOAD stored=stored
    end
    WORKLOAD
end

# ── the recording ──────────────────────────────────────────────────────────
#
# The machinery is `ProjecturedExample`'s, shared with the other repositories'
# leaves. What belongs here is what only this repository knows: which runs to
# record, and where their lines go (`ReplStatementFiles.jl`).

"""
    replay_precompile_statements(; warn = true) -> (compiled, skipped, total)

Compile every statement of this repository's recording that still names
something. Called by the build; call it at the prompt to see what the list is
worth without a rebuild.
"""
replay_precompile_statements(; warn::Bool = true) =
    ProjecturedExample.replay_precompile_statements(PRECOMPILE_STATEMENTS,
                                                    StatementScope; warn = warn)

"""
    record_precompile_statements(recording = "examples"; threads) -> Vector{String}

Run the driver of the recording named `recording` (see
[`PRECOMPILE_RECORDINGS`](@ref)) under `--trace-compile`, in its environment, and
write what it compiled into the statement files of the packages, as
[`write_precompile_statement_files`](@ref) does. Answers the paths that it wrote.
Needs a display: the driver opens a real window, so that what it records is the
whole stack down to SDL.
"""
# @optional: the name of the recording stands first, as at a command line.
function record_precompile_statements(recording::AbstractString = "examples"; kwargs...)
    entry = PRECOMPILE_RECORDINGS[recording]
    statements = ProjecturedExample.trace_precompile_statements(entry.driver;
                                                                project = entry.project, kwargs...)
    write_precompile_statement_files(recording, statements)
end

@setup_workload begin
    # Built outside the workload: constructing the documents is not what needs
    # compiling, and this keeps the measured region to the pipeline.
    _atoms = ProjecturedExample.atomic_documents()
    @compile_workload begin
        WORKLOAD === :recorded && replay_precompile_statements()
        WORKLOAD === :live && ProjecturedExample.precompile_workload(atoms = _atoms)
    end
end
