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

It paints as a real backend paints: in the frame, it reads every part of the
document that it writes, so a cell that a part shows computes in the frame, with
the editor of the frame, and asks for a value that a task reads. A part that
throws a fault is not painted, as a backend draws what it can; the print reports
the fault.
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
    (push!(b.rendered, document); _paint_headless!(document); nothing)

# The fields of a drawn part that hold the parts below it: the windows of a screen,
# the content of a window or a viewport, a canvas, and the elements, children or
# items of a group.
const _PAINTED_FIELDS = (:windows, :content, :canvas, :elements, :children, :items)

# How many links of a list that no paint reached yet one paint reads: a list of
# rows can be endless, and a backend paints only the rows in its viewport.
const _FRESH_LINKS_PER_PAINT = 200

# Read every part of `document` once, in the order of a paint, the parts of a part
# after it in their own order, so a line of text that stands below another one
# reads after it. A list of the parts to read rather than a recursion, so a long
# list of rows needs no deep stack, and a cycle ends.
function _paint_headless!(document)
    seen = IdDict{Any,Nothing}()
    pending = Any[document]
    while !isempty(pending)
        node = popfirst!(pending)
        if node isa AbstractCell
            node = try
                node[]
            catch exception
                is_fault_exception(exception) || rethrow()
                continue
            end
        end
        (node === nothing || node isa AbstractString || node isa Symbol || isbitstype(typeof(node))) && continue
        haskey(seen, node) && continue
        seen[node] = nothing
        type = typeof(node)
        if hasfield(type, :value) && hasfield(type, :next)
            _paint_list!(pending, seen, node)
        elseif any(field -> hasfield(type, field), _PAINTED_FIELDS)
            for field in _PAINTED_FIELDS
                hasfield(type, field) && isdefined(node, field) && push!(pending, getfield(node, field))
            end
        elseif node isa AbstractVector && !(node isa AbstractRange)
            for i in eachindex(node)
                isassigned(node, i) && push!(pending, node[i])
            end
        end
    end
    nothing
end

# The values of the links of a list from `link` on: every link that a computation
# made already, and at most `_FRESH_LINKS_PER_PAINT` new ones.
function _paint_list!(pending, seen, link)
    fresh = _FRESH_LINKS_PER_PAINT
    while true
        push!(pending, getfield(link, :value))
        next = getfield(link, :next)
        if next isa AbstractCell
            if !is_cell_valid(next)
                fresh <= 0 && return nothing
                fresh -= 1
            end
            next = try
                next[]
            catch exception
                is_fault_exception(exception) || rethrow()
                return nothing
            end
        end
        (next === nothing || haskey(seen, next)) && return nothing
        seen[next] = nothing
        link = next
    end
end
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
