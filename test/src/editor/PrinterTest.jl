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
const _WALK_MAX_NODES = 500_000

# Reports back whether the walk completed or stopped because a limit was hit.
# `errors` accumulates real errors (cell failures, missing fields); separate
# fields here so callers can distinguish "ran clean" from "stopped early
# because the structure was too large" — a finding that would otherwise
# crash the host process if left uncapped.
mutable struct WalkStatus
    depth_limit_hit::Bool
    node_cap_hit::Bool
    max_depth::Int
    visited_count::Int
end

WalkStatus() = WalkStatus(false, false, 0, 0)

function _walk!(x, visited::Set{UInt64}, errors::Vector{String},
                status::WalkStatus=WalkStatus(), depth::Int=0)
    x === nothing        && return
    x isa Bool           && return
    x isa Number         && return
    x isa AbstractString && return
    x isa Symbol         && return
    x isa Function       && return
    x isa DataType       && return
    x isa Module         && return

    if depth >= _WALK_MAX_DEPTH
        status.depth_limit_hit = true
        return
    end
    if length(visited) >= _WALK_MAX_NODES
        status.node_cap_hit = true
        return
    end

    id = objectid(x)
    id in visited && return
    push!(visited, id)

    status.visited_count = length(visited)
    if depth > status.max_depth
        status.max_depth = depth
    end

    if x isa Cell
        val = try
            x[]
        catch e
            push!(errors, "Cell[] threw: $e")
            return
        end
        _walk!(val, visited, errors, status, depth + 1)
    elseif x isa Vector
        for el in x
            _walk!(el, visited, errors, status, depth + 1)
        end
    else
        for fname in fieldnames(typeof(x))
            fval = try
                getfield(x, fname)
            catch e
                push!(errors, "getfield($(typeof(x)), :$fname) threw: $e")
                continue
            end
            _walk!(fval, visited, errors, status, depth + 1)
        end
    end
end

# ── Public entry point ───────────────────────────────────────────────────────

"""
    walk_printer_output(document, projection) -> (errors, status)

Print `document` with `projection`, then walk every reachable field of the
resulting iomap, forcing evaluation of every Cell.  `errors` is a list of
real failures (cell evaluation, missing fields).  `status::WalkStatus` records
whether `_WALK_MAX_DEPTH` or `_WALK_MAX_NODES` was hit — surfaced separately
so legitimately infinite/lazy documents don't fail the test.
"""
function walk_printer_output(document, projection)
    errors = String[]
    status = WalkStatus()
    iomap = try
        projection_print(projection, document)
    catch e
        push!(errors, "projection_print threw: $e")
        return (errors, status)
    end
    _walk!(iomap, Set{UInt64}(), errors, status)
    (errors, status)
end

# ── Test helper ──────────────────────────────────────────────────────────────

function test_printer(label, document, projection)
    @testset "$label" begin
        errors, status = walk_printer_output(document, projection)
        for e in errors
            @warn "[$label] $e"
        end
        if status.depth_limit_hit
            @info "[$label] walk hit depth limit ($_WALK_MAX_DEPTH) at $(status.visited_count) nodes (max_depth=$(status.max_depth))"
        end
        if status.node_cap_hit
            @info "[$label] walk hit node cap ($_WALK_MAX_NODES) — structure too large or not properly graph-linked (max_depth=$(status.max_depth))"
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
