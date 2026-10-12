# Formula references by name

**Status (2026-10-12): PENDING. Not started.** The owner and I worked out the model of §3 in a
discussion on 2026-10-12, and the owner decided each point of §4. Do not implement it until the
owner asks. Step 4 of [strict-document-types.md](strict-document-types.md) waits for this plan,
because a formula reference inside a Julia tree keeps 37 Julia fields at `Document`.

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

- [ ] **Step 1: the walk of free names.** `get_formula_names` skips the names that D6 lists, and
  counts a callee that resolves in the scope (the consequence of D4 and D7). Tests for each kind
  of local binding and for a function value.
- [ ] **Step 2: the evaluation by name only.** `wire_result!` binds the names of the scope last
  (D7), and the `result` holds the value (D4). `FormulaFormula.result` declares `Any`.
- [ ] **Step 3: no reference node.** `FormulaReference` goes out of the code of a formula:
  `get_formula_dependencies` resolves names only, `_to_expr` maps no reference node, and the
  example and the tests write identifiers. `FormulaFormula.code` declares
  `Union{JuliaDocument, MathDocument, PrimitiveNumber}`, and `FormulaEnvironment.formulas`
  declares `Vector{FormulaFormula}`.
- [ ] **Step 4: the view of a reference.** The formula projection draws an identifier that
  resolves in the scope in the reference style, and a click on it selects its definition. The
  projection prints the environment and its formulas, so it gives the Julia projection the set of
  names of the scope through the printer context, and reads no other projection.
- [ ] **Step 5: the rename operation** of D3, as one compound operation with one inverse.
- [ ] **Step 6: the strict Julia fields.** Step 4 of
  [strict-document-types.md](strict-document-types.md) then narrows every Julia field to
  `JuliaDocument`, and every list to `CellVector{JuliaDocument}`.

## 6. Open

- A formula in a table (D2) and a formula in a Markdown document need a container that holds
  formulas and an environment for them. This plan does not build them; a plan for each container
  follows when the owner asks.
- How a Markdown paragraph shows the value of a formula inline.
