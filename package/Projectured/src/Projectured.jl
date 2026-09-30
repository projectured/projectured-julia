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
import ProjecturedPlatform
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
import ProjecturedGraph
import ProjecturedChart
import ProjecturedSequenceChart
import ProjecturedDbCatalog
import ProjecturedFormula
import ProjecturedFsm
import ProjecturedProcess

include("../../../source/projectured/Projectured.jl")

end # module Projectured
