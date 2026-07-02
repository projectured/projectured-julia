"""
    MarkdownToSyntaxModule

Markdown → SyntaxDocument projection, written entirely with `@projection_template`
so the reader (selection forward/backward and character type-in) is derived from
the recorded wiring — no hand-written `map_reference_*`/`projection_read`.

Each Markdown node maps to a matching syntax shape:
- leaves: `MarkdownText`, `MarkdownCode` (bound content), `MarkdownThematicBreak`
  and `MarkdownInsertion` (opaque markers);
- homogeneous-collection nodes: `MarkdownParagraph`, `MarkdownEmphasis`,
  `MarkdownStrong`, `MarkdownHeading` (its level is a reactive `#…` open marker),
  `MarkdownQuote`, `MarkdownList`, `MarkdownListItem`, `MarkdownRoot`;
- fixed-children nodes: `MarkdownLink` (`[content](url)`), `MarkdownImage`
  (`![alt](url)`) and `MarkdownCodeBlock` (fenced), each pairing a bound leaf with
  a nested collection or another bound leaf.

Blocks stack flush-left (`indentation=0` + a newline `sep`, the BookToSyntax
idiom); inline runs concatenate (`sep=""`).
"""
module MarkdownToSyntaxModule

import ..ReactiveModule: Cell
import ..ProjectionApiModule: Projection
import ..ProjectionModule: var"@projection"
import ..MarkdownModule: MarkdownInsertion, MarkdownText, MarkdownCode, MarkdownEmphasis,
                         MarkdownStrong, MarkdownLink, MarkdownImage, MarkdownHeading,
                         MarkdownParagraph, MarkdownCodeBlock, MarkdownThematicBreak,
                         MarkdownQuote, MarkdownList, MarkdownListItem, MarkdownRoot
import ..TextModule: TextString, hinted_text
import ..FontModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: color_black, color_solarized_blue, color_solarized_green,
                      color_solarized_magenta, color_solarized_cyan, color_solarized_yellow,
                      color_solarized_gray, color_solarized_violet
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..ProjectionTemplateModule: var"@projection_template", bound, collection
export MarkdownInsertionToSyntaxLeaf, MarkdownTextToSyntaxLeaf, MarkdownCodeToSyntaxLeaf,
       MarkdownThematicBreakToSyntaxLeaf, MarkdownEmphasisToSyntaxNode, MarkdownStrongToSyntaxNode,
       MarkdownParagraphToSyntaxNode, MarkdownHeadingToSyntaxNode, MarkdownQuoteToSyntaxNode,
       MarkdownListToSyntaxNode, MarkdownListItemToSyntaxNode, MarkdownRootToSyntaxNode,
       MarkdownLinkToSyntaxNode, MarkdownImageToSyntaxNode, MarkdownCodeBlockToSyntaxNode,
       MarkdownToSyntax

const _MONO      = font_ubuntu_monospace_regular_20
const _MONO_BOLD = font_ubuntu_monospace_bold_20

# ── MarkdownInsertionToSyntaxLeaf ─────────────────────────────────────────────

@projection struct MarkdownInsertionToSyntaxLeaf
    style::StyleText = StyleText(_MONO, color_solarized_gray)
end

@projection_template MarkdownInsertionToSyntaxLeaf MarkdownInsertion (prj, doc) ->
    SyntaxLeaf(TextString("insert markdown here", prj.style))

# ── MarkdownTextToSyntaxLeaf ──────────────────────────────────────────────────

@projection struct MarkdownTextToSyntaxLeaf
    style::StyleText = StyleText(_MONO, color_black)
end

@projection_template MarkdownTextToSyntaxLeaf MarkdownText (prj, doc) ->
    SyntaxLeaf(bound(:content, String,
                     hinted_text(() -> doc.content, () -> isempty(doc.content), "text", prj.style)))

# ── MarkdownCodeToSyntaxLeaf ──────────────────────────────────────────────────

@projection struct MarkdownCodeToSyntaxLeaf
    value_style::StyleText = StyleText(_MONO, color_solarized_green)
    tick_style::StyleText  = StyleText(_MONO, color_solarized_gray)
end

@projection_template MarkdownCodeToSyntaxLeaf MarkdownCode (prj, doc) ->
    SyntaxLeaf(bound(:content, String,
                     hinted_text(() -> doc.content, () -> isempty(doc.content), "code", prj.value_style));
               open=TextString("`", prj.tick_style),
               close=TextString("`", prj.tick_style))

# ── MarkdownThematicBreakToSyntaxLeaf ─────────────────────────────────────────

@projection struct MarkdownThematicBreakToSyntaxLeaf
    style::StyleText = StyleText(_MONO, color_solarized_gray)
end

@projection_template MarkdownThematicBreakToSyntaxLeaf MarkdownThematicBreak (prj, doc) ->
    SyntaxLeaf(TextString("---", prj.style))

# ── MarkdownEmphasisToSyntaxNode ──────────────────────────────────────────────

@projection struct MarkdownEmphasisToSyntaxNode
    marker_style::StyleText = StyleText(_MONO, color_solarized_gray)
end

@projection_template MarkdownEmphasisToSyntaxNode MarkdownEmphasis (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString("*", prj.marker_style),
               close=TextString("*", prj.marker_style),
               sep=TextString(""))

# ── MarkdownStrongToSyntaxNode ────────────────────────────────────────────────

@projection struct MarkdownStrongToSyntaxNode
    marker_style::StyleText = StyleText(_MONO, color_solarized_gray)
end

@projection_template MarkdownStrongToSyntaxNode MarkdownStrong (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString("**", prj.marker_style),
               close=TextString("**", prj.marker_style),
               sep=TextString(""))

# ── MarkdownParagraphToSyntaxNode ─────────────────────────────────────────────

@projection struct MarkdownParagraphToSyntaxNode end

@projection_template MarkdownParagraphToSyntaxNode MarkdownParagraph (prj, doc) ->
    SyntaxNode(collection(:content); sep=TextString(""), indentation=0)

# ── MarkdownHeadingToSyntaxNode ───────────────────────────────────────────────
# `level` is rendered as a reactive `#…` open marker (projection-introduced, not a
# bound field — level editing is deferred). Content is the inline collection.

@projection struct MarkdownHeadingToSyntaxNode
    hash_style::StyleText = StyleText(_MONO_BOLD, color_solarized_blue)
end

@projection_template MarkdownHeadingToSyntaxNode MarkdownHeading (prj, doc) ->
    SyntaxNode(collection(:content);
               open=TextString(() -> "#"^clamp(doc.level, 1, 6) * " ", prj.hash_style),
               sep=TextString(""), indentation=0)

# ── MarkdownQuoteToSyntaxNode ─────────────────────────────────────────────────

@projection struct MarkdownQuoteToSyntaxNode
    marker_style::StyleText = StyleText(_MONO, color_solarized_gray)
end

@projection_template MarkdownQuoteToSyntaxNode MarkdownQuote (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("> ", prj.marker_style),
               sep=TextString("\n> ", prj.marker_style),
               indentation=0)

# ── MarkdownListItemToSyntaxNode ──────────────────────────────────────────────
# A `- ` bullet (ordered numbering is deferred — see plan). Continuation blocks of
# a multi-block item are joined with an indented newline.

@projection struct MarkdownListItemToSyntaxNode
    bullet_style::StyleText = StyleText(_MONO, color_solarized_gray)
end

@projection_template MarkdownListItemToSyntaxNode MarkdownListItem (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("- ", prj.bullet_style),
               sep=TextString("\n  "),
               indentation=0)

# ── MarkdownListToSyntaxNode ──────────────────────────────────────────────────

@projection struct MarkdownListToSyntaxNode end

@projection_template MarkdownListToSyntaxNode MarkdownList (prj, doc) ->
    SyntaxNode(collection(:items); sep=TextString("\n"), indentation=0)

# ── MarkdownRootToSyntaxNode ──────────────────────────────────────────────────
# Flush-left blocks separated by a blank line (the BookBookToSyntaxNode idiom).

@projection struct MarkdownRootToSyntaxNode
    style::StyleText = StyleText(_MONO, color_black)
end

@projection_template MarkdownRootToSyntaxNode MarkdownRoot (prj, doc) ->
    SyntaxNode(collection(:elements);
               sep=TextString("\n\n", prj.style),
               indentation=0)

# ── MarkdownLinkToSyntaxNode ──────────────────────────────────────────────────
# Fixed node `[content](url)`: the inline content is a nested collection sub-node
# (SubNodeSlot, JuliaCall's `(args)` shape) and the url a bound leaf (KeySlot).

@projection struct MarkdownLinkToSyntaxNode
    bracket_style::StyleText = StyleText(_MONO, color_solarized_gray)
    url_style::StyleText     = StyleText(_MONO, color_solarized_violet)
end

@projection_template MarkdownLinkToSyntaxNode MarkdownLink (prj, doc) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
        [ SyntaxNode(collection(:content);
                     open=TextString("[", prj.bracket_style),
                     close=TextString("]", prj.bracket_style),
                     sep=TextString("")),
          SyntaxLeaf(bound(:url, String,
                           hinted_text(() -> doc.url, () -> isempty(doc.url), "url", prj.url_style));
                     open=TextString("(", prj.bracket_style),
                     close=TextString(")", prj.bracket_style)) ],
        0, false, nothing)

# ── MarkdownImageToSyntaxNode ─────────────────────────────────────────────────
# Fixed node `![alt](url)`: two bound leaves (KeySlots).

@projection struct MarkdownImageToSyntaxNode
    bracket_style::StyleText = StyleText(_MONO, color_solarized_gray)
    alt_style::StyleText     = StyleText(_MONO, color_solarized_cyan)
    url_style::StyleText     = StyleText(_MONO, color_solarized_violet)
end

@projection_template MarkdownImageToSyntaxNode MarkdownImage (prj, doc) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
        [ SyntaxLeaf(bound(:alt, String,
                           hinted_text(() -> doc.alt, () -> isempty(doc.alt), "alt", prj.alt_style));
                     open=TextString("![", prj.bracket_style),
                     close=TextString("]", prj.bracket_style)),
          SyntaxLeaf(bound(:url, String,
                           hinted_text(() -> doc.url, () -> isempty(doc.url), "url", prj.url_style));
                     open=TextString("(", prj.bracket_style),
                     close=TextString(")", prj.bracket_style)) ],
        0, false, nothing)

# ── MarkdownCodeBlockToSyntaxNode ─────────────────────────────────────────────
# Fenced block ```` ```lang\ncode\n``` ````: two bound leaves (language, code).

@projection struct MarkdownCodeBlockToSyntaxNode
    fence_style::StyleText = StyleText(_MONO, color_solarized_gray)
    lang_style::StyleText  = StyleText(_MONO, color_solarized_magenta)
    code_style::StyleText  = StyleText(_MONO, color_solarized_green)
end

@projection_template MarkdownCodeBlockToSyntaxNode MarkdownCodeBlock (prj, doc) ->
    SyntaxNode(TextString("```", prj.fence_style), TextString("\n```", prj.fence_style), TextString(""),
        [ SyntaxLeaf(bound(:language, String,
                           hinted_text(() -> doc.language, () -> isempty(doc.language), "lang", prj.lang_style))),
          SyntaxLeaf(bound(:code, String,
                           hinted_text(() -> doc.code, () -> isempty(doc.code), "code", prj.code_style));
                     open=TextString("\n", prj.fence_style)) ],
        0, false, nothing)

# ── Compound convenience constructor ──────────────────────────────────────────

function MarkdownToSyntax()
    TypeDispatchingProjection(
        MarkdownInsertion     => MarkdownInsertionToSyntaxLeaf(),
        MarkdownText          => MarkdownTextToSyntaxLeaf(),
        MarkdownCode          => MarkdownCodeToSyntaxLeaf(),
        MarkdownThematicBreak => MarkdownThematicBreakToSyntaxLeaf(),
        MarkdownEmphasis      => MarkdownEmphasisToSyntaxNode(),
        MarkdownStrong        => MarkdownStrongToSyntaxNode(),
        MarkdownParagraph     => MarkdownParagraphToSyntaxNode(),
        MarkdownHeading       => MarkdownHeadingToSyntaxNode(),
        MarkdownCodeBlock     => MarkdownCodeBlockToSyntaxNode(),
        MarkdownQuote         => MarkdownQuoteToSyntaxNode(),
        MarkdownList          => MarkdownListToSyntaxNode(),
        MarkdownListItem      => MarkdownListItemToSyntaxNode(),
        MarkdownLink          => MarkdownLinkToSyntaxNode(),
        MarkdownImage         => MarkdownImageToSyntaxNode(),
        MarkdownRoot          => MarkdownRootToSyntaxNode(),
        Vector{Cell}          => CopyingProjection(),
    )
end

end # module
