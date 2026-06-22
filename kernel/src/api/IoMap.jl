module IoMapApiModule

export IoMap

"""
    IoMap

Abstract supertype for all IoMap types. Every IoMap struct (generic or
specialised) should subtype this. The convention is that all IoMap structs
have `projection`, `input`, and `output` fields.
"""
abstract type IoMap end

end # module
