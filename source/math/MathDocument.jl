"""
    MathModule

The math document domain: formulas as `Document`s.
`X = (3*A + B)/2` becomes
`MathAssignment(MathVariable("X"), MathBinaryOperation(:/, …))`.

The domain holds the *structure* of a formula, not its picture and not its
value. Two projections read it: `MathToSyntax` prints one line of text (the
save path), and `MathToGraphics` places real two-dimensional boxes.

A slot that can be absent holds `nothing` when it is absent and a
`MathInsertion` when it is present and empty. Both projections keep that rule:
`nothing` prints nothing, an insertion prints a placeholder.
"""
module MathModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..ReferenceModule
export MathDocument, _operator_string, get_math_operator_glyph, get_math_operator_class,
       get_math_symbol_glyph, get_math_big_operator_glyph, get_math_big_operator_name,
       is_math_big_operator_text,
       get_math_delimiter_strings, is_math_accent_wide, MathSubscript, MathSuperscript
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..ProjectionModule
using ..PrimitiveModule
using ..TextModule
using ..StyleModule
using ..SyntaxModule
using ..ProjectionTemplateModule
using ..ProjectionAlgebraModule
using ..IoMapModule
using ..ProjectionReferenceStepModule
using ..PrinterContextModule
using ..OperationModule
export MathInsertionToSyntaxLeaf, MathVariableToSyntaxLeaf,
       MathBinaryOperationToSyntaxNode, MathParenthesizedToSyntaxNode,
       MathAssignmentToSyntaxNode, MathToSyntax,
       MathSymbolToSyntaxLeaf, MathTextToSyntaxLeaf, MathSpaceToSyntaxLeaf,
       MathRowToSyntaxNode, MathUnaryOperationToSyntaxNode,
       MathFractionToSyntaxNode, MathScriptToSyntaxNode, MathRadicalToSyntaxNode,
       MathBigOperatorToSyntaxNode, MathDifferentialToSyntaxNode,
       MathDerivativeToSyntaxNode, MathFunctionToSyntaxNode,
       MathAccentToSyntaxNode, MathMatrixToSyntaxNode,
       MathCaseToSyntaxNode, MathCasesToSyntaxNode
using ..NaturalModule
using ..GraphicsModule
using ..EventModule
using ..EventPatternModule
export MathIoMap, MathConfig, MathMetrics, compute_math_metrics, MathToGraphics,
       make_math_to_graphics_dispatch,
       MathVariableToGraphics, MathSymbolToGraphics, MathTextToGraphics,
       MathSpaceToGraphics, MathInsertionToGraphics, MathNumberToGraphics,
       MathRowToGraphics, MathBinaryOperationToGraphics,
       MathUnaryOperationToGraphics, MathAssignmentToGraphics,
       MathParenthesizedToGraphics, MathFractionToGraphics, MathScriptToGraphics,
       MathRadicalToGraphics, MathBigOperatorToGraphics,
       MathDifferentialToGraphics, MathDerivativeToGraphics,
       MathFunctionToGraphics, MathAccentToGraphics, MathMatrixToGraphics,
       MathCaseToGraphics, MathCasesToGraphics
export MathInsertion, MathVariable, MathBinaryOperation, MathParenthesized, MathAssignment, MathSymbol, MathText



abstract type MathDocument <: Document end

# ── Atoms ─────────────────────────────────────────────────────────────────────

"""
A placeholder for a math value being entered (the insert-by-typing cursor).
"""
@document struct MathInsertion <: MathDocument
    value::Any = nothing
end

"""
A named variable (e.g. `X`, `A`). Renders slanted, the way a variable is set.
"""
@document struct MathVariable <: MathDocument
    name::String
end

"""
A named symbol: a Greek letter, a constant or an arrow. `name` is what the user
types (`:lambda`); [`get_math_symbol_glyph`](@ref) gives the glyph to draw (`λ`).
"""
@document struct MathSymbol <: MathDocument
    name::Symbol
end

"""
Upright words inside a formula — a unit, a multi-letter name, a word such as
`where`. A variable slants, this does not.
"""
@document struct MathText <: MathDocument
    content::String
end

"""
An explicit space. `kind` is `:thin`, `:medium`, `:thick` or `:quad`.
"""
@document struct MathSpace <: MathDocument
    kind::Symbol
end

# ── Sequences ─────────────────────────────────────────────────────────────────

"""
Juxtaposition: `k T B`, `2 π d`. An explicit operator is a
`MathBinaryOperation`; adjacency without one is a `MathRow`.
"""
@document struct MathRow <: MathDocument
    elements::CellVector = CellVector()
end

"""
An infix operation. `operator` names the operator; its *class*
([`get_math_operator_class`](@ref)) decides the space around it, and both
projections read that one table.
"""
@document struct MathBinaryOperation <: MathDocument
    operator::Symbol
    left::Document
    right::Document
end

"""
A prefix operation (`−x`) or, with `postfix`, a suffix one (`n!`).
"""
@document struct MathUnaryOperation <: MathDocument
    operator::Symbol
    operand::Document
    postfix::Bool = false
end

"""
An assignment expression `target = value` — the root of an equation. A relation
*inside* an expression is a `MathBinaryOperation`.
"""
@document struct MathAssignment <: MathDocument
    target::Document
    value::Document
end

# ── Two-dimensional constructs ────────────────────────────────────────────────

"""
Explicit grouping around a sub-expression. `kind` picks the delimiter pair:
`:parenthesis`, `:bracket`, `:brace`, `:absolute`, `:norm`, `:angle`, `:floor`,
`:ceiling` or `:none`. The delimiter grows with its content.
"""
@document struct MathParenthesized <: MathDocument
    content::Document
    kind::Symbol = :parenthesis
end

"""
A fraction. The graphics projection draws a horizontal rule between the two
children and centers each on it; `inline` asks for the one-line slash form
instead.
"""
@document struct MathFraction <: MathDocument
    numerator::Document
    denominator::Document
    inline::Bool = false
end

"""
A base with a subscript, a superscript or both (`P_t`, `x²`, `A_i^n`). An absent
script is `nothing`; an empty one is a `MathInsertion`.
"""
@document struct MathScript <: MathDocument
    base::Document
    subscript::Any = nothing
    superscript::Any = nothing
end

MathScript(base::Document; subscript=nothing, superscript=nothing) =
    MathScript(Cell(base), Cell(subscript), Cell(superscript), Cell(nothing))

"""
    MathSubscript(base, index) -> MathScript

A base with a subscript only.
"""
MathSubscript(base::Document, index) = MathScript(base; subscript=index)

"""
    MathSuperscript(base, exponent) -> MathScript

A base with a superscript only.
"""
MathSuperscript(base::Document, exponent) = MathScript(base; superscript=exponent)

"""
A root: `√x`, or `ⁿ√x` when `index` is present.
"""
@document struct MathRadical <: MathDocument
    radicand::Document
    index::Any = nothing
end

"""
A large operator with optional limits: `∑`, `∏`, `∫`, `∮`, `⋃`, `lim`.
`limits` is `:under_over` (limits above and below the sign), `:side` (limits as
scripts to its right) or `:auto`, which picks by operator and by style.
"""
@document struct MathBigOperator <: MathDocument
    operator::Symbol
    body::Document
    lower::Any = nothing
    upper::Any = nothing
    limits::Symbol = :auto
end

MathBigOperator(operator::Symbol, body::Document;
                lower=nothing, upper=nothing, limits::Symbol=:auto) =
    MathBigOperator(Cell(operator), Cell(body), Cell(lower), Cell(upper),
                    Cell(limits), Cell(nothing))

"""
A differential: `dt`, or `∂x` when `kind` is `:partial`.
"""
@document struct MathDifferential <: MathDocument
    variable::Document
    kind::Symbol = :total
end

"""
A derivative, drawn as a fraction of two differentials: `dQ/dt`, `∂P/∂t`.
`order` above 1 puts the order on both `d`s.
"""
@document struct MathDerivative <: MathDocument
    body::Document
    variable::Document
    order::Int = 1
    kind::Symbol = :total
end

"""
A function applied to an argument: `sin x`, `log₂(n)`, `Q(x)`. The name is
upright. `base` renders as a subscript on the name, which is what makes a
logarithm's base.
"""
@document struct MathFunction <: MathDocument
    name::String
    argument::Document
    base::Any = nothing
    parenthesized::Bool = true
end

MathFunction(name::AbstractString, argument::Document;
             base=nothing, parenthesized::Bool=true) =
    MathFunction(Cell(String(name)), Cell(argument), Cell(base),
                 Cell(parenthesized), Cell(nothing))

"""
An accent above a base: `:bar`, `:hat`, `:vec`, `:dot`, `:ddot` or `:tilde`.
"""
@document struct MathAccent <: MathDocument
    base::Document
    accent::Symbol
end

# ── Grids ─────────────────────────────────────────────────────────────────────

"""
A matrix or a vector: `elements` in row-major order, `columns` per row, inside
the delimiter pair named by `delimiter`.
"""
@document struct MathMatrix <: MathDocument
    elements::CellVector
    columns::Int
    delimiter::Symbol = :bracket
end

"""
One branch of a piecewise definition: a `value` and the `condition` it holds
under. An absent condition is the `otherwise` branch.
"""
@document struct MathCase <: MathDocument
    value::Document
    condition::Any = nothing
end

"""
A piecewise definition — a brace around a column of `MathCase`s.
"""
@document struct MathCases <: MathDocument
    cases::CellVector = CellVector()
end

# ── Operator tables ───────────────────────────────────────────────────────────

# The two projections read different columns of one table: the linear one prints
# `text` (ASCII where ASCII exists, a backslash name where it does not, so the
# saved line stays unambiguous), the graphics one draws `glyph`, and both space
# the operator by `class`.
const _MATH_OPERATORS = Dict{Symbol, Tuple{String, String, Symbol}}(
    # symbol        text        glyph  class
    :+          => ("+",        "+",   :binary),
    :-          => ("-",        "−",   :binary),
    :*          => ("*",        "*",   :binary),
    :/          => ("/",        "/",   :binary),
    :times      => ("\\times",  "×",   :binary),
    :cdot       => ("\\cdot",   "⋅",   :binary),
    :divide     => ("\\div",    "÷",   :binary),
    :pm         => ("\\pm",     "±",   :binary),
    :mp         => ("\\mp",     "∓",   :binary),
    :cup        => ("\\cup",    "∪",   :binary),
    :cap        => ("\\cap",    "∩",   :binary),
    :oplus      => ("\\oplus",  "⊕",   :binary),
    :otimes     => ("\\otimes", "⊗",   :binary),
    :(=)        => ("=",        "=",   :relation),
    :ne         => ("!=",       "≠",   :relation),
    :lt         => ("<",        "<",   :relation),
    :gt         => (">",        ">",   :relation),
    :le         => ("<=",       "≤",   :relation),
    :ge         => (">=",       "≥",   :relation),
    :approx     => ("\\approx", "≈",   :relation),
    :equiv      => ("\\equiv",  "≡",   :relation),
    :sim        => ("\\sim",    "∼",   :relation),
    :in         => ("\\in",     "∈",   :relation),
    :subset     => ("\\subset", "⊂",   :relation),
    :to         => ("->",       "→",   :relation),
    :propto     => ("\\propto", "∝",   :relation),
    :comma      => (",",        ",",   :punctuation),
    :semicolon  => (";",        ";",   :punctuation),
    :factorial  => ("!",        "!",   :postfix),
    :not        => ("\\neg",    "¬",   :prefix),
)

"""
    _operator_string(op) -> String

The operator as one line of text. Used by the linear projection and by every
text export.
"""
function _operator_string(op::Symbol)
    entry = get(_MATH_OPERATORS, op, nothing)
    entry === nothing && return string(op)
    entry[1]
end

"""
    get_math_operator_glyph(op) -> String

The operator as it is set on the page: a real minus sign, a real multiplication
dot. Used by the graphics projection.
"""
function get_math_operator_glyph(op::Symbol)
    entry = get(_MATH_OPERATORS, op, nothing)
    entry === nothing && return string(op)
    entry[2]
end

"""
    get_math_operator_class(op) -> Symbol

`:binary`, `:relation`, `:punctuation`, `:prefix` or `:postfix`. The class
decides how much space surrounds the operator.
"""
function get_math_operator_class(op::Symbol)
    entry = get(_MATH_OPERATORS, op, nothing)
    entry === nothing && return :binary
    entry[3]
end

# ── Symbol table ──────────────────────────────────────────────────────────────

const _MATH_SYMBOLS = Dict{Symbol, String}(
    :alpha => "α", :beta => "β", :gamma => "γ", :delta => "δ", :epsilon => "ε",
    :zeta => "ζ", :eta => "η", :theta => "θ", :iota => "ι", :kappa => "κ",
    :lambda => "λ", :mu => "μ", :nu => "ν", :xi => "ξ", :pi => "π",
    :rho => "ρ", :sigma => "σ", :tau => "τ", :upsilon => "υ", :phi => "φ",
    :chi => "χ", :psi => "ψ", :omega => "ω",
    :Gamma => "Γ", :Delta => "Δ", :Theta => "Θ", :Lambda => "Λ", :Xi => "Ξ",
    :Pi => "Π", :Sigma => "Σ", :Upsilon => "Υ", :Phi => "Φ", :Psi => "Ψ",
    :Omega => "Ω",
    :infty => "∞", :ell => "ℓ", :emptyset => "∅", :partial => "∂",
    :nabla => "∇", :prime => "′", :degree => "°", :dots => "…",
    :cdots => "⋯", :vdots => "⋮", :ddots => "⋱",
    :forall => "∀", :exists => "∃",
    :rightarrow => "→", :leftarrow => "←", :leftrightarrow => "↔",
    :uparrow => "↑", :downarrow => "↓", :mapsto => "↦",
)

"""
    get_math_symbol_glyph(name) -> String

The glyph of a named symbol. An unknown name renders as its own text, so a
half-typed name is still visible.
"""
get_math_symbol_glyph(name::Symbol) = get(_MATH_SYMBOLS, name, string(name))

# ── Large operators ───────────────────────────────────────────────────────────

# glyph, and the name the linear form writes.
const _MATH_BIG_OPERATORS = Dict{Symbol, Tuple{String, String}}(
    :sum              => ("∑", "\\sum"),
    :prod             => ("∏", "\\prod"),
    :coprod           => ("∐", "\\coprod"),
    :integral         => ("∫", "\\int"),
    :double_integral  => ("∬", "\\iint"),
    :triple_integral  => ("∭", "\\iiint"),
    :contour_integral => ("∮", "\\oint"),
    :union            => ("⋃", "\\bigcup"),
    :intersection     => ("⋂", "\\bigcap"),
    :bigoplus         => ("⨁", "\\bigoplus"),
    :bigotimes        => ("⨂", "\\bigotimes"),
    :lim              => ("lim", "\\lim"),
    :max              => ("max", "\\max"),
    :min              => ("min", "\\min"),
    :sup              => ("sup", "\\sup"),
    :inf              => ("inf", "\\inf"),
    :argmax           => ("argmax", "\\argmax"),
    :argmin           => ("argmin", "\\argmin"),
)

# `lim`, `max` and their kin are set upright in the text size, not as one large
# glyph — that is the whole difference between a word operator and a sign.
const _MATH_TEXT_OPERATORS = Set{Symbol}(
    [:lim, :max, :min, :sup, :inf, :argmax, :argmin])

"""
    get_math_big_operator_glyph(op) -> String

The sign of a large operator, or its word when the operator is a word.
"""
get_math_big_operator_glyph(op::Symbol) =
    haskey(_MATH_BIG_OPERATORS, op) ? _MATH_BIG_OPERATORS[op][1] : string(op)

"""
    get_math_big_operator_name(op) -> String

The name the linear form writes for a large operator: `\\sum`, `\\int`.
"""
get_math_big_operator_name(op::Symbol) =
    haskey(_MATH_BIG_OPERATORS, op) ? _MATH_BIG_OPERATORS[op][2] : "\\" * String(op)

"""
    is_math_big_operator_text(op) -> Bool

True for a word operator (`lim`, `max`), which is set upright and not enlarged.
"""
is_math_big_operator_text(op::Symbol) = op in _MATH_TEXT_OPERATORS

# ── Delimiters ────────────────────────────────────────────────────────────────

const _MATH_DELIMITERS = Dict{Symbol, Tuple{String, String}}(
    :parenthesis => ("(", ")"),
    :bracket     => ("[", "]"),
    :brace       => ("{", "}"),
    :absolute    => ("|", "|"),
    :norm        => ("‖", "‖"),
    :angle       => ("⟨", "⟩"),
    :floor       => ("⌊", "⌋"),
    :ceiling     => ("⌈", "⌉"),
    :none        => ("", ""),
)

"""
    get_math_delimiter_strings(kind) -> (String, String)

The opening and the closing delimiter of a grouping kind, one character each.
The graphics projection grows them; the linear one prints them as they are.
"""
get_math_delimiter_strings(kind::Symbol) = get(_MATH_DELIMITERS, kind, ("(", ")"))

# ── Accents ───────────────────────────────────────────────────────────────────

# A wide accent (a bar, an arrow) covers the whole base and is drawn to the
# base's width; a narrow one (a hat, a dot) is one glyph centered above it.
const _MATH_WIDE_ACCENTS = Set{Symbol}([:bar, :vec, :overline, :widehat, :widetilde])

"""
    is_math_accent_wide(accent) -> Bool

True when the accent covers the whole base and must be drawn to its width.
"""
is_math_accent_wide(accent::Symbol) = accent in _MATH_WIDE_ACCENTS


include("MathToSyntax.jl")
include("MathToGraphics.jl")

end # module
