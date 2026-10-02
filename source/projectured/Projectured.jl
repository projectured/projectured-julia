const _SOURCES = (ProjecturedKernel, ProjecturedPlatform)

# A binding is re-exported when it is a submodule this source defines, or a
# submodule of a package this source reaches but the list does not name. A module
# whose parent IS in the list is skipped, so a module of the kernel that the
# platform binds is bound once. A package module itself (parent `Main`) is not a
# submodule at all.
_reexport(_src, _m) =
    parentmodule(_m) === _src ||
    (parentmodule(_m) !== Main && !(parentmodule(_m) in _SOURCES))

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && _reexport(_src, _m)) || continue
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue

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

# The ProjecturEd packages that load with the umbrella when the user installed
# them: the console and PDF backends, the domains, and the model adapters. None of
# them needs a package of another registry, and a loaded one does nothing until a
# session uses it; an adapter waits until a session asks for it by name
# (`assistant = :ollama`). The integrations with another package load in the
# extensions, when that package is loaded too.
const _INSTALLED_PACKAGES = (
    "ProjecturedConsole",
    "ProjecturedPDF",
    "ProjecturedJSON",
    "ProjecturedYAML",
    "ProjecturedXML",
    "ProjecturedMarkdown",
    "ProjecturedRST",
    "ProjecturedBook",
    "ProjecturedMath",
    "ProjecturedJulia",
    "ProjecturedSQL",
    "ProjecturedDatabase",
    "ProjecturedGraph",
    "ProjecturedChart",
    "ProjecturedSequenceChart",
    "ProjecturedDBCatalog",
    "ProjecturedFormula",
    "ProjecturedFSM",
    "ProjecturedProcess",
    "ProjecturedOllama",
    "ProjecturedAnthropic",
    "ProjecturedOpenRouter")

# Julia restores the packages of one load together, and an `__init__` inside that
# load can not load one of them again. So they load once the load is done,
# where Julia runs the extensions: in the callbacks after a package loads. The
# callback stays in the list, because Julia walks the list while it calls it, and a
# flag makes every later call return at once.
function __init__()
    loaded = Ref(false)
    push!(Base.package_callbacks, _ -> begin
        loaded[] && return nothing
        loaded[] = true
        foreach(ProjecturedPlatform.load_installed_package!, _INSTALLED_PACKAGES)
        nothing
    end)
    nothing
end
