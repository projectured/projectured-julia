# Fragment of `SyntaxModule`.
#
# What the natural renderer draws with when nothing else claimed a document: the
# shared to-syntax fabric, and the `Syntax → Text → Graphics` tail that turns it
# into pixels.
#
# # Why it is registered rather than named
#
# The natural slice cannot name this module directly: this module already
# names the natural slice (`register_natural_syntax!`, `register_natural_rung!`),
# and the arrow cannot turn. So the renderer declares a fallback seam and this
# module fills it, from `ProjecturedPlatform.__init__`.
#
# A session that loads `ProjecturedPlatform` can draw anything, through this
# fallback, once no domain-specific row claims a document; a session that loads
# no platform at all draws nothing.
#
# The rows a domain registers with `register_natural_syntax!` are consumed here,
# which is why the fabric knows every loaded domain without naming one.
"""
    make_natural_to_syntax_dispatch(; appearance::Appearance) -> Vector{Pair{Type,Any}}

The shared *to-syntax* dispatch table: every syntax-producible domain → its
`*ToSyntax`, collections → `CollectionToSyntax`, and the `ObjectToSyntax`
reflection table as the tail (so plain `Bool`/`Number`/`String`/… render as
leaves and any unknown value as a reflected node). Exposed so callers can splice
or extend it the way `WidgetToGraphics(…).dispatch` is spliced. `appearance` is
the `Appearance` of the editor, passed on to every registered row.

No domain is named here. Every source domain registers its own row from a file it
already has, which is also how a domain living downstream of this package — a NED
file, an INI config — gets rendered. The registered rows come FIRST, so a domain
can override another domain's row.
"""
function make_natural_to_syntax_dispatch(; appearance::Appearance)
    vcat(
        get_natural_syntax_entries(; appearance = appearance),
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
    make_natural_prose_graphics(; measure, appearance::Appearance) -> Projection

The same fabric with one more stage: the lines are broken to the width the
context offers. It is what a domain registers for a block whose text is
**prose** — a paragraph, a heading, a quotation — where a line is a sentence
and not a structure.

The fabric itself never breaks a line, because the layout of a syntax tree
carries meaning: an indented line of code says which block it is in, and a
break invented by a measurement would say something the document does not.
Prose has no such layout, so a line that runs past the box is simply lost.

`measure::TextMeasure` is the backend's own, so the break points line up with
what is drawn. `appearance` is the `Appearance` of the editor.
"""
make_natural_prose_graphics(; measure::TextMeasure, appearance::Appearance) = ChainingProjection(
    RecursiveProjection(TypeDispatchingProjection(make_natural_to_syntax_dispatch(; appearance = appearance))),
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
function _fallback_rows(; measure::TextMeasure, font, wrap, appearance::Appearance)
    fabric = ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(make_natural_to_syntax_dispatch(; appearance = appearance))),
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

`syntax → text` is the one rung of the ladder that the natural slice cannot
supply itself — it must not name the syntax slice, because the syntax slice
names it, and the arrow cannot turn. So it is registered here instead, and a
session that loads no platform at all has no rung: a document that only
speaks syntax then has no text and no graphics form, which is what "not
loaded is not supported" means.

Called from `ProjecturedPlatform.__init__`, so loading the platform is what
registers it.
"""
function register_syntax_fallback!()
    register_natural_fallback!(:syntax, _fallback_rows)
    register_natural_rung!(:syntax, :text, (; measure, appearance) -> SyntaxToText())
    nothing
end
