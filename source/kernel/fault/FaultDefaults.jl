# Fragment of `FaultModule` — what each seam of `FaultInterface.jl` answers when
# nothing above the kernel answered it.

# The kernel shows a fault nowhere. A package that owns a log document adds its
# own method, and until one does a record lives in the store alone.
append_fault!(target, record) = nothing

const _BELL = '\a'

# The live global stream, read at each call. A redirect of the global streams
# takes the BEL too, and a write that throws does not stop the report, because
# `report_fault!` catches it.
_get_fault_sound_stream() = Base.stderr

play_fault_sound!(backend) = (print(_get_fault_sound_stream(), _BELL); nothing)

# Most things keep no faults of their own, and an editor is what does.
get_fault_store(target) = nothing

# Nothing in the kernel can draw a fault, so the kernel has no safe mode
# projection of its own. A package that can draw one answers this.
make_safe_mode_projection(store) = nothing

# An ordinary exception is one a barrier may catch. The exceptions that mean
# stop are named one at a time, by the layer that owns each.
is_passthrough_exception(exception) = false

is_passthrough_exception(::InterruptException) = true
is_passthrough_exception(::StackOverflowError) = true
is_passthrough_exception(::OutOfMemoryError) = true
