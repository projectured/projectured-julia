# Fragment of `GraphicsModule` — `GraphicsToGraphics`, the natural projection of
# a graphics document: the document itself.
#
# A renderer that turns every document into graphics has nothing to do for one
# that is graphics already, so a `GraphicsCircle` that a person makes draws as
# the circle and not as a tree of its fields. The reader forwards an operation
# unchanged and declines a gesture: a shape answers no key and no press, and a
# gesture passed on as if it were an operation would stop the chain above it.

struct GraphicsToGraphics <: Projection end

print_document(projection::GraphicsToGraphics, recursion, input::GraphicsDocument, ctx) =
    SimpleIoMap(projection, input, input)

read_intent(::GraphicsToGraphics, iomap, payload) = payload isa Operation ? payload : nothing

map_reference_forward(::GraphicsToGraphics, iomap, reference) = reference

map_reference_backward(::GraphicsToGraphics, iomap, reference) = reference
