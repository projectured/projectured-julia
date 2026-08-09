"""
    Projectured

Umbrella package — a thin **REPL convenience**. Depends on `ProjecturedKernel` (the
headless engine) and `ProjecturedDomain` (all concrete documents/projections/backends),
and re-exports their combined public API as a single flat namespace (`using Projectured`)
plus their submodules as `Projectured.XxxModule` aliases for qualified access.

The re-exports are **generated mechanically** by the loop below — one pass over the
submodules of the two source packages — so adding a document/projection/symbol upstream
needs no edit here. The exported *set* may change freely; this is a
convenience front-door, not a curated API boundary, so it re-exports every public name
of every kernel/domain submodule.

Sources are brought in with `import` (not `using`) so this loop is the sole source of
re-exports — nothing is pulled into the flat namespace except via the pass below. There
are no name collisions between the kernel/domain submodules (verified), so the per-symbol
`using` is unambiguous.
"""
module Projectured

import ProjecturedKernel
import ProjecturedBase
import ProjecturedVisual
import ProjecturedDomain

const _SOURCES = (ProjecturedKernel, ProjecturedBase, ProjecturedVisual, ProjecturedDomain)

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
