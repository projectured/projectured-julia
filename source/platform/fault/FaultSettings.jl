# Fragment of `FaultViewModule` — the settings of what an editor does with a fault.

"""
    FaultSettings(; is_barrier_enabled = true, is_console_enabled = true,
                    is_sound_enabled = true)

Whether the editor catches a fault and goes on, writes it to the log, and
plays a sound for it.

What an editor does with a fault: the three flags of its `FaultPolicy`. The
settings reach the policy of the editor through `apply_settings!`. A change of
`is_barrier_enabled` prints the view again, because each barrier reads it while
it prints. The log and the sound act from the next fault, with no new print.
"""
@settings struct FaultSettings
    "Catch faults: a barrier catches a fault and shows it, and the editor goes on."
    is_barrier_enabled::Bool = true
    "Log faults: write each new fault to the log."
    is_console_enabled::Bool = true
    "Fault sound: play a sound for a fault of the last tier."
    is_sound_enabled::Bool = true
end

# The settings become the fault policy of the editor. `run_print_stage!` puts the policy
# into the printer context, and a barrier decides while it prints whether it
# catches, so a change of `is_barrier_enabled` needs a new print, as in
# `run_editor!`. A report reads the log and the sound flags from the editor.
is_settings_group_applied(::Type{FaultSettings}) = true

function read_settings!(settings::FaultSettings, editor::Editor)
    policy = editor.fault_policy
    settings.is_barrier_enabled = policy.is_barrier_enabled
    settings.is_console_enabled = policy.is_console_enabled
    settings.is_sound_enabled = policy.is_sound_enabled
    nothing
end

"""
    make_fault_policy(settings::FaultSettings) -> FaultPolicy

The fault policy that `settings` choose, for an editor that a program builds
from its settings.
"""
make_fault_policy(settings::FaultSettings) =
    FaultPolicy(is_barrier_enabled = settings.is_barrier_enabled,
                is_console_enabled = settings.is_console_enabled,
                is_sound_enabled = settings.is_sound_enabled)

function apply_settings!(editor::Editor, settings::FaultSettings)
    policy = make_fault_policy(settings)
    editor.fault_policy.is_barrier_enabled == policy.is_barrier_enabled ||
        invalidate_projection!(editor)
    editor.fault_policy = policy
    nothing
end
