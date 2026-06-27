# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/PrinterLocalityTest.jl
#
# Printer *locality* measurement (Phase 1 of plan/pending/printer-locality.md).
#
# A printer should produce the smallest possible change in its output for any
# given change in its input: a minimal input edit must invalidate a minimal set
# of output cells and preserve the identity of every output object whose input
# did not change. This harness measures, for ONE input mutation, exactly:
#
#   • which output cells were invalidated  — tagged by the struct field they
#     back (`:selection`, `:value`, `:content`, …), so a report can say *what
#     kind* of cell moved; and
#   • how many output objects lost identity — reachable before the edit but not
#     after (the signal for structural churn: a rebuilt CellVector replaces its
#     slot cells and re-projects siblings, so the old objects become garbage
#     rather than being marked invalid).
#
# The reactive engine is write-driven with no equality check (see
# documentation/reactive-cells.md), so locality is purely a property of the
# dependency graph the printer builds. We measure that graph directly.
#
# Dimension A — selection isolation — is the headline case the plan calls out:
# a pure `set_selection!` must invalidate ONLY `:selection` cells and rebuild
# NO output object. `explore_selection_locality` / `test_selection_locality`
# drive it over every enumerated text caret.
# ═══════════════════════════════════════════════════════════════════════════

# A printed output cell, tagged with where the walk reached it so a report can
# say which *kind* of cell moved. `field` is the struct field that holds the
# cell (`:selection`, `:value`, …) or `:_` for a vector/anonymous cell; `owner`
# is the struct type that holds it, or `nothing`.
struct LocalityCell
    cell::Cell
    owner::Any
    field::Symbol
end

is_selection_cell(lc::LocalityCell) = lc.field === :selection

# Reflexively force every Cell reachable from `x`, recording each as a
# LocalityCell tagged with the (owner_type, field) it was reached through, and
# the objectid of every reachable object (for identity diffing). Mirrors
# PrinterTest._walk! but keeps the cell objects rather than only forcing them.
# Reuses `_WALK_MAX_DEPTH` / `_WALK_MAX_NODES` from PrinterTest.jl.
function _collect_locality!(x, owner, field::Symbol,
                            visited::Set{UInt64}, cells::Vector{LocalityCell},
                            objects::Set{UInt64}, errors::Vector{String}, depth::Int)
    x === nothing        && return
    x isa Bool           && return
    x isa Number         && return
    x isa AbstractString && return
    x isa Symbol         && return
    x isa Function       && return
    x isa DataType       && return
    x isa Module         && return
    depth >= _WALK_MAX_DEPTH && return
    length(visited) >= _WALK_MAX_NODES && return

    id = objectid(x)
    id in visited && return
    push!(visited, id)
    push!(objects, id)

    if x isa Cell
        push!(cells, LocalityCell(x, owner, field))
        val = try
            x[]
        catch e
            push!(errors, "Cell[] threw: $e")
            return
        end
        _collect_locality!(val, nothing, :_, visited, cells, objects, errors, depth + 1)
    elseif x isa Vector
        for el in x
            _collect_locality!(el, nothing, :_, visited, cells, objects, errors, depth + 1)
        end
    else
        for fname in fieldnames(typeof(x))
            fval = try
                getfield(x, fname)
            catch e
                push!(errors, "getfield($(typeof(x)), :$fname) threw: $e")
                continue
            end
            if fval isa Cell
                _collect_locality!(fval, typeof(x), fname, visited, cells, objects, errors, depth + 1)
            else
                _collect_locality!(fval, nothing, :_, visited, cells, objects, errors, depth + 1)
            end
        end
    end
end

# The result of one locality measurement.
struct LocalityReport
    invalidated::Vector{LocalityCell}   # snapshot output cells now !isuptodate
    cell_count::Int                     # total output cells snapshotted
    preserved_objects::Int              # objectids reachable before AND after
    lost_objects::Int                   # objectids reachable before but NOT after
    before_objects::Int                 # objectids reachable before
    perf::Dict{Symbol,Int}              # counters accrued by mutate! + reforce
    errors::Vector{String}
end

"""
    printer_locality_report(document, projection, mutate!) -> LocalityReport

Print `document` with `projection`, force every reachable **output** cell and
snapshot validity + object identity, run `mutate!(document)` (ONE minimal input
edit — a selection move, a value edit, or a structural edit), then report which
snapshot output cells were invalidated (tagged by owner/field) and how many
output objects lost identity.

The validity scan runs *before* re-forcing, so it observes exactly the eager
invalidation the mutation caused; the identity diff and `perf` counters come
from a subsequent re-force.
"""
function printer_locality_report(document, projection, mutate!)
    errors = String[]
    iomap = try
        projection_print(projection, document)
    catch e
        push!(errors, "projection_print threw: $e")
        return LocalityReport(LocalityCell[], 0, 0, 0, 0, perf_counters(), errors)
    end
    output = iomap.output

    cells = LocalityCell[]
    before_objs = Set{UInt64}()
    _collect_locality!(output, nothing, :_, Set{UInt64}(), cells, before_objs, errors, 0)

    perf_reset!()
    try
        mutate!(document)
    catch e
        push!(errors, "mutate! threw: $e")
    end

    # Eager invalidation has run; read `.valid` only (isuptodate is pure) so we
    # do not recompute anything before observing the footprint.
    invalidated = LocalityCell[lc for lc in cells if !isuptodate(lc.cell)]

    # Re-force to recompute and re-collect object identities + perf delta.
    after_objs = Set{UInt64}()
    _collect_locality!(output, nothing, :_, Set{UInt64}(), LocalityCell[], after_objs, errors, 0)
    perf = perf_counters()

    preserved = length(intersect(before_objs, after_objs))
    lost = length(setdiff(before_objs, after_objs))
    LocalityReport(invalidated, length(cells), preserved, lost, length(before_objs), perf, errors)
end

# ── Dimension A: selection isolation ──────────────────────────────────────────

"""
    explore_selection_locality(document, projection; onstate=nothing)
        -> (count, errors)

Drive dimension A over every enumerated text caret: for each caret, measure a
`set_selection!` to it and require that it invalidated ONLY `:selection` cells
and rebuilt NO output object. Returns the number of carets exercised and a flat
`errors::Vector{String}`; `onstate(ok, msg)` is invoked once per caret so a
`@testset` wrapper can emit one `@test` per selection state.
"""
function explore_selection_locality(document, projection; onstate=nothing)
    errors = String[]
    carets = collect_text_selections(document)
    for target in carets
        r = printer_locality_report(document, projection, doc -> set_selection!(doc, target))
        msgs = String[]
        append!(msgs, r.errors)
        bad = filter(lc -> !is_selection_cell(lc), r.invalidated)
        if !isempty(bad)
            tags = join(sort(unique(["$(lc.owner).$(lc.field)" for lc in bad])), ", ")
            push!(msgs, "→ $(string(target)): invalidated non-selection cells [$tags]")
        end
        if r.lost_objects > 0
            push!(msgs, "→ $(string(target)): rebuilt $(r.lost_objects) output object(s) (expected 0)")
        end
        ok = isempty(msgs)
        append!(errors, msgs)
        onstate === nothing || onstate(ok, ok ? "" : join(msgs, "; "))
    end
    (count = length(carets), errors = errors)
end

# One @test per caret, so the test count reflects every selection state probed
# and a failure pinpoints the exact selection + the offending cell tags.
function test_selection_locality(label, document, projection)
    @testset "$label" begin
        res = explore_selection_locality(document, projection;
            onstate = (ok, msg) -> begin
                ok || @warn "[$label] $msg"
                @test ok
            end)
        if res.count == 0
            @info "[$label] no text carets to probe (selection locality not exercised)"
        end
    end
end

test_selection_locality(example::Example) =
    test_selection_locality(example.name, example.document, example.projection)

function test_selection_localities()
    @testset "Selection locality" begin
        for example in examples
            @testset "$(example.name)" begin
                test_selection_locality(example)
            end
        end
    end
end
