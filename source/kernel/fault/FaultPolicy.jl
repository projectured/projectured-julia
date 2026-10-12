# Fragment of `FaultModule` — whether the barriers catch, and which report tiers
# are open.

"""
    FaultPolicy(; is_barrier_enabled = true, …)

What the barriers and the report do with a fault. One per editor.

- `is_barrier_enabled` — whether a barrier catches at all. **Every form that
  makes an editor starts with it false**, and a program that a person starts
  passes `FaultPolicy()`. A barrier that swallows under test turns a real bug
  into a passing run, which is the one way this whole feature can make the
  program worse. With it false, `run_fault_barrier!` re-raises and a broken
  projection fails its test.
- `is_console_enabled` — whether a new fault is written to the log stream.
- `is_sound_enabled` — whether the last audible tier may play.

# Example

    policy = FaultPolicy(is_sound_enabled = false)

See also [`run_fault_barrier!`](@ref) and [`report_fault!`](@ref).
"""
struct FaultPolicy
    is_barrier_enabled::Bool
    is_console_enabled::Bool
    is_sound_enabled::Bool
end

FaultPolicy(; is_barrier_enabled::Bool = true,
              is_console_enabled::Bool = true,
              is_sound_enabled::Bool = true) =
    FaultPolicy(is_barrier_enabled, is_console_enabled, is_sound_enabled)

"""
    make_strict_fault_policy() -> FaultPolicy

The policy that catches nothing. Every barrier re-raises, so an exception ends
the run and a test sees it.

It is the default of every form that makes an editor. Use it in a test, and in
any harness where a fault is to fail the run rather than be survived.

# Example

    count = run_fault_barrier!(() -> parse(Int, text), store;
                               policy = make_strict_fault_policy(), backend,
                               site = :read)

See also [`FaultPolicy`](@ref).
"""
make_strict_fault_policy() = FaultPolicy(is_barrier_enabled = false)
