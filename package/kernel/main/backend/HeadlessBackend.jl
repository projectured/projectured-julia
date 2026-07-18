"""
    HeadlessBackendModule

A dependency-free in-memory backend and scripted event source that the
kernel editor loop can drive without any real device.

Purpose:
- CI: the editor loop tests do not need SDL to be installed.
- Documentation examples: a self-contained "load and step the editor once"
  snippet.
- Regression fixtures for the layer-6 seams: `initialize_backend!`,
  `quit_backend!`, `measure_text`, `read_from_devices`,
  `write_to_devices`.

`HeadlessBackend` records every rendered document (via `write_to_devices`) into
a `rendered` vector so tests can assert on the write. `push_event!` pushes a
new event onto its scripted event queue; `read_from_devices` pops the next
event or returns `nothing` when the queue drains.

This backend is deliberately document-agnostic — it uses only the abstract
`Document` type (opaque payload) and the device I/O generics, no concrete
document is imported. That is the seam pressure that keeps the backend layer
document-free.
"""
module HeadlessBackendModule

using ..BackendModule

export HeadlessBackend, rendered_output, push_event!

"""
    HeadlessBackend()

A dependency-free backend with a rendered-document log and a scripted event
queue.
"""
mutable struct HeadlessBackend <: Backend
    rendered::Vector{Any}
    events::Vector{Any}
    HeadlessBackend() = new(Any[], Any[])
end

# Lifecycle: both are no-ops; there is no external state to init or release.
BackendModule.initialize_backend!(::HeadlessBackend) = nothing
BackendModule.quit_backend!(::HeadlessBackend) = nothing

# Text measurement: a stub returning a fixed metric per character. Tests that
# depend on exact geometry are not this backend's job.
BackendModule.measure_text(::HeadlessBackend, text::AbstractString, font) =
    (length(text) * 8, 16)

# Batch I/O:
# - write_to_devices logs the document for later assertion
# - read_from_devices pops the next scripted event, or nothing on drain
BackendModule.write_to_devices(b::HeadlessBackend, devices, document) =
    (push!(b.rendered, document); nothing)
BackendModule.read_from_devices(b::HeadlessBackend, devices) =
    isempty(b.events) ? nothing : popfirst!(b.events)

"""
    rendered_output(b::HeadlessBackend) -> Vector

Every document that `write_to_devices` has recorded, in order.
"""
rendered_output(b::HeadlessBackend) = b.rendered

"""
    push_event!(b::HeadlessBackend, event)

Enqueue an event so the next `read_from_devices(b, …)` returns it.
"""
push_event!(b::HeadlessBackend, event) = (push!(b.events, event); nothing)

end # module
