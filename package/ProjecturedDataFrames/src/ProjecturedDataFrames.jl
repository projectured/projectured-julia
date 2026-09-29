"""
    ProjecturedDataFrames

Opt-in package: views and edits of the native structures of DataFrames.jl. It
is a stem of its own and not a domain package, because it owns a third-party
dependency, so no other package carries DataFrames.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedDataFrames

using DataFrames

using ProjecturedCollection
using ProjecturedKernel
using ProjecturedLayout
using ProjecturedNatural
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedStyle
using ProjecturedWidget

for _src in (ProjecturedCollection, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural,
             ProjecturedPrimitive, ProjecturedProjection, ProjecturedStyle, ProjecturedWidget)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/dataframes/DataFramesModule.jl")

# A person loads this package by name, so its names are exported here.
using .DataFramesModule: DataFrameView, jump_to_row, make_data_frame_cell,
                         DataFrameViewToWidget, make_data_frame_view_projection

export DataFrameView, jump_to_row, make_data_frame_cell,
       DataFrameViewToWidget, make_data_frame_view_projection

end # module ProjecturedDataFrames
