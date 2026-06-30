# ═══════════════════════════════════════════════════════════════════════════
# example/src/FileEditor.jl
#
# A configurable, file-backed single editor — as opposed to the `run_example`
# demo gallery. An `EditorDomain` bundles, per content domain, the pieces a
# standalone editor needs: how to make an empty document, how to project it, and
# how to load/save it from/to a file. `run_file_editor` (added in a later phase)
# wires a chosen domain + a file path into a single window and runs the loop.
#
# This is the library half of the configurable executable builder: keeping the
# real logic here (not in the `executable` package) makes it REPL-testable
# without the multi-minute `create_app` build.
# ═══════════════════════════════════════════════════════════════════════════

"""
    EditorDomain(name; make_empty_document, make_projection, load_file=nothing, save_file=nothing)

The per-domain pieces a standalone file editor needs:

- `make_empty_document() -> Document` — the scratch document used when no file is
  given (or the file does not exist yet).
- `make_projection() -> Projection` — the domain's editor projection.
- `load_file(path) -> Document` — parse a file into a document. `nothing` when the
  domain has no file loader.
- `save_file(document, path) -> nothing` — serialize a document back to a file.
  `nothing` when saving is not (yet) available for the domain.

`load_file`/`save_file` are `Union{Function,Nothing}` so a domain can be
load-only (or not file-backed at all) without a separate type. v1 leaves
`:json`'s `save_file` as `nothing`; a serializer can be dropped in later without
changing anything here.
"""
struct EditorDomain
    name::Symbol
    make_empty_document::Function
    make_projection::Function
    load_file::Union{Function,Nothing}
    save_file::Union{Function,Nothing}
end

EditorDomain(name::Symbol; make_empty_document, make_projection,
             load_file=nothing, save_file=nothing) =
    EditorDomain(name, make_empty_document, make_projection, load_file, save_file)

"""
    EDITOR_DOMAINS :: Dict{Symbol,EditorDomain}

Registry of editor domains keyed by symbol, so the builder/launcher are
data-driven rather than a `if domain == …` ladder. v1 registers `:json` (load via
the existing `jsonparse_file`; `save_file = nothing`). Add `:xml`/`:text`/… here
as their loaders/savers land.
"""
const EDITOR_DOMAINS = Dict{Symbol,EditorDomain}(
    :json => EditorDomain(:json;
        make_empty_document = () -> JsonInsertion(),
        make_projection     = make_json_projection_example,
        load_file           = jsonparse_file,
        save_file           = nothing),
)

"""
    editor_domain(name::Symbol) -> EditorDomain

Look up a registered editor domain, erroring with the list of available domains
when `name` is unknown.
"""
function editor_domain(name::Symbol)
    haskey(EDITOR_DOMAINS, name) ||
        error("Unknown editor domain :$name. Available: " *
              join(sort!(string.(collect(keys(EDITOR_DOMAINS)))), ", "))
    EDITOR_DOMAINS[name]
end
