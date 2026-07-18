# Fragment of `IoMapModule` — the IoMap **contract**: the `IoMap` abstract
# supertype and the three accessors every IoMap exposes. The default
# implementations and the concrete IO maps live in `IoMapDefaults.jl`.

"""
    IoMap

Abstract supertype for all IoMap types. Every IoMap subtypes this and exposes the
three accessors [`get_iomap_projection`](@ref), [`get_iomap_input`](@ref) and
[`get_iomap_output`](@ref) — which `projection` produced it and the
`input`/`output` documents it maps between. Specialised IoMaps add further
accessors (child IoMaps, coordinate tables) on top of this minimum.
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
    get_iomap_output(iomap) -> output document

The output-domain document `iomap` maps to. Answered from the conventional
`output` field; override when an IoMap stores it differently.
"""
function get_iomap_output end
