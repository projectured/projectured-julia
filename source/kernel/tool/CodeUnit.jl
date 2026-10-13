# Fragment of `ToolModule` — the code unit: a piece of work that runs on a thread of
# its own and owns the documents of its editor while it runs, the stop that a
# person asks for, and the wait that a stop ends.

"""
    CodeUnit(parts::Vector{String})

A piece of work that runs on a thread of its own while its editor holds its frames:
a run of the code tool, or the calls that other tasks posted to the editor. While
it runs, it owns the documents of its editor.

`parts` are the words that the busy bar of the editor shows, one for each part of
the work, such as the name of each posted call, and [`set_code_unit_part!`](@ref)
says which part runs. A unit also keeps its start time, its stop flag, and the
stop steps that its stop runs.

Use it through [`run_in_code_unit`](@ref). Code that runs in a unit finds it with
[`get_current_code_unit`](@ref), and so does a task that the code starts.
"""
mutable struct CodeUnit
    parts::Vector{String}
    part::Threads.Atomic{Int}
    started::Float64
    stop::Threads.Atomic{Bool}
    steps::Vector{Any}
    lock::ReentrantLock
    task::Union{Task, Nothing}
end

CodeUnit(parts::Vector{String}) =
    CodeUnit(parts, Threads.Atomic{Int}(1), time(), Threads.Atomic{Bool}(false), Any[],
             ReentrantLock(), nothing)

# The unit of the running code, and of each task that the code starts.
const _CURRENT_CODE_UNIT = ScopedValue{Union{CodeUnit, Nothing}}(nothing)

"""
    get_current_code_unit() -> CodeUnit or nothing

The code unit that the calling code runs in, or `nothing` outside a unit. A task
that the code of a unit starts runs in that unit too.
"""
get_current_code_unit() = _CURRENT_CODE_UNIT[]

"""
    is_code_unit_stopped() -> Bool

Whether the person asked to stop the code unit that the calling code runs in.
`false` outside a unit.

Use it in a long loop of a verb that can end early, such as a wait for a group of
tasks.
"""
function is_code_unit_stopped()
    unit = _CURRENT_CODE_UNIT[]
    unit !== nothing && unit.stop[]
end

"""
    set_code_unit_part!(unit, part) -> Nothing

Say that the part `part` of `unit` runs now, as an index into its parts. The busy
bar shows the words of that part.
"""
set_code_unit_part!(unit::CodeUnit, part::Integer) = (unit.part[] = Int(part); nothing)

"""
    attach_code_unit_stop!(step) -> Nothing

Attach `step`, a function with no argument, to the code unit that the calling code
runs in. A stop of the unit runs each of its steps once, on a task of its own.

Use it in a wait of a verb that a stop must end: the step closes what the wait
waits on, or wakes it. Attach the step first and then look at
[`is_code_unit_stopped`](@ref), so that a stop that came before the step is seen.
Outside a unit, it does nothing.
"""
function attach_code_unit_stop!(step)
    unit = _CURRENT_CODE_UNIT[]
    unit === nothing && return nothing
    lock(() -> push!(unit.steps, step), unit.lock)
    nothing
end

"""
    stop_code_unit!(unit) -> Nothing

Stop `unit`: set its stop flag, and run each of its stop steps once, on a task of
the default pool. It does not wait for the steps, so a caller that must never
block, such as a held frame of the editor, can call it. A second call does
nothing.

A stop ends the waits that attached a step and the `sleep` of the code tool, and
nothing else: Julia can not stop code that runs.
"""
function stop_code_unit!(unit::CodeUnit)
    Threads.atomic_xchg!(unit.stop, true) && return nothing
    steps = lock(() -> copy(unit.steps), unit.lock)
    isempty(steps) && return nothing
    Threads.@spawn :default for step in steps
        try
            step()
        catch exception
            is_fault_exception(exception) || rethrow()
            @error "[tool] a stop step of a code unit failed" exception
        end
    end
    nothing
end

"""
    wait_in_code_unit(seconds) -> Nothing

Wait `seconds`, and end the wait early when the code unit that the calling code
runs in is stopped. A stop throws `InterruptException`, which the code tool
answers as an interrupt of the call. Outside a unit it is `sleep(seconds)`.

The `sleep` of the scratch module of the code tool calls it, so a person can stop
model code that sleeps.
"""
function wait_in_code_unit(seconds::Real)
    unit = _CURRENT_CODE_UNIT[]
    unit === nothing && return sleep(seconds)
    condition = Threads.Condition()
    is_done = Ref(false)
    timer = Timer(_ -> lock(() -> (is_done[] = true; notify(condition)), condition), seconds)
    attach_code_unit_stop!(() -> lock(() -> notify(condition), condition))
    lock(condition)
    try
        while !is_done[] && !unit.stop[]
            wait(condition)
        end
    finally
        unlock(condition)
        close(timer)
    end
    unit.stop[] && throw(InterruptException())
    nothing
end

"""
    run_as_code_unit(function_, unit) -> value

Run `function_()` as the code of `unit`: the code, and each task that it starts,
finds `unit` with [`get_current_code_unit`](@ref), and a stop of `unit` reaches
its waits. Use it on the task that runs the unit.
"""
run_as_code_unit(function_, unit::CodeUnit) = with(function_, _CURRENT_CODE_UNIT => unit)

"""
    run_in_code_unit(function_, target; parts) -> value

Run `function_()` as a code unit of `target`, with the words `parts` for its busy
bar, and answer its value. Code that already runs in a unit runs `function_` as a
part of that unit.

The default runs `function_` at once, on the calling task, in a unit that no stop
reaches. An editor adds a method that runs the unit on a thread of its own while
the editor holds its frames, so the window answers and the person can stop the
unit.
"""
function run_in_code_unit(function_, target; parts::Vector{String})
    _CURRENT_CODE_UNIT[] === nothing || return function_()
    run_as_code_unit(function_, CodeUnit(parts))
end
