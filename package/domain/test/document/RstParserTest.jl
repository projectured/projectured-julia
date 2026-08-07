# Tests for the reStructuredText parser (`rstparse`) and the `:source`
# projection's emit path.
#
# Two levels of check:
#
# - unit tests on small strings, one construct at a time;
# - a fixture round-trip on five real files copied from the INET
#   documentation (`package/domain/test/fixture/rst/`).
#
# The round-trip criterion is **AST idempotence**, not byte equality:
#
#     rstparse(document_to_text(rstparse(text))) == rstparse(text)
#
# Byte equality is out of reach because the corpus writes adornment lines
# longer than their titles and mixes indent widths. `test_rst_corpus`
# reports the byte-exact count as a quality figure without asserting it.

const RST_FIXTURE_DIR = joinpath(@__DIR__, "..", "fixture", "rst")

rst_fixture_files() = sort(filter(f -> endswith(f, ".rst"), readdir(RST_FIXTURE_DIR; join = true)))

"""
    test_rst_corpus(dir) -> NamedTuple

Parse every `.rst` file under `dir`, re-emit it through the `:source`
projection, and re-parse the result. Returns a summary of the files that
parsed, that round-tripped at the AST level, and that round-tripped byte
for byte.

Not wired into `test_domain()`: point it at a documentation tree to sweep
it, for example

    test_rst_corpus("/home/projectured/workspace/inet-cpp")
"""
function test_rst_corpus(dir::AbstractString; verbose::Bool = true, limit::Int = typemax(Int))
    files = String[]
    for (root, _, names) in walkdir(dir)
        for n in names
            endswith(n, ".rst") && push!(files, joinpath(root, n))
        end
    end
    sort!(files)
    length(files) > limit && (files = files[1:limit])
    parsed = 0
    idempotent = 0
    exact = 0
    failures = String[]
    for f in files
        text = read(f, String)
        local doc
        try
            doc = rstparse(text)
            parsed += 1
        catch e
            push!(failures, "parse: $f: $(sprint(showerror, e))")
            continue
        end
        local emitted
        try
            emitted = document_to_text(doc)
        catch e
            push!(failures, "emit: $f: $(sprint(showerror, e))")
            continue
        end
        emitted == text && (exact += 1)
        try
            if rst_ast_equal(rstparse(emitted), doc)
                idempotent += 1
            else
                push!(failures, "idempotence: $f")
            end
        catch e
            push!(failures, "reparse: $f: $(sprint(showerror, e))")
        end
    end
    if verbose
        println("rst corpus $dir")
        println("  files       $(length(files))")
        println("  parsed      $parsed")
        println("  idempotent  $idempotent")
        println("  byte-exact  $exact")
        for f in first(failures, 40)
            println("  ! $f")
        end
        length(failures) > 40 && println("  … $(length(failures) - 40) more")
    end
    (files = length(files), parsed = parsed, idempotent = idempotent,
     exact = exact, failures = failures)
end
