function test_clipboard_to_any()

# A reference path built from raw steps.
cpath(steps...) = foldr((s, acc) -> ConcreteReferencePath(s, acc), steps; init=EmptyReferencePath())

# A `replace_document(path, doc)` fold is a CompoundOperation whose first member is
# the ReplaceReferencedValue that writes `doc` at `path`. These read that target
# reference and written value out of the (nested) compound.
_rd_ref(rd) = rd.operations[1].reference
_rd_val(rd) = rd.operations[1].value

ctrl = Modifiers(ctrl=true)
ctrl_shift = Modifiers(ctrl=true, shift=true)

@testset "copy_document independence" begin
    orig = PrimitiveString("hi")
    cp = copy_document(orig)
    @test cp isa PrimitiveString
    @test cp.value == "hi"
    @test cp !== orig
    @test getfield(cp, :value) !== getfield(orig, :value)   # fresh Cell
    orig.value = "bye"
    @test cp.value == "hi"                                   # copy unaffected

    # Nested document + CellVector are cloned, selection is reset.
    coll = ClipboardCollection(PrimitiveString("root");
                               elements=[PrimitiveString("a"), PrimitiveString("b")])
    coll.selection = cpath(FieldReference("content"))
    cc = copy_document(coll)
    @test length(cc.elements) == 2
    @test cc.elements[1].value == "a"
    @test cc.selection === nothing                           # selection reset
    coll.elements[1].value = "X"
    @test cc.elements[1].value == "a"                        # independent
end

@testset "slice printer display toggle" begin
    content = PrimitiveString("hello")
    stored  = PrimitiveString("stored")
    slice = ClipboardSlice(content; slice=stored)

    p = ClipboardSliceToAnyProjection()
    iomap = projection_print(p, PreservingProjection(), slice, PrinterContext())
    @test iomap.output[] === content                         # content shown by default (reactive output cell)

    ps = ClipboardSliceToAnyProjection(display_slice=true)
    iomap_s = projection_print(ps, PreservingProjection(), slice, PrinterContext())
    @test iomap_s.output[] === stored                        # slice shown when toggled

    # The output cell re-derives reactively when display_slice flips — no re-print.
    p.display_slice[] = true
    @test iomap.output[] === stored
    p.display_slice[] = false
    @test iomap.output[] === content
end

@testset "slice reference mapping" begin
    content = PrimitiveString("hello")
    slice = ClipboardSlice(content)
    p = ClipboardSliceToAnyProjection()
    iomap = projection_print(p, PreservingProjection(), slice, PrinterContext())

    back = map_reference_backward(p, iomap, EmptyReferencePath())
    @test back isa ConcreteReferencePath
    @test back.head.name == "content"

    fwd = map_reference_forward(p, iomap, cpath(FieldReference("content")))
    @test fwd isa EmptyReferencePath
end

@testset "slice reader gestures" begin
    content = PrimitiveString("hello")
    slice = ClipboardSlice(content)
    slice.selection = cpath(FieldReference("content"))
    p = ClipboardSliceToAnyProjection()
    iomap = projection_print(p, PreservingProjection(), slice, PrinterContext())

    # Toggle
    op = projection_read(p, iomap, KeyDown(:slash, ctrl))
    @test op isa ToggleClipboardSliceDisplayOperation
    @test op.projection === p

    # Copy — writes a fresh deep copy into the slice, then restores the
    # original selection (the write would otherwise move it to .slice).
    op = projection_read(p, iomap, KeyDown(:c, ctrl))
    @test op isa CompoundOperation
    @test length(op.operations) == 2
    @test op.operations[1] isa CompoundOperation                # folded replace_document
    @test _rd_ref(op.operations[1]).head.name == "slice"
    @test _rd_val(op.operations[1]) isa PrimitiveString
    @test _rd_val(op.operations[1]).value == "hello"
    @test _rd_val(op.operations[1]) !== content                 # deep copy
    @test op.operations[2] isa ReplaceSelectionOperation
    @test op.operations[2].path == cpath(FieldReference("content"))

    # Note — stores the live object, then restores the original selection.
    op = projection_read(p, iomap, KeyDown(:n, ctrl))
    @test op isa CompoundOperation
    @test op.operations[1] isa CompoundOperation
    @test _rd_val(op.operations[1]) === content
    @test op.operations[2] isa ReplaceSelectionOperation
    @test op.operations[2].path == cpath(FieldReference("content"))

    # Cut — compound of (store live) + (blank source).
    op = projection_read(p, iomap, KeyDown(:x, ctrl))
    @test op isa CompoundOperation
    @test length(op.operations) == 2
    @test op.operations[1] isa CompoundOperation
    @test _rd_ref(op.operations[1]).head.name == "slice"
    @test _rd_val(op.operations[1]) === content
    @test op.operations[2] isa CompoundOperation
    @test _rd_ref(op.operations[2]).head.name == "content"
    @test _rd_val(op.operations[2]) isa DocumentNothing
end

@testset "slice reader paste" begin
    content = PrimitiveString("hello")
    stored  = PrimitiveString("stored")
    slice = ClipboardSlice(content; slice=stored)
    slice.selection = cpath(FieldReference("content"))
    p = ClipboardSliceToAnyProjection()
    iomap = projection_print(p, PreservingProjection(), slice, PrinterContext())

    # Paste — replaces the selection target with the live slice, then pins the
    # selection to the pasted target.
    op = projection_read(p, iomap, KeyDown(:v, ctrl))
    @test op isa CompoundOperation
    @test op.operations[1] isa CompoundOperation
    @test _rd_ref(op.operations[1]).head.name == "content"
    @test _rd_val(op.operations[1]) === stored
    @test op.operations[2] isa ReplaceSelectionOperation
    @test op.operations[2].path == cpath(FieldReference("content"))

    # Paste copy — a fresh deep copy each time.
    op = projection_read(p, iomap, KeyDown(:v, ctrl_shift))
    @test op isa CompoundOperation
    @test op.operations[1] isa CompoundOperation
    @test _rd_val(op.operations[1]) !== stored
    @test _rd_val(op.operations[1]).value == "stored"
    @test op.operations[2] isa ReplaceSelectionOperation

    # Paste with no stored slice does not fire: it falls through to the content
    # reader (matching Lisp's merge-commands). With no replace produced here, the
    # clipboard does not emit a paste compound.
    empty_slice = ClipboardSlice(PrimitiveString("x"))
    empty_slice.selection = cpath(FieldReference("content"))
    pe = ClipboardSliceToAnyProjection()
    iomap_e = projection_print(pe, PreservingProjection(), empty_slice, PrinterContext())
    @test !(projection_read(pe, iomap_e, KeyDown(:v, ctrl)) isa CompoundOperation)
end

@testset "collection printer display toggle" begin
    content = PrimitiveString("root")
    coll = ClipboardCollection(content; elements=[PrimitiveString("a"), PrimitiveString("b")])

    p = ClipboardCollectionToAnyProjection()
    iomap = projection_print(p, PreservingProjection(), coll, PrinterContext())
    @test iomap.output[] === content                         # content shown by default (reactive output cell)

    pc = ClipboardCollectionToAnyProjection(display_collection=true)
    iomap_c = projection_print(pc, PreservingProjection(), coll, PrinterContext())
    cv = iomap_c.output[]
    @test cv isa CellVector
    @test length(cv) == 2
    @test cv[1].value == "a"
    @test cv[2].value == "b"

    # The output cell re-derives reactively when display_collection flips.
    p.display_collection[] = true
    @test iomap.output[] isa CellVector
    p.display_collection[] = false
    @test iomap.output[] === content
end

@testset "collection reader gestures" begin
    content = PrimitiveString("root")
    coll = ClipboardCollection(content; elements=[PrimitiveString("a"), PrimitiveString("b")])
    p = ClipboardCollectionToAnyProjection()
    iomap = projection_print(p, PreservingProjection(), coll, PrinterContext())

    # Toggle
    op = projection_read(p, iomap, KeyDown(:asterisk, ctrl))
    @test op isa ToggleClipboardCollectionDisplayOperation
    @test op.projection === p

    # Add — inserts the selected object at the front of `elements`.
    coll.selection = cpath(FieldReference("content"))
    op = projection_read(p, iomap, KeyDown(:equals, ctrl))
    @test op isa ReplaceReferencedValue                     # insert_elements splice
    @test op.reference.head.name == "elements"
    @test op.reference.tail.head isa RangeReference && op.reference.tail.head.start == 0
    @test op.value[1] === content

    # Remove — deletes the selected element (0-based index → RangeReference start).
    coll.selection = cpath(FieldReference("elements"), ElementReference(2))
    op = projection_read(p, iomap, KeyDown(:minus, ctrl))
    @test op isa ReplaceReferencedValue                     # delete_elements splice
    @test op.reference.head.name == "elements"
    @test op.reference.tail.head isa RangeReference && op.reference.tail.head.start == 1
    @test isempty(op.value)

    # Remove with a non-element selection does not delete: it falls through to
    # the content reader rather than emitting a splice.
    coll.selection = cpath(FieldReference("content"))
    @test !(projection_read(p, iomap, KeyDown(:minus, ctrl)) isa ReplaceReferencedValue)
end

end # test_clipboard_to_any
