function test_versioning_to_any()

# A reference path built from raw steps.
cpath(steps...) = foldr((s, acc) -> ConcreteReferencePath(s, acc), steps; init=EmptyReferencePath())

ctrl = ModifierKeys(ctrl=true)
ctrl_shift = ModifierKeys(ctrl=true, shift=true)

# A small versioned object: three versions, newest-first.
function make_versioned()
    v3 = ObjectVersion(PrimitiveString("v3"); timestamp=3, author="carol")
    v2 = ObjectVersion(PrimitiveString("v2"); timestamp=2, author="bob")
    v1 = ObjectVersion(PrimitiveString("v1"); timestamp=1, author="alice")
    VersionedObject([v3, v2, v1])
end

@testset "select_version criteria" begin
    vo = make_versioned()

    # Latest: newest (lowest index).
    sel = select_version(vo)
    @test sel !== nothing
    @test sel[1] == 1
    @test sel[2].value.value == "v3"

    # Index: explicit 1-based pin.
    vo.criterion = VersionCriterionIndex(2)
    sel = select_version(vo)
    @test sel[1] == 2
    @test sel[2].value.value == "v2"

    # Index out of range → nothing.
    vo.criterion = VersionCriterionIndex(9)
    @test select_version(vo) === nothing

    # By author: newest matching (lowest index).
    vo.criterion = VersionCriterionByAuthor("alice")
    sel = select_version(vo)
    @test sel[1] == 3
    @test sel[2].value.value == "v1"

    # By author with no match → nothing.
    vo.criterion = VersionCriterionByAuthor("zoe")
    @test select_version(vo) === nothing

    # As-of: newest with timestamp ≤ cutoff (lowest matching index).
    vo.criterion = VersionCriterionAsOf(2)
    sel = select_version(vo)
    @test sel[1] == 2
    @test sel[2].value.value == "v2"

    # As-of before all → nothing.
    vo.criterion = VersionCriterionAsOf(0)
    @test select_version(vo) === nothing

    # Predicate over properties.
    vo.criterion = VersionCriterionPredicate(p -> p.author == "bob")
    sel = select_version(vo)
    @test sel[1] == 2
    @test sel[2].value.value == "v2"

    # Empty versions → nothing under any criterion.
    empty_vo = VersionedObject(ObjectVersion[])
    @test select_version(empty_vo) === nothing
end

@testset "printer criterion selection" begin
    vo = make_versioned()
    p = VersioningToAnyProjection()

    # Latest: the wrapper vanishes; output is the newest version's value.
    iomap = print_document(p, IdentityProjection(), vo, PrinterContext())
    @test iomap.index == 1
    @test iomap.output isa PrimitiveString
    @test iomap.output.value == "v3"

    # Index(2): the second version's value.
    vo.criterion = VersionCriterionIndex(2)
    iomap2 = print_document(p, IdentityProjection(), vo, PrinterContext())
    @test iomap2.index == 2
    @test iomap2.output.value == "v2"
end

@testset "empty / no-match → DocumentNothing" begin
    p = VersioningToAnyProjection()

    empty_vo = VersionedObject(ObjectVersion[])
    iomap = print_document(p, IdentityProjection(), empty_vo, PrinterContext())
    @test iomap.output isa DocumentNothing
    @test iomap.index === nothing
    @test iomap.value_iomap === nothing

    # A criterion that matches nothing also yields DocumentNothing without error.
    vo = make_versioned()
    vo.criterion = VersionCriterionByAuthor("nobody")
    iomap_nm = print_document(p, IdentityProjection(), vo, PrinterContext())
    @test iomap_nm.output isa DocumentNothing

    # Reference maps decline on the empty case.
    @test map_reference_forward(p, iomap, cpath(FieldReference("versions"))) === nothing
    @test map_reference_backward(p, iomap, EmptyReferencePath()) === nothing
end

@testset "reference mapping peel / prepend" begin
    vo = make_versioned()   # Latest → index 1
    p = VersioningToAnyProjection()
    iomap = print_document(p, IdentityProjection(), vo, PrinterContext())

    # Backward: delegate to value child (IdentityProjection is identity) and
    # prepend versions[1].value.
    back = map_reference_backward(p, iomap, EmptyReferencePath())
    @test back isa ConcreteReferencePath
    @test back.head.name == "versions"
    @test back.tail.head isa RangeReference
    @test back.tail.head.start == 0          # ElementReference(1) → start 0
    @test back.tail.tail.head.name == "value"

    # Forward: strip versions[1].value and return the (identity) tail.
    fwd = map_reference_forward(p, iomap,
        cpath(FieldReference("versions"), ElementReference(1), FieldReference("value")))
    @test fwd isa EmptyReferencePath

    # Forward declines a path that does not descend through the selected version.
    @test map_reference_forward(p, iomap,
        cpath(FieldReference("versions"), ElementReference(2), FieldReference("value"))) === nothing
    @test map_reference_forward(p, iomap, cpath(FieldReference("criterion"))) === nothing
end

@testset "reader re-roots delegated value operations" begin
    vo = make_versioned()   # Latest → index 1
    p = VersioningToAnyProjection()
    iomap = print_document(p, IdentityProjection(), vo, PrinterContext())

    # A value-domain selection move flowing up from the value child is re-rooted
    # under versions[1].value (IdentityProjection passes it through unchanged).
    value_sel = ReplaceSelectionOperation(EmptyReferencePath())
    change = Intent(KeyDown(:right, ModifierKeys()), value_sel)
    out = read_intent(p, IdentityProjection(), change, iomap)
    @test out.operation isa ReplaceSelectionOperation
    rerooted = out.operation.path
    @test rerooted.head.name == "versions"
    @test rerooted.tail.head isa RangeReference
    @test rerooted.tail.head.start == 0
    @test rerooted.tail.tail.head.name == "value"

    # The empty case declines (no value child to delegate into).
    empty_vo = VersionedObject(ObjectVersion[])
    iomap_e = print_document(p, IdentityProjection(), empty_vo, PrinterContext())
    out_e = read_intent(p, IdentityProjection(),
        Intent(KeyDown(:right, ModifierKeys()), value_sel), iomap_e)
    @test out_e.operation === nothing
end

@testset "reader own gestures" begin
    vo = make_versioned()   # Latest → index 1
    p = VersioningToAnyProjection()
    iomap = print_document(p, IdentityProjection(), vo, PrinterContext())

    # Ctrl+Shift+S snapshots the active value into a new front ObjectVersion via a
    # sequence splice (insert_elements) — a ReplaceReferencedValueOperation whose terminal is
    # a zero-width RangeReference(0,0) into `versions` and whose value is the items.
    op = read_intent(p, iomap, KeyDown(:s, ctrl_shift))
    @test op isa ReplaceReferencedValueOperation
    @test op.reference.head.name == "versions"
    @test op.reference.tail.head isa RangeReference && op.reference.tail.head.start == 0
    snapshot = op.value[1]
    @test snapshot isa ObjectVersion
    @test snapshot.value isa PrimitiveString
    @test snapshot.value.value == "v3"
    @test snapshot.value !== vo.versions[1].value       # deep copy

    # Ctrl+Delete deletes the active version via a splice (delete_elements): a
    # ReplaceReferencedValueOperation with terminal RangeReference(0,1) and an empty value.
    op = read_intent(p, iomap, KeyDown(:delete, ctrl))
    @test op isa ReplaceReferencedValueOperation
    @test op.reference.head.name == "versions"
    @test op.reference.tail.head isa RangeReference && op.reference.tail.head.start == 0
    @test isempty(op.value)
end

@testset "recursion: versioned-in-versioned" begin
    # The selected value of the outer version is itself a VersionedObject; the
    # full recursive pipeline must resolve both layers, each by its own criterion.
    inner = VersionedObject([
        ObjectVersion(PrimitiveString("inner-new"); timestamp=2),
        ObjectVersion(PrimitiveString("inner-old"); timestamp=1),
    ])
    outer = VersionedObject([ObjectVersion(inner)])

    pipeline = RecursiveProjection(TypeDispatchingProjection(
        VersionedObject => VersioningToAnyProjection(),
        PrimitiveString => IdentityProjection(),
    ))
    iomap = print_document(VersioningToAnyProjection(), pipeline, outer, PrinterContext())
    # Outer eliminates to its (only) version's value = inner VersionedObject,
    # which the recursion eliminates again to its newest value.
    @test iomap.output isa PrimitiveString
    @test iomap.output.value == "inner-new"
end

end # test_versioning_to_any
