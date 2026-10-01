# Fragment of `ApplicationModule` — the backend of a window that the caller did
# not construct, found among the loaded backends by the name of its type.
#
# A backend is a loaded subtype of `Backend`, so a package that depends on no
# backend still obtains one at run time from what the session loaded, with no
# key coined for it and no registration. The subtypes come from the walk of
# the domain slice, which needs no `InteractiveUtils`.

"""
    default_backend(prefer = (:SdlBackend, :WebBackend, :ConsoleBackend)) -> Backend

Construct a backend by reflection over the loaded `Backend` subtypes, honouring
the caller's `prefer` order. Each entry is matched against a type's own name
(`nameof(T)`), so the caller names real backend types — never a coined `:kind`
alias — and needs no dependency on the backend package. The first `prefer` entry
that is loaded wins; entries whose type is not loaded are skipped. Errors only
when none of `prefer` is present.

The call site owns the ordering: `run_example` prefers SDL, then web, then the
console. A fully-qualified name (`:"ProjecturedWeb.WebBackend"`)
is accepted too, matched against the type's qualified name, to disambiguate when
two backends share a short name.

Backend-specific construction options (SDL render knobs, web host/port) cannot
ride through reflection — pass an already-constructed backend via `backend=`
when you need them.
"""
function default_backend(prefer = (:SdlBackend, :WebBackend, :ConsoleBackend))
    loaded = DomainModule.subtypes(Backend)
    for name in prefer
        i = findfirst(loaded) do T
            nameof(T) === name || Symbol(parentmodule(T), '.', nameof(T)) === name
        end
        i === nothing || return loaded[i]()
    end
    error("default_backend: none of $(prefer) is loaded; loaded backends: " *
          join(nameof.(loaded), ", "))
end
