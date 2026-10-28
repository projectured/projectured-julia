# Fragment of `PrecompileModule` — the report of a failed precompilation when
# the package loads, so that a person sees it when the session or the binary
# starts and not only in the output of a build.

"""
    report_precompile_failure!(package::Module) -> Bool

Show a warning when the precompilation of `package` failed and its preference
`precompile_failure` kept the failure. Answers whether it showed one.
"""
function report_precompile_failure!(package::Module)
    isdefined(package, :PRECOMPILE_FAILURE) || return false
    failure = getglobal(package, :PRECOMPILE_FAILURE)
    failure isa String || return false
    @warn string("The precompilation of ", nameof(package),
                 " failed, so it compiles more while it runs. ", failure)
    true
end

function _report_loaded_package_failure!(id::Base.PkgId)
    package = get(Base.loaded_modules, id, nothing)
    package === nothing || report_precompile_failure!(package)
    nothing
end

# The packages that loaded before this one, as in a binary, report now, and each
# package that loads later reports when it loads. A build shows its failures in
# its own output, so it reports nothing here.
function __init__()
    Base.generating_output() && return
    foreach(report_precompile_failure!, collect(values(Base.loaded_modules)))
    push!(Base.package_callbacks, _report_loaded_package_failure!)
    nothing
end
