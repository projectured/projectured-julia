# Fragment of `ProjectionAlgebraModule`.
#
# A higher-order projection that strips the `WindowInput` off an input gesture
# before handing it to its inner projection's reader.
#
# The editor wraps every backend event in an `WindowInput` (window id + inner
# event) and threads it as the `Intent.gesture`. In the SDL pipeline the
# `ScreenToScreen` projection is the seam that unwraps `window_input.event` and re-roots
# the resulting operation under the window's `content`. A pipeline that has **no**
# screen/window layer — e.g. the `ConsoleBackend`'s `JsonToSyntax → SyntaxToText`
# chain, whose output is a bare `TextBlock` rooted at the domain document — still
# receives the wrapped window input from the editor but has nothing to unwrap it.
#
# `WindowInputUnwrappingProjection` is that missing seam in miniature: the printer is
# a transparent passthrough (its output is the inner projection's output, so the
# backend renders the `TextBlock` directly), and the reader replaces an
# `WindowInput` gesture with its inner `event` before delegating to the inner
# reader. No reference re-rooting is needed because there is no window/content
# nesting above the document.
# Transparent passthrough: `output` forwards the inner output through a cell so the
# IoMap keeps its identity while `inner` re-derives (PAR-STABLE-IOMAP-IDENTITY).
@iomap struct WindowInputUnwrappingIoMap
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
    WindowInputUnwrappingIoMap(p, input, ComputedCell(() -> inner.output), inner)
end

function read_intent(p::WindowInputUnwrappingProjection, recursion, change::Intent, iomap::WindowInputUnwrappingIoMap)
    window_input = change.gesture
    inner_change = window_input isa WindowInput ? Intent(window_input.event, change.operation) : change
    out = read_intent(p.inner, recursion, inner_change, iomap.inner_iomap)
    # Preserve the original (still-wrapped) gesture in the returned change so any
    # outer layer continues to see the window input it sent.
    return Intent(change.gesture, out.operation)
end

read_intent(p::WindowInputUnwrappingProjection, iomap::WindowInputUnwrappingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

map_reference_forward(p::WindowInputUnwrappingProjection, iomap::WindowInputUnwrappingIoMap, reference) =
    map_reference_forward(p.inner, iomap.inner_iomap, reference)

map_reference_backward(p::WindowInputUnwrappingProjection, iomap::WindowInputUnwrappingIoMap, reference) =
    map_reference_backward(p.inner, iomap.inner_iomap, reference)
