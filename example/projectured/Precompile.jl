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
# Sweeping `precompile(…)` over the METHOD TABLE instead does NOT work, and the
# reason is worth keeping: the chain is lazy. Printing builds thunks, the
# printers run when the cells are forced, and much of the cost is in closures
# called dynamically through the cell machinery. A method table describes what a
# reader accepts, not which closure it will be handed, so the sweep cannot name
# them. Measured, it reached under half the render for twice the build cost.
#
# A RECORDING can name them, and this is the distinction to keep: Julia's gensym
# names for closures are stable and nameable, so a `--trace-compile` list writes
# them down and reads them back — measured, 555 of 555 closure statements
# resolved in a later session. That is what `PrecompileRecording.jl` beside this
# file is for. This workload remains what runs when a build must not depend on a
# checked-in list, and what a recording is checked against.
#
# See plan/pending/precompile-workloads.md and
# plan/pending/recorded-precompile-workload.md.
# ═══════════════════════════════════════════════════════════════════════════

# PrecompileTools is not used here — the macro call sites live in the leaves.

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

A downstream package passes its own: one splices its simulation-embed entry
and its own window dispatch into the same renderer, so its
atoms compile through the projection its reader will actually meet.
"""
function precompile_atoms(atoms;
                          projection = NaturalToGraphics(measure = measure_truetype_text))
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
`get_natural_extension(doc)` names the format, `print_natural_text(doc)` renders it
(its own documentation says the text is the editor's rendered form, "which the
domain parser re-reads"), and `parse_natural_text(:ext, text)` is the parser a
domain registered. A domain with no natural format has no extension
method and drops out — the registry answering, rather than a list here going
stale.

Editor scaffolding is expected to fail the round trip rather than pass it: a
document carrying an insertion placeholder has no valid natural text, as
`NaturalModule` says outright. So this counts successes instead of
asserting them, and `test_natural_round_trips_every_atom` is where the count is
held to a number.
"""
function precompile_atom_parsers(atoms)
    parsed = 0
    for atom in atoms
        try
            document = atom.make_document()
            extension = get_natural_extension(document)
            format = Symbol(SubString(extension, 2))
            has_natural_parser(format) || continue
            parse_natural_text(format, print_natural_text(document))
            parsed += 1
        catch
            # As above: not the place a failure is meant to surface.
        end
    end
    parsed
end

"""
    precompile_workload(level::Symbol = :minimal; atoms = atomic_documents()) -> Nothing

The body a leaf package's `@compile_workload` calls. It is an ordinary function
rather than code inside the macro, so the same definition serves the REPL leaf
and the executable, and so it can be called and timed without a rebuild.

It runs the atoms, their parsers and their stub walks — everything this package
can reach. There are no levels: they graded build time against the first click,
and a recording settles that trade, so a build now either replays a recorded
list or runs this. See `ProjecturedRepl.WORKLOAD`.

The workload must *run* the pipeline: the chain is lazy, printing builds thunks,
and a sweep of `precompile` over the method table reached under half the render
for twice the build cost. See the module comment above.
"""
function precompile_workload(; atoms = atomic_documents())
    precompile_atoms(atoms)
    precompile_atom_parsers(atoms)
    nothing
end

# There is deliberately no `@compile_workload` here. A package image is built
# with exactly that package's dependencies present, so code compiled into this
# one is invalidated as soon as a session loads anything above it — measured at
# 3.9 s of `recompile_time` on a first paint, and at 1.15 s on a bare render of
# one JSON document. The workload therefore runs in a leaf: `ProjecturedRepl`
# for a session, and the package that a build writes for a binary. A leaf calls
# a workload function, which is why this is a function rather than a macro body.
