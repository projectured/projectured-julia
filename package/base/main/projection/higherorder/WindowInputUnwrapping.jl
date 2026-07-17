"""
    WindowInputUnwrappingProjectionModule

A higher-order projection that strips the `WindowInput` off an input gesture
before handing it to its inner projection's reader.

The editor wraps every backend event in an `WindowInput` (window id + inner
event) and threads it as the `Intent.gesture`. In the SDL pipeline the
`ScreenToScreen` projection is the seam that unwraps `env.event` and re-roots
the resulting operation under the window's `content`. A pipeline that has **no**
screen/window layer — e.g. the `ConsoleBackend`'s `JsonToSyntax → SyntaxToText`
chain, whose output is a bare `TextBlock` rooted at the domain document — still
receives the wrapped envelope from the editor but has nothing to unwrap it.

`WindowInputUnwrappingProjection` is that missing seam in miniature: the printer is
a transparent passthrough (its output is the inner projection's output, so the
backend renders the `TextBlock` directly), and the reader replaces an
`WindowInput` gesture with its inner `event` before delegating to the inner
reader. No reference re-rooting is needed because there is no window/content
nesting above the document.
"""
module WindowInputUnwrappingProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..IoMapApiModule: IoMap
import ..EventModule: WindowInput
export WindowInputUnwrappingProjection, WindowInputUnwrappingProjectionIoMap

struct WindowInputUnwrappingProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
end

"""
    WindowInputUnwrappingProjection(inner)
    WindowInputUnwrappingProjection(; inner)

Wrap `inner` so that an `WindowInput` gesture is unwrapped to its inner event
before `inner`'s reader sees it. Printing and reference mapping are transparent
passthroughs to `inner`.
"""
struct WindowInputUnwrappingProjection <: Projection
    inner::Any
end

WindowInputUnwrappingProjection(; inner) = WindowInputUnwrappingProjection(inner)

function print_document(p::WindowInputUnwrappingProjection, recursion, input, ctx)
    inner = print_document(p.inner, recursion, input, ctx)
    WindowInputUnwrappingProjectionIoMap(p, input, inner.output, inner)
end

function read_intent(p::WindowInputUnwrappingProjection, recursion, change::Intent, iomap::WindowInputUnwrappingProjectionIoMap)
    env = change.gesture
    inner_change = env isa WindowInput ? Intent(env.event, change.operation) : change
    out = read_intent(p.inner, recursion, inner_change, iomap.inner_iomap)
    # Preserve the original (still-wrapped) gesture in the returned change so any
    # outer layer continues to see the envelope it sent.
    return Intent(change.gesture, out.operation)
end

read_intent(p::WindowInputUnwrappingProjection, iomap::WindowInputUnwrappingProjectionIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

map_reference_forward(p::WindowInputUnwrappingProjection, iomap::WindowInputUnwrappingProjectionIoMap, reference) =
    map_reference_forward(p.inner, iomap.inner_iomap, reference)

map_reference_backward(p::WindowInputUnwrappingProjection, iomap::WindowInputUnwrappingProjectionIoMap, reference) =
    map_reference_backward(p.inner, iomap.inner_iomap, reference)

end # module
