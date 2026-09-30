# Fragment of `FaultModule` — whether the barriers catch, and which report tiers
# are open.

"""
    FaultPolicy(; is_barrier_enabled = true, …)

What the barriers and the report do with a fault. One per editor.

- `is_barrier_enabled` — whether a barrier catches at all. **An editor that a
  test makes has it false.** A barrier that swallows under test turns a real bug
  into a passing run, which is the one way this whole feature can make the
  program worse. With it false, `run_fault_barrier!` re-raises and a broken
  projection fails its test.
- `is_console_enabled` — whether a new fault is written to the log stream.
- `is_sound_enabled` — whether the last audible tier may play.

# Example

    editor.fault_policy = make_strict_fault_policy()   # in a test

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

Use it in a test, and in any harness where a fault is to fail the run rather
than be survived.

# Example

    editor = make_editor(document, projection; backend,
                         fault_policy = make_strict_fault_policy())

See also [`FaultPolicy`](@ref).
"""
make_strict_fault_policy() = FaultPolicy(is_barrier_enabled = false)
