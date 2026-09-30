# Fragment of `SyntaxModule`.
#
# What the natural renderer draws with when nothing else claimed a document: the
# shared to-syntax fabric, and the `Syntax → Text → Graphics` tail that turns it
# into pixels.
#
# # Why it is registered rather than named
#
# Naming this from `ProjecturedPlatform` would make every renderer carry the syntax
# domain — the reflection tail that can draw a document of any shape. A campaign
# runner that draws a form, a table of runs and a chat never reaches it, and would
# pay for it in its dependency list all the same.
#
# So the renderer declares a fallback seam and this module fills it. A session that
# loads `ProjecturedPlatform` can draw anything; one that does not draws what it was
# taught, and an error message for the rest.
#
# The rows a domain registers with `register_natural_syntax!` are consumed here,
# which is why the fabric knows every loaded domain without naming one.
"""
    make_natural_to_syntax_dispatch() -> Vector{Pair{Type,Any}}

The shared *to-syntax* dispatch table: every syntax-producible domain → its
`*ToSyntax`, collections → `CollectionToSyntax`, and the `ObjectToSyntax`
reflection table as the tail (so plain `Bool`/`Number`/`String`/… render as
leaves and any unknown value as a reflected node). Exposed so callers can splice
or extend it the way `WidgetToGraphics(…).dispatch` is spliced.

No domain is named here. Every source domain registers its own row from a file it
already has, which is also how a domain living downstream of this package — a NED
file, an INI config — gets rendered. The registered rows come FIRST, so a domain
can override another domain's row.
"""
function make_natural_to_syntax_dispatch()
    vcat(
        get_natural_syntax_entries(),
        Pair{Type,Any}[
            PrimitiveDocument  => PrimitiveToSyntax(),
            # The Text domain's `@domain` pair. Text has no `TextToSyntax` table
            # of its own to carry them — it *is* the layer syntax prints to — and
            # both leaves are this package's, so its two entries live here.
            TextNothing        => InsertionNothingToSyntaxLeaf(),
            TextInsertion      => DomainInsertionToSyntaxLeaf(TextDocument),
            # The domain-free placeholder and the name buffer a person types into.
            # These two are what an empty pane tab holds: Insert turns the
            # placeholder into the buffer, and Enter commits the typed name to a
            # fresh document of any loaded domain.
            DocumentNothing    => InsertionNothingToSyntaxLeaf(),
            DocumentInsertion  => DocumentInsertionToSyntaxLeaf(),
        ],
        CollectionToSyntax().dispatch,   # CellVector, ListNode
        ObjectToSyntax().dispatch,       # Cell/Nothing/Bool/Number/String/Symbol/Char/Any
    )
end

"""
    make_natural_prose_graphics(; measure) -> Projection

The same fabric with one more stage: the lines are broken to the width the
context offers. It is what a domain registers for a block whose text is
**prose** — a paragraph, a heading, a quotation — where a line is a sentence
and not a structure.

The fabric itself never breaks a line, because the layout of a syntax tree
carries meaning: an indented line of code says which block it is in, and a
break invented by a measurement would say something the document does not.
Prose has no such layout, so a line that runs past the box is simply lost.

`measure::TextMeasure` is the backend's own, so the break points line up with
what is drawn.
"""
make_natural_prose_graphics(; measure::TextMeasure) = ChainingProjection(
    RecursiveProjection(TypeDispatchingProjection(make_natural_to_syntax_dispatch())),
    RecursiveProjection(SyntaxToText()),
    WordWrapping(measure = measure),
    TextToGraphics(measure = measure),
)

# The rows this package fills the natural renderer's fallback with. The four
# editing states are here and not in the renderer because only these leaves can
# draw a placeholder or a name buffer; `Any` is the reflection tail.
#
# The two domain-free rows are what an empty pane tab draws through. They are
# exact types, so the renderer takes them before its own abstract rows, and a
# person who presses Insert in an empty tab sees the name buffer rather than a
# reflected struct.
function _fallback_rows(; measure::TextMeasure, font, wrap)
    fabric = ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(make_natural_to_syntax_dispatch())),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure = measure),
    )
    Pair{Type,Any}[
        TextNothing       => fabric,
        TextInsertion     => fabric,
        DocumentNothing   => fabric,
        DocumentInsertion => fabric,
        Any               => fabric,
    ]
end

"""
    register_syntax_fallback!() -> nothing

Tell the natural machinery what this session can do that it could not before:
draw a document of any shape, and take a syntax tree up to text.

`syntax → text` is the one rung of the ladder that `ProjecturedPlatform` cannot
supply, because it must not name this package — this package names it, and the
arrow cannot turn. So it is registered here, and a session without this package
has no rung: a document that only speaks syntax then has no text and no graphics
form, which is what "not loaded is not supported" means.

Called from `ProjecturedPlatform.__init__`, so loading the package is what
registers both.
"""
function register_syntax_fallback!()
    register_natural_fallback!(:syntax, _fallback_rows)
    register_natural_rung!(:syntax, :text, (; measure) -> SyntaxToText())
    nothing
end
