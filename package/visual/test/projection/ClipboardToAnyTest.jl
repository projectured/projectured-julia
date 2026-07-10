function test_clipboard_to_any()

# A reference path built from raw steps.
cpath(steps...) = foldr((s, acc) -> ConcreteReferencePath(s, acc), steps; init=EmptyReferencePath())

# A `replace_document(path, doc)` fold is a CompoundOperation whose first member is
# the ReplaceReferencedValueOperation that writes `doc` at `path`. These read that target
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

    # Nested document + CellVector are cloned; selection is preserved (call
    # `clear_selection!` explicitly to reset).
    coll = ClipboardCollection(PrimitiveString("root"),
                               [PrimitiveString("a"), PrimitiveString("b")])
    coll.selection = cpath(FieldReference("content"))
    cc = copy_document(coll)
    @test length(cc.elements) == 2
    @test cc.elements[1].value == "a"
    @test cc.selection !== nothing                           # selection preserved
    coll.elements[1].value = "X"
    @test cc.elements[1].value == "a"                        # independent
end

@testset "slice printer display toggle" begin
    content = PrimitiveString("hello")
    stored  = PrimitiveString("stored")
    slice = ClipboardSlice(content, stored)

    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
    @test iomap.output[] === content                         # content shown by default (reactive output cell)

    ps = ClipboardSliceToAnyProjection(display_slice=true)
    iomap_s = print_document(ps, IdentityProjection(), slice, PrinterContext())
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
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())

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
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())

    # Toggle
    op = read_intent(p, iomap, KeyDown(:slash, ctrl))
    @test op isa ToggleClipboardSliceDisplayOperation
    @test op.projection === p

    # Copy — writes a fresh deep copy into the slice, then restores the
    # original selection (the write would otherwise move it to .slice).
    op = read_intent(p, iomap, KeyDown(:c, ctrl))
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
    op = read_intent(p, iomap, KeyDown(:n, ctrl))
    @test op isa CompoundOperation
    @test op.operations[1] isa CompoundOperation
    @test _rd_val(op.operations[1]) === content
    @test op.operations[2] isa ReplaceSelectionOperation
    @test op.operations[2].path == cpath(FieldReference("content"))

    # Cut — compound of (store live) + (blank source).
    op = read_intent(p, iomap, KeyDown(:x, ctrl))
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
    slice = ClipboardSlice(content, stored)
    slice.selection = cpath(FieldReference("content"))
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())

    # Paste — replaces the selection target with the live slice, then pins the
    # selection to the pasted target.
    op = read_intent(p, iomap, KeyDown(:v, ctrl))
    @test op isa CompoundOperation
    @test op.operations[1] isa CompoundOperation
    @test _rd_ref(op.operations[1]).head.name == "content"
    @test _rd_val(op.operations[1]) === stored
    @test op.operations[2] isa ReplaceSelectionOperation
    @test op.operations[2].path == cpath(FieldReference("content"))

    # Paste copy — a fresh deep copy each time.
    op = read_intent(p, iomap, KeyDown(:v, ctrl_shift))
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
    iomap_e = print_document(pe, IdentityProjection(), empty_slice, PrinterContext())
    @test !(read_intent(pe, iomap_e, KeyDown(:v, ctrl)) isa CompoundOperation)
end

@testset "collection printer display toggle" begin
    content = PrimitiveString("root")
    coll = ClipboardCollection(content, [PrimitiveString("a"), PrimitiveString("b")])

    p = ClipboardCollectionToAnyProjection()
    iomap = print_document(p, IdentityProjection(), coll, PrinterContext())
    @test iomap.output[] === content                         # content shown by default (reactive output cell)

    pc = ClipboardCollectionToAnyProjection(display_collection=true)
    iomap_c = print_document(pc, IdentityProjection(), coll, PrinterContext())
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
    coll = ClipboardCollection(content, [PrimitiveString("a"), PrimitiveString("b")])
    p = ClipboardCollectionToAnyProjection()
    iomap = print_document(p, IdentityProjection(), coll, PrinterContext())

    # Toggle
    op = read_intent(p, iomap, KeyDown(:asterisk, ctrl))
    @test op isa ToggleClipboardCollectionDisplayOperation
    @test op.projection === p

    # Add — inserts the selected object at the front of `elements`.
    coll.selection = cpath(FieldReference("content"))
    op = read_intent(p, iomap, KeyDown(:equals, ctrl))
    @test op isa ReplaceReferencedValueOperation                     # insert_elements splice
    @test op.reference.head.name == "elements"
    @test op.reference.tail.head isa RangeReference && op.reference.tail.head.start == 0
    @test op.value[1] === content

    # Remove — deletes the selected element (0-based index → RangeReference start).
    coll.selection = cpath(FieldReference("elements"), ElementReference(2))
    op = read_intent(p, iomap, KeyDown(:minus, ctrl))
    @test op isa ReplaceReferencedValueOperation                     # delete_elements splice
    @test op.reference.head.name == "elements"
    @test op.reference.tail.head isa RangeReference && op.reference.tail.head.start == 1
    @test isempty(op.value)

    # Remove with a non-element selection does not delete: it falls through to
    # the content reader rather than emitting a splice.
    coll.selection = cpath(FieldReference("content"))
    @test !(read_intent(p, iomap, KeyDown(:minus, ctrl)) isa ReplaceReferencedValueOperation)
end

@testset "slice OS clipboard bridge" begin
    # An in-memory fake OS clipboard (CI has no xclip/xsel/wl-*). The try/finally
    # restores the real shell-out backend afterwards.
    buf = Ref("")
    set_os_clipboard_backend!(read = () -> buf[], write = t -> (buf[] = String(t); true))
    try
        to_text   = d -> d isa PrimitiveString ? d.value : nothing
        from_text = t -> PrimitiveString(String(t))

        # Copy mirrors the selected object's text out to the OS clipboard via a
        # trailing WriteOsClipboardOperation; evaluating it performs the write.
        content = PrimitiveString("hello")
        slice = ClipboardSlice(content)
        slice.selection = cpath(FieldReference("content"))
        p = ClipboardSliceToAnyProjection(to_text=to_text, from_text=from_text)
        iomap = print_document(p, IdentityProjection(), slice, PrinterContext())

        op = read_intent(p, iomap, KeyDown(:c, ctrl))
        @test op isa CompoundOperation
        @test op.operations[end] isa WriteOsClipboardOperation
        @test op.operations[end].text == "hello"
        evaluate_operation(nothing, op.operations[end])
        @test buf[] == "hello"                                   # mirrored to OS

        # Cut also mirrors out (and still blanks the source).
        buf[] = ""
        op = read_intent(p, iomap, KeyDown(:x, ctrl))
        @test op.operations[end] isa WriteOsClipboardOperation
        evaluate_operation(nothing, op.operations[end])
        @test buf[] == "hello"

        # Paste with an EMPTY internal slice falls back to the OS clipboard,
        # converting its text via from_text.
        buf[] = "from-os"
        empty = ClipboardSlice(PrimitiveString("x"))
        empty.selection = cpath(FieldReference("content"))
        iomap_e = print_document(p, IdentityProjection(), empty, PrinterContext())
        op = read_intent(p, iomap_e, KeyDown(:v, ctrl))
        @test op isa CompoundOperation
        @test _rd_val(op.operations[1]) isa PrimitiveString
        @test _rd_val(op.operations[1]).value == "from-os"
        @test op.operations[2] isa ReplaceSelectionOperation

        # Without a from_text converter, empty-slice paste still declines (today's
        # behavior — no OS read happens at all).
        pn = ClipboardSliceToAnyProjection()                     # converters nothing
        iomap_n = print_document(pn, IdentityProjection(), empty, PrinterContext())
        @test !(read_intent(pn, iomap_n, KeyDown(:v, ctrl)) isa CompoundOperation)

        # A failed/empty OS read (nothing) declines gracefully rather than erroring.
        set_os_clipboard_backend!(read = () -> nothing, write = t -> false)
        @test !(read_intent(p, iomap_e, KeyDown(:v, ctrl)) isa CompoundOperation)

        # Copy with no to_text converter emits no WriteOsClipboardOperation.
        p2 = ClipboardSliceToAnyProjection()
        iomap2 = print_document(p2, IdentityProjection(), slice, PrinterContext())
        op = read_intent(p2, iomap2, KeyDown(:c, ctrl))
        @test op isa CompoundOperation
        @test !any(o -> o isa WriteOsClipboardOperation, op.operations)
    finally
        reset_os_clipboard_backend!()
    end
end

@testset "slice text clipboard" begin
    # text mode: copy/cut/paste move character ranges over a TextText content; the
    # slice stores a TextString and the OS clipboard mirrors/falls back.
    buf = Ref("")
    set_os_clipboard_backend!(read = () -> buf[], write = t -> (buf[] = String(t); true))
    try
        # "world" = chars 6..11 (0-based boundaries) in span 1 of "hello world".
        trange = cpath(FieldReference("elements"), RangeReference(0, 1),
                       FieldReference("content"), RangeReference(6, 11))
        mkslice(; stored=nothing) = begin
            content = TextText(TextString("hello world"))
            content.selection = trange
            s = ClipboardSlice(content, stored)
            s.selection = ConcreteReferencePath(FieldReference("content"), trange)
            s
        end
        p = ClipboardSliceToAnyProjection(text=true)

        # Copy: stores the substring as a TextString in the slice and mirrors to OS.
        s = mkslice()
        iom = print_document(p, IdentityProjection(), s, PrinterContext())
        op = read_intent(p, iom, KeyDown(:c, ctrl))
        @test op isa CompoundOperation
        @test _rd_val(op.operations[1]) isa TextString
        @test _rd_val(op.operations[1]).content == "world"
        @test op.operations[end] isa WriteOsClipboardOperation
        @test op.operations[end].text == "world"
        evaluate_operation(nothing, op.operations[end])
        @test buf[] == "world"

        # Cut: stores the substring + a delete (ReplaceStringRangeOperation "") rooted
        # under content + OS mirror.
        s = mkslice()
        iom = print_document(p, IdentityProjection(), s, PrinterContext())
        op = read_intent(p, iom, KeyDown(:x, ctrl))
        @test op isa CompoundOperation
        @test _rd_val(op.operations[1]) isa TextString
        del = op.operations[2]
        @test del isa ReplaceStringRangeOperation
        @test del.replacement == ""
        @test del.reference.head.name == "content"
        @test op.operations[end] isa WriteOsClipboardOperation

        # Paste from the projectured slice: a content-rooted ReplaceStringRangeOperation
        # splicing the stored text over the selected range.
        s = mkslice(stored = TextString("ZZZ"))
        iom = print_document(p, IdentityProjection(), s, PrinterContext())
        op = read_intent(p, iom, KeyDown(:v, ctrl))
        @test op isa ReplaceStringRangeOperation
        @test op.replacement == "ZZZ"
        @test op.reference.head.name == "content"

        # Paste with an empty slice falls back to the OS clipboard text.
        buf[] = "OSPASTE"
        s = mkslice()                                   # no stored slice
        iom = print_document(p, IdentityProjection(), s, PrinterContext())
        op = read_intent(p, iom, KeyDown(:v, ctrl))
        @test op isa ReplaceStringRangeOperation
        @test op.replacement == "OSPASTE"

        # An empty caret (no range) declines copy.
        content = TextText(TextString("hello world"))
        content.selection = cpath(FieldReference("elements"), RangeReference(0, 1),
                                  FieldReference("content"), RangeReference(3, 3))
        sc = ClipboardSlice(content)
        sc.selection = ConcreteReferencePath(FieldReference("content"),
            cpath(FieldReference("elements"), RangeReference(0, 1),
                  FieldReference("content"), RangeReference(3, 3)))
        iom = print_document(p, IdentityProjection(), sc, PrinterContext())
        # Declines (no range): no copy compound is produced — it falls through to the
        # content child, which echoes the event rather than a clipboard operation.
        @test !(read_intent(p, iom, KeyDown(:c, ctrl)) isa CompoundOperation)
    finally
        reset_os_clipboard_backend!()
    end
end

end # test_clipboard_to_any
