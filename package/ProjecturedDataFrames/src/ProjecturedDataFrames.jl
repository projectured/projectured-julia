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

include("../../../source/adapter/dataframes/DataFramesModule.jl")

# A person loads this package by name, so its names are exported here.
using .DataFramesModule: DataFrameColumnFilter, DataFrameSortKey, DataFrameQuery, DataFrameView, jump_to_row, make_data_frame_cell,
                         DataFrameColumn, RefreshDataFrameViewOperation,
                         DataFrameViewToWidget, make_data_frame_view_projection

export DataFrameColumnFilter, DataFrameSortKey, DataFrameQuery, DataFrameView, jump_to_row, make_data_frame_cell,
       DataFrameColumn, RefreshDataFrameViewOperation,
       DataFrameViewToWidget, make_data_frame_view_projection

# The display of the platform shows a frame beside the REPL, so a person who
# loads this package to look at a frame needs no other name:
# `using DataFrames, ProjecturedDataFrames, ProjecturedSDL` and
# `display_in_editor(frame)`.
export display_in_editor, close_display_editor!, refresh_display_editor!

end # module ProjecturedDataFrames
