# The testers of the catalog of atomic examples, as functions of a list of
# examples and of a list of atoms, so that the test package of any repository
# runs them on its own atoms: the printer, the reader, the REPL loop, the
# navigation and the click test on each example, and the guard that each document
# type with a printer has an atom.

# The terminals of the examples that a tester applies to, or `nothing` for every
# example. The navigation moves the caret by the geometry that only the graphics
# compute; the click test presses the editor that the app builds, so it takes the
# variant of the app.
_get_catalog_terminals(tester) = nothing
_get_catalog_terminals(::typeof(test_position_navigation)) = (:graphics, :natural)
_get_catalog_terminals(::typeof(test_part_click)) = (:natural,)

_is_catalog_tester_for(tester, example) =
    (terminals = _get_catalog_terminals(tester); terminals === nothing || example.terminal in terminals)

# The mark of a kind of known failure for the example `name`, or `nothing`.
_get_catalog_mark(marks, kind::Symbol, name) = haskey(marks, kind) ? marks[kind](name) : nothing

_run_catalog_tester(::typeof(test_printer), example, marks) =
    test_printer(example.name, example.make_document(), example.make_projection();
                 broken = _get_catalog_mark(marks, :print, example.name))
_run_catalog_tester(::typeof(test_reader), example, marks) =
    test_reader(example.name, example.make_document(), example.make_projection();
                broken = _get_catalog_mark(marks, :edit, example.name))
_run_catalog_tester(::typeof(test_repl), example, marks) =
    test_repl(example.name, example.make_document(), example.make_projection();
              broken = _get_catalog_mark(marks, :edit, example.name))
_run_catalog_tester(::typeof(test_position_navigation), example, marks) =
    test_position_navigation(example.name, example.make_document(), example.make_projection();
                             seed_broken = _get_catalog_mark(marks, :seed, example.name),
                             throws_broken = _get_catalog_mark(marks, :throws, example.name),
                             broken = _get_catalog_mark(marks, :state, example.name))
_run_catalog_tester(::typeof(test_part_click), example, marks) =
    test_part_click(example; broken = _get_catalog_mark(marks, :click, example.name))
_run_catalog_tester(tester, example, marks) = tester(example)

"""
    CATALOG_TESTERS

The testers that `test_catalog_examples` runs by default: the printer, the
reader, the REPL loop and the navigation.
"""
const CATALOG_TESTERS = (test_printer, test_reader, test_repl, test_position_navigation)

"""
    test_catalog_examples(examples; testers = CATALOG_TESTERS, marks = (;))

Run each tester of `testers` that applies to an example on it, in a test set for
each example. A tester applies by the terminal of the example: the navigation to
the variants that draw graphics, the click test (`test_part_click`) to the
variant of the app, `:natural`, and the others to every variant.

`marks` names the known failures: a field `print`, `edit`, `seed`, `throws`,
`state` or `click` is a function of the name of an example that answers the
predicate of the failures to mark broken there, or `nothing`. A failure that
no mark names is a failure.
"""
function test_catalog_examples(examples; testers = CATALOG_TESTERS, marks = (;))
    @testset "Catalog" begin
        for example in examples
            @testset "$(example.name)" begin
                for tester in testers
                    _is_catalog_tester_for(tester, example) && _run_catalog_tester(tester, example, marks)
                end
            end
        end
    end
end

# ── The guard: each document type with a printer has an atom ───────────────────

# The stem type behind a printer's document parameter: `JuliaFunction` from
# `JuliaFunction{C1,…,C6}`, so a printer declared on the UnionAll and an atom
# built as a concrete instance compare equal.
function _get_coverage_stem(type)
    body = type isa UnionAll ? Base.unwrap_unionall(type) : type
    body isa DataType ? Base.typename(body).wrapper : nothing
end

# Whether `type` belongs to a module under one of `roots`, and not to a test
# package, whose fixtures exist only while the tests are loaded.
function _is_coverage_type(type, roots)
    body = type isa UnionAll ? Base.unwrap_unionall(type) : type
    body isa DataType || return false
    root = string(Base.moduleroot(parentmodule(body)))
    any(prefix -> startswith(root, prefix), roots) && !endswith(root, "Test")
end

# The document types that a printer of a module under `roots` prints. A Base
# type, an abstract type and a value that is no document, such as a reference
# or a cell, need no atom: a concrete document of the set prints them.
function _collect_coverage_types(roots)
    wanted = Set{Any}()
    for method in methods(ProjecturedKernel.ProjectionModule.print_document)
        signature = Base.unwrap_unionall(method.sig)
        length(signature.parameters) == 5 || continue
        projection, document = signature.parameters[2], signature.parameters[4]
        (projection isa DataType && isconcretetype(projection)) || continue
        document === Any && continue
        stem = _get_coverage_stem(document)
        (stem === nothing || !_is_coverage_type(stem, roots)) && continue
        body = stem isa UnionAll ? Base.unwrap_unionall(stem) : stem
        (body isa DataType && isabstracttype(body)) && continue
        body <: ProjecturedKernel.DocumentModule.Document || continue
        push!(wanted, stem)
    end
    wanted
end

# The name that a type counts under: the schema of a document, so a printer
# declared on a layout of a document, such as `ACTaskExecution`, and an atom built
# in another layout of it count as the one document `TaskExecution`.
_get_coverage_name(type) = string(ProjecturedKernel.DocumentModule.get_document_schema_name(type))

"""
    find_catalog_coverage_gap(atoms; roots) -> Vector{String}

The names of the document types that a printer of a module under one of `roots`,
such as `"Projectured"` or `"Omnet"`, prints and that no atom of `atoms` makes,
in order.
"""
function find_catalog_coverage_gap(atoms; roots)
    covered = Set{String}()
    for atom in atoms
        stem = try
            _get_coverage_stem(typeof(atom.make_document()))
        catch
            nothing
        end
        stem === nothing || push!(covered, _get_coverage_name(stem))
    end
    sort(collect(setdiff(Set(_get_coverage_name(type) for type in _collect_coverage_types(roots)), covered)))
end

"""
    test_atom_coverage(atoms; roots, no_atom = Set{String}())

Assert that each document type with a printer in a module under `roots` has an
atom in `atoms`, except the types of `no_atom`, which no test can make, and that
`no_atom` names no type that has an atom. While `no_atom` is not empty, the gap
is a known failure.
"""
function test_atom_coverage(atoms; roots, no_atom = Set{String}())
    @testset "catalog coverage" begin
        @test !isempty(_collect_coverage_types(roots))
        gap = Set(find_catalog_coverage_gap(atoms; roots))
        @test sort(collect(setdiff(gap, no_atom))) == String[]
        @test sort(collect(setdiff(no_atom, gap))) == String[]
        isempty(no_atom) ? (@test isempty(gap)) : (@test_broken isempty(gap))
    end
end
