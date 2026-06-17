function test_clipboard_to_any()

# A reference path built from raw steps.
cpath(steps...) = foldr((s, acc) -> ConcreteReferencePath(s, acc), steps; init=EmptyReferencePath())

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
    @test iomap.output === content                           # content shown by default

    ps = ClipboardSliceToAnyProjection(display_slice=true)
    iomap_s = projection_print(ps, PreservingProjection(), slice, PrinterContext())
    @test iomap_s.output === stored                          # slice shown when toggled
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

    # Copy — writes a fresh deep copy into the slice.
    op = projection_read(p, iomap, KeyDown(:c, ctrl))
    @test op isa ReplaceDocumentOperation
    @test op.path.head.name == "slice"
    @test op.document isa PrimitiveString
    @test op.document.value == "hello"
    @test op.document !== content                            # deep copy

    # Note — stores the live object.
    op = projection_read(p, iomap, KeyDown(:n, ctrl))
    @test op isa ReplaceDocumentOperation
    @test op.document === content

    # Cut — compound of (store live) + (blank source).
    op = projection_read(p, iomap, KeyDown(:x, ctrl))
    @test op isa CompoundOperation
    @test length(op.operations) == 2
    @test op.operations[1] isa ReplaceDocumentOperation
    @test op.operations[1].path.head.name == "slice"
    @test op.operations[1].document === content
    @test op.operations[2] isa ReplaceDocumentOperation
    @test op.operations[2].path.head.name == "content"
    @test op.operations[2].document isa DocumentNothing
end

@testset "slice reader paste" begin
    content = PrimitiveString("hello")
    stored  = PrimitiveString("stored")
    slice = ClipboardSlice(content; slice=stored)
    slice.selection = cpath(FieldReference("content"))
    p = ClipboardSliceToAnyProjection()
    iomap = projection_print(p, PreservingProjection(), slice, PrinterContext())

    # Paste — replaces the selection target with the live slice.
    op = projection_read(p, iomap, KeyDown(:v, ctrl))
    @test op isa ReplaceDocumentOperation
    @test op.path.head.name == "content"
    @test op.document === stored

    # Paste copy — a fresh deep copy each time.
    op = projection_read(p, iomap, KeyDown(:v, ctrl_shift))
    @test op isa ReplaceDocumentOperation
    @test op.document !== stored
    @test op.document.value == "stored"

    # Paste with no stored slice does not fire: it falls through to the content
    # reader (matching Lisp's merge-commands). With no replace produced here, the
    # clipboard does not emit a ReplaceDocumentOperation.
    empty_slice = ClipboardSlice(PrimitiveString("x"))
    empty_slice.selection = cpath(FieldReference("content"))
    pe = ClipboardSliceToAnyProjection()
    iomap_e = projection_print(pe, PreservingProjection(), empty_slice, PrinterContext())
    @test !(projection_read(pe, iomap_e, KeyDown(:v, ctrl)) isa ReplaceDocumentOperation)
end

@testset "collection printer display toggle" begin
    content = PrimitiveString("root")
    coll = ClipboardCollection(content; elements=[PrimitiveString("a"), PrimitiveString("b")])

    p = ClipboardCollectionToAnyProjection()
    iomap = projection_print(p, PreservingProjection(), coll, PrinterContext())
    @test iomap.output === content                           # content shown by default

    pc = ClipboardCollectionToAnyProjection(display_collection=true)
    iomap_c = projection_print(pc, PreservingProjection(), coll, PrinterContext())
    @test iomap_c.output isa CellVector
    @test length(iomap_c.output) == 2
    @test iomap_c.output[1].value == "a"
    @test iomap_c.output[2].value == "b"
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
    @test op isa CollectionInsertOperation
    @test op.path.head.name == "elements"
    @test op.index == 0
    @test op.items[1] === content

    # Remove — deletes the selected element (0-based index).
    coll.selection = cpath(FieldReference("elements"), ElementReference(2))
    op = projection_read(p, iomap, KeyDown(:minus, ctrl))
    @test op isa CollectionDeleteOperation
    @test op.path.head.name == "elements"
    @test op.index == 1

    # Remove with a non-element selection does not delete: it falls through to
    # the content reader rather than emitting a CollectionDeleteOperation.
    coll.selection = cpath(FieldReference("content"))
    @test !(projection_read(p, iomap, KeyDown(:minus, ctrl)) isa CollectionDeleteOperation)
end

end # test_clipboard_to_any
