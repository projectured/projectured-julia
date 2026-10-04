# ═══════════════════════════════════════════════════════════════════════════
# example/FileEditor.jl
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
data-driven rather than a `if domain == …` ladder. Every domain loads and saves
through the format-by-extension helpers (`read_document_file` /
`write_document_file`): a matching-extension file round-trips through the domain
parser/printer, a `.pdoc` file through the binary snapshot, and a non-existent
file opens as the extension's insertion seed. `make_empty_document` is the
scratch document used when no file is given.
"""
const EDITOR_DOMAINS = Dict{Symbol,EditorDomain}(
    :json => EditorDomain(:json;
        make_empty_document = () -> JsonInsertion(),
        make_projection     = make_json_projection_example,
        load_file           = read_document_file,
        save_file           = write_document_file),
    :xml => EditorDomain(:xml;
        make_empty_document = () -> XmlInsertion(),
        make_projection     = make_xml_projection_example,
        load_file           = read_document_file,
        save_file           = write_document_file),
    :sql => EditorDomain(:sql;
        make_empty_document = () -> SqlInsertion(),
        make_projection     = make_sql_syntax_projection_example,
        load_file           = read_document_file,
        save_file           = write_document_file),
    :julia => EditorDomain(:julia;
        make_empty_document = () -> JuliaInsertion(),
        make_projection     = make_julia_projection_example,
        load_file           = read_document_file,
        save_file           = write_document_file),
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

"""
    EXTENSION_DOMAINS :: Dict{String,Symbol}

Maps a file extension (lowercased, with the dot) to the editor domain that opens
it — the runtime seam that lets *one* executable edit several file kinds by looking
at the argument's extension. Mirrors the extension set `read_document_file`
understands (see `FileFormatModule`).
"""
const EXTENSION_DOMAINS = Dict{String,Symbol}(
    ".json" => :json,
    ".xml"  => :xml,
    ".sql"  => :sql,
    ".jl"   => :julia,
)

"""
    domain_for_path(path; default::Symbol, allowed=keys(EDITOR_DOMAINS)) -> Symbol

Pick the editor domain for `path` from its file extension (via
[`EXTENSION_DOMAINS`](@ref)), restricted to `allowed`. Falls back to `default` when
the extension is unknown/absent or maps to a domain not in `allowed` — so a
multi-domain binary opens `foo.xml` as XML, `foo.jl` as Julia, etc., and anything
else as its default domain.
"""
function domain_for_path(path; default::Symbol, allowed=keys(EDITOR_DOMAINS))
    d = get(EXTENSION_DOMAINS, lowercase(splitext(String(path))[2]), default)
    d in allowed ? d : default
end

"""
    build_file_editor(domain::Symbol; file=nothing) -> (document, projection, name)

Assemble the `(document, projection, window-name)` triple a file editor runs,
*without* opening a window — the testable core of [`run_file_editor`](@ref).

- `document`: the domain's `load_file(file)` when `file` is given and exists,
  otherwise `make_empty_document()` (a scratch document).
- `projection`: the domain's `make_projection()`.
- `name`: the window id/title — the file's basename, or the domain name when no
  file is given.
"""
function build_file_editor(domain::Symbol; file=nothing)
    dom = editor_domain(domain)
    document = if file !== nothing && isfile(file)
        dom.load_file === nothing &&
            error("editor domain :$domain has no file loader (cannot open $(file))")
        dom.load_file(file)
    else
        dom.make_empty_document()
    end
    projection = dom.make_projection()
    name = file !== nothing ? basename(String(file)) : string(domain)
    (document, projection, name)
end

"""
    run_file_editor(domain::Symbol; file=nothing, backend=nothing,
                    width=nothing, height=nothing, mcp=false)

Open a single editor window for `domain` (a key in [`EDITOR_DOMAINS`](@ref)) and
run the editor loop until the window is closed.

`file` is loaded via the domain's `load_file` when it exists; otherwise the editor
starts on a scratch document (`make_empty_document`). The backend defaults to
SDL; pass a `backend` to override (e.g. the web backend), and `width`/`height`
to fix the window size (defaults to the display size). `mcp=true` starts an MCP
server alongside the loop.

Saving is out of scope in v1 (the domain's `save_file` is `nothing`), so this
opens and edits a file but does not write it back.
"""
function run_file_editor(domain::Symbol; file=nothing,
                         backend=nothing, width=nothing, height=nothing, mcp::Bool=false)
    document, projection, name = build_file_editor(domain; file=file)
    backend === nothing && (backend = default_backend())
    if width === nothing || height === nothing
        sw, sh = get_display_size(backend)
        width  = something(width,  sw)
        height = something(height, sh)
    end
    _run_window_scene(Any[document], Any[projection], String[name];
                      width=width, height=height, backend=backend,
                      compose=(p, b) -> _multi_window_projection(p), mcp=mcp)
end

# ── Headless warm-up (for PackageCompiler / TTFX) ────────────────────────────

# A spread of synthetic input events that exercises the reader → operation →
# reprint machinery: seed the first caret (Ctrl+Home), navigate, type a couple of
# characters, and delete. Events that don't apply to a given domain still warm the
# reader pipeline (the reader runs regardless of whether it yields an operation).
const _WARMUP_EVENTS = Any[
    KeyDown(:home,  ModifierKeys(ctrl = true); time = time()),   # seed the first caret
    KeyDown(:right, ModifierKeys(); time = time()),
    KeyDown(:left,  ModifierKeys(); time = time()),
    KeyDown(:down,  ModifierKeys(); time = time()),
    KeyDown(:up,    ModifierKeys(); time = time()),
    KeyDown(:end,   ModifierKeys(ctrl = true); time = time()),
    KeyPress('x'; time = time()),                             # insert a character
    KeyPress('1'; time = time()),
    KeyDown(:backspace, ModifierKeys(); time = time()),
    KeyDown(:delete,    ModifierKeys(); time = time()),
]

"""
    warm_file_editor(domain::Symbol) -> nothing

Headlessly drive the **exact windowed editor pipeline** [`run_file_editor`](@ref)
runs — the composed multi-window projection over a `ScreenDocument` — through one
print and a spread of synthetic input events (navigation, typing, deletion),
*without opening a window*.

This exists to warm the read → evaluate → reprint code paths for PackageCompiler,
so the first real keystroke of the built binary doesn't pay first-call JIT (the
offscreen `write_image` warm-up only covers the initial paint, not interaction).
The reader/evaluator are backend-independent, so this is worth running for any
baked backend.

Never throws: any hiccup is logged and swallowed, so a warm-up miss can't fail the
build.
"""
function warm_file_editor(domain::Symbol)
    try
        document, projection, name = build_file_editor(domain)
        # The same scene + composed projection `run_file_editor` uses, at a fixed
        # size so no display probe is needed.
        screen    = _build_window_scene(Any[document], String[name]; width = 800, height = 600)
        composed  = _multi_window_projection(Any[projection])
        window_id = Symbol(name)
        # A real `Editor`, but never `initialize_backend!`ed: we drive read/eval/print by hand and
        # skip `write_to_devices!`, so no window opens. The backend is only a field
        # here — `evaluate_operation` dispatches on the operation, not the backend —
        # so the window-free console backend is enough.
        editor = Editor(screen, composed; backend = ConsoleBackend(),
                        devices = Device[Display(), Keyboard(), Mouse()])
        editor.iomap = print_document(composed, screen)
        evaluate_reachable_cells!(editor.iomap)
        for event in _WARMUP_EVENTS
            window_input    = WindowInput(window_id, event)
            change = read_intent(composed, nothing, Intent(window_input), editor.iomap)
            op     = change isa Intent ? change.operation : change
            op isa Operation || continue
            editor.operation = op
            evaluate_operation(editor, op)
            editor.iomap = print_document(composed, editor.document)
            evaluate_reachable_cells!(editor.iomap)
        end
    catch err
        @warn "warm_file_editor: headless warm-up failed (non-fatal)" domain err
    end
    nothing
end
