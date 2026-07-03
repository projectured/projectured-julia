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

# The selection-derived **overlay** geometry — the text caret, the selection
# highlight, and a widget focus ring — are graphics-primitive geometry cells
# (`:x`/`:y`/`:w`/`:h` of a `Graphics*` struct) whose values are computed from the
# selection. `TextToGraphics` builds the cursor/highlight rects from a
# selection-reading `overlay` cell, deliberately separate from the
# selection-independent `layout` cell that lays out the text spans (see
# TextToGraphics.jl) — so on a pure caret move *only* the overlay geometry moves,
# which is the whole point of a caret, not a locality violation.
#
# Content geometry reads `layout` (never the selection), so it is never in a
# selection move's invalidation set; exempting `Graphics*` geometry here therefore
# only ever clears these overlay cells in a correct projection. (Caveat: it would
# also mask a hypothetical future bug where *content* geometry wrongly depended on
# the selection. The exact-for-all-pipelines fix is to structurally separate the
# overlay under a `:selection` field so the plain `is_selection_cell` test catches
# it — see plan/pending/printer-locality.md Phase 5.)
const _OVERLAY_GEOMETRY_FIELDS = (:x, :y, :w, :h)
_is_selection_overlay_cell(lc::LocalityCell) =
    lc.field in _OVERLAY_GEOMETRY_FIELDS &&
    lc.owner isa DataType && startswith(string(nameof(lc.owner)), "Graphics")

# A `CellVector`'s `elements` thunk — the only cell that rebuilds a whole children
# vector. A *router* (a tabbed pane's selector/content strip, a "show the selected
# thing" pane) builds its children from the selection, so on a move that switches
# the active branch this cell legitimately recomputes. It is exempt ONLY on a
# routing move (see `_is_routing_change`); on a pure within-branch caret move a
# `CellVector.elements` invalidation is still a real violation (a content vector
# that wrongly read the selection). The owner is matched by name so a future
# parametric `CellVector{T}` still matches.
_is_router_rebuild_cell(lc::LocalityCell) =
    lc.field === :elements && lc.owner isa DataType && nameof(lc.owner) === :CellVector

# Reflexively force every Cell reachable from `x`, recording each as a
# LocalityCell tagged with the (owner_type, field) it was reached through, and
# the objectid of every reachable object (for identity diffing). Mirrors
# PrinterTest._walk! but keeps the cell objects rather than only forcing them.
# Reuses `_WALK_MAX_DEPTH` / `_WALK_MAX_NODES` from PrinterTest.jl.
function _collect_locality!(x, owner, field::Symbol,
                            visited::Set{UInt64}, cells::Vector{LocalityCell},
                            objects::Set{UInt64}, errors::Vector{String}, depth::Int;
                            sel_objects::Union{Set{UInt64},Nothing}=nothing,
                            under_sel::Bool=false)
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

    # Once the walk crosses a `:selection` cell, everything below it is a
    # selection-path artifact (a ReferencePath / Reference), never output content.
    # `sel_objects` records those ids so a move's lost objects can be split into
    # selection churn (expected) vs. lost content (a routing change). See
    # `printer_locality_report`.
    under_sel = under_sel || (field === :selection)

    id = objectid(x)
    id in visited && return
    push!(visited, id)
    push!(objects, id)
    (under_sel && sel_objects !== nothing) && push!(sel_objects, id)

    if x isa Cell
        push!(cells, LocalityCell(x, owner, field))
        val = try
            x[]
        catch e
            push!(errors, "Cell[] threw: $e")
            return
        end
        _collect_locality!(val, nothing, :_, visited, cells, objects, errors, depth + 1;
                           sel_objects=sel_objects, under_sel=under_sel)
    elseif x isa Vector
        for el in x
            _collect_locality!(el, nothing, :_, visited, cells, objects, errors, depth + 1;
                               sel_objects=sel_objects, under_sel=under_sel)
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
                _collect_locality!(fval, typeof(x), fname, visited, cells, objects, errors, depth + 1;
                                   sel_objects=sel_objects, under_sel=under_sel)
            else
                _collect_locality!(fval, nothing, :_, visited, cells, objects, errors, depth + 1;
                                   sel_objects=sel_objects, under_sel=under_sel)
            end
        end
    end
end

# The result of one locality measurement.
struct LocalityReport
    invalidated::Vector{LocalityCell}   # snapshot output cells now !is_up_to_date
    cell_count::Int                     # total output cells snapshotted
    preserved_objects::Int              # objectids reachable before AND after
    lost_objects::Int                   # objectids reachable before but NOT after
    lost_content::Int                   # lost objectids that are NOT selection-path
                                        # artifacts ⇒ a routing change (the active
                                        # branch switched, dropping old content)
    before_objects::Int                 # objectids reachable before
    perf::Dict{Symbol,Int}              # counters accrued by mutate! + reforce
    errors::Vector{String}
end

# A selection move is a *routing change* when it drops reachable output content
# (not just selection-path churn): switching the active tab/page makes the old
# branch's output unreachable. On such a move a router's `CellVector.elements`
# rebuild is expected, so it is exempt; a pure within-branch caret move drops only
# selection artifacts (`lost_content == 0`) and stays under the strict invariant.
_is_routing_change(r::LocalityReport) = r.lost_content > 0

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
        print_document(projection, document)
    catch e
        push!(errors, "print_document threw: $e")
        return LocalityReport(LocalityCell[], 0, 0, 0, 0, 0, get_performance_counters(), errors)
    end
    output = iomap.output

    cells = LocalityCell[]
    before_objs = Set{UInt64}()
    before_sel_objs = Set{UInt64}()
    _collect_locality!(output, nothing, :_, Set{UInt64}(), cells, before_objs, errors, 0;
                       sel_objects=before_sel_objs)

    perf_reset!()
    try
        mutate!(document)
    catch e
        push!(errors, "mutate! threw: $e")
    end

    # Eager invalidation has run; read `.valid` only (is_up_to_date is pure) so we
    # do not recompute anything before observing the footprint.
    invalidated = LocalityCell[lc for lc in cells if !is_up_to_date(lc.cell)]

    # Re-force to recompute and re-collect object identities + perf delta.
    after_objs = Set{UInt64}()
    _collect_locality!(output, nothing, :_, Set{UInt64}(), LocalityCell[], after_objs, errors, 0)
    perf = get_performance_counters()

    preserved = length(intersect(before_objs, after_objs))
    lost_set = setdiff(before_objs, after_objs)
    lost = length(lost_set)
    # Lost objects minus the selection-path artifacts ⇒ dropped output content.
    lost_content = length(setdiff(lost_set, before_sel_objs))
    LocalityReport(invalidated, length(cells), preserved, lost, lost_content, length(before_objs), perf, errors)
end

# ── Dimension A: selection isolation ──────────────────────────────────────────

"""
    explore_selection_locality(document, projection; onstate=nothing)
        -> (count, errors)

Drive dimension A over every enumerated text caret: for each caret, measure an
`update_selection!` to it and require that it invalidated ONLY `:selection` cells
and rebuilt NO output object. Returns the number of carets exercised and a flat
`errors::Vector{String}`; `onstate(ok, msg)` is invoked once per caret so a
`@testset` wrapper can emit one `@test` per selection state.

The mutation is `update_selection!` — the editor's real caret-move fast path
(every `ReplaceSelectionOperation` uses it), which writes the shared selection
chain *in place*, touching only the cells whose content actually changed. This is
the mutation whose locality we care about. (`set_selection!` is the from-scratch
re-walk that rewrites every node's selection cell — it never happens on a caret
move, so measuring it would flag unchanged routing ancestors, e.g. a tabbed pane's
active-tab cell, as false positives.)
"""
function explore_selection_locality(document, projection; onstate=nothing)
    errors = String[]
    carets = collect_text_selections(document)
    for target in carets
        r = printer_locality_report(document, projection, doc -> update_selection!(doc, target))
        msgs = String[]
        append!(msgs, r.errors)
        # Dimension A is measured by the INVALIDATION set, not object identity: a
        # selection cell legitimately recomputes to a fresh ReferencePath value
        # (the old path object is "lost"), so lost_objects > 0 is expected here
        # and is NOT a violation — only a *content* cell going stale is.
        #
        # Scope: exact for projections that carry selection as a `:selection`
        # field (the syntax/widget/structural layers — most printers). A full
        # pipeline that lowers selection into caret geometry (… → TextToGraphics)
        # invalidates non-:selection geometry cells by design; those need a
        # cursor-field allow-list (Phase 2 follow-up) before this check is exact
        # for them, which is why it is not yet wired into test_all.
        # A routing move (the active tab/page switched) legitimately rebuilds the
        # router's children vector, so a `CellVector.elements` invalidation is
        # exempt *only then*; everything else, and any non-selection cell on a pure
        # within-branch move, is still a violation.
        routing = _is_routing_change(r)
        bad = filter(r.invalidated) do lc
            is_selection_cell(lc) && return false
            _is_selection_overlay_cell(lc) && return false
            routing && _is_router_rebuild_cell(lc) && return false
            return true
        end
        if !isempty(bad)
            tags = join(sort(unique(["$(lc.owner).$(lc.field)" for lc in bad])), ", ")
            push!(msgs, "→ $(string(target)): invalidated non-selection cells [$tags]")
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

# ── Dimension C: structural-edit minimality ───────────────────────────────────
#
# Inserting one element into a collection should rebuild only the changed slot
# and the structural envelope, preserving the OUTPUT objects of the unaffected
# siblings (cell identity), so downstream layout reuses them. A rebuilt slot
# cell / re-projected sibling is *not* an invalidation (the old object is
# orphaned, not marked invalid) — it shows up as a LOST object in the report's
# identity diff. So dimension C is measured by `lost_objects`, not by the
# invalidation footprint.
#
# This is currently a MEASUREMENT, not a pass/fail assertion: the central
# template engine rebuilds the whole children vector on any structural change
# (`CellVector(() -> …)` recreates every slot cell; `child_iomaps` re-projects
# every sibling — see plan/pending/printer-locality.md Phase 4 / dimension C),
# so most collections will report large `lost_objects` until that fix lands.
# Phase 4 decides fix-vs-justified-exception; until then we report the numbers.

# Every `CellVector` reachable from an input document, with a short path label.
# Mirrors SelectionEnumeration._walk_document's descent (Cell-unwrapping fields
# and CellVector elements) so it visits exactly the navigable structure.
function _find_input_collections(document)
    found = Tuple{String,Any}[]
    seen = Set{UInt64}()
    function walk(node, label)
        node === nothing && return
        node isa Union{Bool,Number,AbstractString,Symbol} && return
        oid = objectid(node)
        oid in seen && return
        push!(seen, oid)
        if node isa CellVector
            length(node) >= 1 && push!(found, (label, node))
            for i in 1:length(node)
                walk(node[i], "$label[$i]")
            end
            return
        end
        T = typeof(node)
        isstructtype(T) || return
        for fname in fieldnames(T)
            fname === :selection && continue
            fv = try getfield(node, fname) catch; continue end
            v = fv isa Cell ? fv[] : fv
            (v isa CellVector || (v !== nothing && hasproperty(v, :selection))) &&
                walk(v, label == "" ? ".$fname" : "$label.$fname")
        end
    end
    walk(document, "")
    found
end

"""
    explore_structural_locality(document, projection; onresult=nothing)
        -> (count, results)

Measure dimension C over every input `CellVector` of length ≥ 1: append a
duplicate of the first element, then report how many output objects survived
(`preserved`) vs. were rebuilt (`lost`). The document is restored afterwards
(the appended slot is popped), so the call leaves it as found. Returns one
`(label, lost, preserved, total)` NamedTuple per collection.
"""
function explore_structural_locality(document, projection; onresult=nothing)
    results = NamedTuple[]
    for (label, cv) in _find_input_collections(document)
        n0 = length(cv)
        r = printer_locality_report(document, projection, _ -> push!(cv, cv[1]))
        # Restore the document to its original shape regardless of outcome.
        while length(cv) > n0
            try pop!(cv) catch; break end
        end
        res = (label = label, lost = r.lost_objects,
               preserved = r.preserved_objects, total = r.before_objects,
               errors = r.errors)
        push!(results, res)
        onresult === nothing || onresult(res)
    end
    (count = length(results), results = results)
end

# Report-only (no @test): the engine fix has not landed, so this prints the
# per-collection identity-churn measurement for the Phase 3 audit table rather
# than asserting. Promote to assertions in Phase 5 once dimension C is enforced.
function report_structural_locality(label, document, projection)
    res = explore_structural_locality(document, projection;
        onresult = r -> begin
            for e in r.errors; @warn "[$label] $(r.label): $e"; end
            @info "[$label] $(r.label): lost $(r.lost)/$(r.total) output objects on insert (preserved $(r.preserved))"
        end)
    res.count == 0 && @info "[$label] no input collections to probe (structural locality not exercised)"
    res
end

report_structural_locality(example::Example) =
    report_structural_locality(example.name, example.document, example.projection)

"""
    test_template_structural_locality()

Dimension C for the projection-template engine (`ProjectionTemplate._node_print`):
inserting one element into a template `collection()` must preserve the OUTPUT
identity of every unchanged sibling — keyed reconciliation reuses each prior child
iomap whose element is the same object at the same index — so a structural edit
rebuilds only the changed slot and the envelope, not the whole children vector.

Measured at the SYNTAX layer (`RecursiveProjection(JsonToSyntax())`) to isolate the
template engine from the downstream render layers (which are exercised separately
by `test_graphics_structural_locality`). Without reconciliation each JSON collection
orphaned ≈97% of its output objects on insert; with it, ≤1%.
"""
function test_template_structural_locality()
    @testset "Template structural locality (dimension C)" begin
        doc = make_json_document_example()
        proj = RecursiveProjection(JsonToSyntax())
        res = explore_structural_locality(doc, proj)
        @test res.count >= 1
        for r in res.results
            @test isempty(r.errors)
            frac = r.total == 0 ? 0.0 : r.lost / r.total
            frac < 0.05 || @warn "[$(r.label)] structural loss $(round(100*frac; digits=1))% (>5%): reconciliation regressed"
            @test frac < 0.05
        end
    end
end

"""
    test_graphics_structural_locality()

Dimension C end-to-end, through the full JSON render pipeline
(`JsonToSyntax → SyntaxToText → TextToGraphics`): a structural insert must preserve
the output-object identity of the unchanged siblings all the way down to the
graphics. Each layer reconciles — the template engine reuses child iomaps, the text
layer shares decorative whitespace spans, and `TextToGraphics` reuses a persistent
GraphicsText per segment (its geometry derived reactively). Without these the
graphics output orphaned ≈97% of its objects on insert; with them, ≈9% (essentially
the newly inserted element plus the decoration that genuinely shifted).
"""
function test_graphics_structural_locality()
    @testset "Graphics structural locality (dimension C, end-to-end)" begin
        doc = make_json_document_example()
        proj = make_json_projection_example()
        res = explore_structural_locality(doc, proj)
        @test res.count >= 1
        for r in res.results
            @test isempty(r.errors)
            frac = r.total == 0 ? 0.0 : r.lost / r.total
            frac < 0.20 || @warn "[$(r.label)] end-to-end graphics loss $(round(100*frac; digits=1))% (>20%): downstream reconciliation regressed"
            @test frac < 0.20
        end
    end
end

# ── Dimension B: value-edit isolation ─────────────────────────────────────────
#
# Editing one leaf's scalar value must invalidate only that leaf's value/text
# cell and the cells strictly derived from it — never a sibling subtree, and
# never any output STRUCTURE. Because a value edit writes into an existing
# slot's cell (CellVector `cv[i] = val` keeps `.elements`, so the structure cell
# is untouched — Collection.jl invariants), no output object should be rebuilt:
# the leaf's text cell recomputes to a new (uncounted) String in place. So the
# clean, generic dimension-B invariant is `lost_objects == 0`.
#
# This is predicted CLEAN for the template engine (value cells read `doc.value`,
# children cells read `child_iomaps` which does not depend on an element's value
# cell — see plan/pending/printer-locality-findings.md Finding 1), so it is an
# assertion, not a report.

# Every input leaf carrying an editable scalar `:value` field (String / Real /
# Bool), with a path label and the original value, so the edit can be undone.
function _find_input_value_leaves(document)
    found = Tuple{String,Any,Any}[]   # (label, node, original_value)
    seen = Set{UInt64}()
    function walk(node, label)
        node === nothing && return
        node isa Union{Bool,Number,AbstractString,Symbol} && return
        oid = objectid(node)
        oid in seen && return
        push!(seen, oid)
        if node isa CellVector
            for i in 1:length(node)
                walk(node[i], "$label[$i]")
            end
            return
        end
        T = typeof(node)
        isstructtype(T) || return
        if hasproperty(node, :value)
            v = try node.value catch; nothing end
            v isa Union{AbstractString,Real,Bool} && push!(found, (label, node, v))
        end
        for fname in fieldnames(T)
            fname === :selection && continue
            fv = try getfield(node, fname) catch; continue end
            fval = fv isa Cell ? fv[] : fv
            (fval isa CellVector || (fval !== nothing && hasproperty(fval, :selection))) &&
                walk(fval, label == "" ? ".$fname" : "$label.$fname")
        end
    end
    walk(document, "")
    found
end

# A minimal same-typed perturbation of a scalar value (so the projection still
# renders without error): flip a Bool, bump a Real, extend a String.
_perturb(v::Bool)          = !v
_perturb(v::Real)          = v + oneunit(v)
_perturb(v::AbstractString) = v * "x"

"""
    explore_value_locality(document, projection; onstate=nothing)
        -> (count, errors)

Drive dimension B over every input scalar leaf: perturb its value (restoring it
afterwards) and require that the edit rebuilt NO output object (`lost == 0`).
`onstate(ok, msg)` is invoked once per leaf for one `@test` apiece.
"""
function explore_value_locality(document, projection; onstate=nothing)
    errors = String[]
    leaves = _find_input_value_leaves(document)
    for (label, node, original) in leaves
        r = printer_locality_report(document, projection,
                                    _ -> (node.value = _perturb(original)))
        try node.value = original catch end   # restore
        msgs = String[]
        append!(msgs, r.errors)
        if r.lost_objects > 0
            push!(msgs, "→ $label: value edit rebuilt $(r.lost_objects)/$(r.before_objects) output object(s) (expected 0)")
        end
        ok = isempty(msgs)
        append!(errors, msgs)
        onstate === nothing || onstate(ok, ok ? "" : join(msgs, "; "))
    end
    (count = length(leaves), errors = errors)
end

function test_value_locality(label, document, projection)
    @testset "$label" begin
        res = explore_value_locality(document, projection;
            onstate = (ok, msg) -> begin
                ok || @warn "[$label] $msg"
                @test ok
            end)
        res.count == 0 && @info "[$label] no scalar value leaves to probe (value locality not exercised)"
    end
end

test_value_locality(example::Example) =
    test_value_locality(example.name, example.document, example.projection)

function test_value_localities()
    @testset "Value locality" begin
        for example in examples
            @testset "$(example.name)" begin
                test_value_locality(example)
            end
        end
    end
end
