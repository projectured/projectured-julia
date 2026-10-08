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

# The platform loads before DataFrames, as in a session that writes `using
# Projectured, DataFrames`. So the build meets the platform code that the
# methods of DataFrames invalidate, and the workload compiles it into this image.
using ProjecturedKernel
using ProjecturedPlatform

using DataFrames

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

# A person who names this package gets the names that most users call.
using ProjecturedPlatform.EssentialsModule
Core.eval(@__MODULE__, Expr(:export, filter(!=(:EssentialsModule), names(EssentialsModule))...))

# The first window of a data frame, with the column types that a frame has most,
# so that this image holds the code of its view.
using PrecompileTools: @setup_workload, @compile_workload
@setup_workload begin
    # More rows than a window shows, so the rows come from the lazy list.
    frame = DataFrame(n = 1:200, square = (1:200) .^ 2, ratio = (1:200) ./ 3,
                      name = string.("row ", 1:200), even = iseven.(1:200),
                      maybe = [isodd(i) ? i : missing for i in 1:200])
    @compile_workload begin
        ProjecturedPlatform.run_display_workload(frame)
    end
end

end # module ProjecturedDataFrames
