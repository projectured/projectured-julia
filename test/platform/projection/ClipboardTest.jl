# Documents for the paste rules: a record that refuses a pasted document, a pair
# that holds one, and a document whose field cell takes only a primitive string.
@document struct _ClipboardRecord <: Document
    item::Any
end
DomainModule.accepts_pasted_document(::_ClipboardRecord) = false
DomainModule.accepts_pasted_text(::_ClipboardRecord) = false

@document struct _ClipboardPair <: Document
    left::Any
    right::Any
end

@document MutableCell struct _ClipboardTyped <: Document
    label::PrimitiveString
end

# A tool: it refuses a paste, and its kind declares a duplicate.
@document struct _ClipboardTool <: Document
    item::Any
end
DomainModule.accepts_pasted_document(::_ClipboardTool) = false
DocumentModule.has_document_duplicate(::_ClipboardTool) = true

# A frame around a document: a copy or a note of the frame takes what it shows.
@document struct _ClipboardFrame <: Document
    shown::Any
end
ProjecturedPlatform.ClipboardModule.find_clipboard_document(frame::_ClipboardFrame) = frame.shown

# A document that only another of its kind may replace.
@document struct _ClipboardKeeper <: Document
    value::Any
end
DomainModule.accepts_pasted_replacement(::_ClipboardKeeper, value) = value isa _ClipboardKeeper

function test_clipboard()

# A reference path built from raw steps.
cpath(steps...) = foldr((s, acc) -> ConcreteReference(s, acc), steps; init=EmptyReference())

# A `replace_document(path, doc)` fold is a CompoundOperation whose first member is
# the ReplaceReferencedValueOperation that writes `doc` at `path`. These read that target
# reference and written value out of the (nested) compound.
_rd_ref(rd) = rd.operations[1].reference
_rd_val(rd) = rd.operations[1].value

ctrl = ModifierKeys(ctrl=true)
ctrl_shift = ModifierKeys(ctrl=true, shift=true)

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
    coll.selection = cpath(FieldReferenceStep("content"))
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
    @test iomap.output === content                         # content shown by default (reactive output cell)

    ps = ClipboardSliceToAnyProjection(display_slice=true)
    iomap_s = print_document(ps, IdentityProjection(), slice, PrinterContext())
    @test iomap_s.output === stored                        # slice shown when toggled

    # The output cell re-derives reactively when display_slice flips — no re-print.
    p.display_slice[] = true
    @test iomap.output === stored
    p.display_slice[] = false
    @test iomap.output === content
end

@testset "slice reference mapping" begin
    content = PrimitiveString("hello")
    slice = ClipboardSlice(content)
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())

    back = map_reference_backward(p, iomap, EmptyReference())
    @test back isa ConcreteReference
    @test back.head.name == "content"

    fwd = map_reference_forward(p, iomap, cpath(FieldReferenceStep("content")))
    @test fwd isa EmptyReference
end

@testset "slice reader gestures" begin
    content = PrimitiveString("hello")
    slice = ClipboardSlice(content)
    slice.selection = cpath(FieldReferenceStep("content"))
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())

    # Toggle
    op = read_intent(p, iomap, KeyDown(:slash, ctrl; time = 0.0))
    @test op isa ToggleClipboardSliceOperation
    @test op.projection === p

    # Copy — writes a fresh deep copy into the slice, then restores the
    # original selection (the write would otherwise move it to .slice).
    op = read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0))
    @test op isa CompoundOperation
    @test length(op.operations) == 2
    @test op.operations[1] isa CompoundOperation                # folded replace_document
    @test _rd_ref(op.operations[1]).head.name == "slice"
    @test _rd_val(op.operations[1]) isa PrimitiveString
    @test _rd_val(op.operations[1]).value == "hello"
    @test _rd_val(op.operations[1]) !== content                 # deep copy
    @test op.operations[2] isa ReplaceSelectionOperation
    @test op.operations[2].path == cpath(FieldReferenceStep("content"))

    # Note — stores the live object, then restores the original selection.
    op = read_intent(p, iomap, KeyDown(:n, ctrl; time = 0.0))
    @test op isa CompoundOperation
    @test op.operations[1] isa CompoundOperation
    @test _rd_val(op.operations[1]) === content
    @test op.operations[2] isa ReplaceSelectionOperation
    @test op.operations[2].path == cpath(FieldReferenceStep("content"))

    # Cut — compound of (store live) + (blank source).
    op = read_intent(p, iomap, KeyDown(:x, ctrl; time = 0.0))
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
    slice.selection = cpath(FieldReferenceStep("content"))
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())

    # Paste — replaces the selection target with the live slice, then pins the
    # selection to the pasted target.
    op = read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0))
    @test op isa CompoundOperation
    @test op.operations[1] isa CompoundOperation
    @test _rd_ref(op.operations[1]).head.name == "content"
    @test _rd_val(op.operations[1]) === stored
    @test op.operations[2] isa ReplaceSelectionOperation
    @test op.operations[2].path == cpath(FieldReferenceStep("content"))

    # Paste copy — a fresh deep copy each time.
    op = read_intent(p, iomap, KeyDown(:v, ctrl_shift; time = 0.0))
    @test op isa CompoundOperation
    @test op.operations[1] isa CompoundOperation
    @test _rd_val(op.operations[1]) !== stored
    @test _rd_val(op.operations[1]).value == "stored"
    @test op.operations[2] isa ReplaceSelectionOperation

    # Paste with no stored slice does not fire: it falls through to the content
    # reader (matching Lisp's merge-commands). With no replace produced here, the
    # clipboard does not emit a paste compound.
    empty_slice = ClipboardSlice(PrimitiveString("x"))
    empty_slice.selection = cpath(FieldReferenceStep("content"))
    pe = ClipboardSliceToAnyProjection()
    iomap_e = print_document(pe, IdentityProjection(), empty_slice, PrinterContext())
    @test !(read_intent(pe, iomap_e, KeyDown(:v, ctrl; time = 0.0)) isa CompoundOperation)
end

@testset "collection printer display toggle" begin
    content = PrimitiveString("root")
    coll = ClipboardCollection(content, [PrimitiveString("a"), PrimitiveString("b")])

    p = ClipboardCollectionToAnyProjection()
    iomap = print_document(p, IdentityProjection(), coll, PrinterContext())
    @test iomap.output === content                         # content shown by default (reactive output cell)

    pc = ClipboardCollectionToAnyProjection(display_collection=true)
    iomap_c = print_document(pc, IdentityProjection(), coll, PrinterContext())
    cv = iomap_c.output
    @test cv isa CellVector
    @test length(cv) == 2
    @test cv[1].value == "a"
    @test cv[2].value == "b"

    # The output cell re-derives reactively when display_collection flips.
    p.display_collection[] = true
    @test iomap.output isa CellVector
    p.display_collection[] = false
    @test iomap.output === content
end

@testset "collection reader gestures" begin
    content = PrimitiveString("root")
    coll = ClipboardCollection(content, [PrimitiveString("a"), PrimitiveString("b")])
    p = ClipboardCollectionToAnyProjection()
    iomap = print_document(p, IdentityProjection(), coll, PrinterContext())

    # Toggle
    op = read_intent(p, iomap, KeyDown(:asterisk, ctrl; time = 0.0))
    @test op isa ToggleClipboardCollectionOperation
    @test op.projection === p

    # Add — inserts the selected object at the front of `elements`.
    coll.selection = cpath(FieldReferenceStep("content"))
    op = read_intent(p, iomap, KeyDown(:equals, ctrl; time = 0.0))
    @test op isa ReplaceReferencedValueOperation                     # insert_elements splice
    @test op.reference.head.name == "elements"
    @test op.reference.tail.head isa RangeReferenceStep && op.reference.tail.head.start == 0
    @test op.value[1] === content

    # Remove — deletes the selected element (0-based index → RangeReferenceStep start).
    coll.selection = cpath(FieldReferenceStep("elements"), ElementReferenceStep(2))
    op = read_intent(p, iomap, KeyDown(:minus, ctrl; time = 0.0))
    @test op isa ReplaceReferencedValueOperation                     # delete_elements splice
    @test op.reference.head.name == "elements"
    @test op.reference.tail.head isa RangeReferenceStep && op.reference.tail.head.start == 1
    @test isempty(op.value)

    # Remove with a non-element selection does not delete: it falls through to
    # the content reader rather than emitting a splice.
    coll.selection = cpath(FieldReferenceStep("content"))
    @test !(read_intent(p, iomap, KeyDown(:minus, ctrl; time = 0.0)) isa ReplaceReferencedValueOperation)
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
        slice.selection = cpath(FieldReferenceStep("content"))
        p = ClipboardSliceToAnyProjection(to_text=to_text, from_text=from_text)
        iomap = print_document(p, IdentityProjection(), slice, PrinterContext())

        op = read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0))
        @test op isa CompoundOperation
        @test op.operations[end] isa WriteOsClipboardOperation
        @test op.operations[end].text == "hello"
        evaluate_operation(nothing, op.operations[end])
        @test buf[] == "hello"                                   # mirrored to OS

        # Cut also mirrors out (and still blanks the source).
        buf[] = ""
        op = read_intent(p, iomap, KeyDown(:x, ctrl; time = 0.0))
        @test op.operations[end] isa WriteOsClipboardOperation
        evaluate_operation(nothing, op.operations[end])
        @test buf[] == "hello"

        # Paste with an EMPTY internal slice falls back to the OS clipboard,
        # converting its text via from_text.
        buf[] = "from-os"
        empty = ClipboardSlice(PrimitiveString("x"))
        empty.selection = cpath(FieldReferenceStep("content"))
        iomap_e = print_document(p, IdentityProjection(), empty, PrinterContext())
        op = read_intent(p, iomap_e, KeyDown(:v, ctrl; time = 0.0))
        @test op isa CompoundOperation
        @test _rd_val(op.operations[1]) isa PrimitiveString
        @test _rd_val(op.operations[1]).value == "from-os"
        @test op.operations[2] isa ReplaceSelectionOperation

        # Without a from_text converter, empty-slice paste still declines (today's
        # behavior — no OS read happens at all).
        pn = ClipboardSliceToAnyProjection()                     # converters nothing
        iomap_n = print_document(pn, IdentityProjection(), empty, PrinterContext())
        @test !(read_intent(pn, iomap_n, KeyDown(:v, ctrl; time = 0.0)) isa CompoundOperation)

        # A failed/empty OS read (nothing) declines gracefully rather than erroring.
        set_os_clipboard_backend!(read = () -> nothing, write = t -> false)
        @test !(read_intent(p, iomap_e, KeyDown(:v, ctrl; time = 0.0)) isa CompoundOperation)

        # Copy with no to_text converter emits no WriteOsClipboardOperation.
        p2 = ClipboardSliceToAnyProjection()
        iomap2 = print_document(p2, IdentityProjection(), slice, PrinterContext())
        op = read_intent(p2, iomap2, KeyDown(:c, ctrl; time = 0.0))
        @test op isa CompoundOperation
        @test !any(o -> o isa WriteOsClipboardOperation, op.operations)
    finally
        reset_os_clipboard_backend!()
    end
end

@testset "slice text clipboard" begin
    # text mode: copy/cut/paste move character ranges over a TextBlock content; the
    # slice stores a TextString and the OS clipboard mirrors/falls back.
    buf = Ref("")
    set_os_clipboard_backend!(read = () -> buf[], write = t -> (buf[] = String(t); true))
    try
        # "world" = chars 6..11 (0-based boundaries) in span 1 of "hello world".
        trange = cpath(FieldReferenceStep("elements"), RangeReferenceStep(0, 1),
                       FieldReferenceStep("content"), RangeReferenceStep(6, 11))
        mkslice(; stored=nothing) = begin
            content = TextBlock(TextString("hello world"))
            content.selection = trange
            s = ClipboardSlice(content, stored)
            s.selection = ConcreteReference(FieldReferenceStep("content"), trange)
            s
        end
        p = ClipboardSliceToAnyProjection(text=true)

        # Copy: stores the substring as a TextString in the slice and mirrors to OS.
        s = mkslice()
        iom = print_document(p, IdentityProjection(), s, PrinterContext())
        op = read_intent(p, iom, KeyDown(:c, ctrl; time = 0.0))
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
        op = read_intent(p, iom, KeyDown(:x, ctrl; time = 0.0))
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
        op = read_intent(p, iom, KeyDown(:v, ctrl; time = 0.0))
        @test op isa ReplaceStringRangeOperation
        @test op.replacement == "ZZZ"
        @test op.reference.head.name == "content"

        # Paste with an empty slice falls back to the OS clipboard text.
        buf[] = "OSPASTE"
        s = mkslice()                                   # no stored slice
        iom = print_document(p, IdentityProjection(), s, PrinterContext())
        op = read_intent(p, iom, KeyDown(:v, ctrl; time = 0.0))
        @test op isa ReplaceStringRangeOperation
        @test op.replacement == "OSPASTE"

        # An empty caret (no range) declines copy.
        content = TextBlock(TextString("hello world"))
        content.selection = cpath(FieldReferenceStep("elements"), RangeReferenceStep(0, 1),
                                  FieldReferenceStep("content"), RangeReferenceStep(3, 3))
        sc = ClipboardSlice(content)
        sc.selection = ConcreteReference(FieldReferenceStep("content"),
            cpath(FieldReferenceStep("elements"), RangeReferenceStep(0, 1),
                  FieldReferenceStep("content"), RangeReferenceStep(3, 3)))
        iom = print_document(p, IdentityProjection(), sc, PrinterContext())
        # Declines (no range): no copy compound is produced — it falls through to the
        # content child, which echoes the event rather than a clipboard operation.
        @test !(read_intent(p, iom, KeyDown(:c, ctrl; time = 0.0)) isa CompoundOperation)
    finally
        reset_os_clipboard_backend!()
    end
end

@testset "a text target takes the system clipboard's text, and a range is copied as text" begin
    buf = Ref("")
    set_os_clipboard_backend!(read = () -> buf[], write = t -> (buf[] = String(t); true))
    try
        content_step = FieldReferenceStep("content")
        value_step = FieldReferenceStep("value")
        # A slice over `document`, with the selection `content.<steps>` set the way
        # an editor sets it, so every document on the path holds its part.
        function text_slice(document, steps...; stored = nothing)
            slice = stored === nothing ? ClipboardSlice(document) : ClipboardSlice(document, stored)
            set_selection!(slice, cpath(content_step, steps...))
            p = ClipboardSliceToAnyProjection()
            (slice, p, print_document(p, IdentityProjection(), slice, PrinterContext()))
        end
        apply!(slice, op) = evaluate_operation((document = slice,), op)
        ends(document) = (steps = get_reference_steps(strip_reference_types(getfield(document, :selection)[]));
                          (last(steps).start, last(steps).stop))

        @test accepts_pasted_text(PrimitiveString("x"))

        # A caret takes the text, and the caret follows it.
        buf[] = "XY"
        text = PrimitiveString("hello")
        (slice, p, iomap) = text_slice(text, value_step, RangeReferenceStep(2, 2))
        op = read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0))
        @test op isa ReplaceStringRangeOperation
        @test op.replacement == "XY"
        apply!(slice, op)
        @test text.value == "heXYllo"
        @test ends(text) == (4, 4)
        # Paste-copy is the same edit.
        @test read_intent(p, iomap, KeyDown(:v, ctrl_shift; time = 0.0)) isa ReplaceStringRangeOperation

        # A range is replaced.
        buf[] = "Z"
        text = PrimitiveString("hello")
        (slice, p, iomap) = text_slice(text, value_step, RangeReferenceStep(1, 4))
        apply!(slice, read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)))
        @test text.value == "hZo"

        # A copy and a note of a range store its characters in the slice and on
        # the system clipboard, and the selection stays.
        for key in (:c, :n)
            buf[] = ""
            text = PrimitiveString("hello")
            (slice, p, iomap) = text_slice(text, value_step, RangeReferenceStep(1, 4))
            op = read_intent(p, iomap, KeyDown(key, ctrl; time = 0.0))
            @test op isa CompoundOperation
            apply!(slice, op)
            @test buf[] == "ell"
            @test slice.slice isa PrimitiveString && slice.slice.value == "ell"
            @test ends(text) == (1, 4)
            @test text.value == "hello"
        end

        # A copy at a caret has nothing to take: the slice and the system
        # clipboard stay as they are.
        buf[] = "kept"
        text = PrimitiveString("hello")
        (slice, p, iomap) = text_slice(text, value_step, RangeReferenceStep(2, 2);
                                       stored = PrimitiveString("stored"))
        op = read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0))
        op isa Operation && apply!(slice, op)
        @test buf[] == "kept"
        @test slice.slice.value == "stored"

        # A cut of a range takes it out.
        buf[] = ""
        text = PrimitiveString("hello")
        (slice, p, iomap) = text_slice(text, value_step, RangeReferenceStep(1, 4))
        apply!(slice, read_intent(p, iomap, KeyDown(:x, ctrl; time = 0.0)))
        @test text.value == "ho"
        @test buf[] == "ell"
        @test ends(text) == (1, 1)

        # A number takes digits and refuses letters.
        number = PrimitiveNumber(42)
        (slice, p, iomap) = text_slice(number, value_step, RangeReferenceStep(1, 1))
        buf[] = "7"
        op = read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0))
        @test op isa ReplaceNumberRangeOperation
        apply!(slice, op)
        @test number.value == 472
        buf[] = "x"
        @test !(read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)) isa ReplaceRangeOperation)
        @test number.value == 472

        # A string with no line break drops the ones the text ends with; a string
        # that holds one keeps them.
        buf[] = "X\n"
        one_line = PrimitiveString("ab")
        (slice, p, iomap) = text_slice(one_line, value_step, RangeReferenceStep(1, 1))
        apply!(slice, read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)))
        @test one_line.value == "aXb"
        two_lines = PrimitiveString("a\nb")
        (slice, p, iomap) = text_slice(two_lines, value_step, RangeReferenceStep(1, 1))
        apply!(slice, read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)))
        @test two_lines.value == "aX\n\nb"

        # A document that refuses pasted text protects its strings from a paste
        # and a cut; a copy only reads, and takes the text.
        record = _ClipboardRecord(PrimitiveString("kept"))
        buf[] = "no"
        (slice, p, iomap) = text_slice(record, FieldReferenceStep("item"), value_step,
                                       RangeReferenceStep(1, 3))
        @test !(read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)) isa ReplaceRangeOperation)
        @test !(read_intent(p, iomap, KeyDown(:x, ctrl; time = 0.0)) isa CompoundOperation)
        apply!(slice, read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0)))
        @test buf[] == "ep"
        @test record.item.value == "kept"

        # With no system clipboard, the text the slice holds is pasted, and any
        # other slice is refused.
        set_os_clipboard_backend!(read = () -> nothing, write = t -> false)
        text = PrimitiveString("ab")
        (slice, p, iomap) = text_slice(text, value_step, RangeReferenceStep(1, 1);
                                       stored = PrimitiveString("S"))
        apply!(slice, read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)))
        @test text.value == "aSb"
        (slice, p, iomap) = text_slice(PrimitiveString("ab"), value_step, RangeReferenceStep(1, 1);
                                       stored = _ClipboardPair(PrimitiveString("l"), PrimitiveString("r")))
        @test !(read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)) isa ReplaceRangeOperation)
    finally
        reset_os_clipboard_backend!()
    end
end

@testset "a paste needs a whole document, and a caret goes on to the content" begin
    slice = ClipboardSlice(PrimitiveString("hello"), PrimitiveString("stored"))
    # A caret between the second and the third letter.
    slice.selection = cpath(FieldReferenceStep("content"), RangeReferenceStep(2, 2))
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
    @test !(read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)) isa CompoundOperation)
    @test !(read_intent(p, iomap, KeyDown(:v, ctrl_shift; time = 0.0)) isa CompoundOperation)
    @test !(read_intent(p, iomap, KeyDown(:x, ctrl; time = 0.0)) isa CompoundOperation)
end

@testset "a document that refuses a paste protects itself and what it holds" begin
    record = _ClipboardRecord(PrimitiveString("kept"))
    pair = _ClipboardPair(record, PrimitiveString("free"))
    slice = ClipboardSlice(pair, PrimitiveString("stored"))
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
    content = FieldReferenceStep("content")
    for refused in (cpath(content, FieldReferenceStep("left")),
                    cpath(content, FieldReferenceStep("left"), FieldReferenceStep("item")))
        slice.selection = refused
        @test !(read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)) isa CompoundOperation)
        @test !(read_intent(p, iomap, KeyDown(:x, ctrl; time = 0.0)) isa CompoundOperation)
    end
    # A record whose kind declares no duplicate is not copied, and it is noted
    # as itself. What it holds is copied.
    slice.selection = cpath(content, FieldReferenceStep("left"))
    @test !(read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0)) isa CompoundOperation)
    noted = read_intent(p, iomap, KeyDown(:n, ctrl; time = 0.0))
    @test noted isa CompoundOperation
    @test _rd_val(noted.operations[1]) === record
    slice.selection = cpath(content, FieldReferenceStep("left"), FieldReferenceStep("item"))
    @test read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0)) isa CompoundOperation
    slice.selection = cpath(content, FieldReferenceStep("right"))
    op = read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0))
    @test op isa CompoundOperation
    @test _rd_ref(op.operations[1]) == cpath(content, FieldReferenceStep("right"))
    # A noted record pastes as itself where a paste may write. A paste of a new
    # copy is refused, because the record has no duplicate.
    held = ClipboardSlice(_ClipboardPair(PrimitiveString("x"), PrimitiveString("y")),
                          _ClipboardRecord(PrimitiveString("kept")))
    held.selection = cpath(content, FieldReferenceStep("right"))
    io = print_document(p, IdentityProjection(), held, PrinterContext())
    pasted = read_intent(p, io, KeyDown(:v, ctrl; time = 0.0))
    @test pasted isa CompoundOperation
    @test _rd_val(pasted.operations[1]) === held.slice
    @test !(read_intent(p, io, KeyDown(:v, ctrl_shift; time = 0.0)) isa CompoundOperation)
end

@testset "a copy of a tool is its duplicate, and a note is the tool itself" begin
    content = FieldReferenceStep("content")
    p = ClipboardSliceToAnyProjection()
    tool = _ClipboardTool(PrimitiveString("state"))
    slice = ClipboardSlice(_ClipboardPair(tool, PrimitiveString("free")))
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
    slice.selection = cpath(content, FieldReferenceStep("left"))
    copied = read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0))
    @test copied isa CompoundOperation
    duplicate = _rd_val(copied.operations[1])
    @test duplicate isa _ClipboardTool
    @test duplicate !== tool
    noted = read_intent(p, iomap, KeyDown(:n, ctrl; time = 0.0))
    @test _rd_val(noted.operations[1]) === tool
    # A document that holds a tool is copied, and the tool inside it is the
    # duplicate. A document that holds a record with no duplicate is not copied.
    slice.selection = cpath(content)
    whole = _rd_val(read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0)).operations[1])
    @test whole isa _ClipboardPair && whole !== slice.content
    @test whole.left isa _ClipboardTool && whole.left !== tool
    kept = ClipboardSlice(_ClipboardPair(_ClipboardRecord(PrimitiveString("r")), PrimitiveString("s")))
    kept.selection = cpath(content)
    io = print_document(p, IdentityProjection(), kept, PrinterContext())
    @test !(read_intent(p, io, KeyDown(:c, ctrl; time = 0.0)) isa CompoundOperation)
    # A stored tool pastes as itself, and a paste of a new copy pastes a new
    # duplicate each time.
    held = ClipboardSlice(_ClipboardPair(PrimitiveString("x"), PrimitiveString("y")), tool)
    held.selection = cpath(content, FieldReferenceStep("right"))
    io = print_document(p, IdentityProjection(), held, PrinterContext())
    @test _rd_val(read_intent(p, io, KeyDown(:v, ctrl; time = 0.0)).operations[1]) === tool
    fresh = _rd_val(read_intent(p, io, KeyDown(:v, ctrl_shift; time = 0.0)).operations[1])
    @test fresh isa _ClipboardTool && fresh !== tool
end

@testset "a copy refuses a document that holds itself" begin
    content = FieldReferenceStep("content")
    looped = _ClipboardPair(PrimitiveString("a"), PrimitiveString("b"))
    looped.right = _ClipboardPair(PrimitiveString("c"), looped)
    slice = ClipboardSlice(_ClipboardPair(looped, PrimitiveString("d")))
    slice.selection = cpath(content, FieldReferenceStep("left"))
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
    @test !(read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0)) isa CompoundOperation)
    # A document met twice without a loop is copied once.
    shared = _ClipboardKeeper(PrimitiveString("shared"))
    twice = ClipboardSlice(_ClipboardPair(_ClipboardPair(shared, shared), PrimitiveString("e")))
    twice.selection = cpath(content, FieldReferenceStep("left"))
    io = print_document(p, IdentityProjection(), twice, PrinterContext())
    copy = _rd_val(read_intent(p, io, KeyDown(:c, ctrl; time = 0.0)).operations[1])
    @test copy.left === copy.right
end

@testset "a copy and a note of a frame take what the frame shows" begin
    content = FieldReferenceStep("content")
    shown = PrimitiveString("shown")
    slice = ClipboardSlice(_ClipboardPair(_ClipboardFrame(shown), PrimitiveString("f")))
    slice.selection = cpath(content, FieldReferenceStep("left"))
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
    copied = _rd_val(read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0)).operations[1])
    @test copied isa PrimitiveString && copied !== shown
    @test _rd_val(read_intent(p, iomap, KeyDown(:n, ctrl; time = 0.0)).operations[1]) === shown
    @test ProjecturedPlatform.ClipboardModule.find_clipboard_document(42) === nothing
end

@testset "a copy and a note reach a widget a projection drew, and a paste leaves it" begin
    focus = ProjecturedPlatform.FocusModule
    owner = _ClipboardPair(PrimitiveString("a"), PrimitiveString("b"))
    drawn = _ClipboardKeeper(PrimitiveString("drawn"))
    slice = ClipboardSlice(_ClipboardPair(owner, PrimitiveString("c")), PrimitiveString("stored"))
    slice.selection = concat_references(
        cpath(FieldReferenceStep("content"), FieldReferenceStep("left")),
        focus.make_output_reference(owner, drawn, cpath(FieldReferenceStep("value"))))
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
    copied = _rd_val(read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0)).operations[1])
    @test copied isa _ClipboardKeeper && copied !== drawn
    @test _rd_val(read_intent(p, iomap, KeyDown(:n, ctrl; time = 0.0)).operations[1]) === drawn
    # The drawn widget is not a slot of the document that drew it.
    @test !(read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)) isa CompoundOperation)
end

@testset "a paste writes only a value its slot takes" begin
    typed = _ClipboardTyped(PrimitiveString("name"))
    content = FieldReferenceStep("content")
    at_label = cpath(content, FieldReferenceStep("label"))
    for (stored, taken) in ((PrimitiveString("other"), true), (DocumentNothing(), false))
        slice = ClipboardSlice(typed, stored)
        slice.selection = at_label
        p = ClipboardSliceToAnyProjection()
        iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
        @test (read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)) isa CompoundOperation) == taken
        # A cut writes an empty document, which this slot does not take either.
        @test !(read_intent(p, iomap, KeyDown(:x, ctrl; time = 0.0)) isa CompoundOperation)
    end
end

@testset "a document can say what may take its place" begin
    content = FieldReferenceStep("content")
    for (stored, taken) in ((_ClipboardKeeper(PrimitiveString("new")), true),
                            (PrimitiveString("other"), false))
        pair = _ClipboardPair(_ClipboardKeeper(PrimitiveString("old")), PrimitiveString("b"))
        slice = ClipboardSlice(pair, stored)
        slice.selection = cpath(content, FieldReferenceStep("left"))
        p = ClipboardSliceToAnyProjection()
        iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
        @test (read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)) isa CompoundOperation) == taken
    end
    @test accepts_pasted_replacement(PrimitiveString("a"), PrimitiveString("b"))
end

@testset "a gesture the host does not offer goes on to the content" begin
    slice = ClipboardSlice(PrimitiveString("hello"), PrimitiveString("stored"))
    slice.selection = cpath(FieldReferenceStep("content"))
    offered = (:copy, :note, :paste, :paste_copy)
    p = ClipboardSliceToAnyProjection(offered_gestures = offered)
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
    @test !(read_intent(p, iomap, KeyDown(:x, ctrl; time = 0.0)) isa CompoundOperation)
    @test !(read_intent(p, iomap, KeyDown(:slash, ctrl; time = 0.0)) isa ToggleClipboardSliceOperation)
    @test read_intent(p, iomap, KeyDown(:c, ctrl; time = 0.0)) isa CompoundOperation
    @test read_intent(p, iomap, KeyDown(:n, ctrl; time = 0.0)) isa CompoundOperation
    @test read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0)) isa CompoundOperation
    @test read_intent(p, iomap, KeyDown(:v, ctrl_shift; time = 0.0)) isa CompoundOperation
    @test Set(CLIPBOARD_GESTURES) ==
              Set((:toggle, :copy, :copy_reference, :cut, :note, :paste, :paste_copy))
end

@testset "Ctrl+Shift+C copies the reference of the selected object as code" begin
    buffer = Ref("")
    set_os_clipboard_backend!(read = () -> buffer[], write = text -> (buffer[] = text; true))
    try
        slice = ClipboardSlice(PrimitiveString("abc"))
        p = ClipboardSliceToAnyProjection()
        iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
        operation = read_intent(p, iomap, KeyDown(:c, ModifierKeys(ctrl = true, shift = true); time = 0.0))
        @test operation isa CopyReferenceOperation
        # A caret inside the text names the document that holds the text.
        set_selection!(slice, ConcreteReference(FieldReferenceStep("content"),
            ConcreteReference(FieldReferenceStep("value"),
                ConcreteReference(RangeReferenceStep(1, 1), EmptyReference()))))
        editor = (document = slice,)
        evaluate_operation(editor, operation)
        @test buffer[] == "evaluate_reference(editor.document, @reference(editor.document, content))"
        @test slice.slice isa PrimitiveString && slice.slice.value == buffer[]
        # The code gives the object where `editor` is bound, as in an evaluator.
        scratch = Module()
        Core.eval(scratch, :(using ProjecturedKernel.ReferenceModule))
        Core.eval(scratch, :(editor = $(QuoteNode(editor))))
        @test Core.eval(scratch, Meta.parse(buffer[])) === slice.content
    finally
        reset_os_clipboard_backend!()
    end
end

@testset "an operation from the content is re-rooted under it" begin
    slice = ClipboardSlice(_ClipboardPair(PrimitiveString("a"), PrimitiveString("b")))
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
    right = cpath(FieldReferenceStep("right"))
    write = ReplaceReferencedValueOperation(nothing, right, PrimitiveString("c"))
    moved = read_intent(p, iomap, CompoundOperation(Any[write, ReplaceSelectionOperation(right)]))
    @test moved isa CompoundOperation
    @test moved.operations[1].reference == cpath(FieldReferenceStep("content"), FieldReferenceStep("right"))
    @test moved.operations[2].path == cpath(FieldReferenceStep("content"), FieldReferenceStep("right"))
    # A write that carries its own document is not re-rooted.
    own = ReplaceReferencedValueOperation(slice.content, "right", PrimitiveString("d"))
    @test read_intent(p, iomap, own) === own
end

@testset "the clipboard reads its own selection, and not the content's" begin
    left, right = PrimitiveString("a"), PrimitiveString("b")
    pair = _ClipboardPair(left, right)
    slice = ClipboardSlice(pair)
    # The clipboard's own cell names the whole content, and then the content's
    # selection is written directly, below the clipboard. Every write of the live
    # selection starts at the root, so the clipboard does not look below itself:
    # it acts on what its own selection names.
    slice.selection = cpath(FieldReferenceStep("content"))
    set_selection!(pair, cpath(FieldReferenceStep("right")))
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
    op = read_intent(p, iomap, KeyDown(:n, ctrl; time = 0.0))
    @test op isa CompoundOperation
    @test _rd_val(op.operations[1]) === pair
end

@testset "a noted object that lost the focus still pastes" begin
    # The noted object was selected where it was shown, and that selection went
    # dormant when the focus moved on. The paste starts it afresh.
    noted = _ClipboardPair(PrimitiveString("a"), PrimitiveString("b"))
    getfield(noted, :selection)[] =
        SelectionDocument(primary = cpath(FieldReferenceStep("left")), live = false)
    pair = _ClipboardPair(PrimitiveString("x"), PrimitiveString("y"))
    slice = ClipboardSlice(pair, noted)
    slice.selection = cpath(FieldReferenceStep("content"), FieldReferenceStep("right"))
    p = ClipboardSliceToAnyProjection()
    iomap = print_document(p, IdentityProjection(), slice, PrinterContext())
    op = read_intent(p, iomap, KeyDown(:v, ctrl; time = 0.0))
    @test op isa CompoundOperation
    @test _rd_val(op.operations[1]) === noted
    # The write's own selection move names the target and nothing inside it.
    @test op.operations[1].operations[2].path ==
          cpath(FieldReferenceStep("content"), FieldReferenceStep("right"))
end

@testset "the wrapper helpers build the clipboard and its dispatch" begin
    document = make_clipboard_document(PrimitiveString("x"))
    @test document isa ClipboardSlice
    @test make_clipboard_document(PrimitiveString("x"); collection = true) isa ClipboardCollection
    projection = make_clipboard_projection(IdentityProjection(); offered_gestures = (:copy,))
    @test projection isa RecursiveProjection
    clipboard = only(q for (t, q) in projection.child.dispatch if t === ClipboardSlice)
    @test clipboard isa ClipboardSliceToAnyProjection
    @test clipboard.offered_gestures == (:copy,)
end

@testset "the wrapper prints the child on display with its own step" begin
    # The projection of the content records the reference it is printed with.
    seen = String[]
    recording = ReferenceDispatchingProjection(reference -> begin
        push!(seen, repr(strip_reference_types(reference)))
        IdentityProjection()
    end)
    content, stored = PrimitiveString("root"), PrimitiveString("stored")
    projection = make_clipboard_projection(recording)
    clipboard = only(q for (t, q) in projection.child.dispatch if t === ClipboardSlice)
    iomap = print_document(projection, ClipboardSlice(content, stored))
    # The content is printed at `content`, and the slice is not printed while it
    # is not on display.
    @test seen == [".content"]
    @test iomap.output === content
    # A toggle prints the slice at `slice`, and the output follows it.
    clipboard.display_slice[] = true
    @test iomap.output === stored
    @test seen == [".content", ".slice"]
    clipboard.display_slice[] = false
    @test iomap.output === content
    # A press that neither the clipboard nor the content answers gives no
    # operation, and not the press itself.
    change = read_intent(projection, nothing, Intent(MouseClick(:right, 1, 1, ModifierKeys(); time = 0.0)), iomap)
    @test change.operation === nothing
end

end # test_clipboard
