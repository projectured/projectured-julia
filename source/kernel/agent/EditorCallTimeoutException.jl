# Fragment of `AgentModule` — `EditorCallTimeoutException`, the end of the wait of a
# call that `run_on_editor_task!` posted and the editor did not start in time.

"""
    EDITOR_CALL_TIMEOUT_SECONDS

How long a call that [`run_on_editor_task!`](@ref) posts with `wait = true` waits
for the editor to start it, by default: 30 seconds. After the start, the caller
waits for the end with no bound, because Julia can not stop a task half way.
"""
const EDITOR_CALL_TIMEOUT_SECONDS = 30.0

"""
    EditorCallTimeoutException(description, seconds)

A call that [`run_on_editor_task!`](@ref) posted waited `seconds`, and the editor did
not start it, because it was busy, such as with a long code unit. The call is
withdrawn: it never runs. A tool call that meets it answers its message as an
error, so a model reads it and can try again.
"""
struct EditorCallTimeoutException <: Exception
    description::String
    seconds::Float64
end

Base.showerror(io::IO, exception::EditorCallTimeoutException) =
    print(io, "EditorCallTimeoutException: the call \"", exception.description, "\" waited ",
          round(exception.seconds; digits = 1), " s, and the editor did not start it, ",
          "because it was busy. The call did not run; try it again later.")
