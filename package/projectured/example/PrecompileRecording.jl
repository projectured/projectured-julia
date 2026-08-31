# ═══════════════════════════════════════════════════════════════════════════
# example/PrecompileRecording.jl
#
# The other way to fill a package image: instead of running a workload and
# hoping it covered the product, run the product once, write down every method
# instance Julia had to compile, check the list in, and let later builds replay
# it.
#
# What a workload cannot cover is what nobody thought to run. Measured
# downstream, the workload reached the printers and never reached the
# readers — atoms are documents and a document is printed, not read — so the
# read half of the first click cost 528 ms with the workload and 518 ms without
# it. A recording does not need the thought: it records what a person did.
#
# This file is the machinery only. What to drive is a driver script, and which
# list to replay is a file, and both belong to the leaf being built —
# `ProjecturedRepl` here, and the repl leaf of each downstream repository.
# One implementation, three products.
#
# See plan/pending/recorded-precompile-workload.md.
# ═══════════════════════════════════════════════════════════════════════════

"""
    PRECOMPILE_STALE_RATIO

The share of a recorded list that may be skipped before
[`replay_precompile_statements`](@ref) asks for a new recording. A statement is
skipped when it names a type or a method that no longer exists, which is what an
old list looks like as the code moves under it.
"""
const PRECOMPILE_STALE_RATIO = 0.1

"""
    bind_loaded_modules!(scope::Module) -> Int

Bind every loaded module into `scope` under its own name, and answer how many
took. What a recorded statement names is a type in the module that defines it —
`ProjecturedSerialization.FileProjectModule.var"#…"` — so a name that is not bound is a
statement that cannot resolve. Measured on one recording: 12.9 % of the list
resolves against a single package's own imports and 99.2 % against every loaded
module.

`scope` must be a module of the package **being built**. Binding into a module
that belongs to a dependency would be one package's build writing into another
package's image, which is what makes incremental compilation unsafe.
"""
function bind_loaded_modules!(scope::Module)
    bound = 0
    for (_, loaded) in Base.loaded_modules
        name = nameof(loaded)
        name === :Main && continue
        isdefined(scope, name) && continue
        try
            Core.eval(scope, :(const $name = $loaded))
            bound += 1
        catch
            # A module whose name cannot be bound costs the statements rooted at
            # it and nothing else.
        end
    end
    bound
end

"""
    replay_precompile_statements(statements, scope; warn = true, ratio = PRECOMPILE_STALE_RATIO)
        -> (compiled, skipped, total)

Compile every statement in `statements` that still names something, resolving it
in `scope`, and answer how many did. A leaf calls this inside its
`@compile_workload`; call it at the prompt to see what a list is worth without a
rebuild.

A statement that names nothing is skipped, never thrown, so a list is allowed to
be as old as the last recording. `warn = true` reports when more than `ratio` of
it was skipped, which is the signal that
[`record_precompile_statements`](@ref) should be run again.
"""
function replay_precompile_statements(statements::AbstractVector{<:AbstractString},
                                      scope::Module;
                                      warn::Bool = true,
                                      ratio::Real = PRECOMPILE_STALE_RATIO)
    bind_loaded_modules!(scope)
    compiled = 0
    skipped = 0
    for source in statements
        try
            signature = Core.eval(scope, Meta.parse(source))
            precompile(signature) ? (compiled += 1) : (skipped += 1)
        catch
            # The graceful case: the list is older than the code.
            skipped += 1
        end
    end
    total = length(statements)
    if warn && total > 0 && skipped / total > ratio
        skipped_ratio = round(skipped / total; digits = 3)
        @warn "the recorded precompile statements are going stale — record them again" skipped total skipped_ratio
    end
    (compiled = compiled, skipped = skipped, total = total)
end

"""
    record_precompile_statements(driver, output; project, threads) -> output

Run `driver` in a fresh process under `--trace-compile`, and write what it
compiled to `output` as a list [`replay_precompile_statements`](@ref) can replay.
Answers the path it wrote.

The run is a separate process because `--trace-compile` is a command-line flag
rather than something a running session can turn on. It is also a person's step
rather than a build's, which is what lets a driver open a real window and take
as long as it likes.

`project` is the environment to run in, and defaults to the active one.
"""
function record_precompile_statements(driver::AbstractString,
                                      output::AbstractString;
                                      project::AbstractString = dirname(Base.active_project()),
                                      threads::Integer = 4)
    trace = tempname() * ".jl"
    command = `$(Base.julia_cmd()) --project=$project --threads=$threads --trace-compile=$trace $driver`
    @info "recording — the driver opens a window and drives it" driver project
    run(command)
    statements = clean_precompile_trace(trace)
    write_precompile_statements(output, statements)
    @info "recorded" statements = length(statements) output
    output
end

"""
    clean_precompile_trace(trace) -> Vector{String}

The signature sources worth keeping from a `--trace-compile` file: one per line,
deduplicated, and sorted so that a re-recording makes a diff a person can read.

Three kinds are dropped. A statement naming `Main` belongs to the driver script
rather than to the stack. A statement that does not parse cannot be read back —
a unit carries its value inside its type, and such a type does not survive being
written down. Anything that is not a `precompile(…)` call is not ours.

The signature is cut out of the line rather than re-printed from the parsed
expression: a printed expression is not always the text that was parsed, and a
statement that does not read back is one that is skipped for ever.
"""
function clean_precompile_trace(trace::AbstractString)
    prefix = "precompile("
    kept = Set{String}()
    for line in eachline(trace)
        line = strip(line)
        (isempty(line) || occursin("Main.", line)) && continue
        (startswith(line, prefix) && endswith(line, ")")) || continue
        source = line[(length(prefix) + 1):(end - 1)]
        try
            Meta.parse(source)
        catch
            continue
        end
        push!(kept, source)
    end
    sort!(collect(kept))
end

"""
    write_precompile_statements(path, statements) -> path

Write `statements` as the generated file a leaf includes.
"""
function write_precompile_statements(path::AbstractString,
                                     statements::AbstractVector{<:AbstractString})
    open(path, "w") do io
        println(io, "# ═══════════════════════════════════════════════════════════════════════════")
        println(io, "# Generated by `record_precompile_statements`. Do not edit.")
        println(io, "#")
        println(io, "# One entry per method instance a traced run of this repository's driver had")
        println(io, "# to compile, written as the source of its signature type.")
        println(io, "# `replay_precompile_statements` resolves each one and compiles it into the")
        println(io, "# image of the leaf that includes this file.")
        println(io, "#")
        println(io, "# An entry that no longer names anything is skipped, so this file may be as")
        println(io, "# old as you like. The build says how many were skipped and asks for a new")
        println(io, "# recording when too many are.")
        println(io, "# ═══════════════════════════════════════════════════════════════════════════")
        println(io)
        println(io, "const PRECOMPILE_STATEMENTS = String[")
        for statement in statements
            println(io, "    ", repr(statement), ",")
        end
        println(io, "]")
    end
    path
end
