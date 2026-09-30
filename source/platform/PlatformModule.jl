"""
    PlatformModule

Every module of the platform, and every name that one of them exports, in one
module. The code above the platform writes `using ..PlatformModule` in place of a
`using` line for each module of the platform that it calls.

A module of the platform does not use it: each slice names each module that it
uses, so the table of the edges between the slices (`PLATFORM_SLICE_EDGES`)
reads them. An extension imports its names from the module that owns them
(PAR-QUALIFIED-EXTENSION), not from here. The export-collision guard keeps the
names unambiguous.
"""
module PlatformModule

for _n in names(parentmodule(@__MODULE__); all = true)
    isdefined(parentmodule(@__MODULE__), _n) || continue
    _m = getfield(parentmodule(@__MODULE__), _n)
    (_m isa Module && parentmodule(_m) === parentmodule(@__MODULE__) &&
     _m !== @__MODULE__) || continue
    Core.eval(@__MODULE__, Expr(:using, Expr(:., :., :., _n)))
    Core.eval(@__MODULE__, Expr(:export, _n, (s for s in names(_m) if s !== _n)...))
end

end # module PlatformModule
