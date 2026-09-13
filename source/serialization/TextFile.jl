# ──────────────────────────────────────────────────────────────────────────
# Folded in from TextFile.jl.
"""
    TextFile(filename, content)

A file document whose `content` is a plain `String` — no parser
runs, no projection is invoked. Used both as the driver's simplest
test target and as the fallback for any file whose extension the
higher formats don't claim (registered as `""` so an unknown
extension routes here).
"""
@document struct TextFile <: FileDocument
    filename::String
    content::String = ""
end

emit_text(f::TextFile) = get_file_content(f)

function populate_file!(f::TextFile, filename::AbstractString, ctx)
    getfield(f, :content)[] = read(joinpath(ctx.base_dir, filename), String)
    f
end

# Fallback: any extension nothing else claims (including "") loads
# as a raw text file. A concrete format that wants an unknown
# extension registers itself on top. Registered in `__init__` so the
# mutation survives precompilation (Julia does not preserve state
# built up by top-level statements across the precompile boundary).

