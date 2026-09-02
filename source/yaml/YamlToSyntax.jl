"""
    YamlToSyntaxModule

YAML → SyntaxDocument projection. Maps each YAML value type to a matching syntax
tree shape: null, bool, number, and string scalars become leaves; sequences and
mappings become nodes.

The container rendering is selectable via `YamlToSyntax(; style)`:

- `:block` (default) — idiomatic block YAML: `key: value` lines and `- item`
  sequences, laid out by indentation, no braces/brackets/commas.
- `:flow` — flow YAML (a JSON superset): `{key: value}` and `[a, b]` with commas.

String scalars and mapping keys are plain (unquoted) in both styles.

Mappings are rendered through `@projection_template` (the flow/block difference is
just the wrapper's open/close/separator). Block **sequences** need a `- ` before
every item, which the template's homogeneous `collection` cannot inject, so the
block sequence is a hand-written projection (like `FileSystemDirectoryToSyntaxNode`).
"""
module YamlToSyntaxModule

import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..YamlModule: YamlDocument, YamlNothing, YamlInsertion, YamlNull, YamlBool, YamlNumber, YamlString, YamlSequence, YamlMapping, YamlMappingEntry
import ..DocumentInsertionToSyntaxModule: DomainInsertionToSyntaxLeaf, InsertionNothingToSyntaxLeaf
import ..TextModule: TextString, hinted_text
import ..FontModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode, SyntaxDelimitation
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..ProjectionTemplateModule: var"@projection_template", bound, project, collection
import ..PrimitiveModule: ReplaceNumberRangeOperation, ReplaceStringRangeOperation
import ..IoMapModule: ChildrenIoMap
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, FieldReferenceStep, RangeReferenceStep, EmptyReference
import ..ProjectionReferenceStepModule: ProjectionReferenceStep
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference"
import ..PrinterContextModule: make_child_context
import ..OperationModule: ReplaceSelectionOperation
import ..OperationModule: reroot_operation
import ..GestureBindingModule: read_gesture
import ..EventModule: KeyPress, KeyDown
export YamlInsertionToSyntaxLeaf, YamlNullToSyntaxLeaf, YamlBoolToSyntaxLeaf, YamlNumberToSyntaxLeaf,
       YamlStringToSyntaxLeaf, YamlSequenceToSyntaxNode, YamlSequenceToBlockSyntaxNode, YamlMappingToSyntaxNode,
       YamlToSyntax

# ── YamlNullToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct YamlNullToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template YamlNullToSyntaxLeaf YamlNull (prj, doc) ->
    SyntaxLeaf(TextString("null", prj.style))

# ── YamlInsertionToSyntaxLeaf ───────────────────────────────────────────────────
#
# The shared typed-name insertion buffer, constrained to the YAML candidates
# (prefix-free: `string` → `YamlString`). The char type-to-replace gestures on
# a whole-selected insertion keep working: the leaf declines without a value
# cursor, so those keys fall through to `@gestures YamlDocument`.

YamlInsertionToSyntaxLeaf() = DomainInsertionToSyntaxLeaf(YamlDocument)

# ── YamlBoolToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct YamlBoolToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
end

# See JsonBoolToSyntaxLeaf: `hinted_text` guards the `doc.value ? …` thunk against a
# transient non-`Bool` value produced by mid-edit `bound` reads.
@projection_template YamlBoolToSyntaxLeaf YamlBool (prj, doc) ->
    SyntaxLeaf(bound(:value, Bool,
                     hinted_text(() -> doc.value ? "true" : "false",
                                 () -> !(doc.value isa Bool), "enter yaml bool", prj.style)))

# ── YamlNumberToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct YamlNumberToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template YamlNumberToSyntaxLeaf YamlNumber (prj, doc) ->
    SyntaxLeaf(bound(:value, Real,
                     hinted_text(() -> string(doc.value), () -> doc.value === nothing, "enter yaml number", prj.style);
                     retype = ReplaceNumberRangeOperation))

# ── YamlStringToSyntaxLeaf ───────────────────────────────────────────────────
#
# A plain scalar: rendered unquoted (the distinctly-YAML choice). The bound value
# lives on the leaf's `.value` span with empty open/close delimiters.

@projection struct YamlStringToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template YamlStringToSyntaxLeaf YamlString (prj, doc) ->
    SyntaxLeaf(bound(:value, String,
                     hinted_text(() -> doc.value, () -> isempty(doc.value), "enter yaml string", prj.style)))

# ── YamlMappingToSyntaxNode (template; flow or block via delimiter fields) ────
#
# Each entry renders `key: value` with an unquoted (plain) key leaf and the value
# delegated to its own projection. The wrapper's open/close/separator are fields so
# the same rule renders flow (`{a: 1, b: 2}`) or block (indented `key: value`
# lines) — see `YamlToSyntax`.

@projection struct YamlMappingToSyntaxNode
    delimiter_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    separator_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    key_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    colon_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    open::String = ""      # "{" flow, "" block
    close::String = ""     # "}" flow, "" block
    sep::String = ""       # ", " flow, "" block (indentation provides the newline)
    # +1 (flow) keeps a trailing newline so the close brace lands on its own line;
    # -1 (block) is block layout WITHOUT that trailing newline, so nested blocks
    # don't leave a blank line before the next sibling.
    indent::Int = -1
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
               open=TextString(prj.open, prj.delimiter_style),
               close=TextString(prj.close, prj.delimiter_style),
               sep=TextString(prj.sep, prj.separator_style),
               indentation=prj.indent)

# ── YamlSequenceToSyntaxNode (template; flow style [a, b]) ────────────────────

@projection struct YamlSequenceToSyntaxNode
    delimiter_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
    separator_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template YamlSequenceToSyntaxNode YamlSequence (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", prj.delimiter_style),
               close=TextString("]", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
               indentation=1)

# ── YamlSequenceToBlockSyntaxNode (hand-written; block style `- item`) ────────
#
# The template cannot put a `- ` before each element (a homogeneous `collection`
# projects the bare element with no per-item open), so the block sequence is
# hand-written like `FileSystemDirectoryToSyntaxNode`. Output shape:
#
#   SyntaxNode(indentation=1):                 ← one item per indented line
#     children[i] = SyntaxDelimitation(          ← the "- " marker
#                     opening_delimiter="- ", content = <projected element i>)
#
# Selection: .elements[i].rest ↔ .children[i].content.<child-mapped rest>
# (the `.content` hop steps through the "- " delimitation). The tail is
# delegated through the stored child iomaps (School A); the two mappers are the
# single source of truth for the printer's selection cell and the readers.

@projection struct YamlSequenceToBlockSyntaxNode
    marker_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
end

function print_document(p::YamlSequenceToBlockSyntaxNode, recursion, seq::YamlSequence, ctx)
    child_iomaps = ComputedCell(() -> [print_child(recursion, elem,
                                   make_child_context(ctx, FieldReferenceStep("elements"), ElementReferenceStep(i)))
                               for (i, elem) in enumerate(seq.elements)])

    items = ComputedCellVector(() -> SyntaxDocument[
        SyntaxDelimitation(im.output; opening_delimiter=TextString("- ", p.marker_style))
        for im in child_iomaps[]])

    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = seq.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    # indentation=-1: block layout (one item per indented line) without the
    # trailing newline, so a nested sequence leaves no blank line after its items.
    node = SyntaxNode(items; indentation=-1, selection=sel)
    iomap = ChildrenIoMap(p, seq, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::YamlSequenceToBlockSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::YamlSequence.elements{s:e}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[child_i]::SyntaxDelimitation.content.^(inner)
        end
    end
end

function map_reference_backward(p::YamlSequenceToBlockSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::YamlSequence
        ::SyntaxNode.children{s:e}.content.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::YamlSequence.elements::CellVector[child_i].^(inner)
        end
    end
end

function read_intent(p::YamlSequenceToBlockSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing && return nothing
    ReplaceSelectionOperation(result)
end

function read_intent(p::YamlSequenceToBlockSyntaxNode, iomap::ChildrenIoMap, op::ReplaceStringRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# The input step into the focused child plus that child's iomap, derived from the
# sequence's own selection — the reader-side mirror of the recursive printer. A
# non-`.elements[i]` selection yields nothing, so the gesture falls to the
# sequence's own `read_gesture` (its `@gestures`, e.g. `,` to insert an element).
function _block_seq_focused_child(iomap, sel)
    @reference_case sel begin
        ::YamlSequence.elements{s:e}.rest... => begin
            i = s + 1
            ims = iomap.child_iomaps
            1 <= i <= length(ims) || return nothing
            (ims[i], (FieldReferenceStep("elements"), ElementReferenceStep(i)))
        end
    end
end

function read_intent(p::YamlSequenceToBlockSyntaxNode, iomap::ChildrenIoMap, evt::Union{KeyPress, KeyDown})
    seq = iomap.input
    sel = getfield(seq, :selection)[]
    if sel !== nothing
        fc = _block_seq_focused_child(iomap, sel)
        if fc !== nothing
            child, steps = fc
            child_op = read_intent(child.projection, child, evt)
            child_op === nothing || return reroot_operation(child_op, steps)
        end
    end
    return read_gesture(seq, evt)
end

# ── Compound convenience constructor ────────────────────────────────────────

"""
    YamlToSyntax(; style::Symbol = :block)

Build the YAML → Syntax projection. `style` is `:block` (idiomatic block YAML) or
`:flow` (JSON-superset flow YAML). See the module docstring.
"""
function YamlToSyntax(; style::Symbol = :block)
    style in (:block, :flow) || error("YamlToSyntax: style must be :block or :flow, got :$style")
    sequence = style === :flow ? YamlSequenceToSyntaxNode() : YamlSequenceToBlockSyntaxNode()
    mapping  = style === :flow ? YamlMappingToSyntaxNode(open="{", close="}", sep=", ", indent=1) :
                                 YamlMappingToSyntaxNode()
    TypeDispatchingProjection(
        YamlNull         => YamlNullToSyntaxLeaf(),
        YamlBool         => YamlBoolToSyntaxLeaf(),
        YamlNumber       => YamlNumberToSyntaxLeaf(),
        YamlString       => YamlStringToSyntaxLeaf(),
        YamlSequence     => sequence,
        YamlMapping      => mapping,
        YamlInsertion    => YamlInsertionToSyntaxLeaf(),
        YamlNothing      => InsertionNothingToSyntaxLeaf(),
        YamlMappingEntry => CopyingProjection(),
        Vector{Cell}     => CopyingProjection(),
    )
end

# ── What this domain's natural notation is ──────────────────────────────────
# YAML was the one source domain that declared none of this, so a caller that
# asked the seam rather than the domain — the assistant's fenced code blocks, for
# one — got nothing for it while JSON, XML, Julia and Markdown worked.
import ..YamlParserModule: yamlparse
import ..NaturalNotationModule: register_natural_domain!, register_natural_parser!

function __init__()
    register_natural_domain!(YamlDocument;
                             rung      = :syntax,
                             make      = () -> YamlToSyntax(),
                             format    = :yaml,
                             extension = ".yaml",
                             parse     = yamlparse)
    # `.yml` is the same format under the other spelling, and a fenced block is
    # written either way.
    register_natural_parser!(:yml, yamlparse)
end

end # module
