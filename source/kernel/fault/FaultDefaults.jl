# Fragment of `FaultModule` — what each seam of `FaultInterface.jl` answers when
# nothing above the kernel answered it.

append_fault!(target, record) = false

const _BELL = '\a'

# The live global stream, read at each call. A redirect of the global streams
# takes the BEL too, and a write that throws does not stop the report, because
# `report_fault!` catches it.
_get_fault_sound_stream() = Base.stderr

play_fault_sound!(backend) = (print(_get_fault_sound_stream(), _BELL); nothing)

get_fault_store(target) = nothing

is_passthrough_exception(exception) = false

is_passthrough_exception(::InterruptException) = true
is_passthrough_exception(::StackOverflowError) = true
is_passthrough_exception(::OutOfMemoryError) = true
