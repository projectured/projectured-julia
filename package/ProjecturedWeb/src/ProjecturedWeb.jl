"""
    ProjecturedWeb

The web backend, a package of its own because it needs HTTP and JSON3.
`using ProjecturedWeb` gives `WebBackend`; the slice is `WebModule`, in
`source/backend/web/`.

The loop below binds every submodule of the kernel and the platform as a
`const`, so a source file here names a module exactly as the module names
itself.
"""
module ProjecturedWeb

using ProjecturedKernel
using ProjecturedPlatform

for _src in (ProjecturedKernel, ProjecturedPlatform)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/backend/web/WebModule.jl")

# A person loads this package by name, so its names are exported here.
using .WebModule: WebBackend, get_web_asset_directory, convert_web_key_to_symbol
export WebBackend, get_web_asset_directory, convert_web_key_to_symbol

end # module ProjecturedWeb
