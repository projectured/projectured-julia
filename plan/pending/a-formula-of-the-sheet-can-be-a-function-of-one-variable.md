# A formula of the sheet can be a function of one variable

> **Kind:** plan · **Status:** pending, written 2026-10-26 from a survey of
> projectured-julia `main` at `31b19cda3` and omnet-julia `main` at `139bd1bec`;
> revised the same day after the owner's answer to the first Q1 (§1), and again
> after the owner's answers to Q1, Q2 and Q3 (§8). Not started. No question is
> open. · **Scope:**
> `ProjecturedMath` (the reader of the linear form), `ProjecturedFormula`,
> `ProjecturedResearch`, `ProjecturedChart`; and in omnet-julia
> `OmnetLegacyResultPresentation` and `OmnetIde` (§7, the omnet half). ·
> **Sibling plan:** omnet-julia
> `plan/pending/the-assistant-carries-out-an-aloha-study-on-the-legacy-simulator.md`,
> §6.5 and Step 4 ("A curve samples a formula of the sheet. Not built"). The
> omnet half of this plan closes that step. · **Stands on:**
> [formula.md](../../documentation/package/domain/formula/formula.md),
> [math.md](../../documentation/package/domain/math/math.md),
> [chart.md](../../documentation/package/domain/chart/chart.md),
> [cell.md](../../documentation/package/kernel/cell.md) (a provisional value),
> [formula-references-by-name.md](../done/formula-references-by-name.md).

## 1. Goal

A formula of a sheet can name one parameter, as Mathcad does. The formula is
then a Julia function, and a chart draws any function:

```julia
S_pure = add_study_formula!(study, "S_{pure}(G)", "G e^{-2G}")
S_pure(0.5)                      # 0.18394…
get_formula_value(S_pure)        # the function itself
add_study_formula!(study, "S_{peak}", "S_{pure}(0.5)")        # another formula calls it

make_result_plot(summary; x = "G", series = ["slot", "N"], project,
                 curves = ["textbook, pure" => S_pure, "a guess" => G -> 0.9G * exp(-2G)])
```

The owner chose this shape on 2026-10-26, first as "Option (a)", then in the
answer to the first Q1: "a formula (math or Julia based) should be possible to
turn into a Julia executable function, which in turn should be plottable just
like any other function, either by sampling or passing the function to the
plot", and "yes" to the three parts: a formula of one variable is callable; the
chart domain gets a `ChartFunctionSeries` of any callable; the omnet plot hands
each curve to it, and omnet names no formula. Two gaps that the assistant hit
in the run of 2026-10-25 close too: `get_formula_value` takes a formula read
back from a study, and `e` is Euler's number.

## 2. Current state

- **A name is a key.** `get_formula_key(name)` (`FormulaDocument.jl:95`) reads
  a name as one line of math and takes it when it reads as an identifier, so
  `p_{block}` is `p_block`. Any other name is its own text.
  `resolve(env, name)` (`:79`) compares keys.
- **The free names of the code bind to the sheet.** `get_formula_names(code)`
  (`:166`) walks the code from an empty set of bound names
  (`_find_free_identifiers`, `:171`). `evaluate_formula` (`:500`) and the job of
  the formula task (`_make_formula_job`, `FormulaComputation.jl:38`) bind each
  name that resolves to the stored value of its formula in a `let`, and run the
  `Expr` of `convert_formula_to_expr(code, env)` (`:480`) in a scratch module
  (`_run_formula_code`, `:520`). A free name that resolves nowhere stays for
  Julia, so the `G` of `G exp(-2G)` raises `UndefVarError`.
- **A value can already be a function.** `F = x -> x^2` in Julia code gives a
  closure, and `G = F(3)` gives `9`. Math code has no lambda. A
  `FormulaFormula` is not callable.
- **The key of a stored value** is the hash of the code text and of the keys
  of its inputs (`compute_formula_key`, `FormulaComputation.jl:16`).
- **The math reader.** "A name directly before `(` is a function"
  (`MathParser.jl:325`, `:382`): a letter or a word before `(` gives a
  `MathFunction`, so `f(x)` and `exp(1)` are calls, and a word with a braced
  subscript, `log_{2}(x)`, is a `MathFunction` with a `base`. A Greek letter
  and a one-letter name with a subscript are not: `ρ(1 - ρ)` and `S_{pure}(G)`
  read as rows, `rho * (1 - rho)` and `S_pure * G`. So the spelling decides
  between a call and a product. The reading has no sheet
  (`convert_math_to_julia(tree)`, `MathToJulia.jl:34`), and the reading of a
  function with a base other than `log` refuses (`:98`). A function name draws
  upright (`MathToGraphics.jl:1341`). A comma inside `(…)` is refused. `e`
  reads as the free name `e`, which no module binds, so `G e^{-2G}` fails and
  `exp(1)` works.
- **A rename by keys starts no computation**, because today a rename does not
  change a value (`_read_rename`, `FormulaToSyntax.jl`).
- **A view shows only the stored value, and no print runs the code of a
  formula** (formula.md, "Evaluation"). `_format_stored_formula_value`
  (`FormulaDocument.jl:599`) prints a closure as
  `#3 (generic function with 1 method)`.
- **`get_formula_value`** has one method, for `FormulaFormula` (`:584`). A
  formula that a model reads back from a study, such as
  `get_study().analyses[1].method.formulas[3]`, is a `ReferencedDocument`, and
  the call raises a `MethodError`.
- **A loaded study does not compute its sheet.** omnet's `_open_study_pane!`
  (`StudyVerbs.jl:247`) posts `AcquireDocumentOperation(study)` and says that
  "its sheet computes", but no method of `acquire_document!` exists for
  `ResearchStudy`, so the default starts nothing.
- **The kernel tells a computation apart.** `is_computation_running()`
  (`ReactiveCell.jl:651`) says whether a computation runs on this task, and
  `mark_computation_provisional!()` makes its value provisional while a value
  that a task computes is still to come.
- **The chart draws only stored columns.** Each series holds whole columns
  (`ChartDocument.jl:169`). The renderer takes the x and y bounds of each series
  (`_series_x_bounds`, `_data_bounds`, `ChartPlotToGraphics.jl:110`, `:176`) and
  fits the window over them (`_compute_fit_view`, `:249`) in one computed cell
  of the frame, which also the readers of the gestures call. No series takes a
  function.
- **The plot view of omnet** holds selections, `x_column` and
  `series_columns` (`LegacyResultView.jl:78`). Its printer reads the summary
  from the files in the print (`_read_plot`, `LegacyResultViewToDocument.jl:176`)
  into a `LegacySimulationPlotDocument`, which `_chart_of`
  (`LegacySimulationPlotToChart.jl:56`) turns into a `Chart`.

No file that this plan touches is sealed: `SEALING.md` of projectured seals
only kernel files, and omnet's lists the files of this plan as ⬜.

## 3. Design of the projectured half

### 3.1 The parameter lives in the name (D1)

The name holds the parameter as the person writes it: `S_{pure}(G)`. A name
that parses as a name with one name in parentheses (the node of §3.2) is a
function name:

| name | key | parameter |
| --- | --- | --- |
| `S_{pure}(G)` | `S_pure` | `G` |
| `f(x)` | `f` | `x` |
| `P_{block}(ρ)` | `P_block` | `rho` |
| `S_{pure}` | `S_pure` | none |
| `f(x, y)` | `f(x, y)` (its text, as an unreadable name today) | none |

`get_formula_key` answers the key; a private `_find_formula_parameter(formula)`
answers the parameter or `nothing`. Both read the name with the same math
reading, so `ρ` and `rho` are one parameter, as they are one name.

- **The file** writes the name as it is:
  `FormulaFormula(name = "S_{pure}(G)", code = "G e^{-2 G}", notation = :math, display_mode = :both)`.
  No new argument, and an old file reads as before.
- **The sheet** draws the name as it draws any name: the text view shows the
  text, the graphics row draws `S_pure(G)` as a math function.
- **A rename** works as today: a key in `S` or `pure` changes the key, and the
  uses follow. A key in the parameter changes the parameter and not its uses in
  the code (§9, limits). A rename that adds, removes or changes the parameter
  computes the formula again (§3.10).

### 3.2 What a name with an argument means follows the sheet (D2)

The meaning of `name(…)` follows what the name is, not how it is spelled, as in
Desmos and Mathcad. The parser reads the shape; the reading into Julia, which
knows the sheet, reads the meaning.

- **The parser** reads any name directly before `(` as one neutral node, a name
  with an argument in parentheses: a letter `f(2)`, a Greek letter `ρ(1 - ρ)`,
  a word `exp(1)`, a name with a braced subscript `S_{pure}(0.5)` and
  `log_{2}(x)`. The node is the `MathFunction` that the parser already makes for
  `f(x)` and `exp(1)`: `name`, the subscript as `base`, and the `argument`. Its
  docstring says that it is neutral. A space keeps a row: `ρ (1 - ρ)`. The
  parser does not know the sheet, and the node prints the same text whatever it
  means, so a line reads back to the tree that prints it.
- **The drawing** is the same whatever the node means. Its name draws as the
  name draws alone: a letter and a lowercase Greek letter slanted, as a
  variable; a word upright, as `exp`; the subscript below. So `ρ(1 - ρ)` keeps
  the slanted `ρ` that it has as a row today.
- **The reading** decides, with the names of the functions of the sheet:
  `convert_math_to_julia(tree; functions = ())`, where `functions` holds the
  key of each formula of the sheet whose name names a parameter (§3.1). The
  name of the node reads as a name reads alone, `ρ` as `rho` and `S_{pure}` as
  `S_pure`. Then:

  | the name | the node reads as |
  | --- | --- |
  | the key of a formula of the sheet that names a parameter | a call: `S_pure(0.5)` |
  | the key of a formula of the sheet that names none | a product: `rho * (1 - rho)`, `f * 2` |
  | no formula of the sheet, and a function of the notation | a call: `exp(1)`, `sqrt(x)` |
  | no formula of the sheet, and any other name | a product |
  | `log` with a subscript | `log(2, x)`, as today |

  A name of the sheet wins over a function of the notation, as a formula named
  `pi` wins over Julia's `pi`. The functions of the notation are a fixed list in
  `MathToJulia.jl`: `exp`, `log`, `log2`, `log10`, `sqrt`, `cbrt`, `sin`, `cos`,
  `tan`, `asin`, `acos`, `atan`, `sinh`, `cosh`, `tanh`, `abs`, `sign`,
  `floor`, `ceil`, `round`, `factorial`, `min`, `max`. A comma in the
  parentheses can only be a call, whatever the name; the parser refuses a comma
  there today, and a plan of functions of several variables adds it (§10).
- **The names of a formula are the same in both readings.** A call `f(2)` and a
  product `f * 2` hold the identifiers `f` and nothing else, so
  `get_formula_names`, which reads with no sheet, finds each name, and the walk
  of the dependencies, the order of computation (`_order_formulas`) and the
  check of a cycle do not change. The order puts a function before each formula
  that calls it, because the caller names it.
- **The expression** of math code reads with the sheet:
  `convert_formula_to_expr(code::MathDocument, env)` passes the function names
  of `env`, on the loop, when the job of a formula is prepared, and in
  `evaluate_formula`.

No text in projectured-julia or omnet-julia holds a Greek or a subscripted name
directly before `(` today (grep of 2026-10-26).

### 3.3 The generated Julia (D3)

The value of a function formula is a closure. The code runs inside the `let`
of today, and the parameter binds in a lambda inside it:

```julia
let T = <stored value of T>        # every other free name that resolves
    G -> G * exp(-2 * G)           # the parameter, bound by the lambda
end
```

- `convert_formula_to_expr(formula, env)`, a new method of the exported
  function, wraps the `Expr` of the code in `Expr(:->, :G, body)` when the
  formula has a parameter. `_make_formula_job` and `evaluate_formula` call it.
- `get_formula_names(formula)`, a new method of the exported function, walks
  the code with the parameter bound. So the parameter is no dependency, and it
  shadows a formula of the sheet with the same name, as a lambda parameter does
  today. Every walk that starts at a formula takes this method:
  `get_formula_dependencies`, `compute_formula_key`, `_depends_on_itself`,
  `_find_reference_identifiers`, `_find_identifier_scopes` and the rename
  check.
- `compute_formula_key` hashes the parameter too, so a new parameter computes
  the value again.
- Each other name binds to the stored value of its formula when the function
  computes. A new value of that formula computes the function again, and each
  formula that calls it computes again, as for any input.
- A function that reaches itself is a cycle, `#CYCLE!`, as today.

### 3.4 The sheet draws a function as its equation (D4)

A function has no one-line text that a person reads. A row of a formula whose
stored value is a function shows the equation and no value:
`S_{pure}(G) = G e^{-2G}`. While a computation of it runs, the row shows the
mark alone: `S_{pure}(G) = G e^{-2G} ⋯`. The rule holds for `F = x -> x^2`
too. The grid is not affected: `S_{pure}(G)` is no cell name.

### 3.5 `e` is Euler's number (D5)

`_make_formula_scratch_module()` binds `e` to `Base.MathConstants.e` in each
scratch module. The `let` of the sheet is the innermost scope, so a formula of
the sheet named `e` still means that formula, as a formula named `pi` does
today. The guide says so in one sentence.

### 3.6 A formula read back from a study (D6)

`get_formula_value(formula::ReferencedDocument)` forwards to
`get_document(formula)`, as `print_natural_text` and `find_pivot_value` do. The
call of §3.8 takes a referenced formula in the same way: a call method on a
`ReferencedDocument` of a formula, in the formula domain.

### 3.7 A study computes its sheets when it enters the window (D7)

`acquire_document!(editor, study::ResearchStudy)` holds each sheet that an
analysis of the study holds as its method, with `hold_documents!`, and
`release_document!` releases them with `release_held_documents!`. The acquire
of the sheet computes its values (`FormulaComputation.jl:239`). So
`open_study!` gives the sheet its stored values, and a chart that calls a
formula of the study finds its function. A sheet that a later analysis adds
needs no hold: `add_study_formula!` computes each formula that it adds.

### 3.8 A formula is callable (D8)

`(formula::FormulaFormula)(x)` calls the function of the formula. It follows the
rule of the domain: **a computation never runs the code of a formula; it reads
the stored value.**

| where the call runs | the function it calls | when there is none |
| --- | --- | --- |
| outside a computation: a script, a verb, a code unit | `get_formula_value(formula)`, computed on the calling task for the code and the inputs now | — |
| inside a computation: a print, such as the print of a chart | the stored value, `formula.result`, read as a cell, so a new value draws again | `ErrorException("S_{pure}(G) has no value yet")` |

Inside a computation, while a computation of the formula runs, the call takes
the stored function of the old code and calls `mark_computation_provisional!()`,
because a newer value comes later: the sheet shows the old value with `⋯` in
the same state. In both places a `FormulaError` raises an `ErrorException` with
its text (`#ERROR! …`), and a value that is no function raises an
`ArgumentError` ("S_{pure}(G) is no function of one number"). The call goes
through `Base.invokelatest`, because the closure is newer than the world of the
task that calls it. `S_pure(0.5)` right after `add_study_formula!` answers
0.18394…, with the loop or without it.

### 3.9 A chart draws a function (D9, D10)

A new series of `ChartDocument.jl`:

```julia
ChartFunctionSeries(label, callable; x_range = nothing, sample_count = 200,
                    line_style = :solid, line_width = 1, color = nothing, visible = true)
```

`callable` is anything that takes one number and answers one: a Julia function,
a formula, a callable object. The chart samples it when it computes its frame,
as `plot(sin, 0, 2π)` does:

- **The x range.** The x bounds come first, from the other visible series and
  from `x_range` (a pair `(lower, upper)`) of each function series that has one.
  The series samples the x window that the plot shows: the fit of those bounds,
  or the window of a zoom, so a zoom samples again and shows more detail. With
  `x_range`, it samples only the part of the window inside that range. With no
  `x_range` and no other series, it has no range.
- **The samples.** `sample_count` points, evenly spaced over the range, each
  `Float64(Base.invokelatest(callable, x))`. The samples over the fit window
  give the y bounds of the series, so the fit holds the curve.
- **The line.** A line through the samples, with no marker and no interval,
  in the line style and the color of the series. It goes through the legend as
  a line series does, and a click on it selects the series. A function series
  has no sample to select.
- **No line.** A call that raises, or a value that is no real number, stops the
  samples. The series then draws no line, keeps its legend entry, and the entry
  says why after the label:

  | case | the legend entry |
  | --- | --- |
  | no range | `sin: no x range; give x_range` |
  | a formula with no stored value, in a print | `textbook, pure: S_{pure}(G) has no value yet` |
  | a formula whose value is an error | `textbook, pure: #ERROR! …` |
  | a formula whose value is no function | `textbook, pure: S_{pure}(G) is no function of one number` |
  | a call that raises, or a value that is no real number | `a guess: gives no number at x = 0.1` |

  While a formula computes, the line is the one of its stored function (§3.8).

One function of the renderer, `_compute_function_samples(series, lower, upper)`,
answers the samples or the reason, and every part that reads the bounds, the
line, the legend and the hit of a series calls it. **The print of the chart
calls the function** (D10, the owner's answer to Q2): 200 calls in the computed
cell of the frame, and 200 again at each new window, such as a zoom, or a new
function.

**The later route, if a drawn function is slow:** the series keeps its samples
in a cell that a background task fills, and the print draws the last samples
while new ones come. It waits because it needs two things that do not exist: a
place outside a print to make that cell (a background cell is made where its
document is built, never in a computation, and the chart builds its `ChartPlot`
in a print, as omnet builds its `Chart`), and a way to give the task the plain
function of a formula (the task must read no document, so it can not call a
formula; the chart would need a new generic that the formula domain
implements).

### 3.10 A formula that turns into a function computes again (D13)

A formula whose name turns from a number into a function, or back, changes
what the formulas that use it mean: `g = f(2)` is `f * 2` while `f` names no
parameter, and `f(2)` once the name is `f(x)`. So a rename that adds, removes
or changes the parameter of a formula also computes that formula: the sheet
rule adds `ComputeFormulasOperation(env, [formula])` to the compound of the
rename (`_read_rename`). Its key changes, because the key hashes the parameter
(§3.3), so its stored value is new, and each formula that names it computes
again with the new reading (`ReplaceFormulaResultOperation` computes the users
of a new value). `add_study_formula!` and a commit compute already. This is the
one key that starts a computation: a name has no edit mode, and the rename
writes the uses at once too.

A key that leaves the name unreadable on the way, such as the `(` of `f(`,
gives a key that is no identifier; the rename then writes no use, and the uses
keep the old key until the name reads again, as `f(x)` reads with the key `f`.

## 4. Decisions of the projectured half

The owner took the shape of §1, D2, D8 and D10 on 2026-10-26 (§8). The other
decisions are my recommendations, and the owner has not refused any.

- **D1. Where the parameter lives.** In the name, as written. *Reason:* the
  file, `add_study_formula!` and the rename need no change, and the name says
  what the sheet shows. A field of `FormulaFormula` needs a new argument in the
  file and a second place to edit; the code can not hold it, because math code
  has no lambda. One parameter only.
- **D2. The meaning of `name(…)` follows the sheet, not the spelling.**
  *Taken by the owner on 2026-10-26* (answer (b) to Q3, in place of my first
  D2, which made every subscripted name before `(` a call): the parser reads one
  neutral node, and the reading with the sheet makes a call of a function of the
  sheet or of the notation and a product of anything else (§3.2). I reuse
  `MathFunction` as the node, because the parser and both drawings have it for
  `f(x)` and `exp(1)` already; a new node would repeat it.
- **D3. The parameter binds in a lambda inside the `let`.** *Reason:* the other
  names keep the binding to the sheet that they have today, and the walk of free
  names treats the parameter as it treats a lambda parameter.
- **D4. A function shows no value text.** *Reason:* the brief's own form,
  `S_{pure}(G) = G e^{-2G}`; Mathcad shows none either.
- **D5. `e` is Euler's number, in the scratch module.** *Reason:* the textbook
  and the assistant write `G e^{-2G}`. A binding in the reading of the math
  (`e` as `ℯ`) would hide a formula of the sheet named `e`.
- **D6. Methods for `ReferencedDocument`.** *Reason:* the owner's rule that
  verbs combine through the forward of an interface, not a special case in a
  verb (2026-10-21).
- **D7. A study holds its sheets.** *Reason:* the comment of
  `_open_study_pane!` already says that the sheet computes; without the method
  a formula of a loaded study has no stored function, and its curve says so.
- **D8. The call reads the stored function inside a computation, and computes
  the value elsewhere.** *Reason:* a script must get `S_pure(0.5)` at once, as
  `get_formula_value` gives a value at once; and the owner's rule of 2026-10-13
  ("a formula value is computed off the loop: the value is stored in the
  document and updated outside the print") must hold for a chart that calls a
  formula. The kernel already tells the two places apart
  (`is_computation_running`) and has the state of a value still to come
  (`mark_computation_provisional!`). It needs no new mechanism. *Taken by the
  owner on 2026-10-26* (yes to Q1): in code the call computes the formula when
  it has no value yet; in a print it uses only the stored function, the old one
  and a provisional value while it computes, and no line with "no value yet"
  before the first value.
- **D9. The function series samples the window that the plot shows, 200
  points, and draws no line with a reason when it can not.** *Reason:* a zoom
  then shows detail, as for any other series; a reason in the legend tells the
  person what to fix, and a fault of the chart would stop the whole picture.
  With no range the series draws nothing rather than guess one.
- **D10. The print of the chart samples.** *Taken by the owner on 2026-10-26*
  (answer (A) to Q2, "for now"): 200 calls in the print, and again at each
  zoom. The samples kept in a cell that a background task fills are the later
  route, if a drawn function is slow; §3.9 says why it waits.
- **D13. A rename that changes the parameter computes the formula.** *Reason:*
  the owner's answer to Q3 says that the formulas that use a formula compute
  again when its name turns from a number into a function; the rename is the
  one place where a name changes after the formula exists, and the existing
  operation and the existing walk to the users do the rest. A rename to a name
  that does not read writes no use, so the keys on the way to `f(x)` break no
  use.

## 5. Steps of the projectured half

Each step is one commit with its own test. The projectured steps land on
`main` before the omnet half starts, because omnet reads projectured through
`[sources]`.

### Step 1 — a name with an argument is one node, and the reading decides (D2)

- [x] `MathParser.jl`: a Greek letter, and a letter followed by `_{…}`, directly
      before `(` give `MathFunction(name, argument; base = subscript)`, as a
      letter and a word do, with the look-ahead and the step back of
      `_parse_word`. The docstring of `MathFunction` says that the node is
      neutral.
- [x] `MathToGraphics.jl`: the name of the node draws as the name alone, a
      letter and a lowercase Greek letter slanted, a word upright.
- [x] `MathToJulia.jl`: `convert_math_to_julia(tree; functions = ())` and the
      table of §3.2, with the list of the functions of the notation.
- [x] Test: `test_math_parser()`: `ρ(1 - ρ)`, `S_{pure}(0.5)`, `f(2)` and
      `exp(1)` each read as the node and print back the same line; `ρ (1 - ρ)`
      reads as a row. `test_math_to_graphics()`: the name of `ρ(1 - ρ)` draws
      slanted, the name of `exp(1)` upright. `test_formula_math()`: with no
      `functions`, `ρ(1 - ρ)` reads as `rho * (1 - rho)` and `f(2)` as `f * 2`;
      with `functions = ["f", "S_pure"]`, `f(2)` reads as `f(2)` and
      `S_{pure}(0.5)` as `S_pure(0.5)`; `exp(1)` is a call with or without
      `functions`; `log_{2}(8)` reads as `log(2, 8)`;
      both readings of `f(2)` give the names `["f"]`.
- **As built:** the node is `MathFunction`; `_parse_subscripted_call` (letter or
  letter symbol with `_{…}` and `(` directly after) and `_parse_symbol` (a letter
  symbol, glyph or `\rho`, with `(` directly after) make it, and a Greek letter
  is stored as its glyph in `name`. `_function_name_font` slants a one-letter and
  a lowercase Greek name. `convert_math_to_julia(tree; functions = ())` threads
  `functions` through every `_julia_of`; the new exported
  `find_math_symbol_name(glyph)` answers `:rho` for `ρ`, so the reading finds the
  key of a Greek name. A word with a base other than `log` that is no function of
  the sheet reads as a product (`foo_{2}(x)` is `foo_2 * x`), where it refused.

### Step 2 — a formula with a parameter computes a function (D1, D3, D13)

- [x] `get_formula_key` reads a name that parses as the node with one name in
      parentheses as the name of the node; `_find_formula_parameter(formula)`
      answers the argument.
- [x] `get_formula_names(formula::FormulaFormula)` walks the code with the
      parameter bound; every walk that starts at a formula takes it (§3.3).
- [x] `convert_formula_to_expr(formula::FormulaFormula, env)` wraps a lambda,
      and its math reading passes the function names of `env` (§3.2);
      `compute_formula_key` hashes the parameter.
- [x] `_read_rename` adds the computation of the formula when its parameter
      changes, and writes no use when the new key is no identifier (§3.10).
- [x] Test: `test_formula_names()`: the key and the parameter of each name of
      the table of §3.1; the names of `S_{pure}(G) = G exp(-2G)` hold no `G`,
      also when the sheet holds a formula `G`. `test_formula_evaluation()`:
      `get_formula_value(S_pure)` is a function whose value at `0.5` is
      `0.5 exp(-1)`; a formula `S_{peak} = S_{pure}(0.5)` gives that number,
      and `_order_formulas` puts `S_pure` before it; with `ρ = 0.8`,
      `ρ(1 - ρ)` gives `0.16`; with `f = 3`, `f(2)` gives `6`, and with
      `f(x) = x^2` it gives `4`; a new value of an input `T` of the function
      computes the function and its caller again; a sheet formula `G = 3`
      changes nothing. `test_formula_to_syntax()`: the keys `(`, `x`, `)` typed
      after the name of `f = 3` with a user `g = f(2)` leave `f(x)`, write no
      use on the way, and `g` holds `3` after the last key (no loop: the
      computation runs at once). `test_formula_file()`: a sheet with
      `S_{pure}(G)` writes the name as it is and reads back to a function.
- **As built:** `_find_formula_parameter(name_or_formula)` answers the parameter
  (a variable, a symbol or a word in the parentheses), `_find_function_keys(env)`
  the keys of the function formulas that the math reading takes as `functions`.
  `get_formula_names(::FormulaFormula)` binds the parameter; `_find_readable_names`
  now takes a formula, `_find_identifier_scopes` too, and `_find_free_identifiers`
  takes the bound set. `convert_formula_to_expr(::FormulaFormula, env)` wraps the
  `Expr` in `Expr(:->, Symbol(parameter), body)`. `_read_rename` appends
  `ComputeFormulasOperation(env, [formula])` when the old and the new name differ in
  their parameter, also when no use is written. A use is written only when the
  new name reads in the math notation (`_is_readable_name`): `f(` writes none,
  while a name that reads as a number (`1`) still writes its key, as before.
  The rename of a formula that a math formula names is refused as before, so
  the test of the keys uses a Julia `g = f(2)`.

### Step 3 — the sheet draws a function as its equation (D4)

- [x] `_formula_value_text` of a function is empty; the `:both` layout of
      `FormulaFormulaToSyntaxNode` and the row of `FormulaFormulaToLayout` leave
      out `⇒` or `=` and the value for a function, and keep the mark `⋯` while a
      computation runs.
- [x] Test: `test_formula_to_syntax()`: `S_{pure}(G) = G exp(-2 G)` with no `⇒`,
      and with `⋯` while it computes; a number formula keeps `⇒ value`.
      `test_example(formula_example)`, because `F = x -> x^2` changes its row.
- **As built:** `_formula_value_text(::Function)` is empty and
  `_has_function_value(formula)` tells a row to leave out the value. The `:both`
  layout of `FormulaFormulaToSyntaxNode` has the children `[name, =, code]` for a
  function and adds the leaf `⋯` while it computes; `FormulaFormulaToLayout` draws
  the assignment alone, plus the label `⋯` while it computes. A cell of the grid
  that holds a function is empty, because it shows `_format_stored_formula_value`.
  The type-in sweep of `formula_example` (`test_typein`) fails 489 assertions on
  `main` at `03e5d58c1` too (74 pass, 489 fail, 1 broken, the same counts), so
  it is not a regression of this plan.

### Step 4 — a formula is callable; `e`; a referenced formula (D5, D6, D8)

- [x] The call of `FormulaFormula` and of a `ReferencedDocument` of one (§3.8),
      with a docstring on the call; `get_formula_value(::ReferencedDocument)`;
      `e` in `_make_formula_scratch_module()`.
- [x] The docstring of `add_study_formula!` shows a function formula, its call
      and a call from another formula.
- [x] Test: `test_formula_evaluation()`: `S_pure(0.5)` ≈ 0.18394 with no loop;
      in `Cell(@computation S_pure(0.5))` before a stored value the call raises
      "has no value yet"; with a stored value and `is_computing` the cell
      answers the old function's value and is provisional; a number formula
      raises the `ArgumentError`; an error formula raises its text; a
      referenced formula calls and answers its value; `e^{1}` is `ℯ`, and a
      sheet formula named `e` wins.
- **As built:** `(formula::FormulaFormula)(x)` and `(formula::ReferencedDocument)(x)`
  are in `FormulaDocument.jl`; inside a computation `_read_stored_formula_value`
  reads `formula.result` (raises "has no value yet" when it is `nothing`) and calls
  `mark_computation_provisional!()` while `formula.is_computing`; outside one the
  call takes `get_formula_value`. The test of a cell uses
  `Cell(@computation …)` and `is_cell_provisional`. `e` is `const e` in the
  scratch module. The docstring of `add_study_formula!` shows the function
  formula, its call and a call from another formula.

### Step 5 — a study computes its sheets when it enters the window (D7)

- [x] `acquire_document!` and `release_document!` for `ResearchStudy`.
- [x] Test: `test_research_document()`: a study read back from its folder holds
      no stored value; after `add_document_holder!` with the stand-in editor of
      a test (which computes at once) each formula of its sheet holds its value.
- **As built:** both methods are in `ResearchDocument.jl` beside the struct, with
  `_collect_study_sheets(study)`; `ResearchModule` imports `acquire_document!` and
  `release_document!` from `DomainModule`. The test uses `add_document_holder!(nothing, back)`,
  where the stand-in editor acquires at once and `ComputeFormulasOperation` computes
  with no loop. `test_research_assistant_api()` passes with the new docstring.

### Step 6 — a chart draws a function (D9, D10)

- [x] `ChartFunctionSeries` in `ChartDocument.jl`, exported; its docstring
      with `Chart("S", [ChartFunctionSeries("sin", sin; x_range = (0, 2π))])`.
- [x] `_compute_function_samples` and the parts of `ChartPlotToGraphics.jl`
      that read a series: the bounds, the fit, the line, the legend entry, the
      hit.
- [x] Test: `test_chart_projection()`: `sin` with `x_range = (0, 2π)` alone
      draws 200 samples from 0 to 2π within 1e-12; beside a line series over
      `[1, 3]` with no `x_range` it samples the fit window of the line series
      and the fit holds its y; a zoom samples the new window; a function that
      raises and a function that answers a string draw no line and the legend
      says why; no range says `no x range`; a formula of a sheet draws its
      stored function and, with no stored value, says "has no value yet".
- **As built:** `ChartFunctionSeries` has an outer constructor that checks the
  `x_range` (a pair of numbers, lower below upper) and `sample_count >= 2`; its
  family is `:xy`. `_compute_function_samples(series, lower, upper)` answers
  `(x, y, reason)`; a value that is not finite is dropped from the samples, and a
  call that raises or answers a non-`Real` stops them. The reason of a raise is
  the text of the exception when the callable is no `Function` (a formula or a
  callable object says why in its own words) and `gives no number at x = …`
  otherwise, so the chart names no formula. `_data_bounds` samples the fit of the
  x bounds for the y bounds; `_layout` samples the window of the view once into
  `g.function_samples`, which the legend (`_legend_items` takes the samples), the
  line and the hit (`_series_points`) read. A series with no range anywhere says
  `no x range; give x_range`. A fit without a zoom calls the function twice, once
  for the bounds and once for the window. The series is not added to the
  assistant API list of the chart.

### Step 7 — the guides

- [x] `formula.md`: a function formula in "References and names" and
      "Evaluation", the call of §3.8, the row of §3.4 in "Views", `e` in "Math
      code", and the limits of §9.
- [x] `math.md`: a name directly before `(`, of any spelling, is one node that
      draws its name as a name; what it means is the reader's. `formula.md`
      holds the table of §3.2 and the list of the functions of the notation.
- [x] `chart.md`: `ChartFunctionSeries` in "The documents", the samples in
      "The chain", and the limit that it has no sample to select.
- [x] Test: `test_formula()`, `test_chart()`, then `test_formula_examples()` of
      the umbrella.
- **As built:** `formula.md` holds the table of §3.2, the list of the functions of
  the notation, the call, the row, `e` and the limits; `math.md` states the neutral
  node; `chart.md` states the samples in the print and the limits. The private
  helpers carry a verb (`_get_function_key`, `_get_function_fault_reason`,
  `_compute_function_points`). The whole suites pass: `test_math()` 204,
  `test_formula()` 295, `test_chart()` 418, `test_research()` 381, each with its
  layering guard; `test_printer`, `test_reader`, `test_repl`, `test_position_navigation`
  of `formula_example` and `test_formula_examples()` pass. `test_typein(formula_example)`
  fails 489 assertions with and without this plan (step 3).

## 6. Tests

| step | the narrowest test |
| --- | --- |
| 1 | `test_math_parser()`, `test_math_to_graphics()`, `test_formula_math()` |
| 2 | `test_formula_names()`, `test_formula_evaluation()`, `test_formula_to_syntax()`, `test_formula_file()` |
| 3 | `test_formula_to_syntax()`, `test_example(formula_example)` |
| 4 | `test_formula_evaluation()` |
| 5 | `test_research_document()` |
| 6 | `test_chart_projection()` |
| 7 | `test_formula()`, `test_chart()`, `test_formula_examples()` |
| O1–O3 | `test_result_summaries()` and `test_study_verbs()` of `OmnetIdeTest` |
| O4 | `test_ide_documentation()` |

## 7. The omnet half

The steps O1 to O4 belong to omnet-julia and close Step 4 of the sibling plan.
They start after Step 7 is on projectured `main`. **The omnet code calls only
the callable and never names the formula domain**: no package of omnet gets a
new dependency, and no new kernel function is needed.

### 7.1 What the view holds (D11)

A new document of `LegacySimulationPlotDocument.jl`, beside `LegacyPlotSeries`,
so that the view and the plot document both hold it:

```julia
@document struct LegacyPlotCurve <: SimulationDocument
    label::String
    callable::Any
end
```

It is the pair `label => callable` as a document. A `Pair` has no form in a
`.pred` file, and the cut of a study folder finds a node that two places hold
only in a document. `LegacyResultPlotView` gets `curves::CellVector` of
`LegacyPlotCurve`, empty by default, and `make_result_plot_view(selections; …,
curves = Pair[])` makes one curve for each pair. The constructor of `@document`
stores `get_document` of the callable, so a formula read back from the study is
the node of the sheet, not a copy. `LegacyPlotCurve` declares no duplicate, so a
duplicate of the view shares its curves and does not copy a function.

**The file.** `pred_arguments` of the view writes `curves` only for a curve
whose callable is a document, and leaves out a curve whose callable is a plain
Julia function, which no file can write. The study folder writes a node that two
places hold once, so the sheet in `study.pred` holds the formula, and the curve
in the view holds a marker such as
`node(file("study.pred"), "analyses[1].method.formulas[3]")`, as an expectation
with a reference does today.

### 7.2 What the printer does (D12)

`_read_plot` builds the plot of the selections as today and gives the plot
document the curves of the view: `LegacySimulationPlotDocument` gets
`curves::CellVector` too. `_chart_of` appends one
`ChartFunctionSeries(curve.label, curve.callable)` for each curve after the
series of the points, and shows the legend when the chart has more than one
series. The chart samples each curve over the window of the points (§3.9), so
the curve spans the range of the x values of the summary. The states of a
formula and the reasons in the legend are the chart's (§3.9), so omnet adds
none.

### 7.3 The verb

`make_result_plot(items...; title, project, x, series, curves = nothing)`.
`curves` is a list of `label => callable`: a formula that `add_study_formula!`
answers, a formula read back from the study, or a Julia function. The verb
refuses curves without a summary ("a curve draws over the x of a summary; give
a summary and x"), and an entry that is no `label => callable`, with an
`ArgumentError` that names the type it got. Its docstring shows the call of §1
and says: a curve of a formula of the sheet is saved with the plot; a curve of a
plain Julia function draws, but the saved plot leaves it out.

### 7.4 Decisions of the omnet half

- **D11. The view holds `LegacyPlotCurve(label, callable)`.** *Reason:* a
  document of two fields writes with the default `pred_arguments`, and the cut
  of the folder sees a formula in it as a node. It names no formula.
- **D12. The printer hands each callable to `ChartFunctionSeries`.** *Reason:*
  the owner's shape; the chart owns the samples, the range and the reasons, so a
  plot of omnet and any other chart draw a function in one way.

### 7.5 Steps of the omnet half

#### Step O1 — the view holds its curves (D11)

- [ ] `LegacyPlotCurve`; `curves` of `LegacyResultPlotView`, of
      `make_result_plot_view` and of `LegacySimulationPlotDocument`;
      `pred_arguments` and `make_pred_document` of the view.
- [ ] Test: `test_result_summaries()`: a view with a formula curve and a
      function curve writes `curves = [LegacyPlotCurve(…)]` with the formula
      curve only, and reads back with its label and formula name; a view with
      none writes no `curves`; a duplicate of a view with a function curve
      shares the curve.

#### Step O2 — the print hands the curves to the chart (D12)

- [ ] `_read_plot` gives the plot document the curves; `_chart_of` appends a
      `ChartFunctionSeries` for each.
- [ ] Test: `test_result_summaries()`: the chart of the plot of the Step 3
      frame with a sheet `S_{pure}(G) = G exp(-2G)` and a Julia function has two
      more series, each a `ChartFunctionSeries` with its label and callable; the
      chart prints through `ChartToChartPlot` and `ChartPlotToGraphicsCanvas`.

#### Step O3 — the verb, and the folder

- [ ] `curves` of `make_result_plot`, its refusals and its docstring.
- [ ] Test: `test_result_summaries()`: the verb with a formula, a referenced
      formula and a Julia function; the two refusals. `test_study_verbs()`: a
      study whose report holds the plot saves; `study.pred` writes the formula
      once and the file of the plot holds a marker and no function curve;
      `open_study!` gives a curve whose callable is the formula of the sheet
      (`===`) and holds a stored function.

#### Step O4 — the documents

- [ ] `documentation/package/study/study.md`: a curve of a plot holds a
      marker, as an expectation does; a curve of a Julia function is not saved.
- [ ] `documentation/guide/assistant-guide.md`: the closed form section shows
      `S_{pure}(G)`, its call, `e`, and the plot with a curve.
- [ ] The sibling plan: Step 4 "A curve samples a formula of the sheet" done,
      with an **As built** note; the two gaps of the run of Step 9 closed.
- [ ] Test: `test_ide_documentation()`.

## 8. The owner's answers (2026-10-26)

No question is open.

1. **Q1. May the call of a formula act in two ways?** **Yes (a)** → D8. In code
   the call computes the formula when it has no value yet; in a print it uses
   only the stored function: the old function and a provisional value while it
   computes, and no line with "no value yet" before the first value.
2. **Q2. Where does a function series take its samples?** **(A), for now** →
   D10. The chart samples the function in its print: 200 calls, and again at
   each zoom. (B), the samples kept in a cell that a background task fills, is
   the later route if a drawn function is slow. It waits because it needs a
   place outside the print to make the cell and a way to give the task the
   function (§3.9).
3. **Q3. What does `name(…)` mean?** **(b), changed from my first D2** → D2
   and D13. The meaning follows what the name is, not how it is spelled, as in
   Desmos and Mathcad: the parser reads one neutral node and draws it the same
   either way; the reading into Julia, which knows the sheet, makes a call of a
   function of the sheet or of the notation and a product of anything else; a
   comma can only be a call. A formula whose name turns from a number into a
   function changes the meaning of the formulas that use it, which then compute
   again.

## 9. Risks and limits

- **The keys of every formula change once**, because the key hashes the
  parameter. Each sheet computes again at its next acquire. No file holds a
  key. `test_formula_task()` tells.
- **The row of `F = x -> x^2` changes** (Step 3): a printer baseline of
  `formula_example` can move. `test_example(formula_example)` tells.
- **A slow function slows the frame of a chart** that draws it, at each new
  window (D10). A call that raises draws no line and says why; it does not fault
  the chart.
- **A product that a person spelled as a call reads as before** only while the
  name is no function: `ρ(1 - ρ)` is a product with `ρ = 0.8`. **A word before
  `(` that is no formula and not in the list of the notation now reads as a
  product**, where it read as a call of Julia before, such as `erf(x)`. The
  grep of 2026-10-26 finds only `exp`, `log`, `abs` and `log_{2}` in the texts
  of both repositories, all in the list. `test_formula()` and
  `test_formula_examples()` tell.
- **Math code that calls a formula whose name names no parameter**, such as a
  Julia formula `F = x -> x^2`, reads `F(3)` as a product. Julia code is not
  affected (`G = F(3)` of `formula_example` is Julia). The guide says to name
  such a formula `F(x)`.
- **The world of the loop.** A call of a closure that is newer than the task
  without `Base.invokelatest` raises a `MethodError`. Steps 4 and 6 test a
  closure made after the test started.
- **The readers of the gestures fit the window too** (`resolve_view`), so they
  call the function as the print does. Step 6 tests a zoom.
- **A plot saved alone** writes the formula of a curve inline, with no sheet;
  read back, the formula holds no value, and the legend says so.
- Limits that the guides state: one parameter; a key in the parameter of a name
  does not rename its uses in the code; a function that calls itself is a
  cycle; a function series has no sample to select; a curve of a Julia function
  is not saved.

## 10. Not in this plan

A function of more than one parameter, and the comma in the parentheses that
it needs; the samples off the loop in a background cell (the later route of
D10); a function series on a category axis; a curve on a plot of vectors or
scalars.
