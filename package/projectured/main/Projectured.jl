"""
    Projectured

Umbrella package — a thin **REPL convenience**. It depends on the kernel, on
the twenty-eight packages of the substrate and on every concrete domain, and
re-exports their combined public API as
a single flat namespace (`using Projectured`) plus their submodules as
`Projectured.XxxModule` aliases for qualified access.

The re-exports are **generated mechanically** by the loop below — one pass over the
submodules of every source package — so adding a document, a projection or a symbol
upstream needs no edit here. The exported *set* may change freely; this is a
convenience front-door, not a curated API boundary, so it re-exports every public name
of every submodule.

Adding a **new package** does need an edit here: put it in the `import` list and
in `_SOURCES`. That is the only place the full set is written down.

Sources are brought in with `import` (not `using`) so this loop is the sole source of
re-exports — nothing is pulled into the flat namespace except via the pass below. There
are no name collisions between the submodules (verified by
`ProjecturedTest.test_export_collisions`), so the per-symbol `using` is unambiguous.
"""
module Projectured

import ProjecturedKernel
import ProjecturedCollection
import ProjecturedPrimitive
import ProjecturedDomain
import ProjecturedSerialization
import ProjecturedStyle
import ProjecturedComponent
import ProjecturedProjection
import ProjecturedReflection
import ProjecturedDragging
import ProjecturedFocus
import ProjecturedVersioning
import ProjecturedPlot
import ProjecturedGraphics
import ProjecturedScreen
import ProjecturedLayout
import ProjecturedText
import ProjecturedWidget
import ProjecturedSyntax
import ProjecturedPane
import ProjecturedClipboard
import ProjecturedTooltip
import ProjecturedInspector
import ProjecturedGestureHelp
import ProjecturedGestureLog
import ProjecturedFileFormat
import ProjecturedNaturalProjection
import ProjecturedConsole
import ProjecturedPdf

# The concrete domains, in dependency order: the ones that need no other domain,
# then the ones that build on them, then the application on top.
import ProjecturedJson
import ProjecturedYaml
import ProjecturedXml
import ProjecturedMarkdown
import ProjecturedRst
import ProjecturedBook
import ProjecturedMath
import ProjecturedJulia
import ProjecturedSql
import ProjecturedDatabase
import ProjecturedFileSystem
import ProjecturedGraph
import ProjecturedChart
import ProjecturedSequenceChart
import ProjecturedDbCatalog
import ProjecturedFormula
import ProjecturedFsm
import ProjecturedProcess
import ProjecturedConversation
import ProjecturedAssistant
import ProjecturedWorkbench

const _SOURCES = (ProjecturedKernel,
                  ProjecturedCollection, ProjecturedPrimitive, ProjecturedDomain,
                  ProjecturedSerialization, ProjecturedStyle, ProjecturedComponent,
                  ProjecturedProjection, ProjecturedReflection, ProjecturedDragging,
                  ProjecturedFocus, ProjecturedVersioning, ProjecturedPlot,
                  ProjecturedGraphics, ProjecturedScreen, ProjecturedLayout,
                  ProjecturedText, ProjecturedWidget, ProjecturedSyntax,
                  ProjecturedPane, ProjecturedClipboard, ProjecturedTooltip,
                  ProjecturedInspector, ProjecturedGestureHelp, ProjecturedGestureLog,
                  ProjecturedFileFormat, ProjecturedNaturalProjection, ProjecturedConsole,
                  ProjecturedPdf,
                  ProjecturedJson, ProjecturedYaml, ProjecturedXml,
                  ProjecturedMarkdown, ProjecturedRst, ProjecturedBook,
                  ProjecturedMath, ProjecturedJulia, ProjecturedSql,
                  ProjecturedDatabase, ProjecturedFileSystem, ProjecturedGraph,
                  ProjecturedChart, ProjecturedSequenceChart,
                  ProjecturedDbCatalog, ProjecturedFormula, ProjecturedFsm,
                  ProjecturedProcess, ProjecturedConversation,
                  ProjecturedAssistant, ProjecturedWorkbench)

# A binding is re-exported when it is a submodule this source defines, or a
# submodule of a package this source reaches but the list does not name. The
# second case is a concrete domain that already left `ProjecturedDomain` for its
# own package: `ProjecturedDomain` binds it, so it arrives here through that
# binding and is bound exactly once. A module whose parent IS in the list is
# skipped, so a kernel module aliased in visual and domain is not bound three
# times. A package module itself (parent `Main`) is not a submodule at all.
_reexport(_src, _m) =
    parentmodule(_m) === _src ||
    (parentmodule(_m) !== Main && !(parentmodule(_m) in _SOURCES))

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && _reexport(_src, _m)) || continue

        # 1) alias the submodule so `Projectured.XxxModule.foo` keeps resolving
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))

        # 2) re-export its exported names into the flat `Projectured` namespace
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
        Core.eval(@__MODULE__, Expr(:export, _syms...))
    end
end

end # module Projectured
