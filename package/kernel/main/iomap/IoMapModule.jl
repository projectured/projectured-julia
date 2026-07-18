"""
    IoMapModule

An IoMap is the record a projection's forward pass leaves behind: the
correspondence between the `input` it consumed and the `output` it produced,
which the reader and the reference mappers walk to invert the transformation.

This module declares the `IoMap` supertype and its three accessors
(`get_iomap_projection`, `get_iomap_input`, `get_iomap_output`) and provides
their default implementations and the concrete IO maps (`SimpleIoMap`,
`ChildrenIoMap`, `ContentIoMap`) plus the `@iomap` transparent-cell macro. A
projection with a strict positional contract returns a `SimpleIoMap`; one that
needs richer data (child IoMaps, coordinate tables) defines its own `IoMap`
subtype alongside its projection type.

The module lives in two fragments that share this namespace:
[`IoMapInterface.jl`](IoMapInterface.jl) declares the contract, and
[`IoMapDefaults.jl`](IoMapDefaults.jl) provides the implementations.
"""
module IoMapModule

using ..CellModule
using ..CellStructModule

export IoMap, get_iomap_projection, get_iomap_input, get_iomap_output,
       SimpleIoMap, ChildrenIoMap, ContentIoMap, @iomap

include("IoMapInterface.jl")
include("IoMapDefaults.jl")

end # module
