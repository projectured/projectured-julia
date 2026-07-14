"""
    EnvelopeUnwrappingProjectionModule

A higher-order projection that strips the `EventEnvelope` off an input gesture
before handing it to its inner projection's reader.

The editor wraps every backend event in an `EventEnvelope` (window id + inner
event) and threads it as the `Intent.gesture`. In the SDL pipeline the
`ScreenToScreen` projection is the seam that unwraps `env.event` and re-roots
the resulting operation under the window's `content`. A pipeline that has **no**
screen/window layer — e.g. the `ConsoleBackend`'s `JsonToSyntax → SyntaxToText`
chain, whose output is a bare `TextText` rooted at the domain document — still
receives the wrapped envelope from the editor but has nothing to unwrap it.

`EnvelopeUnwrappingProjection` is that missing seam in miniature: the printer is
a transparent passthrough (its output is the inner projection's output, so the
backend renders the `TextText` directly), and the reader replaces an
`EventEnvelope` gesture with its inner `event` before delegating to the inner
reader. No reference re-rooting is needed because there is no window/content
nesting above the document.
"""
module EnvelopeUnwrappingProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..IoMapApiModule: IoMap
import ..EventModule: EventEnvelope
export EnvelopeUnwrappingProjection, EnvelopeUnwrappingProjectionIoMap

struct EnvelopeUnwrappingProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
end

"""
    EnvelopeUnwrappingProjection(inner)
    EnvelopeUnwrappingProjection(; inner)

Wrap `inner` so that an `EventEnvelope` gesture is unwrapped to its inner event
before `inner`'s reader sees it. Printing and reference mapping are transparent
passthroughs to `inner`.
"""
struct EnvelopeUnwrappingProjection <: Projection
    inner::Any
end

EnvelopeUnwrappingProjection(; inner) = EnvelopeUnwrappingProjection(inner)

function print_document(p::EnvelopeUnwrappingProjection, recursion, input, ctx)
    inner = print_document(p.inner, recursion, input, ctx)
    EnvelopeUnwrappingProjectionIoMap(p, input, inner.output, inner)
end

function read_intent(p::EnvelopeUnwrappingProjection, recursion, change::Intent, iomap::EnvelopeUnwrappingProjectionIoMap)
    env = change.gesture
    inner_change = env isa EventEnvelope ? Intent(env.event, change.operation) : change
    out = read_intent(p.inner, recursion, inner_change, iomap.inner_iomap)
    # Preserve the original (still-wrapped) gesture in the returned change so any
    # outer layer continues to see the envelope it sent.
    return Intent(change.gesture, out.operation)
end

read_intent(p::EnvelopeUnwrappingProjection, iomap::EnvelopeUnwrappingProjectionIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

map_reference_forward(p::EnvelopeUnwrappingProjection, iomap::EnvelopeUnwrappingProjectionIoMap, reference) =
    map_reference_forward(p.inner, iomap.inner_iomap, reference)

map_reference_backward(p::EnvelopeUnwrappingProjection, iomap::EnvelopeUnwrappingProjectionIoMap, reference) =
    map_reference_backward(p.inner, iomap.inner_iomap, reference)

end # module
