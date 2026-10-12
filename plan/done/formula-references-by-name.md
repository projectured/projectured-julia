# Formula references by name

**Status (2026-10-12): DONE.** The owner and I worked out the model of §3 in a discussion on
2026-10-12, and the owner decided each point of §4. The owner asked to implement it on
2026-10-12, and Steps 1 to 6 are built on the branch `formula-references-by-name`. The Julia
fields of Step 4 of [strict-document-types.md](../pending/strict-document-types.md) are built
with Step 6. Three questions stay open (§6).

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
- [x] **Step 4: the view of a reference.** The formula projection draws an identifier that
  resolves in the scope in the reference style, and a click on it selects its definition. The
  projection prints the environment and its formulas, so it gives the Julia projection the set of
  names of the scope through the printer context, and reads no other projection.
  *Open, two questions for the owner (found 2026-10-12, before the code of this step):*
  - **Decided by the owner, 2026-10-12: option (c)** of the first question below. Only an
    identifier that the table reaches takes the reference style, and a callee keeps the callee
    style.
  - *The drawing, done (2026-10-12).* `FormulaIdentifierToSyntaxLeaf` draws an identifier in
    `reference_text` of `FormulaTheme` when the identifier refers to a formula of the sheet, and
    in `identifier_text` of `JuliaTheme` otherwise. `FormulaToSyntax()` puts it in front of the
    Julia table. The sheet rule gives each formula the sheet through the printer context
    (`:formula_environment`); the formula rule computes the free identifiers of its code that
    resolve (`_find_reference_identifiers`, held by identity) and gives them to its code
    (`:formula_references`). The rule reads the set when it prints, so a formula that the sheet
    gains turns its uses into references. The walk of Step 1 now collects the identifier nodes,
    and `get_formula_names` gives their names. The rule holds two styles and no projection, and
    prints through `print_template_document`, as the rules of the RST domain do.
  - **Decided by the owner, 2026-10-12: Ctrl+click goes to the definition**, and it selects the
    name of the target formula.
  - *The gesture, done (2026-10-12).* The sheet rule reads Ctrl+click with its own `read_intent`,
    in the form that `SyntaxLeafToText` uses for Alt+click: the generic reader maps the claimed
    selection of the click back to the sheet, and when that path goes through a reference
    identifier, the answer selects `formulas[j].name`. The sheet is the lowest node that holds
    both the reference and the definition. A gesture binding can not do it: its operation gets
    only the node and the event, not the part that the click selected. The formula rule maps a
    selection of the whole name to its name leaf when the layout is `:both`; for another layout
    the click selects the whole formula, because the name does not show. A place inside the name
    still maps to nothing; that belongs to Step 5.
  - Limits: the jump works where the sheet is the root of the view, as in the gallery. A view
    that prints the sheet inside a template asks only the bindings of the parts, so there a
    Ctrl+click selects the identifier. The gesture help does not list the jump, because it is
    no binding.
  - Tests: the view test presses a Ctrl+click through a headless editor, and checks the
    selection and the rectangle that the frame draws over the name. `test_formula()` passes,
    173 of 173; `test_example` gives the counts of Step 3.
  - Facts: in the default palette the callee color and the reference color are the same blue;
    the reference style is bold, the callee style is not. With and without the rule, the
    navigation of the gallery sheet reaches the same 416 states. The count of states of
    `test_example` moves from run to run, because the text of a function value holds the number
    of its type, `#563`, and the caret places of that result follow its length.
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
- [x] **Step 5: the rename operation** of D3, as one compound operation with one inverse, and
  a gesture for it that a person can try on the name of a formula in the gallery.
  - **Decided by the owner, 2026-10-12: each key in the name is a rename** (option (b) of three:
    (a) F2 and a draft name, committed by Enter; (b) each key renames the formula and every use;
    (c) a popup with a text field). The owner: "merging the edit operations can still be done by
    the undo buffer in a generic way". So one key is one operation and one undo step, and a
    merge of the keys of one name is a matter of the undo buffer, not of this plan.
  - *Done (2026-10-12).* What is built:
    - The formula rule maps a place in the name to the text of its name leaf and back, where the
      layout is `:both`, so a caret shows in a name and a key types there.
    - The sheet rule turns a string edit of `formulas[j].name` into one `CompoundOperation`: the
      edit, then a `ReplaceReferencedValueOperation` that writes the new name into each use, by
      its path from the sheet. A use spelled as the name takes the new name; a use spelled as the
      key of the name, such as `rho` for `ρ`, takes the key of the new name.
    - A key that would make a use mean something else does nothing, and the description of the
      answer says why: a math formula uses the name (its uses are math nodes, and the rename
      writes Julia identifiers), another formula has the new name, or a local name of the code
      would take the use (the walk now records the names bound around each identifier). The
      editor shows no message for a declined key today.
    - The type-in walker of `TypeinTest.jl` accepts a compound whose first member is the string
      edit, and evaluates that edit alone, so its restore takes the edit back. Over every
      example of the registry, the old and the new walker give the same counts except
      `formula`.
  - Facts: with `undo = true`, one Ctrl+Z takes back the name and every use of one key. In
    `test_example`, the 66 type-ins into names now pass; the type-in part fails 486 times, the
    identifiers of code (96) and the computed results (390), kinds that `main` has.
  - Open: the edit of the name field alone, D3's operation that rewrites no use, has no gesture
    now, because a key in the name is a rename. And a rename to a name that some code reads
    free, such as `Z` in `E = A + Z`, makes that name refer to the renamed formula: a key that
    refused it would also keep a person from naming a new formula `Z`, and making a binding is
    the other operation of D3.
- [x] **Step 6: the strict Julia fields.** Step 4 of
  [strict-document-types.md](../pending/strict-document-types.md) then narrows every Julia field to
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
  - **Decided by the owner, 2026-10-12:** "the paste should check the place if it takes the
    value by type", and "julia should keep JuliaDocument for now until we have a concrete use
    case".
  - *A fact found after that answer (2026-10-12), put to the owner before any field changes:*
    the evaluator has a built use of a pasted object in code. With the option "Structured
    forms" on (off by default), a person selects a node of a form whole with Alt+click and
    pastes a copied document with Ctrl+V; the form runs with that very object (`154f33062`,
    2026-09-23; `EvaluatorToplevelTest.jl`, "a form that holds an object runs with that very
    object", which writes a `GraphicsCircle` into `call.arguments[1]`). With `JuliaDocument`
    fields, that paste is refused by the type of the place, and the test becomes a test of the
    refusal.
  - **Decided by the owner, 2026-10-12, after that fact: a Julia node holds a pasted object as
    a literal.** The owner asked: "shouldn't we paste a julia literal object or something to say
    that this object is meant as a literal to be passed in the call?", and accepted the node
    `JuliaObject`, made at the write: a document of another domain that a write puts into a
    Julia place becomes `JuliaObject(document)`, as text becomes the insertion of the domain
    (rule 3). So every Julia field declares `JuliaDocument`, and the structured forms of the
    evaluator keep the paste. It narrows the decision "no foreign type" of strict-document-types
    §3 for Julia: the node lets a value stand as itself, not the code of another domain.
  - *Done (2026-10-12).* What is built:
    - The 77 fields of the Julia nodes declare `JuliaDocument`, `Union{JuliaDocument,Nothing}`
      or `CellVector{JuliaDocument}`; the constructors of `JuliaCall` give typed lists.
      `JuliaFile.content` stays `Document`.
    - `JuliaObject(value::Document)`, a literal. A method of `convert_to_declared_type` for an
      owner of the Julia domain turns a document of another domain into `JuliaObject(document)`
      where the place admits a `JuliaObject`. So a paste, a typed edit and an operation wrap;
      a direct write by program code goes through `convert_assigned_value`, which converts no
      value by design ("program code wrote it, not a person"), so program code writes
      `JuliaObject(object)` itself, and a bare object there is refused.
    - The table entry `JuliaObject => JuliaObjectToSyntaxLeaf()` draws the title of the value;
      the last entry, `Document`, stays for a document that is not Julia at the root. The copy
      policy of `make_julia_expression` puts a placeholder where a `JuliaObject` stands and puts
      its value back as a `QuoteNode`; a bare document keeps its placeholder too, for the
      modes `:record` and `:off`.
    - `JuliaObject` is no insertion candidate: it needs its value, so it has no zero-argument
      constructor.
    - The invariant `PAR-DOMAINS-INDEPENDENT` says how a domain holds a value of another domain.
  - Tests in the mode `:throw`: `test_julia()` 557, `test_formula()` 184, `test_fsm()` 174,
    `test_process()` 312, `test_evaluator_toplevel()` 239, all pass; `test_application()` 372
    pass and 2 broken, its two markers of the Files pane. The two application tests that paste a
    noted object into a form with Ctrl+V pass: the paste wraps the object, and the form runs
    with that very object.
  - `test_example` on fresh examples: `julia`, `formula`, `fsm`, `fsm_toggle` and `fsm_diagram`
    pass the printer, the reader, the REPL and the navigation. Each fails only in the type-in
    part: `julia` 84 (the known caret gap of identifiers), `formula` 486 (as in Step 5), and the
    three FSM examples 3957, 167 and 231. No type-in result of the FSM examples threw: 4020 are
    "no cursor", 320 a caret at another place after the edit, and 17 a key that made no edit,
    so none is a refusal of a type. The FSM counts were not measured on `main`.

## 6. Open

- A formula in a table (D2) and a formula in a Markdown document need a container that holds
  formulas and an environment for them, and a Markdown paragraph needs a way to show the value
  of a formula inline. This plan does not build them; a plan for each container follows when
  the owner asks.
- The other operation of D3, to break a binding and to make one: the edit of the name field
  alone has no gesture, because a key in a name is a rename (Step 5), and a rename to a name
  that some code reads free, such as `Z` in `E = A + Z`, makes that name refer to the formula.
- Math code in the text view of a formula: `FormulaToSyntax()` prints it as one object leaf, and
  the up and down keys fail next to it, so the gallery has no math row `D` (Step 3). The rules
  of `MathToSyntax()` could join the table, as the formula rules join the table of Julia.
