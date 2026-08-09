# ═══════════════════════════════════════════════════════════════════════════
# example/Precompile.jl
#
# Compile the projection stack at build time instead of in front of a reader.
#
# Nothing here is a sample. The unit of compilation is the (printer, document
# node type) pair — a page with a Julia fragment on it compiles 18 separate
# `Julia*ToSyntax*` printers at ~200 ms each, and that figure is flat whether
# the printer is a one-liner or not, because what is inferred is the
# projection-template machinery instantiated for that node type. The atomic
# document registry is exactly one minimal document per node type, so walking it
# compiles the pairs and nothing else. `test_catalog_coverage` is what keeps the
# registry honest about which pairs it can still not reach.
#
# `precompile(…)` on the signatures instead does NOT work, and the reason is
# worth keeping: the chain is lazy. Printing builds thunks, the printers run
# when the cells are forced, and much of the cost is in closures called
# dynamically through the cell machinery — which a `precompile` call cannot name.
# Measured, the signature sweep reached under half the render for twice the
# build cost. The workload has to run the pipeline and force the output.
#
# See plan/pending/precompile-workloads.md.
# ═══════════════════════════════════════════════════════════════════════════

using PrecompileTools: @setup_workload, @compile_workload

"""
    precompile_atoms(atoms; projection = NaturalToGraphics(…)) -> Int

Print every atom through `projection` and force the result, returning how many
rendered without error. Used by the workload below, and by
`test_natural_renders_every_atom` so that a projection an atom cannot survive is
a test failure rather than something the workload silently skips.

`NaturalToGraphics` is the default rather than a per-domain chain because it is
the one projection that dispatches on document type across every domain,
collection, layout and widget — the same renderer an editor puts on screen. A
hand-written domain→chain table would be a second registry to keep in step with
this one.

A downstream package passes its own: `OmnetppPresentationExample` splices the
simulation-embed entry and the workbench dispatch into the same renderer, so its
atoms compile through the projection its reader will actually meet.
"""
function precompile_atoms(atoms;
                          projection = NaturalToGraphics(measure = truetype_measure_text))
    context = PrinterContext(EmptyReference(),
                             Cell(1200),
                             Cell(800),
                             Dict{Symbol,Any}())
    rendered = 0
    for atom in atoms
        try
            iomap = print_document(projection, nothing, atom.make_document(), context)
            force_projected(get_iomap_output(iomap))
            rendered += 1
        catch
            # Swallowed on purpose: a precompile workload must not fail a build.
            # This is NOT where such a failure is meant to be noticed —
            # `test_natural_renders_every_atom` asserts the same loop and reports
            # which atom broke.
        end
    end
    rendered
end

"""
    precompile_atom_parsers(atoms) -> Int

Round-trip every atom that has a natural text format — render it to text, read
that text back — and return how many completed. Compiles the reading half of the
stack, which is otherwise JIT'd the first time anyone opens a file.

No domain→parser table is needed: the natural format is already a registry.
`natural_extension(doc)` names the format, `document_to_text(doc)` renders it
(its own documentation says the text is the editor's rendered form, "which the
domain parser re-reads"), and `parse_natural(Val(:ext), text)` is the parser a
domain registered. A domain with no natural format has no `natural_extension`
method and drops out — the registry answering, rather than a list here going
stale.

Editor scaffolding is expected to fail the round trip rather than pass it: a
document carrying an insertion placeholder has no valid natural text, as
`NaturalFormatModule` says outright. So this counts successes instead of
asserting them, and `test_natural_round_trips_every_atom` is where the count is
held to a number.
"""
function precompile_atom_parsers(atoms)
    parsed = 0
    for atom in atoms
        try
            document = atom.make_document()
            extension = natural_extension(document)
            format = Symbol(SubString(extension, 2))
            applicable(parse_natural, Val(format), "") || continue
            parse_natural(Val(format), document_to_text(document))
            parsed += 1
        catch
            # As above: not the place a failure is meant to surface.
        end
    end
    parsed
end

"""
    precompile_atom_walks(atoms) -> Int

Resolve stubs over every atom, returning how many completed.

`resolve_stubs!` is what opening a document does before anything renders it, and
it is specialised per node type *and* per predicate closure — so it is only
reached by calling `resolve_stubs!` itself, not by an equivalent walk written
here. On the demo it was the single largest item in opening a page: 2.65 s
across 317 closure instantiations, more than the embed, the JSON decode and the
Expr conversion together.

Most atoms carry no stub, which does not matter: the walk still specialises for
the node types it descends through, and those are the specialisations being
bought.
"""
function precompile_atom_walks(atoms)
    walked = 0
    for atom in atoms
        try
            resolve_stubs!(atom.make_document())
            walked += 1
        catch
            # As above: not the place a failure is meant to surface.
        end
    end
    walked
end

"""
    precompile_workload(level::Symbol = :minimal; atoms = atomic_documents()) -> Nothing

The body a leaf package's `@compile_workload` calls. It is an ordinary function
rather than code inside the macro, so the same definition serves the REPL leaf
and the executable, and so it can be called and timed without a rebuild.

`level` says how much to compile. Each level includes the ones before it:

| level | what it runs | measured on the demo |
| --- | --- | --- |
| `:none` | nothing | the click costs 5.98 s |
| `:minimal` | the atoms rendered and forced | |
| `:demo` | and their parsers and stub walks | the click costs 0.55 s |
| `:full` | the same as `:demo` here | |

`:full` is not larger than `:demo` in this package because there is no page to
open below the domains. A downstream package's `precompile_workload` calls this
one and adds what only it can reach — `OmnetppExample` opens a catalog page —
so `:full` is where the levels differ downstream.

The workload must *run* the pipeline: the chain is lazy, printing builds thunks,
and `precompile` on the signatures reached under half the render for twice the
build cost. See the module comment above.
"""
function precompile_workload(level::Symbol = :minimal; atoms = atomic_documents())
    level === :none && return nothing
    level in (:minimal, :demo, :full) ||
        error("precompile_workload: level must be :none, :minimal, :demo or :full, got ",
              repr(level))
    precompile_atoms(atoms)
    level === :minimal && return nothing
    precompile_atom_parsers(atoms)
    precompile_atom_walks(atoms)
    nothing
end

@setup_workload begin
    # Built outside the workload: constructing the documents is not what needs
    # compiling, and doing it here keeps the measured region to the pipeline.
    _atoms = atomic_documents()
    @compile_workload begin
        precompile_workload(:demo; atoms = _atoms)
    end
end
