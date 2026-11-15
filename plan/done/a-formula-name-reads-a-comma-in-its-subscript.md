# A formula name reads a comma in its subscript

## 1. The request

In three takes of the video of the Aloha study, the agent named formulas with a
comma in the subscript, such as `U_{slotted,5}(G) = (T/s) G (1 - G/5)^4`. The
sheet showed `#ERROR! UndefVarError: G not defined in Main.FormulaScratch`. The
same formula named `U_slotted5(G)` works. The owner chose to fix it
(2026-10-27): the parser reads a comma in a subscript, and a name that does not
read gives an error that names the failure of the reading.

## 2. Facts

- The lexer makes `,` a `:comma` token (`MathParser.jl`), but `_parse_script`
  reads one expression in `{…}` and then expects `}`. Only a matrix and the
  cases read a comma.
- The operator table already holds `:comma` as a binary operator of the class
  `:punctuation` (`MathDocument.jl`), so the document and its projections know
  `MathBinaryOperation(:comma, a, b)`. Only the reader never makes one.
- `get_formula_key` and `_find_formula_parameter` swallow a failure of
  `parse_math`: the key is the text of the name, and the parameter is
  `nothing`. `convert_formula_to_expr` then gives the body with no lambda, so
  the body runs with no `G`.
- A name that reads as no math is allowed and is itself, such as a name with
  words in parentheses, so a failure of the reading alone is no error.

## 3. Steps

- [x] 1. The reader reads a comma list in braces, `{a,b,c}`, as `:comma`
  operations from the left. `U_{slotted,5}` is `U` with the subscript
  `slotted,5`, and its Julia name is `U_slotted_5`: `_name_of_node` joins the
  names of the parts with `_`. Tests: `MathParserTest.jl` (a comma in a
  subscript reads, and its line reads back), `FormulaNameTest.jl` (the key and
  the parameter of `U_{slotted,5}(G)`), and a sheet that computes it.
  Done. The rule of the comma is `_subscript_name`, used by a script and by
  the key of a function, and not `_name_of_node`: that one also names a bound
  variable, where a comma list must not read as one name.
- [x] 2. A formula whose name ends in `(X)` and does not read, where `X` is a
  free name of its code, gives `#ERROR!` with the failure of the reading of
  its name, not `X not defined`. Test: `FormulaNameTest.jl` or the evaluation
  test, with a name that does not read, such as `U_{slotted;5}(G)`.
  Done: `_check_function_name`, called by `convert_formula_to_expr` when the
  name gives no parameter. A name with words in parentheses whose code does
  not name the words stays a plain name. The sheet now shows
  `#ERROR! the name "V_{slotted;5}(G)" does not read as a function of G: math: …`.
- [x] 3. Run `test_formula()` and `test_math()`, the suites of the two
  packages. Done in `environment/all`: ProjecturedMath 215 pass,
  ProjecturedFormula 308 pass, nothing broken.
