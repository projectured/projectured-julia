# Fragment of `FaultViewModule` — the settings of what an editor does with a fault.

"""
    FaultSettings(; is_barrier_enabled = true, is_console_enabled = true,
                    is_sound_enabled = true)

What an editor does with a fault: the three flags of its `FaultPolicy`. The
settings reach the policy of the editor through `apply_settings!`, and a change
prints the view again, because the barriers read the policy while they print.
"""
@settings struct FaultSettings
    "Catch faults: a barrier catches a fault and shows it, and the editor goes on."
    is_barrier_enabled::Bool = true
    "Log faults: write each new fault to the log."
    is_console_enabled::Bool = true
    "Fault sound: play a sound for a fault of the last tier."
    is_sound_enabled::Bool = true
end

# The settings become the fault policy of the editor. `print!` puts the policy
# into the printer context, so a new policy needs a new print, as
# `run_editor!` does.
function read_settings!(settings::FaultSettings, editor::Editor)
    policy = editor.fault_policy
    settings.is_barrier_enabled = policy.is_barrier_enabled
    settings.is_console_enabled = policy.is_console_enabled
    settings.is_sound_enabled = policy.is_sound_enabled
    nothing
end

function apply_settings!(editor::Editor, settings::FaultSettings)
    policy = FaultPolicy(is_barrier_enabled = settings.is_barrier_enabled,
                         is_console_enabled = settings.is_console_enabled,
                         is_sound_enabled = settings.is_sound_enabled)
    editor.fault_policy == policy || invalidate_projection!(editor)
    editor.fault_policy = policy
    nothing
end
