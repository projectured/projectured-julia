# Julia domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [serialization.md](../../platform/serialization/serialization.md)

The Julia domain, `ProjecturedJulia`, holds Julia source code as a tree of reactive documents. Other domains embed its expressions: a state machine guard, a process action and a formula are Julia code. This document says where it differs from the [shape of every domain](../../../design/domain-anatomy.md).

<img width="396" alt="Julia example" src="../../../asset/image/example/julia.png">

## How it works

`JuliaDocument` has about fifty concrete types, in three groups:

- **Literals:** `JuliaIdentifier`, `JuliaInteger`, `JuliaFloat`, `JuliaString`, `JuliaBool`, `JuliaSymbol`, `JuliaChar`.
- **Expressions:** `JuliaCall`, `JuliaBinaryOperation`, `JuliaUnaryOperation`, `JuliaIndex`, `JuliaFieldAccess`, `JuliaTuple`, `JuliaArray`, `JuliaRange` and others.
- **Statements and definitions:** `JuliaBlock`, `JuliaToplevel`, `JuliaAssignment`, `JuliaIf`, `JuliaFor`, `JuliaWhile`, `JuliaTry`, `JuliaFunction`, `JuliaStruct`, `JuliaModuleDefinition`, `JuliaUsing`, `JuliaDocstring` and others.

A variable-length list of children is a `CellVector`: `arguments`, `statements`, `params`. `JuliaEmpty` prints nothing, for example a missing `else` branch. It is not the same as `JuliaNothing`, the `nothing` literal.

`JuliaNothing` is also the empty placeholder of the domain. So the domain adopts its own types in the `@domain` call:

```julia
@domain Julia root = JuliaDocument nothing = JuliaNothing insertion = JuliaInsertion
```

### The parser

`parse_julia(text)` calls `Meta.parseall`, the parser of Julia itself, and converts the `Expr` tree into documents in one recursive pass. It has one `_convert_head(::Val{head}, x)` method for each `Expr` head. It builds no syntax tree of its own. Where the `Expr` tree has one shape for two spellings, the document has one type: `a ? b : c` and `if` both become `JuliaIf`, and `begin … end` becomes `JuliaBlock`. A head with no converter raises an error. A call of an infix operator becomes a `JuliaBinaryOperation`, so it prints between its operands: the arithmetic and comparison operators, `%`, `÷`, `isa`, `in`, `∈`, `∉`, `=>`, `|>`, and the dotted forms of the arithmetic and comparison operators. Any other callee stays a `JuliaCall`. Statements on one line with `;` between them have a `:toplevel` of their own in the `Expr` tree, and they become a `JuliaToplevel`, which prints them on their line. The `Expr` tree does not say whether a `;` follows the last statement, so `parse_julia` reads that from the tokens of the text and sets `trailing_semicolon`. A `;` inside `begin … end` separates statements of that block.

### The printer

`JuliaToSyntax()` is a `TypeDispatchingProjection` of `@projection_template` rules, one for each type. A `JuliaBinaryOperation` puts parentheses around an operand that binds looser than its operator, by the order of the Julia manual: `=>`, `||`, `&&`, the comparisons, `|>`, the additions, the multiplications and `^`. The parser folds a chained comparison `a < b < c` to the left, and a comparison associates to the left in the printer, so the chain prints as it was written. The template markers cover the keyword headers, the coloured callee and the lists of variable length.

The last entry of the dispatch is `Document => JuliaObjectToSyntaxLeaf()`. The dispatch takes the first entry that matches, so no Julia node reaches it: it draws a document that is not Julia, an object that stands in the code, as one leaf with its title in angle marks, `⟨a.json⟩`, or its type name when it has no title. It is the one leaf written by hand, because the reader of a template would give a key on the label to the object's own table. It answers no key, maps a whole selection both ways, and shows a selection only when the object is selected whole. A chain that recurses through this table, as `print_natural_text` does, draws the label; a bare `NaturalToGraphics` recurses a child of the code through its own shared table by the child's own type, and would draw a pasted object as the reflected tree of its own domain instead of the leaf above. So `__init__` registers `JuliaDocument` with `register_natural_graphics!(:julia_code, …)`, a closed chain of `JuliaToSyntax()`, `SyntaxToText()` and `TextToGraphics()`: every natural renderer then draws Julia code through this one table, and an object pasted into the code stays one leaf in every tab and every transcript, not only in a host that names Julia itself. A domain that embeds Julia code passes the entries of its own types to `JuliaToSyntax(entries...)`, which puts them before that last entry: `FsmToSyntax()`, `FormulaToSyntax()` and `ProcessToSyntax()` do so.

The leaves are opaque: they have no `bound` marker. So a caret selects an identifier, a number or a string as a whole, and does not go into its characters. A `bound` leaf needs the flat-offset mapping of JSON for the tokens that no document field produces, such as `function`, `(` and `end`.

### The expression

`make_julia_expression(document)` gives the `Expr(:toplevel, …)` that runs a Julia document, the shape `Meta.parseall` gives. It copies the document with `copy_document` under a copy policy whose stop hooks put a placeholder identifier where a node that is not Julia stands, prints the copy, parses the text, and puts each object back as a `QuoteNode`. So an evaluation uses the object itself, and a noted live object keeps its identity. A hole stands for the parse of its text, because its print adds the completion; a hole whose text does not parse raises an error. The domain registers the function as the expression of its format, `:jl`, in the natural seam.

### Type-in

`JuliaInsertion` is a text buffer. The `@gestures JuliaInsertion` table does the editing, the commit and the navigation, so `JuliaInsertionToSyntaxLeaf` only prints the buffer and a pale-green completion. On commit, a complete keyword (`function`, `if`, `while`, `for`, `begin`, `return`) expands into a scaffold with holes, and the first hole is selected. Any other text goes to `parse_julia`.

### The file

`JuliaFile` holds a `.jl` file. A reference to a node in another file is the call `pred_ref("<<file(\"path\")>>")`, so the file stays valid Julia. `find_julia_definition(document, name)` finds a top-level definition by its name. It is the `definition` verb of the marker language, so `definition(file("steps.jl"), "queue_step")` names one function of a file. No match, or more than one, raises an error.

A `JuliaFunction` gives its call signature as its tooltip, and a `JuliaDocstring` gives the signature and the text.

### The duplicate

`has_document_duplicate` is `true` for every `JuliaDocument`, because Julia code is what a person typed. A duplicated pane copies the code into nodes of its own, and an edit in one pane does not change the other. The code of an evaluator form is a Julia document, so a duplicated evaluator does not type into the original. See [document.md](../../kernel/document.md#the-duplicate).

### The theme

`JuliaTheme` holds the look of the Julia projections: the text of an identifier, a literal, punctuation, a keyword, a symbol, an operator, a called function, a module name and plain text, the completion hint, and the colors of a typed name that names nothing and of one that names one thing. Each value has
the default that the domain draws with no appearance. A projection holds its
styles as fields, and no theme; nothing in it scales or asks whether a theme is
scaled. `JuliaToSyntax(entries...; theme, syntax_theme)` gives each projection the style of
its role with `get_julia_style`, from `theme`, a `JuliaTheme` scaled or not, or the
default styles for `nothing`, and the entries that a domain adds keep their own
styles. The natural registration gives the scaled theme of the `Appearance` of
the editor, so the view follows its scales, and the appearance tab shows a
section for `JuliaTheme`.

## How it fits

`ProjecturedJulia` depends only on the engine and the platform. The domains that embed Julia code depend on it: `ProjecturedFSM`, `ProjecturedProcess` and `ProjecturedFormula`. `ProjecturedFormula` copies the dispatch table of `JuliaToSyntax()` and adds its own rules, so one recursion prints a tree that mixes Julia and formula nodes.

Its `__init__` registers the natural notation (format `:jl`, extension `.jl`, parser `parse_julia`), `JuliaFile` for `.jl`, the `:definition` marker verb, and the graphics factory `:julia_code` that closes the dispatch of `JuliaToSyntax` for every natural renderer.

**The code of a Julia file has a gutter.** `make_graphics_projection(::Type{JuliaFile})` gives a file the view `make_julia_file_code_projection`: `JuliaToSyntax`, `SyntaxToText` with text folds, `TextLineNumbering`, `TextFolding` and `TextBlockToScrollLayout`. The scroll pane of the file tab takes its `ScrollLayout` apart, so the numbers and the fold triangles stay at the left edge, and a closed node hides its lines while the numbers still count them. A Julia document inside another document, such as a message or a value of a form, draws by the row of `:julia_code`, with no gutter. A docstring, and a string of many lines, is one leaf value that holds `'\n'`, so it is one line with rows, and its closing fence joins the line after it: the numbers count such a block as one line, until the plan [a-text-span-holds-no-line-break.md](../../../../plan/pending/a-text-span-holds-no-line-break.md) makes it lines.

## Design decisions

- **The parser of Julia itself.** A hand-written grammar would drift from the language. `Meta.parseall` is in Base, so it adds no dependency. See [plan/done/julia-parser.md](../../../../plan/done/julia-parser.md).
- **One document type for one `Expr` shape.** The document can not keep a difference that the `Expr` tree does not keep. See [plan/done/julia-basic-language-support.md](../../../../plan/done/julia-basic-language-support.md).
- **Type-in is a gesture table on the document.** The insertion leaf has no reader of its own, as `@gestures PrimitiveString` does for a string. See [plan/done/julia-typein-operations.md](../../../../plan/done/julia-typein-operations.md).
- **Every rule is a template.** A set of hand-written reference maps was tried, and it left the structural tokens without a caret. The template rules give every token a caret. See [plan/pending/julia-syntax-navigation.md](../../../../plan/pending/julia-syntax-navigation.md).

## Usage

```julia
code = parse_julia("function f(x)\n    x + 1\nend")   # one statement: a bare JuliaFunction
code.name                                     # the JuliaIdentifier `f`
parse_julia("a = 1\nb = 2")                   # two statements: a JuliaBlock
parse_julia("x = 1;")                         # a JuliaToplevel with trailing_semicolon
print_natural_text(code)                      # back to source text
run_example("julia")
```

- Examples: `julia_example`, from `make_julia_document_example()` and `make_julia_projection_example()`. The atomic catalog has about fifty documents, one for each type.
- Test: `test_julia()` runs the layering guard, the parser test, the definition test and the type-in test.

## Limits

- A caret does not go into the characters of a leaf. `test_position_navigation(julia_example; check_reaches_all = true)` has 28 failures for this reason. [plan/pending/julia-syntax-navigation.md](../../../../plan/pending/julia-syntax-navigation.md) tracks it.
- A formula evaluates only a subset of the Julia types; see [formula.md](../formula/formula.md).
