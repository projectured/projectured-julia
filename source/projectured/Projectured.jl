const _SOURCES = (ProjecturedKernel,
                  ProjecturedCollection, ProjecturedPrimitive, ProjecturedDomain,
                  ProjecturedSerialization, ProjecturedStyle, ProjecturedComponent,
                  ProjecturedProjection, ProjecturedReflection, ProjecturedDragging,
                  ProjecturedFocus, ProjecturedVersioning, ProjecturedPlot,
                  ProjecturedGraphics, ProjecturedScreen, ProjecturedLayout,
                  ProjecturedText, ProjecturedWidget, ProjecturedSyntax,
                  ProjecturedPane, ProjecturedClipboard, ProjecturedTooltip,
                  ProjecturedInspector, ProjecturedGestureHelp, ProjecturedGestureLog,
                  ProjecturedFault,
                  ProjecturedLog, ProjecturedShell,
                  ProjecturedFileFormat, ProjecturedNatural, ProjecturedConsole,
                  ProjecturedPdf,
                  ProjecturedJson, ProjecturedYaml, ProjecturedXml,
                  ProjecturedMarkdown, ProjecturedRst, ProjecturedBook,
                  ProjecturedMath, ProjecturedJulia, ProjecturedSql,
                  ProjecturedDatabase, ProjecturedFileSystem, ProjecturedGraph,
                  ProjecturedChart, ProjecturedSequenceChart,
                  ProjecturedDbCatalog, ProjecturedFormula, ProjecturedFsm,
                  ProjecturedProcess, ProjecturedConversation,
                  ProjecturedAssistant, ProjecturedUndo)

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
