# Formula references by name

**Status (2026-10-12): IN PROGRESS.** The owner and I worked out the model of §3 in a
discussion on 2026-10-12, and the owner decided each point of §4. The owner asked to implement it
on 2026-10-12. Steps 1 to 3 are done. Step 4 of
[strict-document-types.md](strict-document-types.md) waits for this plan, because a formula
reference inside a Julia tree kept 37 Julia fields at `Document`.

**Goal:** a formula is a named computation in an explicit scope. Its definition is written in the
math notation or in Julia, and a reference to another formula is a name in that notation, which
the scope resolves. A Julia tree then holds only Julia, a math tree only math, and a reference has
one form: the same in memory, in a file, and when a person types it.

**Repositories:** projectured-julia only. omnet-julia and inet-julia have no formula.

## 1. The request

Step 4 of the strict types narrows the fields of the Julia domain. Its probe found a
`FormulaReference`, a document of the formula domain, in `JuliaBinaryOperation.left` and `right`,
and the formula domain describes its code as "a `JuliaDocument` that may contain
`FormulaReference`s". A Julia field can not name the formula domain, so every expression place of
Julia would stay `Document`. The owner was not sure that the formula domain must work this way,
and asked what a formula is, how it relates to the math and the Julia domain, and how a person
uses it. Backward compatibility is no constraint.

## 2. The facts today

- `FormulaFormula` holds `name::String`, `code::Document` (a `JuliaDocument`, a `MathDocument`
  or a `PrimitiveNumber`), `result::Document` and `display_mode`. `FormulaEnvironment` holds the
  formulas of one sheet in an untyped `CellVector`.
- A reference has two forms. A `FormulaReference` holds its target formula, and stands as a node
  inside the Julia tree of the code. A plain `JuliaIdentifier` names a formula, and
  `get_formula_dependencies(formula, env)` resolves it in the sheet with `resolve(env, name)`.
- No editor path makes a `FormulaReference`: no gesture, no insertion and no reader. Only code
  makes one: the example `make_formula_document_example` and 12 lines of tests. A `.pred` file
  stores the code as text, so a loaded formula holds identifiers, and a formula that a person
  types holds identifiers too.
- `_collect_names!` collects every `JuliaIdentifier` of the code, except the callee identifier of
  a call and the field of a field access. It does not skip a name that a lambda, a `let`, a
  comprehension, a `for` or a `do` binds.
- `wire_result!` computes the value: it reads the `result` cell of each dependency, binds each
  value to its name in a `let` block, and evaluates the code in a scratch module. The `result` is
  a `TextBlock` of the text of the value (`make_formula_result_text`).
- `convert_math_to_julia` interprets math code as Julia: a fraction is a division, a superscript
  a power, a sum with limits a `sum` over a range. A math node without a computational meaning
  raises a `MathReadingException`.
- `FormulaToSyntax()` adds four formula rules to the table of `JuliaToSyntax()`, so one recursion
  prints Julia nodes and formula nodes together.

## 3. The model

**A formula is a named computation in a scope.** It has a name, a definition written in a
notation, and a value that the formula domain computes from the definition.

| Layer | What it represents | Computes a value |
| --- | --- | --- |
| Math | mathematical notation and its meaning | no |
| Julia | a Julia program, with the meaning of the Julia language | yes, when it runs |
| Formula | a binding `name = definition`, its scope, its dependencies and its value | yes, reactively |
| A container, such as a table or a Markdown document | a place for formulas | no |

The formula domain sits above math and Julia and can name both. Math and Julia name no formula.
The formula domain owns the names, the scope, the references, the evaluation and the display. The
notation domains own only how an expression is written.

A math definition gets a value through an **interpretation**, a mapping from math to Julia that
the formula domain chooses: `\sin` means `Base.sin`, a fraction means a division. A math sine and
a Julia sine are not the same thing, so the mapping is an explicit choice, and a math node with no
computational meaning is refused with a message. A Julia definition needs no interpretation.

**A reference is a name.** `C = A + B` holds two identifiers. The scope resolves them:

1. The formula domain collects the free names of the code of `C`, `A` and `B`, and looks up the
   key of each in the environment. They are the dependencies of `C`. A name that the environment
   does not hold, such as `sin`, stays for Julia.
2. The `result` cell of `C` reads the results of `A` and `B`, so the reactive graph records both,
   binds the values to the names, and evaluates `let A = 42, B = 13; A + B end`. A change of `A`
   invalidates the result of `C`.
3. The view draws a name that resolves in the scope in the reference style, and a click goes to
   its definition. A name that resolves to nothing shows as an error.

## 4. The decisions

Decided by the owner, 2026-10-12:

- **D1. The scope is explicit**, a sheet as `FormulaEnvironment` is today. A container gives no
  scope by itself.
- **D2. A table names a cell both by its address, such as `A1`, and by a name that a person
  gives it.**
- **D3. A rename rewrites the names in place.** The rename of `A` to `Alpha` is one operation and
  one step of undo: it changes the name of the formula and every free identifier `A` of the scope,
  so `C` becomes `Alpha + B` and keeps its value. To break a binding and make a new one is an
  operation of its own: an edit of the name field alone rewrites no use, so `A` in `C` resolves to
  nothing and `C` shows an error until a new binding exists.
- **D4. A value can be any value.** The value is bound as the object itself, so `A = [1, 2, 3]`
  and `C = A .+ B` give a vector. The `result` holds the value, and the view shows it through its
  own projection, in place of a `TextBlock` of its text.
- **D5. The interpretation of math stays in the formula domain** for now.
- **D6. A local name does not refer.** A name that a lambda, a `let`, a comprehension, a `for`, a
  `do` or a parameter list binds is not a dependency: in `sum(x -> x * A, 1:3)` only `A` is.
- **D7. The scope wins over a Julia global.** A formula named `pi` means that formula in another
  formula of the scope, because the evaluation binds the names of the scope last, and the view
  shows `pi` as a reference.
- **D8. A reference does not depend on the notation.** A math formula `D = \frac{C}{2}` refers to
  `C` with the math variable `C`: the interpretation maps it to the identifier `C`, and the same
  environment binds it. A name has one key in both notations (`get_formula_key`).

A consequence of D4 and D7: a callee that names a formula of the scope is a dependency, because
the value of a formula can be a function. `F = x -> x^2` and `C = F(3)` give `9`. Today the walk
skips every callee identifier.

## 5. The steps

**The gallery follows each step** (asked by the owner, 2026-10-12). Each step that adds or changes
a feature adds it to the formula example of the gallery in the same step, so a person can try it
in the REPL (`test_repl(formula_example)`) and in the gallery. The example is `formula_example`
in `example/projectured/DomainExamples.jl`, built by `make_formula_document_example`. When the
plan is done, its sheet holds:

| Formula | What it shows |
| --- | --- |
| `A = 42`, `B = 13`, `C = A + B` | a reference by name, and a change of `A` that computes `C` again |
| `V = [1, 2, 3]`, `W = V .* A` | a value that is not a number (D4) |
| `F = x -> x^2`, `G = F(3)` | a function value, and a callee that is a dependency |
| `S = sum(x -> x * A, 1:3)` | a local name `x` that is not a dependency (D6) |
| `D = \frac{C}{2}`, in math notation | a math formula that refers to a Julia formula (D8) |
| `E = A + Z` | a name that resolves to nothing, which shows as an error |
| `H = 2 * K` and `K = H + 1` | a cycle, which shows `#CYCLE!` |

`test_example(formula_example)` passes after each step: the printer, the reader and the position
navigation. The atomic documents of the catalog follow too: the `reference` entry goes with Step 2.
The scope-wins rule (D7) gets a test of its own and no formula in the gallery sheet, because a
formula named `pi` would make every other `pi` of the sheet mean it.

- [x] **Step 1: the walk of free names.** `get_formula_names` skips the names that D6 lists, and
  counts a callee that resolves in the scope (the consequence of D4 and D7). Tests for each kind
  of local binding and for a function value.
  *Done (2026-10-12).* What is built:
  - `get_formula_names(code)` gives every free name, and a callee is one of them.
    `get_formula_dependencies(formula, env)` keeps the names that resolve, so `sqrt` stays for
    Julia and `F` in `F(3)` is a dependency.
  - The walk is one method of `_collect_names!` for each kind of binding, with the set of the
    names that a binding above covers. Parameters, the bindings of a `let` and the parameters of a
    `where` bind from left to right, so a default can read a parameter before it.
  - Two kinds of local name that D6 does not list are local too, because Julia makes them local:
    the target of an `=` covers the statements after it in its block, and the variable of a
    `catch` covers its branch. A function definition, `f(x) = …` or `function f(x) … end`,
    binds `f` and its parameters.
  - The target of an `=` is no name, so the keyword `k` of a call `f(A; k = B)` and the field
    `a` of a named tuple `(a = A,)` are not free.
  - Tests: `test_formula_names()` in `test/domain/formula/FormulaNameTest.jl`.
  - The gallery gets `F`, `G` and `S` with the evaluation by name (now Step 3), because the
    evaluator of today has no lambda.
  - `test_example(formula_example)` gives 2901 passes and 72 failures, the same as `main`. The 72
    failures are type-ins into the name and the result of a formula ("no cursor in Graphics
    image"), and `main` has them too.
- [x] **Step 2: no reference node.** `FormulaReference` goes out of the code of a formula:
  `get_formula_dependencies` resolves names only, `_to_expr` maps no reference node, and the
  example and the tests write identifiers. `FormulaFormula.code` declares
  `Union{JuliaDocument, MathDocument, PrimitiveNumber}`, and `FormulaEnvironment.formulas`
  declares `Vector{FormulaFormula}`.
  *Done (2026-10-12).* What is built, and what differs:
  - `FormulaReference`, `FormulaReferenceToSyntaxLeaf`, `get_formula_references` and the
    method `get_formula_dependencies(formula)` with no environment are gone. The theme keeps
    `reference_text` for the view of Step 4.
  - `FormulaEnvironment.formulas` declares `CellVector{FormulaFormula}`, the form that a list
    of documents takes (as `JsonArray.elements`), and not `Vector{FormulaFormula}`.
  - The gallery sheet is `A = 42`, `B = 13`, `C = A + B`, and the catalog has no `reference`
    entry. The theme test checks the insertion leaf in place of the reference leaf.
  - `ProjecturedFormula` and `ProjecturedFormulaExample` lose exported names, so each takes a
    minor step at the next release. The generator of the release finds a removed export by
    itself (R36, B7), so the release plan needs no new item.
  - omnet-julia makes no reference node. Its sheets, `FormulaEnvironment(Any[])` and a push of
    a `Cell` of a formula, fit the typed list.
  - `test_formula()` passes, 140 of 140: the 3 assertions of the test of the reference leaf are
    gone. `test_example(formula_example)` gives 2191 passes and 57 failures. 45 failures are
    the type-ins into a name and a result that `main` has too. 12 are type-ins into the
    identifiers `A` and `B` of `C`: an identifier leaf of Julia code shows no caret, a gap of the
    Julia domain that `julia_example` has too (0 of 28 positions). The old example had
    reference nodes there, which the type-in walk does not try. `test_catalog_coverage()` has
    the failure of `main`: a list of types with no catalog entry, and no formula type in it.
- [x] **Step 3: the evaluation by name only.** `wire_result!` binds the names of the scope last
  (D7), and the `result` holds the value (D4). `FormulaFormula.result` declares `Any`.
  *Done (2026-10-12).* What is built, and the choices made in the implementation:
  - `convert_formula_to_expr` builds the `Expr` with `make_julia_expression`, so every Julia node
    evaluates, the lambda too. `_to_expr` is gone.
  - The `let` binds each free name of the code as it is written, to the value of the formula it
    resolves to. So Julia code that writes `ρ` reads the formula `rho`, as D8 asks.
  - **An error is a value of its own type, `FormulaError(text)`** (my choice, exported). It
    shows as `#ERROR! …` or `#CYCLE!`. A formula that reads one gives the same value on, as a
    spreadsheet does. `make_formula_result_text` is gone, and `get_formula_value` gives the
    value itself.
  - **The cycle check walks the names, and reads no result.** The engine computes a cell again
    when its computation reads it from inside, and that inner run clears the subscriptions of
    the outer run. So the guard of before (a set of the formulas in evaluation) left a formula
    of a cycle at `#CYCLE!` after a person broke the cycle. Now `evaluate_formula` first walks
    the free names through the environment; it reads the code and the name of each formula on
    the way, so each formula of a cycle computes again when one of them changes. A formula
    that names itself, `A = A + 1`, is a cycle too.
  - The views show a value on one line: a float to six digits, another value in its
    `text/plain` form, or its compact form when that form takes more lines. A function shows
    as `#563 (generic function with 1 method)`, the text of Julia.
  - Each evaluation of code with a lambda makes a new function type in the scratch module, as
    each line of the Julia REPL does. The cost grows with the edits, not with the frames.
  - Tests: `test_formula_evaluation()` in `test/domain/formula/FormulaEvaluationTest.jl`. The
    suite passes, 162 of 162.
  - The gallery sheet holds every row of the table except `D`. **`D` waits for the owner.**
    Math code in the text view of a formula, `FormulaToSyntax()`, prints as one object leaf,
    `⟨MathFraction⟩`, and the up and down keys fail next to it ("under-typed @reference" at
    `FormulaToSyntax.jl:141`), even for `parse_math("2")`. The old gallery had no math row, so
    its test did not meet this. A fix is to put the rules of `MathToSyntax()` into the table of
    `FormulaToSyntax()`, as the formula rules go into the table of `JuliaToSyntax()`, so math
    code prints in its linear form. That is a feature that no step of this plan names.
  - `test_example` on a fresh `Example` of the factories: printer 7398, reader 225, REPL 225 and
    navigation 309 pass. The type-in part fails 552 times, each of a kind that `main` has: a
    type-in into a name, into an identifier of Julia code (which shows no caret), or into a
    computed result, here the text of an error. A number in a result no longer counts, because
    it is a number and not a text. Note: `formula_example` keeps the document it built first, so
    a warm session must test a fresh `Example` after it changes the factory.

  *The order of Steps 2 and 3 changed on 2026-10-12, in the implementation.* The evaluation by
  name builds its `Expr` with `make_julia_expression` of the Julia domain, which takes every
  Julia node, the lambda too. That function puts a node that is not Julia into the `Expr` as the
  object itself, so it can run only on code with no `FormulaReference`.
- [ ] **Step 4: the view of a reference.** The formula projection draws an identifier that
  resolves in the scope in the reference style, and a click on it selects its definition. The
  projection prints the environment and its formulas, so it gives the Julia projection the set of
  names of the scope through the printer context, and reads no other projection.
  *Open, two questions for the owner (found 2026-10-12, before the code of this step):*
  - **How the style reaches every identifier.** `JuliaToSyntax(entries...)` puts the entries of
    another domain after its own, and the dispatch takes the first match, so a formula rule for
    `JuliaIdentifier` must go in front of the table (the formula domain can build its table so).
    But `JuliaCallToSyntaxNode` draws a callee with its own `JuliaIdentifierToSyntaxLeaf`, past
    the table, so the `F` of `G = F(3)` would keep the callee style. The choices: (a) the Julia
    identifier leaf reads a property of the printer context that a host sets, the identifier
    nodes to mark and their style; a small capability of the Julia domain that names no
    formula (my recommendation); (b) the formula domain overrides the call rule too, a copy of
    it; (c) only the identifiers that the table reaches take the style, and a callee does not.
    In each choice the formula rule finds the marked nodes by identity, the free identifiers of
    its code that resolve in the scope, so a local name that a formula also has (D6) stays plain.
  - **The gesture that goes to the definition.** A plain click on an identifier selects the
    identifier today, as a whole. If a plain click goes to the definition, a person can not
    select a reference to edit it. The choices: Ctrl+click, as code editors do (my
    recommendation); a key on a selected reference; or a plain click as the step says.
- [ ] **Step 5: the rename operation** of D3, as one compound operation with one inverse, and
  a gesture for it that a person can try on the name of a formula in the gallery.
- [ ] **Step 6: the strict Julia fields.** Step 4 of
  [strict-document-types.md](strict-document-types.md) then narrows every Julia field to
  `JuliaDocument`, and every list to `CellVector{JuliaDocument}`.
  *Open, a question for the owner (found 2026-10-12):* Julia code holds a pasted object of
  another domain by design. The last entry of the `JuliaToSyntax` table,
  `Document => JuliaObjectToSyntaxLeaf()`, draws it as one leaf, `make_julia_expression` puts it
  into the `Expr` as the object itself, and the test "a pasted object stands as that very object"
  writes a `PrimitiveString` into `call.arguments[2]`. The probe of 2026-10-11 did not see it,
  because the constructors of `JuliaCall` gave untyped lists. By the model of §3 of
  strict-document-types.md, a field that admits other domains declares `Document`. The choices:
  keep the paste, and the expression places stay `Document` (my recommendation); remove the
  paste from code, and every field becomes `JuliaDocument`; or a Julia node that wraps the
  object, which §3 rejected. The probe did not run `test_fsm()` and `test_process()` either.

## 6. Open

- A formula in a table (D2) and a formula in a Markdown document need a container that holds
  formulas and an environment for them. This plan does not build them; a plan for each container
  follows when the owner asks.
- How a Markdown paragraph shows the value of a formula inline.
