# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/PrinterTest.jl
#
# Generic printer walk test.  For each (document, projection) pair:
#   1. Call projection_print to obtain an iomap.
#   2. Reflexively walk every field of iomap (and its .output) using
#      fieldnames / getfield so that new document types are covered
#      automatically.
#   3. Force-evaluate every Cell encountered by calling c[].
#   4. Track visited objects by objectid to handle circular references.
#   5. Collect and report any errors.
# ═══════════════════════════════════════════════════════════════════════════

# ── Reflexive walker ─────────────────────────────────────────────────────────
#
# Recursively descends into every field of every object reachable from `x`.
# Calls c[] on every Cell to force evaluation.
# Stops at:
#   • primitive leaf types (nothing, Bool, Number, String, Symbol, …)
#   • already-visited objects  (cycle guard via objectid)
#   • Julia internals (Function, DataType, Module)

const _WALK_MAX_DEPTH = 100

function _walk!(x, visited::Set{UInt64}, errors::Vector{String}, depth::Int=0)
    x === nothing        && return
    x isa Bool           && return
    x isa Number         && return
    x isa AbstractString && return
    x isa Symbol         && return
    x isa Function       && return
    x isa DataType       && return
    x isa Module         && return

    depth >= _WALK_MAX_DEPTH && return

    id = objectid(x)
    id in visited && return
    push!(visited, id)

    if x isa Cell
        val = try
            x[]
        catch e
            push!(errors, "Cell[] threw: $e")
            return
        end
        _walk!(val, visited, errors, depth + 1)
    elseif x isa Vector
        for el in x
            _walk!(el, visited, errors, depth + 1)
        end
    else
        for fname in fieldnames(typeof(x))
            fval = try
                getfield(x, fname)
            catch e
                push!(errors, "getfield($(typeof(x)), :$fname) threw: $e")
                continue
            end
            _walk!(fval, visited, errors, depth + 1)
        end
    end
end

# ── Public entry point ───────────────────────────────────────────────────────

"""
    walk_printer_output(document, projection) -> Vector{String}

Print `document` with `projection`, then walk every reachable field of the
resulting iomap, forcing evaluation of every Cell.  Returns a (possibly
empty) list of error strings.
"""
function walk_printer_output(document, projection)
    errors = String[]
    iomap = try
        projection_print(projection, document)
    catch e
        push!(errors, "projection_print threw: $e")
        return errors
    end
    _walk!(iomap, Set{UInt64}(), errors)
    errors
end

# ── Test helper ──────────────────────────────────────────────────────────────

function test_printer(label, document, projection)
    @testset "$label" begin
        errors = walk_printer_output(document, projection)
        for e in errors
            @warn "[$label] $e"
        end
        @test isempty(errors)
    end
end

function test_printer(example::Example)
    test_printer(example.name, example.document, example.projection)
end

function test_printers()
    @testset "Printers" begin
        for example in examples
            @testset "$(example.name)" begin
                test_printer(example)
            end
        end
    end
end
