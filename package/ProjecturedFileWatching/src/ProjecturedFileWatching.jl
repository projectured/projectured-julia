"""
    ProjecturedFileWatching

The file watching adapter, a package of its own because it needs the standard
library FileWatching. When it loads, the store of the watched files of the
platform takes the notifications of the system for each folder, in place of a
poll. `using ProjecturedFileWatching` gives `start_folder_monitor!`; the slice is
`FileWatchingModule`, in `source/adapter/filewatching/`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself.
"""
module ProjecturedFileWatching

using ProjecturedPlatform

for _src in (ProjecturedPlatform,)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/adapter/filewatching/FileWatchingModule.jl")

# A person loads this package by name, so its names are exported here.
using .FileWatchingModule: start_folder_monitor!
export start_folder_monitor!

end # module ProjecturedFileWatching
