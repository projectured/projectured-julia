# Bound Julia code stores each name once

> **Status:** proposal, not started. Nothing is implemented. The owner decided
> Q1, Q2 and Q12 on 2026-10-09 (section 14); the other questions are in
> section 13. This plan is part B2 of
> [a-value-takes-the-color-of-its-kind.md](a-value-takes-the-color-of-its-kind.md),
> whose parts A and B1 landed on `main` at `ee32195c6` on 2026-10-09.

## 1. The request

The owner wrote on 2026-10-09:

> we should make this a plan including the coloring and the analysis
>
> what new julia types and/or fields would be introduced? does it worth a
> separate projection step from going bound julia types to julia ast?

A first draft of this plan put the scope of each name into the context of the
printer, so that a name leaf found its binding while it printed. The owner
answered:

> no, I don't like the scope stuff
>
> I would like to have the possibility to store the completely resolved and
> bound version of julia code where each name is stored exactly one time. For
> example, a function and it's call do not store the function name twice, a
> variable definition and it's use do not store the name twice, the completely
> resolved document data structure is like what a compiler needs

So the draft is gone, and this plan describes the bound document.

## 2. What is there now

- **The document is the tree of the parser.** `parse_julia` calls
  `Meta.parseall` and converts each `Expr` head into a document
  ([julia.md](../../documentation/package/domain/julia/julia.md)). A name is a
  string in a `JuliaIdentifier`, so `area` in `function area(c)` and `area` in
  `area(x)` are two strings.
- **A `.jl` file is the text form.** `JuliaFile` holds the tree, and the save
  prints it.
- **B1 colors a name by its place**, such as the name of a function at its
  definition. A use of a name in a body keeps the role `variable`.
- **No analysis binds a name.** `find_julia_definition(document, name)` finds a
  top-level definition by its name, for the marker language.
- **A document can hold a node by identity.** `FsmTransition.trigger` holds its
  `FsmEvent`, and the printer reads the name from the event.
- **A save can store a node that a file reaches twice.** The cut of a project
  save writes the node at its first path and a reference leaf at each other
  path ([FileCut.jl:177](../../source/platform/serialization/FileCut.jl#L177)).
  A single-file save refuses such a node.

## 3. The rule

**Bound Julia code stores each binding once, in its binder. Every other
occurrence of the binding is a use, which holds the binder and no name.** A
rename of a binder renames every use, because no use stores the name.

The binder is the one place that a compiler gives a binding: a function, a
method argument, a static parameter, a local, a global, a type, a field of a
type, a module, and a name that comes from another module.

Three kinds of name stay names, because Julia resolves them only at run time,
and a compiler keeps them as symbols too:

- a field after a dot, `c.radius`, which is `getproperty(c, :radius)`;
- the name of a keyword argument at a call, `f(x; color = 1)`;
- a symbol, `:radius`.

The bound code keeps the form that the person wrote: `a[i] = v` stays an
assignment to an index, and a macro call stays a macro call. It binds names; it
does not lower the code.

## 4. The types

### 4.1 New types

Fifteen new `@document` types, under the root `JuliaDocument`:

| Type | Fields | What it is |
| --- | --- | --- |
| `JuliaBoundCode` | `bindings`, `externals`, `locals`, `statements` | The bound code of a file or of the body of a module: the globals and the functions that it declares, the names that come from other modules, the locals of its top-level loops, and its statements in order. |
| `JuliaModuleBinding` | `name`, `bare`, `code` | A module. |
| `JuliaFunctionBinding` | `name` | A generic function. Its methods are statements that use it. |
| `JuliaMethod` | `function`, `arguments`, `keyword_arguments`, `static_parameters`, `result_type`, `locals`, `body`, `short` | A method of a function: `function f(x) … end` and `f(x) = …`. `function` is a use of its `JuliaFunctionBinding`. |
| `JuliaArgumentBinding` | `name`, `type`, `default`, `splat` | An argument of a method or of a closure. |
| `JuliaStaticParameterBinding` | `name`, `upper_bound` | A name of `where`, and a parameter in the braces of a type. |
| `JuliaLocalBinding` | `name` | A local variable. The locals of a method are a list, as the slots of a compiled method are. |
| `JuliaGlobalBinding` | `name`, `constant` | A global variable of a module, or a constant. |
| `JuliaTypeBinding` | `name`, `kind`, `parameters`, `supertype`, `fields`, `constructors` | A `struct`, a `mutable struct` or an `abstract type`. |
| `JuliaFieldBinding` | `name`, `type` | A field of a type. |
| `JuliaExternalBinding` | `module_path`, `name`, `kind` | A name from another module, such as `Base.println`. `kind` comes from reflection when the code binds (section 7.3). |
| `JuliaClosure` | `arguments`, `locals`, `body`, `form` | An anonymous function: `x -> …` and a `do` block. |
| `JuliaImport` | `keyword`, `module`, `bindings` | A `using` or an `import`, with a use of each external binding that it brings. |
| `JuliaBindingUse` | `binding` | A use of a binding: it holds the binder by identity. |
| `JuliaUnresolvedName` | `name` | A name that no binder binds yet: a typed name, or a name of a file that the code does not define and that no module gives. |

### 4.2 Types of the tree that stay

The bound code reuses every type of the tree that holds no binder, with
`JuliaBindingUse` where the tree holds a `JuliaIdentifier`: the literals,
`JuliaCall`, `JuliaUnaryOperation`, `JuliaIndex`, `JuliaFieldAccess` (its
field stays a `JuliaIdentifier`), `JuliaTuple`, `JuliaArray`, `JuliaRange`,
`JuliaAssignment`, `JuliaIf`, `JuliaFor`, `JuliaForIterator`, `JuliaWhile`,
`JuliaLet`, `JuliaTry`, `JuliaComprehension`, `JuliaBlock`, `JuliaReturn`,
`JuliaTypeAnnotation`, `JuliaCurly`, `JuliaSubtype`, `JuliaWhere`,
`JuliaStringInterpolation`, `JuliaDocstring`, `JuliaFunctionDeclaration` (its
name becomes a use) and the others. The fields of these types hold any
`Document`, so a use fits where an identifier was.

### 4.3 Types of the tree that the bound code replaces

| Tree | Bound code |
| --- | --- |
| `JuliaIdentifier` as a name of a binding | `JuliaBindingUse` or `JuliaUnresolvedName` |
| `JuliaFunction` | `JuliaMethod` |
| `JuliaLambda`, `JuliaDo` | `JuliaClosure` |
| `JuliaStruct`, `JuliaAbstractType` | `JuliaTypeBinding` |
| `JuliaModuleDefinition` | `JuliaModuleBinding` |
| `JuliaUsing` | `JuliaImport` |
| `JuliaConst` | a `JuliaAssignment` to a `JuliaGlobalBinding` with `constant = true` |

Four fields of the tree hold a name as a string or a symbol and not as a
document: `JuliaBinaryOperation.operator`, `JuliaUnaryOperation.operator`,
`JuliaAssignment.operator` and `JuliaMacroCall.name`. An operator is a binding
too, such as `Base.:+` (decision Q2), so each `operator` field takes a document:
a `JuliaBindingUse` in bound code. Two kinds of operator stay symbols, because
they are syntax and no function: `&&` and `||`, and the `=` of an assignment.
An update such as `x += 1` holds a use of `+`, and the printer writes `+=`. The
printer reads the spelling and the precedence of an operator from the name of
its binder. A macro is a binding too, so `JuliaMacroCall.name` takes a use as
well if the owner agrees (question Q3).

### 4.4 An example

```julia
function area(c::Circle)
    r = c.radius
    return pi * r^2
end
area(Circle(1.0))
```

The bound code, where `Circle` is a `JuliaTypeBinding` of an earlier statement:

```julia
area_function = JuliaFunctionBinding("area")
c = JuliaArgumentBinding("c"; type = JuliaBindingUse(circle_type))
r = JuliaLocalBinding("r")
pi_constant = JuliaExternalBinding("Base", "pi", :global)
JuliaBoundCode(
    bindings = [area_function],
    externals = [pi_constant],
    statements = [
        JuliaMethod(function = JuliaBindingUse(area_function), arguments = [c], locals = [r],
                    body = JuliaBlock([
                        JuliaAssignment(:(=), JuliaBindingUse(r),
                                        JuliaFieldAccess(JuliaBindingUse(c), JuliaIdentifier("radius"))),
                        JuliaReturn(JuliaBinaryOperation(:*, JuliaBindingUse(pi_constant),
                                                         JuliaBinaryOperation(:^, JuliaBindingUse(r), JuliaInteger(2))))])),
        JuliaCall(JuliaBindingUse(area_function), [JuliaCall(JuliaBindingUse(circle_type), [JuliaFloat(1.0)])])])
```

`area`, `c`, `r` and `pi` are each stored once. `radius` stays a name, because
Julia finds the field at run time.

## 5. A separate step from the bound code to the tree?

**No separate step** (decision Q1).

- **The printer can print the bound code directly.** The bound code reuses the
  types of the tree, so `JuliaToSyntax` already prints every node that holds no
  binder. It needs one rule for each new type: a use prints the name of its
  binder, a method prints `function`, its function, its arguments and its body,
  and so on.
- **A step copies the whole tree.** `BoundJuliaToJulia` would rebuild every
  node at each print, and every caret move, selection and edit would pass
  through its two reference maps and its reader.
- **The text form needs no step.** The save of a `.jl` file prints the bound
  code with the same printer.
- **The tree stays the input of the binder.** `parse_julia` gives the tree, and
  the bind of section 7 makes bound code from it.

A step pays only when another part of the program needs the plain tree of bound
code. `make_julia_expression` prints a document and parses the text, so it takes
bound code as it is.

```
text ──parse_julia──▶ tree ──bind_julia──▶ bound code ──JuliaToSyntax──▶ SyntaxNode ──▶ text, graphics
```

## 6. The colouring

The rule of a `JuliaBindingUse` takes the style of the type of its binder:

| Binder | Role | Font |
| --- | --- | --- |
| `JuliaArgumentBinding` | `parameter` | italic |
| `JuliaStaticParameterBinding` | `type_parameter` | |
| `JuliaLocalBinding`, `JuliaGlobalBinding` | `variable` | |
| `JuliaFunctionBinding` | `function_name` | |
| `JuliaTypeBinding` | `type_name` | |
| `JuliaFieldBinding` | `field` | |
| `JuliaModuleBinding` | `module_name` | |
| `JuliaExternalBinding` | the role of its `kind` | |
| `JuliaUnresolvedName` | `variable` (question Q9) | |

The name of a binder takes the same role in bold. The roles exist since B1;
`JuliaTheme` gets a field for each row that it has no field for. Whether a
local, a global and a parameter need hues of their own is the question of
section 10.3 of the plan of B1, and it waits for screenshots (question Q10).

## 7. The bind

`bind_julia(tree) -> JuliaBoundCode` makes bound code from the tree of the
parser. The scope rules of Julia live here and nowhere else: a print, a caret
move and an edit of bound code need no scope. The bind runs when text becomes
code: a `.jl` file loads, a person commits typed code, or code is pasted.

### 7.1 What the bind does

1. It walks the statements in order and makes a binder for each definition: a
   function binding for the first method of a name, a type binding for a
   `struct`, a global binding for the first assignment of a name at the top
   level, a module binding for a module.
2. It walks each method and closure: its arguments, its static parameters, and
   a local binding for each name that the body assigns, by the rules of 7.2.
3. It replaces each name with a use of the binder that Julia gives it, or with
   an external binding (7.3), or with a `JuliaUnresolvedName`.

### 7.2 The rules

The rules of the Julia manual for a file:

- An assignment in a function, a closure or a `let` makes a local, unless the
  name is a local of an enclosing function or `global x` declares it.
- A `for` variable and a variable of a comprehension are new locals of their
  loop, unless `outer` precedes them. A `catch` variable is a local of its
  `catch`.
- Two locals of one method with the same name, such as `x` of an outer block
  and `x` of an inner `let`, are two `JuliaLocalBinding`s.
- An assignment at the top level of a file or a module makes a global; a `for`
  at the top level that assigns a name makes a local, as Julia does in a file.

Where the bind can not know, a name stays a `JuliaUnresolvedName`:

- a macro call can bind names that the bind does not see, such as the fields of
  `@kwdef`;
- `@eval`, `include` and generated code bind names at run time.

### 7.3 A name from another module

A name that the code does not bind takes its binding from the modules that it
uses, by reflection: `isdefined(module, name)` in the module of the evaluation
(question Q8), then in each module of a `using`. A function gives the kind
`:function`, a type `:type`, a module `:module`, a macro `:macro`, and any other
value `:global`. The bound code stores each such name once, in `externals`, and
each occurrence uses it. A name of a module that the editor did not load stays
unresolved.

### 7.4 The binder of Julia itself

Julia has a binder of its own: `JuliaLowering` gives each name a binding id. It
works on the syntax trees of `JuliaSyntax`, while `parse_julia` converts the
`Expr` of `Meta.parseall`. My recommendation is a bind of our own over our tree,
with a test that compares it with `JuliaLowering` on a corpus when the package
is there (question Q11).

## 8. Editing

| Edit | What happens |
| --- | --- |
| a person types in the name of a binder | the binder takes the new name, and every use prints it (a rename) |
| a person types a name in place of a use | the reader binds the text at that place: a use of the binder that Julia gives that name there, or a `JuliaUnresolvedName` |
| a person commits typed code | `parse_julia` gives a tree, and the bind binds it at the place of the insertion; a new assignment adds a local to the method |
| a person deletes a binder that has uses | each use becomes a `JuliaUnresolvedName` with the old name (question Q6) |
| a person pastes or moves code | each use binds again by its name at the new place, as the text means (question Q7) |
| a rename makes a name that an inner binder already has | the text of an outer use would bind to the inner binder (question Q5) |

The rename is the gain: one edit, and every use follows. The bind at a typed
name is the cost: it must find the binders that are visible at one place, which
is the walk of 7.2 along the path from the method to the place.

## 9. Storage

Bound code can be saved in three forms, and each one is supported in the end
(the owner, 2026-10-09):

1. **A plain `.jl` file.** A use writes the name of its binder, and the file is
   normal Julia that other tools read. The load parses the text and binds it,
   so the binders come back from the names. The cut of the save must not follow
   the field `binding` of a use: `is_written_in_file` answers `false` for it.
2. **A `.jl` file with references.** A use writes a reference to its binder,
   in the notation that a `.jl` file already has for a node of another file:
   the call `pred_ref("<<marker>>")`. A reference to a binder of the same file
   is a special case of a reference to another file. The load resolves the
   references, so the binders keep their identity across a save, and a use can
   hold a binder of another file or of another domain.
3. **A `.pred` file**, which writes the bound code as constructor calls, each
   binder once and each other place as a reference.

The binary snapshot, `save_document`, also keeps every identity, for one
version of the program.

### 9.1 The stages

The first stage is the plain `.jl` file (decision Q4). My proposal for the
order of the others (question Q13):

| Stage | Form | What it adds |
| --- | --- | --- |
| 1 | plain `.jl`, one file | bound code by default; the load binds by the names |
| 2 | plain `.jl`, the files of one module | the files that a module `include`s bind together, so a function of one file has one binder for the uses of every file |
| 3 | `.jl` with references | the identity of a binder on disk, and a use where a name can not carry the binding |
| 4 | `.pred` | the bound code as data, in the format of any document |

Stage 2 comes before stage 3, because a real package spreads one module over
many files, and its files must bind together before a reference between them
has a binder to name.

### 9.2 What stage 3 must solve

- **Where a reference may stand.** `pred_ref("…")` is a call, and Julia allows
  a call only where an expression stands. A use in an expression, such as an
  argument, an operand or a callee, can be a reference. A use in a place that
  defines, such as the name of a method, of an argument, or the target of the
  assignment that makes a local, must stay a name, because a call is no valid
  Julia there. That place is where the text shows the binder, and the
  references point to it.
- **The load.** The project load replaces each reference with the node that its
  marker names: a node of the tree at a place that defines. The bind then makes
  the binder at that place, and turns each reference to the place into a use of
  the binder.
- **One file alone.** The save of one file alone, `save_file!`, refuses every
  reference today, because it was made for a reference into another file. A
  reference into the same file needs no other file, so the save of one file
  must write it.
- **Which uses write a reference.** Every use, or only a use whose name would
  not bind back to the same binder: a use that an inner binder of the same name
  captures, a use of a binder of another file that the module does not
  `include`, and a use of a binder of another domain (question Q14).

## 10. Where bound code is used

**Julia code is bound code by default, as far as it can be** (decision Q12).
The tree stays the output of the parser, which the bind takes as its input, and
the form of a name that Julia resolves at run time.

- **A `.jl` file** opens as bound code.
- **Typed code** binds when the person commits it: a hole of a Julia document,
  a field of code of a form, a cell of the evaluator.
- **The Julia code inside another domain** binds against the binders of its
  host. A use may hold a binder of another domain, such as an `FsmVariable` of
  a state machine, so the name stays in one place across the two domains. Each
  type that is a binder answers two functions: `get_binding_name(binder)` and
  `get_binding_kind(binder)`. The Julia binders answer them, and a host domain
  adds methods for its own binders.
- **What stays a tree:** text that does not parse yet stays in its hole, and a
  name that nothing binds is a `JuliaUnresolvedName` in bound code.

These parts of the program read or make Julia documents, and each must take
bound code:

| Part | What it does with Julia code |
| --- | --- |
| `JuliaFile` | opens and saves a `.jl` file |
| `@gestures JuliaInsertion` | commits typed code with `parse_julia` |
| `make_julia_expression` | prints the code and parses it to run it |
| `find_julia_definition` | finds a top-level definition by its name, for the `definition` verb of the marker language |
| the tooltip of a `JuliaFunction` | gives its signature |
| `JuliaCodePieces` | colors a field of code token by token, from its text |
| the formula (`FormulaDocument.jl`, `MathToJulia.jl`) | holds and makes Julia code |
| the state machine (`FsmDocument.jl`, `FsmToJuliaCode.jl`) | holds guards and actions, and makes Julia code from a machine |
| the process (`ProcessDocument.jl`, `ProcessToJuliaCode.jl`) | holds steps, and makes Julia code from a process |
| the conversation (`Evaluator.jl`, `ConversationEditor.jl`) | evaluates code, and shows a `nothing` result as Julia |
| the examples and the atomic catalog | one document of each type; `CatalogCoverageTest` lists a type with no entry |
| inet-julia `generate_mac_fsm.jl`, `generate_plca_control_fsm.jl` | make state machines with Julia code |

The colours of B1 by the place of a name stay for a tree, which the parser
gives before the bind.

## 11. Tests

- **The bind:** a table of small sources and the binder of each name, for each
  rule of 7.2: a parameter used in a body, a local that a nested `for` assigns,
  a `for` variable, `global x`, a closure that captures, a shadowing `let`, a
  method of a function that an earlier statement defined, a struct and its
  fields, a `where` parameter, `using M: x`, `println`.
- **The round trip:** every `.jl` file of `source/` binds and prints back to the
  same text as the tree prints.
- **Each name once:** in the bound code of each file of the corpus, no binder
  name occurs twice in one scope, and every use holds a binder of the code or an
  external binding.
- **The rename:** a rename of a function, of an argument and of a local changes
  every use, and nothing else.
- **What the screen shows:** `draw_texts` asserts the color and the font of each
  name.
- **The editing chain:** `test_position_navigation` of a bound example, and the
  edits of section 8.
- **The storage:** a `.jl` and a `.pred` round trip; the `.pred` keeps the
  identity of the binders.
- **The cost:** the time of the bind and of the first print of a large `.jl`
  file.

## 12. Steps

1. ⬜ The types of section 4.1, and the fields of section 4.3 for an operator
   and a macro, by the answers to Q2 and Q3.
2. ⬜ The rules of the printer for the new types, with the colouring of
   section 6.
3. ⬜ `bind_julia`: the walk, the rules, the reflection, and the tests of the
   bind, of the round trip and of each name once.
4. ⬜ A `.jl` file as bound code: the open, the save, and `is_written_in_file`.
5. ⬜ The edits of section 8: the rename, the typed name, the commit of typed
   code, the delete, the paste.
6. ⬜ The parts of section 10 take bound code; a `.jl` file, typed code and the
   code of a form bind by default.
7. ⬜ The host domains bind their Julia code against their own binders, with
   `get_binding_name` and `get_binding_kind`: the state machine, the process
   and the formula.
8. ⬜ The later stages of the storage, by section 9.1: the files of one module
   (stage 2), the `.jl` file with references (stage 3), the `.pred` file
   (stage 4). Each stage is a plan of its own when it starts.
9. ⬜ Screenshots in each palette and mode, and the decision on the hues.
10. ⬜ [julia.md](../../documentation/package/domain/julia/julia.md) describes
    bound code.
11. ⬜ The measure of the cost on a large file.

## 13. Questions

- **Q3. A macro:** the name of a macro call becomes a use of its binding (my
  recommendation)?
- **Q4 (answered, section 14). The `.pred` file of bound code alone.** In bound code one node sits at
  several places: the binder `r` is in the `locals` of its method, and each
  use of `r` holds the same binder. A file can write an object only once, so
  the writer writes it at its first place and writes a reference, such as "the
  node at `locals[1]`", at each other place. The save of a project of several
  files does this today. The save of one file alone, `save_file!`, refuses any
  reference, because it was made for a reference into another file, which a
  file alone can not reach. May the save of one file alone write a reference to
  a place in the same file? Without it, bound code is saved alone as a `.jl`
  text, which keeps the names, and its binders come back from the names at the
  next load. My recommendation: yes, because a reference into the same file
  needs no other file.
- **Q5. A rename that captures:** refuse the rename (my recommendation), or
  allow it and mark each use whose text would bind to another binder?
- **Q6. A delete of a binder with uses:** the uses become unresolved names (my
  recommendation), or the delete is refused?
- **Q7. A paste or a move:** the uses bind again by their names (my
  recommendation, because the text means that), or they keep their binders?
- **Q8. The module of the reflection:** `Main`, or the module where the
  evaluator of the editor runs the code?
- **Q9. An unresolved name:** the color of `variable` (my recommendation), or a
  color that warns?
- **Q10. The hues:** fonts first and screenshots, then a decision on more hues
  (my recommendation)?
- **Q13. The stages of the storage** (section 9.1): plain `.jl` of one file,
  then of the files of one module, then `.jl` with references, then `.pred`?
- **Q14. The uses that write a reference** (section 9.2): every use, or only a
  use whose name would not bind back to the same binder?
- **Q11. The binder:** our own bind over our tree, compared with
  `JuliaLowering` in a test (my recommendation), or `JuliaLowering` itself?

## 14. Decisions

The owner answered on 2026-10-09:

- **Q1. The step:** "agreed": no step `BoundJuliaToJulia`; the printer prints
  bound code directly (section 5).
- **Q2. An operator:** "yes": an operator is a use of its binding, such as
  `Base.:+`; `&&`, `||` and the `=` of an assignment stay symbols
  (section 4.3).
- **Q4.** "I don't understand this question": section 13 says it again in
  other words.
- **Q12. The default:** "bound by default as much as possible": a `.jl` file,
  typed code and the Julia code of the other domains bind by default
  (section 10).
- **Q4. The storage:** "Just save as .jl for now, .pred files can come later."
  The owner added that a `.jl` file can hold references too, internal and to
  other files, and that each form of section 9 is to be supported; the order of
  the stages is open (section 9.1).
