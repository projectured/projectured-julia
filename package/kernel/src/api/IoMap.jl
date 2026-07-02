module IoMapApiModule

export IoMap, iomap_projection, iomap_input, iomap_output

"""
    IoMap

Abstract supertype for all IoMap types. Every IoMap struct (generic or
specialised) should subtype this and expose, as its minimal interface, the three
accessors [`iomap_projection`](@ref), [`iomap_input`](@ref) and
[`iomap_output`](@ref) — the correspondence an IoMap records: which
`projection` produced it, and the `input`/`output` documents it maps between.
Specialised IoMaps add further accessors (e.g. child IoMaps, coordinate tables)
on top of this minimum.
"""
abstract type IoMap end

"""
    iomap_projection(iomap) -> projection

The projection that produced `iomap`. Defaults to the conventional `projection`
field; an IoMap that stores it differently overrides this method.
"""
iomap_projection(iomap::IoMap) = getfield(iomap, :projection)

"""
    iomap_input(iomap) -> input document

The input-domain document `iomap` maps from. Defaults to the conventional
`input` field; override when an IoMap stores it differently.
"""
iomap_input(iomap::IoMap) = getfield(iomap, :input)

"""
    iomap_output(iomap) -> output document

The output-domain document `iomap` maps to. Defaults to the conventional
`output` field; override when an IoMap stores it differently.
"""
iomap_output(iomap::IoMap) = getfield(iomap, :output)

end # module
