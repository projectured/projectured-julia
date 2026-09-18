# Fragment of `NaturalModule`.
#
# The **natural projection**: one generic factory, [`NaturalToGraphics`](@ref),
# that projects *almost any* document to a `GraphicsCanvas` — recursively and
# bidirectionally — without the caller hand-assembling a per-context dispatch
# table.
#
# It is built entirely from existing, already-bidirectional projections
# (`TypeDispatchingProjection`, `RecursiveProjection`, `ChainingProjection`, and
# the per-domain `*ToSyntax` / `*ToGraphics` projections), so it inherits the
# printer, the reader, and both reference maps for free — there are no new
# `print_document` / `read_intent` / `map_reference_*` methods here.
#
# ## How "render anything, including nestings" works
#
# Two recursion fabrics, tied together by the four-function recursion contract:
#
# - **`natural_to_syntax`** — a `TypeDispatchingProjection` that routes every
#   *syntax-producible* domain to its `*ToSyntax`, collections (`CellVector` /
#   `ListNode`) to `CollectionToSyntax`, and *anything else* to `ObjectToSyntax`'s
#   reflection table (`Cell`/`Nothing`/`Bool`/`Number`/`String`/`Symbol`/`Char`/`Any`).
#   Wrapped in a `RecursiveProjection`, it is the shared element-recursion fabric:
#   a collection of mixed-domain values, or any cross-domain nesting, projects to a
#   single syntax tree because each element re-enters this same fabric by type.
#
# - **the to-graphics dispatcher** — the returned `RecursiveProjection(
#   TypeDispatchingProjection(…))`. It routes layout combinators and widget nodes
#   to their direct graphics renderers (which recurse their embedded content back
#   through this same dispatcher), a domain that draws itself to its own stages
#   (whose content re-enters here, so a diagram node may be a widget or prose or a
#   table), prose `TextDocument` to a text→graphics chain,
#   and **everything else** (`Any`) to `syntax_to_graphics =
#   RecursiveProjection(natural_to_syntax) → SyntaxToText → Text→Graphics`. The
#   `Any` catch-all means the renderer never errors — it degrades to a reflected
#   object tree for genuinely unknown values.
#
# ## No domain is named here
#
# Both tables come from [`NaturalModule`](@ref). A domain registers its
# own row in a file it already has, so this module names no domain and sits below
# all of them. A domain in a package this one cannot see registers the same way.
#
# ## Scope
#
# This renders *content / data* documents. Structural shells (the conversation
# chat bubbles, the pane tabs/splits) are projected to widgets by their own
# panels as a separate top-level stage; a `ConversationDocument` / `PaneDocument`
# reaching a content slot here falls through to the reflective `Any` fallback. A
# caller that wants the real rendering injects an entry via `extra`.
#
# ## Collections render as stacked blocks
#
# A `CellVector` renders as a `VerticalLayout` of independent graphics blocks
# (`CellVectorToVerticalLayout` → `VerticalLayoutToGraphicsCanvas`): each element
# re-enters *this* renderer in its own domain (prose→prose, JSON→JSON,
# widget→widget), rather than the whole collection collapsing to one syntax tree.
# So a `CellVector` of mixed content — including `TextBlock` prose — renders
# naturally.
#
# A `ListNode` is **not** treated this way: it stays in the to-syntax fabric
# (`CollectionToSyntax`), because a list may be lazy/infinite and must not be forced
# into a finite layout. A `TextBlock` placed directly inside a `ListNode` therefore
# still reflects via `ObjectToSyntax` rather than rendering as prose — an accepted
# edge case.
"""
    PhraseToGraphics(message, style, measure)

A document drawn as one line of prose. `message(document)` is what the line says.

Two rows use it, and neither may need a domain that can reflect a document into a
tree: the empty-document placeholder, and the message a document nothing claimed
draws. Drawing that message is the whole difference between a renderer that is
composed of what a session loaded and one that must carry everything.
"""
struct PhraseToGraphics <: Projection
    message::Any
    style::StyleText
    measure::Any
end

function print_document(p::PhraseToGraphics, recursion, document, ctx)
    line = TextBlock(TextString(p.message(document), p.style))
    inner = print_document(TextToGraphics(measure = p.measure), recursion, line, ctx)
    SimpleIoMap(p, document, get_iomap_output(inner))
end

_unsupported_message(document) =
    "no natural rendering for " * String(nameof(typeof(document)))

"""
    NaturalToGraphics(; measure, font=font_ubuntu_monospace_regular_20,
                        wrap=true, extra=Pair{Type,Any}[])
        -> RecursiveProjection

Build the natural projection: a recursive type-dispatching projection mapping
almost any document to a `GraphicsCanvas`. `measure(text, font) -> (w, h)` is the
text-measurement function (backend-supplied; e.g. `measure_truetype_text`).

- `font`    — base font for widget/text rendering.
- `wrap`    — word-wrap prose (`TextDocument`). Structured syntax/code is always
              rendered no-wrap (its layout carries meaning; overflow is the
              viewport's job).
- `extra`   — `Pair{Type,Any}` entries prepended to the table, so a caller can
              override or add routing (e.g. a placeholder text chain, or a real
              renderer for a structural document) without forking the table.
              First match wins, so `extra` beats the defaults.
"""
function NaturalToGraphics(; measure::Function,
                           font = font_ubuntu_monospace_regular_20,
                           wrap::Bool = true,
                           extra = Pair{Type,Any}[])
    w2g = WidgetToGraphics(font; measure = measure)

    # Prose: optionally word-wrapped. Structured syntax/code: never wrapped.
    prose_chain = wrap ?
        ChainingProjection(WordWrapping(measure = measure), TextToGraphics(measure = measure)) :
        TextToGraphics(measure = measure)

    style = StyleText(font, color_default)

    # A fallback registers rows for exact types and, usually, one for `Any`. The
    # two go to different places in the table: the exact ones before this
    # package's abstract rows, the `Any` after them.
    registered = get_natural_fallback_entries(measure = measure, font = font, wrap = wrap)
    specific = Pair{Type,Any}[p for p in registered if first(p) !== Any]
    tail     = Pair{Type,Any}[p for p in registered if first(p) === Any]

    table = vcat(
        Pair{Type,Any}[p for p in extra],
        LayoutToGraphics().dispatch,   # layouts before widgets: a WidgetTable builds a GridLayout
        w2g.dispatch,                  # every widget node (incl. WidgetTable)
        # The domains that draw themselves rather than going through the syntax
        # fabric: a page of blocks (markdown, RST), a diagram (graph), a typeset
        # formula (math). Each registers its own rows; none is named here. A row
        # is spliced one type at a time (not as one dispatching projection) so
        # every child re-enters *this* renderer — which is what lets a diagram
        # node be a widget, a page hold a live card, and a number inside a
        # formula render through the shared primitive path.
        get_natural_graphics_entries(measure = measure),
        # A fallback's own rows: the placeholders only it can draw. They name
        # exact types, so they come before the abstract rows below — a
        # `TextInsertion` is a `TextDocument`, and prose is not what it is, and a
        # `DocumentNothing` drawn as a leaf beats the same one drawn as prose.
        specific,
        Pair{Type,Any}[
            # The domain-free placeholder, for a session that can not reflect a
            # document into a tree. A session that loaded the syntax package
            # registers an exact row for it above, and that row wins, so a person
            # there gets the placeholder leaf and the Insert key that goes with
            # it. Without that package there is no leaf, and one line of prose is
            # what an empty tab can say.
            DocumentNothing => PhraseToGraphics(_ -> "empty document", style, measure),
            TextDocument    => prose_chain,
            # A collection renders as a stack of independent graphics blocks: each
            # element re-enters this renderer in its own domain (prose→prose,
            # JSON→JSON, widget→widget), instead of collapsing to one syntax tree.
            CellVector      => ChainingProjection(CellVectorToVerticalLayout(),
                                                 VerticalLayoutToGraphicsCanvas()),
        ],
        # The fallback's own tail, then this one. A session that loaded a package
        # that can draw anything reaches its tail; one that did not reaches the
        # message.
        tail,
        Pair{Type,Any}[
            Any => PhraseToGraphics(_unsupported_message, style, measure),
        ],
    )

    RecursiveProjection(TypeDispatchingProjection(table))
end
