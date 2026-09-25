"""
    ProjecturedFileSystem

The file-system domain.

The file and directory documents, read from a real path, and their two
projections: a syntax tree and a widget tree. The workspace — one or more
named folder roots, and the tool view a person opens by typing `explorer` —
is here too: it is the file system's own document, not a consumer's.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedFileSystem

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedFileFormat
using ProjecturedFocus
using ProjecturedKernel
using ProjecturedNatural
using ProjecturedPane
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedSerialization
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText
using ProjecturedWidget

for _src in (ProjecturedCollection, ProjecturedDomain, ProjecturedFileFormat, ProjecturedFocus, ProjecturedKernel, ProjecturedNatural, ProjecturedPane, ProjecturedPrimitive, ProjecturedProjection, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedWidget)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/filesystem/FileSystemModule.jl")

end # module ProjecturedFileSystem
