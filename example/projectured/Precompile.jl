# Fragment of `ProjecturedExample` — the atoms of the catalog, printed and parsed
# once each.
#
# The atomic document registry holds one minimal document per node type, so a
# walk over it reaches each pair of a printer and a node type. The catalog
# coverage test uses these walks to check that each atom renders and parses.

"""
    precompile_atoms(atoms; projection = NaturalToGraphics(…)) -> Int

Print every atom through `projection` and force the result, returning how many
rendered without error. `test_natural_renders_every_atom` uses it, so that a
projection an atom cannot survive is a test failure.

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
                          projection = NaturalToGraphics(measure = FontFileMeasure()))
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
            # The count is the answer: `test_natural_renders_every_atom`
            # asserts the same loop and reports which atom broke.
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
            # As above: the count is the answer.
        end
    end
    parsed
end
