# A Julia name takes the color of its binding

> **Status:** proposal, not started. Nothing is implemented. The questions are
> in section 11. This plan is part B2 of
> [a-value-takes-the-color-of-its-kind.md](a-value-takes-the-color-of-its-kind.md),
> whose parts A and B1 landed on `main` at `ee32195c6` on 2026-10-09.

## 1. The request

The owner wrote on 2026-10-09, after the explanation of B2:

> we should make this a plan including the coloring and the analysis
>
> what new julia types and/or fields would be introduced? does it worth a
> separate projection step from going bound julia types to julia ast?

## 2. What is there now

- **The document is the tree of the parser.** `parse_julia` calls
  `Meta.parseall` and converts each `Expr` head into a document
  ([julia.md](../../documentation/package/domain/julia/julia.md)). A name is a
  string: `JuliaIdentifier(name)`. A `.jl` file on disk is the persistent form,
  and the document prints back to it.
- **B1 colors a name by its place.** A slot whose place gives the kind prints a
  bare identifier in the style of the kind, with
  `project(:slot; as = _style_identifier(style))`: the name of a function or a
  type at its definition, a type after `::`, a field after a dot, a module, a
  macro.
- **What B1 can not do.** A use of a name in a body is a plain
  `JuliaIdentifier`. Only its binding says if it is a parameter, a local, a
  global, a function, a type or a module. Also a parameter of a signature, of a
  lambda and of `where`, the name of a keyword argument, a field of a struct and
  `P` in `struct P{T}` keep the role `variable`
  (section 10.10 of the plan of B1).
- **No scope analysis exists.** `find_julia_definition(document, name)` finds a
  top-level definition by its name, for the marker language, and nothing more.
- **A parent can already pass data to its subtree.** `PrinterContext` has
  `properties`, `with_property(ctx, key, value)` sets one for the subtree, and
  `get_property(ctx, key)` reads it. `make_child_context` keeps the properties,
  so they reach every descendant, also through the template rules.
  `ObjectToSyntax` passes the set of objects that it saw down the tree this way
  ([ObjectToSyntax.jl:133](../../source/platform/syntax/ObjectToSyntax.jl#L133)).
- **A template rule can not set a property.** An `@projection_template` rule
  prints its children with the context that it gets.
- **The palettes have nine hues**, and the token roles use all the free ones
  (section 10.3 of the plan of B1).

## 3. The rule

**A name takes the role of the kind of its binding, at the binder and at each
use.** The binder is the place that binds the name, such as a parameter of a
signature or the target of an assignment. It takes the font of a definition,
bold. A name that binds nowhere in the document takes the kind that the module
of the evaluation gives it by reflection, and the role `variable` when nothing
gives it a kind.

## 4. Where the bindings live

This section answers the two questions of the owner. Three designs can hold
the bindings. My recommendation is 4.3; the decision is the owner's
(question Q1).

### 4.1 Bound types are the document, and a step projects them to the tree

This is the model of a classic projectional editor: a use of a name holds its
binder by identity, as `FsmTransition.trigger` holds its `FsmEvent`. A step
`BoundJuliaToJulia` would print names, and the chain of today would follow.

New types: a binder for each kind (a parameter, a local, a global), a use that
holds its binder (`JuliaNameUse(binder)`), and a free name for a name that binds
outside the document (`JuliaFreeName(name)`). New fields: the binder in each
use, and the binders in each scope node.

Why I do not recommend it:

- **The text is the source of truth.** A `.jl` file holds names. The parser
  must bind every name on load, so the analysis is needed anyway.
- **Type-in gives names.** A person types `x`, so the commit of an insertion
  must find the binder in scope: the same analysis again.
- **Julia binds by name.** A move or a paste of `x + 1` into another scope
  changes what `x` means in Julia. A use that holds its old binder by identity
  prints `x` but means the old binder, so the document and its text disagree.
  A new inner `x` that shadows an outer one has the same problem.
- **The FSM is different.** A person picks a trigger from a list, and a state
  machine has no text form that rebinds names. Julia code has one.

### 4.2 A separate stage builds a bound tree from the tree

This is the design of
[bound-sql-statement.md](bound-sql-statement.md): a projection
`JuliaToBoundJulia` gives a tree whose names are wrapped, and the printer
prints the wrapped names.

```
JuliaDocument ──JuliaToBoundJulia──▶ bound tree ──JuliaToSyntax──▶ SyntaxNode ──▶ …
```

New types: `BoundJuliaName(identifier, binding)`, a document that wraps a
`JuliaIdentifier` with its binding, and the stage `JuliaToBoundJulia`. The
containers are the `Julia*` types, rebuilt with bound names in them, as the
SQL plan reuses the `Sql*` containers.

Why I do not recommend it for the colors:

- **Every edit passes one more stage.** A caret move, a selection, a typed
  character and a structural gesture go through its two reference maps and its
  reader, for every node of the tree. The SQL plan avoids this cost by being
  read-only; Julia code must stay editable.
- **It mirrors the whole tree.** Each container is rebuilt to hold the bound
  names, so the memory and the work of a reprint double.
- **It adds one fact for each name.** The kind of a binding is small data. A
  stage of its own is the right tool when the output is a document that a
  person or a tool uses for itself.

When it pays: a feature that shows the bindings as a document, such as a view
of all the uses of a name or a list of the free names of a file. Such a view
can be a read-only side projection, as in the SQL plan, and not a stage of the
editing chain.

### 4.3 The scope flows down the printer context (recommended)

Each node that opens a scope computes the names that it binds and gives them
to its subtree as a property of the context. A name leaf reads the nearest
scope and finds its binding there.

```
JuliaFunction  ── sets :julia_scope = {x ⇒ parameter, y ⇒ local} ──▶ its subtree
  JuliaIdentifier("x")  ── get_property(ctx, :julia_scope) ──▶ parameter ⇒ the parameter style
```

- **No new document types and no new fields of a Julia document.** The
  document stays the tree of the parser, with names.
- **New plain types**, which are not documents:
  - `JuliaScope`: its parent scope, the kind of the node that opens it, and
    its bindings by name.
  - `JuliaBinding`: the kind of a binding and the node that binds it.
- **New functions:** `compute_julia_scope(node, parent)`, one method for each
  scope node; `find_julia_binding(scope, name)`; and
  `find_external_binding(name, module)`, the reflection of section 5.4.
- **New fields of `JuliaTheme`** for the kinds that B1 has no field for:
  `parameter_text`, `local_text`, `global_text`, `type_parameter_text` and
  `import_text`; the fields of B1 serve the rest.
- **One change of a projection:** `JuliaIdentifierToSyntaxLeaf` holds one style
  for each kind and takes the style of its binding, as
  `SqlScalarValueToSyntaxLeaf` takes the style of the kind of its value.
- **One small mechanism:** a scope node must set a property for its children.
  Section 8 gives two ways (question Q2).

Why I recommend it:

- **The editing chain does not change.** The leaves, the reference maps and the
  readers stay as they are. Only the style of a leaf changes.
- **It is local.** Each scope node computes its own scope from its own fields,
  and each leaf reads the scope that its context gives. No walk over the whole
  document runs for a print.
- **It is reactive.** A scope is a computed cell over the fields of its node. An
  edit that adds an assignment in a function recomputes the scope of that
  function, and only the leaves under it recolor.
- **The analysis serves tools too.** `compute_julia_scope` and
  `find_julia_binding` are plain functions. Go to definition, a highlight of all
  uses, a rename that respects scopes and a warning for an unused name can call
  them without a print.
- **It covers what B1 can not.** A parameter, a `where` parameter, a keyword
  argument name, a field of a struct and `P` in `struct P{T}` all bind in a
  scope, so their leaves find their kind. The `as` on `collection` (question
  QB4 of the plan of B1) is then not needed.

## 5. The analysis

### 5.1 The kinds of a binding

| Kind | Bound by | Role |
| --- | --- | --- |
| `parameter` | a parameter of a function, of a lambda and of a `do` block; a keyword parameter | `parameter` |
| `type_parameter` | a name of `where`; a name in the braces of a `struct` or `abstract type` header | `type_parameter` |
| `local` | an assignment in a local scope; a `for` variable; a `let` binding; a `catch` variable; a variable of a comprehension; `local x` | `variable` |
| `global` | an assignment or a `const` at the top level of a module or a file; `global x` | `variable` |
| `function` | `function f`, `f(x) = …` | `function_name` |
| `type` | `struct T`, `abstract type T` | `type_name` |
| `module` | `module M`, and a module that `using` or `import` names | `module_name` |
| `import` | a name in `using M: x` or `import M: x` | `variable` |
| `field` | a field of a struct, in the body of the struct | `field` |
| `macro` | a macro of the module of the evaluation, by reflection | `macro_name` |

### 5.2 The scope nodes

| Node | Opens | Binds |
| --- | --- | --- |
| a `.jl` file, `JuliaModuleDefinition` | a global scope | the names of section 5.3, in the top-level statements |
| `JuliaFunction` | a hard local scope | `params`, the names of `where_clause`, the locals of `body` |
| `JuliaAssignment` whose `target` is a `JuliaCall`, the short form `f(x) = …` | a hard local scope | the `arguments` and `keyword_arguments` of the call, the locals of `value`; the callee binds a `function` in the enclosing scope |
| `JuliaLambda`, `JuliaDo` | a hard local scope | `parameters`, the locals of `body` |
| `JuliaLet` | a hard local scope | `bindings`, the locals of `body` |
| `JuliaFor`, `JuliaComprehension` | a soft local scope | the `variable` of each `JuliaForIterator`, the locals of `body` |
| `JuliaTry` | a soft local scope | `catch_var` in `catch_branch` |
| `JuliaStruct`, `JuliaAbstractType` | a type scope | the defined name, the names in the braces of `header`, the fields in `body` |
| `JuliaWhere` | a type scope | `parameters` |

The locals of a body are the targets of its assignments, without the bodies of
the nested functions, lambdas and `do` blocks, which open scopes of their own.

### 5.3 The rules, and where the analysis approximates

The analysis follows the scope rules of the Julia manual for a file:

- In a hard local scope, an assignment makes a local, unless the name is a
  local of an enclosing local scope (then it is that local) or `global x`
  declares it.
- A `for` variable and a variable of a comprehension are new locals of their
  loop, unless `outer` precedes them.
- At the top level, a `for` and a `while` body that assigns a global makes a
  local, as Julia does in a file. The REPL rule, which assigns the global,
  differs; the analysis takes the rule of a file.
- A `using M: x, y` binds `x` and `y`; a `using M` binds `M`. `JuliaUsing.path`
  is a flat string today, so the analysis reads the names from it.

The analysis approximates in these cases, and a name keeps the role `variable`:

- A macro call can bind names that the analysis does not see, such as the
  fields of `@kwdef`. The arguments of a macro call are uses.
- `@eval`, `include` and generated code bind names at run time.
- A name of a module that the editor did not load has no reflection.

### 5.4 A name that binds outside the document

A name with no binding in the document takes its kind from the module where
the code runs, by reflection: `isdefined(module, name)`, then the value gives
the kind. A function gives `function`, a type `type`, a module `module`, and any
other value `global`. So `println` is a function, `Int` is a type and `Base` is
a module. The module is `Main` by default; question Q3 asks if it is the module
of the evaluator instead.

## 6. The colouring

- `JuliaIdentifierToSyntaxLeaf` takes the style of the kind of its binding. At
  its binder it takes the bold font of a definition.
- The styles of the slots of B1 stay. A slot style and a binding agree, because
  both name the kind of the same name.
- The roles exist since B1: `parameter`, `type_parameter`, `variable`,
  `function_name`, `type_name`, `module_name`, `field`, `macro_name`. A new
  role is needed only if a kind must have a color of its own (section 7).

## 7. The hues

With the analysis, a parameter, a local, a global and an imported name still
share the color of `variable`, because the palettes have no free hue. There are
two ways:

- **(a) More hues.** Add hues to `PALETTE_HUES`, such as indigo, cyan, lime and
  brown. Radix and Tailwind have such scales, and the OKLCH palette computes
  any hue. Solarized has only eight accents, so some kinds share a color there.
- **(c) Fonts.** A parameter is italic, as many editors draw it, and a
  definition is bold. The other kinds share the color of `variable`.

My recommendation: start with (c), make screenshots of real Julia files in
each palette, and then decide on (a) (question Q4).

## 8. How a scope node sets its scope

A template rule can not set a property for its children today. Two ways give it
that power:

- **(i) An option of `@projection_template`**, in the kernel
  (`source/kernel/projection/ProjectionTemplate.jl`), that names a property and
  a function of the input: the rule prints its children with
  `with_property(ctx, :julia_scope, compute_julia_scope(input, scope))`.
- **(ii) A projection of the algebra**, such as
  `PropertyProjection(inner, key, compute)`, that prints `inner` with the
  property set and gives the IO map of `inner` as its own, so that its reference
  maps and its reader are those of `inner`. A projection of the algebra may hold
  a projection. The dispatch of `JuliaToSyntax` then wraps the rule of each
  scope node.

My recommendation: (ii), because it changes no kernel file, and step 1 first
checks that the IO map of `inner` stays the map that the editor uses. If it
does not, (i) is the way (question Q2).

A domain that embeds Julia code sets the scope of its own names the same way:
an FSM gives its variables to its guards and actions, and a process and a
formula do likewise.

## 9. Tests

- **The analysis:** a table of small Julia sources and the kind that each name
  takes, for every rule of section 5.3: a parameter used in a body, a local
  that a nested `for` assigns, a `for` variable, `global x`, a closure, a
  shadowing `let`, a struct field, a `where` parameter, `using M: x`, `println`.
- **What the screen shows:** `draw_texts`, as in `JuliaThemeTest`, asserts the
  color and the weight of each name.
- **The editing chain does not change:** `test_position_navigation(julia_example)`
  and `test_julia()` give the same counts as before, and the FSM and process
  suites pass.
- **The cost:** the time of the first print and of an edit of a large `.jl`
  file, before and after, measured by the performance expert.

## 10. Steps

1. ⬜ The mechanism of section 8, with a test that a wrapped rule keeps its
   reference maps and its reader.
2. ⬜ `JuliaScope`, `JuliaBinding`, `compute_julia_scope` for each scope node,
   `find_julia_binding`, `find_external_binding`, and the tests of the
   analysis.
3. ⬜ The leaf takes the style of its binding; the scope nodes set their scope;
   a `.jl` file and a module set the global scope; the new fields of
   `JuliaTheme`; the tests of the screen.
4. ⬜ The FSM, the process and the formula give their names to their Julia
   code.
5. ⬜ Screenshots in each palette and mode, and the decision on the hues.
6. ⬜ [julia.md](../../documentation/package/domain/julia/julia.md) and
   [style.md](../../documentation/package/platform/style/style.md) describe the
   analysis and the roles.
7. ⬜ The measure of the cost on a large file.

## 11. Questions

- **Q1. Where the bindings live** (section 4): the scope in the printer context
  (my recommendation), a separate bound stage, or bound types as the document?
- **Q2. How a scope node sets its scope** (section 8): a projection of the
  algebra (my recommendation) or an option of the kernel template?
- **Q3. The module of the reflection** (section 5.4): `Main`, or the module
  where the evaluator of the editor runs the code?
- **Q4. The hues** (section 7): fonts first and then a decision on more hues
  (my recommendation), or more hues now?
- **Q5. A name that binds nowhere**: the color of `variable` (my
  recommendation), or a color that warns?
- **Q6. The `as` on `collection`** (QB4 of the plan of B1): drop it, because the
  analysis covers its names (my recommendation)?
