# Fragment of `FaultModule` — what each seam of `FaultInterface.jl` answers when
# nothing above the kernel answered it.

# The kernel shows a fault nowhere. A package that owns a log document adds its
# own method, and until one does a record lives in the store alone.
append_fault!(target, record) = nothing

# The one stream a fault may be written to. `execute_julia_code` redirects the
# global stdout and stderr to a pipe while it runs, and that pipe is closed by
# the time a later frame writes to it, so a raw write to the live global stream
# can land in a closed pipe and end the process. The logger holds the stream as
# it was at start, and this is the same stream.
const _BELL = '\a'

_get_fault_sound_stream() = Base.stderr

"""
    play_fault_sound!(backend)

Write the BEL character. Every backend that adds no method of its own gets this.
"""
play_fault_sound!(backend) = (print(_get_fault_sound_stream(), _BELL); nothing)

# Most things keep no faults of their own, and an editor is what does.
get_fault_store(target) = nothing
get_fault_policy(target) = make_strict_fault_policy()

# An ordinary exception is one a barrier may catch. The exceptions that mean
# stop are named one at a time, by the layer that owns each.
is_passthrough_exception(exception) = false

is_passthrough_exception(::InterruptException) = true
is_passthrough_exception(::StackOverflowError) = true
is_passthrough_exception(::OutOfMemoryError) = true
