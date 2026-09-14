# Fragment of `SyntaxModule`.
#
# What the natural renderer draws with when nothing else claimed a document: the
# shared to-syntax fabric, and the `Syntax → Text → Graphics` tail that turns it
# into pixels.
#
# # Why it is registered rather than named
#
# Naming this from `ProjecturedNatural` would make every renderer carry the syntax
# domain — the reflection tail that can draw a document of any shape. A campaign
# runner that draws a form, a table of runs and a chat never reaches it, and would
# pay for it in its dependency list all the same.
#
# So the renderer declares a fallback seam and this module fills it. A session that
# loads `ProjecturedSyntax` can draw anything; one that does not draws what it was
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
            # The domain-free placeholder, for a caller that renders through the
            # fabric directly. The natural renderer draws it as prose and never
            # reaches this row.
            DocumentNothing    => InsertionNothingToSyntaxLeaf(),
        ],
        CollectionToSyntax().dispatch,   # CellVector, ListNode
        ObjectToSyntax().dispatch,       # Cell/Nothing/Bool/Number/String/Symbol/Char/Any
    )
end

# The rows this package fills the natural renderer's fallback with. The two Text
# editing states are here and not in the renderer because only these leaves can
# draw a placeholder or a name buffer; `Any` is the reflection tail.
function _fallback_rows(; measure, font, wrap)
    fabric = ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(make_natural_to_syntax_dispatch())),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure = measure),
    )
    Pair{Type,Any}[
        TextNothing   => fabric,
        TextInsertion => fabric,
        Any           => fabric,
    ]
end

"""
    register_syntax_fallback!() -> nothing

Tell the natural machinery what this session can do that it could not before:
draw a document of any shape, and take a syntax tree up to text.

`syntax → text` is the one rung of the ladder that `ProjecturedNatural` cannot
supply, because it must not name this package — this package names it, and the
arrow cannot turn. So it is registered here, and a session without this package
has no rung: a document that only speaks syntax then has no text and no graphics
form, which is what "not loaded is not supported" means.

Called from `ProjecturedSyntax.__init__`, so loading the package is what
registers both.
"""
function register_syntax_fallback!()
    register_natural_fallback!(:syntax, _fallback_rows)
    register_natural_rung!(:syntax, :text, (; measure) -> SyntaxToText())
    nothing
end
