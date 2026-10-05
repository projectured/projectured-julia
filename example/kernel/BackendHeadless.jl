# Fragment of `ProjecturedKernelExample` — the in-memory `HeadlessBackend`: a
# dependency-free `BackendModule.Backend` that logs rendered documents and sources
# scripted events. A test double for the backend seam; it lives in the example
# package (never in `main`) so no double reaches a production build. Useful for
# offline development, the editor-loop tests (no SDL needed), and the
# "load and step the editor once" documentation snippet.

"""
    HeadlessBackend(; system_colors = nothing)

A dependency-free backend with a rendered-document log, a scripted event queue,
and a scripted answer of `find_system_colors`: `system_colors`, a `SystemColors`
or `nothing`.
"""
mutable struct HeadlessBackend <: Backend
    rendered::Vector{Any}
    events::Vector{Any}
    system_colors::Union{Nothing,SystemColors}
    HeadlessBackend(; system_colors::Union{Nothing,SystemColors} = nothing) =
        new(Any[], Any[], system_colors)
end

# Lifecycle: both are no-ops; there is no external state to init or release.
BackendModule.initialize_backend!(::HeadlessBackend) = nothing
BackendModule.quit_backend!(::HeadlessBackend) = nothing

# Batch I/O:
# - write_to_devices! logs the document for later assertion
# - take_from_devices! pops the next scripted event, or nothing on drain
BackendModule.write_to_devices!(b::HeadlessBackend, devices, document) =
    (push!(b.rendered, document); nothing)
BackendModule.take_from_devices!(b::HeadlessBackend, devices) =
    isempty(b.events) ? nothing : popfirst!(b.events)

# The colour settings of the system are the scripted answer.
BackendModule.find_system_colors(b::HeadlessBackend) = b.system_colors

"""
    rendered_output(b::HeadlessBackend) -> Vector

Every document that `write_to_devices!` has recorded, in order.
"""
rendered_output(b::HeadlessBackend) = b.rendered

"""
    push_event!(b::HeadlessBackend, event)

Enqueue an event so the next `take_from_devices!(b, …)` returns it.
"""
push_event!(b::HeadlessBackend, event) = (push!(b.events, event); nothing)
