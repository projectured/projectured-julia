"""
    ProjecturedLanguageServer

The language server adapter, a package of its own because it needs JSON3. It
starts a language server, such as `clangd`, for each editor, and gives the
names of a source file the colours of their kinds. The slice is
`LanguageServerModule`, in `source/adapter/languageserver/`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself.
"""
module ProjecturedLanguageServer

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

include("../../../source/adapter/languageserver/LanguageServerModule.jl")

# A person loads this package by name, so its names are exported here.
using .LanguageServerModule
for _n in names(LanguageServerModule)
    _n === :LanguageServerModule || Core.eval(@__MODULE__, Expr(:export, _n))
end

# The view of a source file is a natural row, which every first window of the
# display builds.
using PrecompileTools: @compile_workload
@compile_workload run_natural_rows_workload(LanguageServerModule)

end # module ProjecturedLanguageServer
