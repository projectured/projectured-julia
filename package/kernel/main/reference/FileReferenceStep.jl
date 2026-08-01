# Fragment of `ReferenceModule` — the `FileReferenceStep`: a cross-file
# reference step that names an external file by relative path. The first
# step of a cross-file reference chain (`file("model/Aloha.ned").a.b.c`).
#
# Registered as `:structural` and hooked into the `@reference` DSL as the
# `.file(path)` / leading `file(path)` extension. Evaluation is delegated
# to whatever `FileProject` driver is loaded — the reference layer does
# not know how to open a file. Until a driver overrides
# `evaluate_reference_step(::FileReferenceStep, …)`, the default
# implementation errors with a message pointing at the driver, so a stray
# cross-file reference in an editor that hasn't wired a project fails
# loudly at the walk point.

"""
    FileReferenceStep(path::AbstractString)

A reference step that names an external file by a POSIX-style relative
`path`. Intended to appear at the head of a cross-file reference chain,
e.g. `@reference file("model/Aloha.ned").networks.Aloha`. Evaluation is
delegated to the running `FileProject` driver; a bare walk without one
errors with a message naming the driver.
"""
@cell_struct struct FileReferenceStep <: ReferenceStep
    path::String
end

Base.show(io::IO, s::FileReferenceStep) = print(io, ".file(", repr(s.path), ")")

Base.:(==)(a::FileReferenceStep, b::FileReferenceStep) = a.path == b.path

get_reference_step_kind(::FileReferenceStep) = :structural

evaluate_reference_step(::FileReferenceStep, ::Any) =
    error("FileReferenceStep: cross-file navigation requires a FileProject driver — no default resolver is registered")

# ── DSL registrations ────────────────────────────────────────────────────

# `.file(path)` — argument 1 is an ordinary value expression (the path
# string). Nothing subpath-shaped, so the default `get_reference_step_subpath_args`
# answer of `()` is right.

build_reference_step(::Val{:file}, pathex) =
    :($(GlobalRef(@__MODULE__, :FileReferenceStep))(String($pathex)))

function match_reference_step(::Val{:file}, hex, argpats, rest_success, bound,
                              gen_value_match, gen_path_match)
    pathpat = argpats[1]
    pathexpr = :($hex.path)
    after_path, bound1 = gen_value_match(pathexpr, pathpat, rest_success, bound)
    ex = quote
        if $hex isa $(GlobalRef(@__MODULE__, :FileReferenceStep))
            $after_path
        else
            _nomatch
        end
    end
    return ex, bound1
end
