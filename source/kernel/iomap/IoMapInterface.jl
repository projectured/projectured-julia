# Fragment of `IoMapModule` — the IoMap **contract**: the `IoMap` abstract
# supertype and the three accessors every IoMap exposes. The default
# implementations and the concrete IO maps live in `IoMapDefaults.jl`.

"""
    IoMap

What a projection made, and what it made it from: the record that maps an edit
on the output back to the input.

Use it to hold the result of showing a document. It carries the projection, the
document that went in, and what came out, so a later click on the output can be
carried back to the place in the input that it belongs to. Every printer
returns one.

# Example

    iomap = print_document(projection, projection, document, PrinterContext())
    get_iomap_output(iomap)          # what is shown
    get_iomap_input(iomap)           # what it was made from

See also `print_document`, `read_intent`, and the guide
`kernel/projection-system`.

Abstract supertype for all IoMap types. Every IoMap subtypes this and exposes the
three accessors [`get_iomap_projection`](@ref), [`get_iomap_input`](@ref) and
[`get_iomap_output`](@ref) — which `projection` produced it and the
`input`/`output` it maps between. Specialised IoMaps add further accessors (child
IoMaps, coordinate tables) on top of this minimum.
"""
abstract type IoMap end

"""
    get_iomap_projection(iomap) -> projection

The projection that produced `iomap`. Answered from the conventional `projection`
field; an IoMap that stores it differently overrides this.
"""
function get_iomap_projection end

"""
    get_iomap_input(iomap) -> input document

The input-domain document `iomap` maps from. Answered from the conventional
`input` field; override when an IoMap stores it differently.
"""
function get_iomap_input end

"""
    get_iomap_output(iomap) -> output

What a projection made: the document as it is shown.

Use it to take the result of a print, to draw it, to measure it, or to hand it
to the next projection of a chain.

# Example

    drawn = get_iomap_output(print_document(projection, projection, document, context))

See also `get_iomap_input`, for what it was made from, and `IoMap`.

The output-domain value `iomap` maps to — usually a `Document`, but a terminal
projection may map to a plain value (e.g. a string). Answered from the conventional
`output` field; override when an IoMap stores it differently.
"""
function get_iomap_output end
