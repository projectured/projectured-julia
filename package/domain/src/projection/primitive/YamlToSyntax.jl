"""
    YamlToSyntaxModule

YAML → SyntaxDocument projection. Maps each YAML value type to a matching syntax
tree shape: null, bool, number, and string scalars become leaves; sequences and
mappings become nodes carrying their flow delimiters and comma separators.

YAML is a JSON superset, so the structure closely follows `JsonToSyntaxModule`,
rendered in **flow style** with YAML flavor: mapping keys and string scalars are
plain (unquoted), sequences read `[…]` and mappings `{…}`.
"""
module YamlToSyntaxModule

import ..ReactiveModule: Cell
import ..ProjectionApiModule: projection_print, Projection
import ..ProjectionModule: var"@projection"
import ..YamlModule: YamlInsertion, YamlNull, YamlBool, YamlNumber, YamlString, YamlSequence, YamlMapping, YamlMappingEntry
import ..TextModule: TextString, hinted_text
import ..FontModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..ProjectionTemplateModule: var"@projection_template", bound, project, collection
import ..PrimitiveModule: NumberReplaceRangeOperation
export YamlInsertionToSyntaxLeaf, YamlNullToSyntaxLeaf, YamlBoolToSyntaxLeaf, YamlNumberToSyntaxLeaf,
       YamlStringToSyntaxLeaf, YamlSequenceToSyntaxNode, YamlMappingToSyntaxNode,
       YamlToSyntax

# ── YamlNullToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct YamlNullToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template YamlNullToSyntaxLeaf YamlNull (prj, doc) ->
    SyntaxLeaf(TextString("null", prj.style))

# ── YamlInsertionToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct YamlInsertionToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template YamlInsertionToSyntaxLeaf YamlInsertion (prj, doc) ->
    SyntaxLeaf(TextString("insert YAML here", prj.style))

# ── YamlBoolToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct YamlBoolToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
end

@projection_template YamlBoolToSyntaxLeaf YamlBool (prj, doc) ->
    SyntaxLeaf(bound(:value, Bool, TextString(() -> doc.value ? "true" : "false", prj.style)))

# ── YamlNumberToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct YamlNumberToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template YamlNumberToSyntaxLeaf YamlNumber (prj, doc) ->
    SyntaxLeaf(bound(:value, Real,
                     hinted_text(() -> string(doc.value), () -> doc.value === nothing, "enter yaml number", prj.style);
                     retype = NumberReplaceRangeOperation))

# ── YamlStringToSyntaxLeaf ───────────────────────────────────────────────────
#
# A plain scalar: rendered unquoted (the distinctly-YAML choice). The bound value
# lives on the leaf's `.value` span with empty open/close delimiters.

@projection struct YamlStringToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template YamlStringToSyntaxLeaf YamlString (prj, doc) ->
    SyntaxLeaf(bound(:value, String,
                     hinted_text(() -> doc.value, () -> isempty(doc.value), "enter yaml string", prj.style)))

# ── YamlSequenceToSyntaxNode ─────────────────────────────────────────────────

@projection struct YamlSequenceToSyntaxNode
    delimiter_style::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    separator_style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template YamlSequenceToSyntaxNode YamlSequence (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", prj.delimiter_style),
               close=TextString("]", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
               indentation=1)

# ── YamlMappingToSyntaxNode ──────────────────────────────────────────────────
#
# Each entry renders `key: value` with an unquoted (plain) key leaf and the value
# delegated to its own projection. The mapping wraps its entries in flow `{…}`.

@projection struct YamlMappingToSyntaxNode
    delimiter_style::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    separator_style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    key_style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    colon_style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template YamlMappingToSyntaxNode YamlMapping (prj, doc) ->
    SyntaxNode(collection(:entries) do e
                   SyntaxNode(TextString("", prj.delimiter_style),
                              TextString("", prj.delimiter_style),
                              TextString(": ", prj.colon_style),
                              [ SyntaxLeaf(bound(:key, String, hinted_text(() -> e.key, () -> isempty(e.key), "enter key", prj.key_style))),
                                project(:value) ],
                              0, false, getfield(e, :selection))
               end;
               open=TextString("{", prj.delimiter_style),
               close=TextString("}", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
               indentation=1)

# ── Compound convenience constructor ────────────────────────────────────────

function YamlToSyntax()
    TypeDispatchingProjection(
        YamlNull         => YamlNullToSyntaxLeaf(),
        YamlBool         => YamlBoolToSyntaxLeaf(),
        YamlNumber       => YamlNumberToSyntaxLeaf(),
        YamlString       => YamlStringToSyntaxLeaf(),
        YamlSequence     => YamlSequenceToSyntaxNode(),
        YamlMapping      => YamlMappingToSyntaxNode(),
        YamlInsertion    => YamlInsertionToSyntaxLeaf(),
        YamlMappingEntry => CopyingProjection(),
        Vector{Cell}     => CopyingProjection(),
    )
end

end # module
