"""
    ProjecturedConsole

The console backend. It renders the text domain to an ANSI terminal and needs
no third-party package, so the umbrella still aggregates it. It is a peer of
`ProjecturedSDL`, `ProjecturedWeb` and `ProjecturedPDF`, which is what a
concrete backend is.

The loop below binds every submodule of the kernel and the platform as a
`const`, so a source file here names a module exactly as the module names
itself.
"""
module ProjecturedConsole

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

include("../../../source/backend/console/ConsoleModule.jl")

# A person loads this package by name, so its names are exported here.
using .ConsoleModule: ConsoleBackend, render_console
export ConsoleBackend, render_console

# A person who names this package gets the names that most users call.
using ProjecturedEssentials
Core.eval(@__MODULE__, Expr(:export, filter(!=(:ProjecturedEssentials),
                                            names(ProjecturedEssentials))...))

end # module ProjecturedConsole
