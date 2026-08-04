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

# Read every cell the printer produced. The printer alone builds thunks; the
# compilation this file exists for happens when they are read, so a workload
# that prints without walking compiles almost nothing.
#
# An atom is minimal by construction, so walking one completely is cheap — the
# "walking the whole output is too expensive" problem belongs to real documents
# and does not arise here. The depth cap is for cyclic structure, not size.
function _force_projected(node, depth = 0)
    depth > 40 && return nothing
    node isa ProjecturedKernel.CellModule.AbstractCell &&
        return _force_projected(node[], depth)
    for f in (:elements, :content, :canvas, :children, :items)
        hasproperty(node, f) || continue
        v = getproperty(node, f)
        v isa ProjecturedKernel.CellModule.AbstractCell && (v = v[])
        if v isa AbstractVector || v isa ProjecturedBase.CollectionModule.CellVector
            for c in v
                _force_projected(c, depth + 1)
            end
        elseif v !== nothing && !(v isa AbstractString)
            _force_projected(v, depth + 1)
        end
    end
    nothing
end

"""
    precompile_atoms(atoms) -> Int

Print every atom through `NaturalToGraphics` and force the result, returning how
many rendered without error. Used by the workload below, and by
`test_natural_renders_every_atom` so that a projection an atom cannot survive is
a test failure rather than something the workload silently skips.

`NaturalToGraphics` is the projection to use rather than a per-domain chain
because it is the one that dispatches on document type across every domain,
collection, layout and widget — the same renderer an editor puts on screen. A
hand-written domain→chain table would be a second registry to keep in step with
this one.
"""
function precompile_atoms(atoms)
    projection = NaturalToGraphics(measure = truetype_measure_text)
    context = PrinterContext(EmptyReference(),
                             ProjecturedKernel.CellModule.Cell(1200),
                             ProjecturedKernel.CellModule.Cell(800),
                             Dict{Symbol,Any}())
    rendered = 0
    for atom in atoms
        try
            iomap = print_document(projection, nothing, atom.make_document(), context)
            _force_projected(get_iomap_output(iomap))
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

@setup_workload begin
    # Built outside the workload: constructing the documents is not what needs
    # compiling, and doing it here keeps the measured region to the pipeline.
    _atoms = AtomicDocument[visual_atomic_documents; domain_atomic_documents]
    @compile_workload begin
        precompile_atoms(_atoms)
    end
end
