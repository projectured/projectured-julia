"""
    DefaultBackendModule

Reflection-based backend selection. `default_backend` picks a loaded concrete
`Backend` subtype **by its own type name** and constructs it — no coined symbol
key and no per-backend registration (unlike a `make_backend(::Val{kind})`
factory, a backend just needs to be a loaded subtype). This lets a package that
does not depend on a backend (e.g. the domain examples, which never name
`SdlBackend`) still obtain one at runtime from whatever the session loaded.

Lives in the example package because its only two callers are the gallery and
the file-editor harness, and because it needs `InteractiveUtils.subtypes`,
which no package of the substrate would otherwise carry.
"""
module DefaultBackendModule

import InteractiveUtils: subtypes
using ..BackendModule

export default_backend

"""
    default_backend(prefer = (:SdlBackend, :WebBackend, :ConsoleBackend)) -> Backend

Construct a backend by reflection over the loaded `Backend` subtypes, honouring
the caller's `prefer` order. Each entry is matched against a type's own name
(`nameof(T)`), so the caller names real backend types — never a coined `:kind`
alias — and needs no dependency on the backend package. The first `prefer` entry
that is loaded wins; entries whose type is not loaded are skipped. Errors only
when none of `prefer` is present.

The call site owns the ordering: `run_example` prefers SDL, then web, then the
always-present console. A fully-qualified name (`:"ProjecturedWeb.WebBackend"`)
is accepted too, matched against the type's qualified name, to disambiguate when
two backends share a short name.

Backend-specific construction options (SDL render knobs, web host/port) cannot
ride through reflection — pass an already-constructed backend via `backend=`
when you need them.
"""
function default_backend(prefer = (:SdlBackend, :WebBackend, :ConsoleBackend))
    loaded = subtypes(Backend)
    for name in prefer
        i = findfirst(loaded) do T
            nameof(T) === name || Symbol(parentmodule(T), '.', nameof(T)) === name
        end
        i === nothing || return loaded[i]()
    end
    error("default_backend: none of $(prefer) is loaded; loaded backends: " *
          join(nameof.(loaded), ", "))
end

end
