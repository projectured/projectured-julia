# Julia code keeps its comments and its docstrings

> **Kind:** plan · **Status:** done 2026-10-13, on the branch `julia-comments`,
> not on `main`. The owner answered the three questions of section 8 on
> 2026-10-13. ·
> **Stands on:**
> [julia.md](../../documentation/package/domain/julia/julia.md),
> [syntax.md](../../documentation/package/platform/syntax/syntax.md),
> [strict-document-types.md](../pending/strict-document-types.md)

The Julia domain drops every comment when it parses code, so a save of a `.jl`
file deletes the comments of the file. This plan adds three comment types to the
domain, places each comment with the byte positions that the parser of Julia
gives, and prints the comments to the syntax domain. It also escapes the text of
a docstring, makes that text editable, and keeps the docstring of a struct field.

## 1. The request

The owner wrote on 2026-10-13:

> in projectured-julia, we should extend the Julia domain with storing the Julia
> documentation and comments and also extend the printer to properly print them
> to syntax domain

## 2. What is there now

**Comments.**

- `parse_julia` calls `Meta.parseall`
  ([JuliaParser.jl:48](../../source/domain/julia/JuliaParser.jl#L48)). The `Expr`
  tree holds no comment, so the document holds none.
- A `JuliaFile` saves the print of its document
  ([JuliaFile.jl:25](../../source/domain/julia/JuliaFile.jl#L25)). So an open and
  a save of a `.jl` file deletes every comment in it.
- The syntax domain has no comment type. A domain prints a comment as a
  `SyntaxLeaf`, as `RstCommentToSyntaxLeaf` does
  ([RstToSyntax.jl:420](../../source/domain/rst/RstToSyntax.jl#L420)).
- `JuliaTheme` has the role `comment_text`
  ([JuliaTheme.jl:41](../../source/domain/julia/JuliaTheme.jl#L41)). Only the
  colors of code in a text field use it now.
- The printer of a module writes `end # module Name` itself
  ([JuliaToSyntax.jl:336](../../source/domain/julia/JuliaToSyntax.jl#L336)). Most
  source files of this repository end a module with the same comment, for example
  `end # module AcpModule`.
- `ProcessToJuliaCode.jl` says that the Julia domain has no comment node
  ([ProcessToJuliaCode.jl:40-41](../../source/domain/process/ProcessToJuliaCode.jl#L40-L41)).
- `make_julia_expression` prints a document and parses the text again
  ([JuliaExpression.jl:27](../../source/domain/julia/JuliaExpression.jl#L27)). So
  a comment never reaches an evaluation.

**Docstrings.**

- `JuliaDocstring(text, subject)` holds the text of a docstring as a `String`
  ([JuliaDocument.jl:316](../../source/domain/julia/JuliaDocument.jl#L316)). The
  parser converts `Core.@doc "text" subject` into it
  ([JuliaParser.jl:181-185](../../source/domain/julia/JuliaParser.jl#L181-L185)).
- The printer writes the text between `"""` fences with no escapes
  ([JuliaToSyntax.jl:272-277](../../source/domain/julia/JuliaToSyntax.jl#L272-L277)).
  Julia 1.13.1 can not parse the print of these three docstrings:

  | the text of the docstring | the error of `Meta.parseall` for the print |
  | --- | --- |
  | `Costs $5.` | `identifier or parenthesized expression expected after $ in string` |
  | `A \ backslash.` | `invalid escape sequence` |
  | `Three """ quotes.` | `unterminated string literal` |

  So a save of such a file writes text that the next load refuses.
- The text of a docstring has no `bound` marker. A person can not edit it in the
  editor.
- A docstring of a struct field is a bare string in the `Expr` tree. The document
  holds it as a `JuliaString` statement, and the printer writes it on one line,
  with `\n` escapes.
- A docstring with an interpolation, `"""… $(x) …"""`, and a raw docstring,
  `raw"""…"""`, stay a `JuliaMacroCall` of `Core.@doc`. The printer writes each
  as a macro call on one line.

**The parser of Julia in Base.** A probe with Julia 1.12.7 and 1.13.1 found these
facts. Both versions give the same results.

- `Base.JuliaSyntax.tokenize(text)` gives each comment as a token of the kind
  `K"Comment"`, with its byte range. A `#!` line is one token, and a nested
  `#= … =#` is one token.
- `Base.JuliaSyntax.parseall(SyntaxNode, text)` gives the byte range of each
  node. A statement list is a node of the kind `K"toplevel"` or `K"block"`. The
  body of a function, a struct, a module, a branch and a `begin` is a `K"block"`.
  The bindings of a `let` are a `K"block"` too, but they are not statements.
- The innermost node that holds the byte range of a comment, and the child before
  the comment, give the place of the comment. Section 3.2 lists the cases of the
  probe.
- The parser already reads the tokens to find a `;` at the end of the text
  ([JuliaParser.jl:65-75](../../source/domain/julia/JuliaParser.jl#L65-L75)).

**Code that reads the statements of Julia code.**

- `get_julia_definition_name` gives the name of a top-level definition, and
  `find_julia_definition` uses it
  ([JuliaFile.jl:73-79](../../source/domain/julia/JuliaFile.jl#L73-L79)). It
  gives `nothing` for a node that it does not know.
- `FsmToJuliaCode` joins the guard of a transition with `&&`
  ([FsmToJuliaCode.jl:225](../../source/domain/fsm/FsmToJuliaCode.jl#L225)).
  `ProcessToJuliaCode` puts a condition into an `if` and a `while`. In both, the
  code of a person goes into an expression place.
- The type-in commit replaces the hole with the parse of its text
  ([JuliaInsertionToSyntax.jl:181](../../source/domain/julia/JuliaInsertionToSyntax.jl#L181)).
  The commit does not know whether the hole is a statement or an expression.

## 3. The model

### 3.1 Three comment types

```julia
"""A comment on a line of its own: `#` and the rest of the line."""
@document struct JuliaComment <: JuliaDocument
    text::String            # after the `#`, as written; one line
end

"""A comment between `#=` and `=#`. It can hold more than one line."""
@document struct JuliaMultilineComment <: JuliaDocument
    text::String            # between the fences, as written
end

"""A `#` comment after the code on the same line."""
@document struct JuliaEndOfLineComment <: JuliaDocument
    subject::JuliaDocument  # the statement before the comment
    text::String            # after the `#`, as written; one line
end
```

- `JuliaComment` and `JuliaMultilineComment` are statements. They stand in a
  statement list: the `statements` of a `JuliaBlock` or of a `JuliaToplevel`, or
  the root.
- `JuliaEndOfLineComment` holds the statement before it, as `JuliaDocstring`
  holds its subject. A move of the statement moves its comment too.
- The text keeps every character after the `#`, the first space too. So `# note`
  keeps ` note`, and a `#!/usr/bin/env julia` line prints back as it was.
- A comment binds no name and runs no code. `get_julia_definition_name` of an
  end-of-line comment is the name of its subject, as for a docstring.

### 3.2 Where a comment goes

The parser finds the innermost node of `Base.JuliaSyntax` that holds the comment.

| the place of the comment | the document | cases of the probe |
| --- | --- | --- |
| in a statement list, after a statement on the same line | the statement becomes the `subject` of a `JuliaEndOfLineComment` | `x = 1  # c`, `end  # c`, `x = 1;  # c`, `a = 1; b = 2  # c`, `x::Int  # c` |
| in a statement list, on a line of its own | a `JuliaComment` or a `JuliaMultilineComment` between the statements | between two statements, before `end`, in an empty body |
| in a statement list, on the header line of a block | a comment statement at the start of the body | `function f(x)  # c`, `if x  # c`, `else  # c` |
| in a node that is not a statement list | a comment statement before the statement that holds the node | `g(a,  # c`, `[1,  # c`, `let a = 1,  # c` |
| `#= … =#` after the code on a line | a `JuliaMultilineComment` after the statement | `x = 1 #= c =#` |

The third row and the fourth row move the comment. The print shows it on another
line, but its text stays in the file. Section 4 gives the reason.

A comment between a docstring and its definition needs no rule. Julia then does
not attach the docstring, so the string, the comment and the definition are three
statements.

### 3.3 How the parser finds the place

The `Expr` tree gives the line where each statement starts. It gives no column and
no end. So the converter of `Expr` can not find the place of a comment alone. The
parser of Julia can put it there:

1. `parse_julia` collects the comment tokens. If there are none, it parses as
   now.
2. It parses the text with `Base.JuliaSyntax.parseall(SyntaxNode, text)`, and
   computes the place of each comment by the rules of section 3.2.
3. It writes a copy of the text with a marker call for each comment:
   `var"#comment#"("text", :kind)`. The text is a Julia string literal, made by
   `repr`. The kind is `:own_line`, `:multiline` or `:end_of_line`. Julia gives
   names with `#` only to what the compiler makes, so no code of a person calls
   this name. The copy keeps every comment where it is.
   - For a comment that becomes a statement, the marker goes on the line after
     the comment. A line break comes after the marker when code is after the
     comment on its line.
   - For an end-of-line comment, the marker goes on the line after the comment.
     So the marker is the next statement of the same list.
   - For a comment that no statement list holds, the marker and a line break go
     before the statement that holds the comment. A line break comes before the
     marker when code is before that statement on its line.

   *Changed in step 3:* the first form of the copy put the marker in the place of
   the comment. Then in `"doc"`, a comment line and `f(x) = x`, the marker came
   directly after the string, and Julia made the marker the subject of a
   docstring. Julia does not attach a docstring across a comment line. With the
   comment kept, the marker follows the same tokens as the code after the comment
   did, so a docstring attaches exactly as in the text.
4. It parses the copy with `Meta.parseall`, and converts it as now. The
   converter turns a marker call into a comment type. `_convert_statements` wraps
   the statement before an end-of-line marker in a `JuliaEndOfLineComment`.

The parser of Julia puts each marker into the correct `Expr` block, so the
converter needs no table of positions. The text and the copy parse to the same
code, apart from the markers.

### 3.4 Docstrings

- **The escape.** The printer escapes the text by the rules of a triple-quoted
  string: `\` becomes `\\`, `$` becomes `\$`, and the third quote of a run of
  three becomes `\"`. The parser removes the escapes, so the text goes through a
  save and a load unchanged.
- **The edit.** The text of a docstring becomes
  `bound(:text, String, make_text_block(…))`. The leaf shows the escaped text, as
  the leaf of a JSON string does
  ([JsonToSyntax.jl:89-96](../../source/domain/json/JsonToSyntax.jl#L89-L96)).
- **The docstring of a field.** In the body of a struct, a string statement
  directly before another statement becomes a `JuliaDocstring` of that
  statement. Julia reads the same pair as the documentation of a field. So a field
  gets a tooltip with its documentation, and the printer writes the docstring
  with fences.
- **The fences stay `"""`.** The `Expr` tree does not keep a single `"`, and this
  plan reads only the comments from the tokens.

### 3.5 The printer

| type | rule | print |
| --- | --- | --- |
| `JuliaComment` | `JuliaCommentToSyntaxLeaf` | `#` as the `open` of a leaf, and the text as one line, `bound` |
| `JuliaMultilineComment` | `JuliaMultilineCommentToSyntaxLeaf` | `#=` and `=#` as the `open` and the `close`, and the text as lines, `bound` |
| `JuliaEndOfLineComment` | `JuliaEndOfLineCommentToSyntaxNode` | the subject, two spaces, `#` and the text, `bound` |

- Each rule is a `@projection_template` rule, as every rule of the domain is.
- The style of each rule is the role `comment_text` of `JuliaTheme`.
- A comment statement is an element of a statement list. So the block puts it on
  a line of its own, at the indentation of the block.
- A multiline comment prints its lines with `make_text_block`, so each line
  follows the indentation of the code. The parser removes the indentation of the
  first line of the comment from the lines after it.
- The text of a `#` comment holds no line break. A `bound` text that a
  `TextString` shows takes no break: a Return key in it gives no operation, and
  the key goes on to the readers around the text. So the rule needs no reader of
  its own. In the text of a multiline comment, which `make_text_block` shows, a
  Return key puts a break, as it must.

### 3.6 A comment stands where a statement stands

A comment in an expression place breaks the print. In `a  # c && b`, the comment
holds `&& b`, and a `)` after it goes into the comment too. So:

- The parser makes a comment only in a statement list (section 3.2).
- A new function, `get_julia_expression_without_comments(document)`, gives the
  expression of a document of one statement. That is the subject of an
  end-of-line comment, or the one statement of a block whose other statements are
  comments. `FsmToJuliaCode` and `ProcessToJuliaCode` call it where they put the
  code of a person into an expression place. The comment stays in the document of
  the state machine or of the process.
- The type-in commit keeps what the person typed (Q3). A comment typed into an
  expression hole prints as broken Julia, as other text typed into a wrong place
  does.

## 4. Decisions in this plan

These are my recommendations. The owner can change each one.

- **A comment on a line of its own is a statement of its own.** It does not
  attach to the statement after it. A section heading such as `# ── Parser ──`
  belongs to no single statement. A docstring attaches, because Julia attaches
  it.
- **One `JuliaComment` holds one line.** A run of `#` lines is a run of nodes. So
  the text of one node is one line, a `TextString` shows it, and an edit can not
  put a line without its `#` into the file.
- **A comment that no statement list holds moves before its statement.** Its text
  stays in the file. The other choice is to refuse the file. That makes a valid
  Julia file unreadable because of one comment in an argument list.
- **The space before an end-of-line comment is two spaces.** The document keeps
  no column. Comments that the source aligns at one column lose the alignment.
- **Only the comments come from the tokens.** The document keeps no blank line,
  no quote form and no column, as now. The design decision "one document type
  for one `Expr` shape" of julia.md gets this one exception.

## 5. Not in this plan

- **Blank lines.** The print puts no blank line between two statements now. It
  puts none between a comment and a statement either. The positions of section
  3.3 can give the blank lines in a later plan.
- **A docstring with an interpolation, and a raw docstring.** Each stays a macro
  call of `Core.@doc`.
- **A gesture that adds a comment.** A person types `# text` into a hole of a
  statement list, and the commit makes a `JuliaComment`.
- **A check that a typed comment stands in a statement list.** The owner accepts
  broken Julia from a type-in (Q3).
- **A `=#` in the text of a multiline comment.** Julia has no escape in a
  comment, so a typed `=#` ends the comment early. The printer does not check it.

## 6. Steps

The work runs in a worktree, on the branch `julia-comments`. Each step is one
commit. Nothing lands on `main` before the owner approves it.

- [x] **Step 1: the comment types and their print.** *Done 2026-10-13.*
  `test_julia()` passes 590 and fails 1, `JuliaExpressionTest.jl:31`. That failure
  is on `main` too: the `julia_code` example stands in a scroll pane. A Return key
  in a `#` comment gives no operation, so the rule needs no reader of its own
  (section 3.5). The `test_example` sweeps of the three catalog examples fail
  only where the same kind fails for unchanged atoms:
  - The `syntax` and `text` variants find no caret in graphics, as for every
    `bound` text: `json/string/syntax` fails 40, `xml/text/syntax` 40,
    `julia/module_def/syntax` 7.
  - `julia/end_of_line_comment/graphics` fails 6 at the identifier `x` of its
    subject, which is an opaque leaf. `julia/docstring/graphics` fails the same 6
    on the same subject, and 27 more on its text, which step 2 makes `bound`.
  - `julia/comment/graphics` and `julia/multiline_comment/graphics` fail none.
  - Add `JuliaComment`, `JuliaMultilineComment` and `JuliaEndOfLineComment` to
    [JuliaDocument.jl](../../source/domain/julia/JuliaDocument.jl), and export them
    from [JuliaModule.jl](../../source/domain/julia/JuliaModule.jl).
  - Add the three rules, and their entries of `JuliaToSyntax`, to
    [JuliaToSyntax.jl](../../source/domain/julia/JuliaToSyntax.jl), with the style
    `:comment_text`.
  - Add `get_julia_definition_name(::JuliaEndOfLineComment)`.
  - Add one catalog example for each type to
    [JuliaDocumentExample.jl](../../example/domain/julia/JuliaDocumentExample.jl).
  - Change the docstring of `comment_text` in
    [JuliaTheme.jl](../../source/domain/julia/JuliaTheme.jl), so that it names the
    comments of the code too.
  - Change the comment at
    [ProcessToJuliaCode.jl:40-41](../../source/domain/process/ProcessToJuliaCode.jl#L40-L41)
    to the present state.
  - Test: `test_julia_to_syntax()` prints each type alone and in a block with
    indentation, and sends a Return key to a `#` comment. `test_example` runs for
    the three catalog examples.

- [x] **Step 2: docstrings.** *Done 2026-10-13.* `test_julia()` passes 606 and
  fails only the known `JuliaExpressionTest.jl:31`. The sweep of
  `julia/docstring/graphics` fails 6, all at the identifier of its subject, where
  it failed 33 before; the 27 failures on its text are gone. Facts found:
  - A string before a comment or before another string in a struct body stays a
    string, so a field docstring never takes a comment as its subject.
  - A docstring in single quotes, such as `"The y."`, gets a line break at its
    end after one save and one load, because the triple quotes write one. From
    the second save on, the print is the same. The top-level docstrings did the
    same before this plan.
  - Found and not changed: the print of a `JuliaString` does not escape `$`
    ([JuliaToSyntax.jl, `_julia_string_escape`](../../source/domain/julia/JuliaToSyntax.jl)),
    so a string that holds a `$` prints as text that Julia does not read back.
  - Escape the text of a docstring in the print, and make the text `bound`.
  - Convert the docstrings of the fields in a struct body.
  - Test: `test_julia_parser()` parses, prints and parses again the three texts of
    section 2 and a struct with field docstrings, and compares the documents.
    `test_julia_tooltip()` shows the documentation of a field. A typed `$` in the
    text of a docstring puts a `$` into `text`.

- [x] **Step 3: the parser keeps the comments.** *Done 2026-10-13.*
  `test_julia()` passes 665 and fails only the known `JuliaExpressionTest.jl:31`;
  `test_fsm_to_julia_code()` passes 39. Section 3.3 holds the change of the copy.
  Facts found:
  - 51 files of the Julia, FSM, process, JSON and syntax slices, read with their
    comments and without them, have the same result each way: 12 print back
    exactly, 13 print a second time differently, 23 print text that does not
    parse, and 3 do not parse. Every file that parses keeps every comment in
    order. The 36 files that do not print back show limits of the printer that
    comments do not cause, such as the `$` of a string.
  - `test_example(julia_code_example)` fails 423 in the type-in sweep, all on
    opaque leaves: 408 on the name of an identifier and 15 on the string `"! = "`.
    The comment and the docstring texts of the example pass. `julia_example`
    fails its known 84 (28 positions on identifiers, 3 edits each).
  - The end of a module prints `end  # module M` from `end # module M`: two
    spaces, as decision 4 says.
  - Add the parts of section 3.3 to
    [JuliaParser.jl](../../source/domain/julia/JuliaParser.jl): collect the
    comment tokens, compute their places, and write the copy with the markers.
    Convert the markers in `convert_expr` and in `_convert_statements`.
  - `parse_julia` reads the `;` at the end of the last statement before the
    end-of-line comment of that statement.
  - The printer of a module writes `end`, with no comment of its own (Q2). A
    `# module Name` in a file is an end-of-line comment like any other.
  - Change the code shape in the comment at
    [FsmToJuliaCode.jl:24-42](../../source/domain/fsm/FsmToJuliaCode.jl#L24-L42),
    which ends with `end # module FooFsm`. Change the assertion at
    [FsmToJuliaCodeTest.jl:9](../../test/domain/fsm/projection/FsmToJuliaCodeTest.jl#L9),
    which looks for `end # module ToggleFsm`, to look for the bare `end`.
  - Add a section comment, an end-of-line comment and a docstring to
    `_JULIA_CODE_EXAMPLE_SOURCE` in
    [JuliaDocumentExample.jl](../../example/domain/julia/JuliaDocumentExample.jl).
  - Test: `test_julia_parser()` runs the cases of section 3.2 as pairs of a source
    text and the text of its print. A second test reads a fixed list of real files
    of this repository. For each file, `parse_julia` reads it, the print holds
    every comment text of the file in the same order, and `parse_julia` of the
    print prints the same text again. Step 3 takes the list from the files that
    `parse_julia` reads today. `test_julia_to_syntax()` prints a module that code
    made, with a bare `end`, and a module from a text with `end # module`, with
    the comment. `test_julia_file_view()` runs for the changed example.
    `test_fsm()` runs for the changed assertion.

- [x] **Step 4: a comment stands where a statement stands.** *Done 2026-10-13.*
  `test_julia_typein()` passes 12, `test_fsm()` 177 and `test_process()` 315. The
  expression places are the guard of a transition and the default of a variable
  in `FsmToJuliaCode`, and the condition of a decision and of a loop, the
  variable and the iterable of a loop and a returned value in
  `ProcessToJuliaCode`. An action and an entry block are statement places, so
  their comments go into the generated code. The type-in commit does not change
  (Q3).
  - Add `get_julia_expression_without_comments`. Call it in `FsmToJuliaCode` and
    in `ProcessToJuliaCode` at each expression place.
  - Test: `test_fsm()` and `test_process()` with a guard and a condition that hold
    an end-of-line comment. `test_julia_typein()` types `# note` into a hole of a
    block, and the commit makes a `JuliaComment`.

- [x] **Step 5: the guide, and the close.** *Done 2026-10-13.* Results:
  - `test_julia()` passes 667 and fails only the known `JuliaExpressionTest.jl:31`.
    `test_formula()` passes 187, `test_fsm()` 177 and `test_process()` 315.
  - `test_file_project()` passes 143 with 1 broken and no error: `main` marks the
    Julia case `@test_broken` since `cb540d963`.
  - `test_documentation()` passes. The navigation of `julia_example` fails its
    known 28; the count did not grow.
  - `test_application()` fails 2 and errors 2 at `ApplicationTest.jl` 1066, 1077,
    1114 and 1462, which fail on `main` too (the full run of 2026-10-13).
  - *A change of behavior found in step 5:* an evaluated form with an end-of-line
    comment now prints back as the same tokens, so the evaluator makes a Julia
    document of it, where it kept a string before. A comment above a statement
    still keeps the string, because the form is two statements. Three tests used
    a comment to get a string form: `EvaluatorToplevelTest.jl` takes the
    two-line form `x = 1` and `# one`, or expects the parse, and
    `ApplicationTest.jl` takes `y = 2x + 1`. `test_evaluator_toplevel()` passes
    239. The docstring of `find_form_document` and
    [conversation.md](../../documentation/package/platform/conversation/conversation.md)
    say so.
  - Write the comment types, the rule of section 3.2, the docstring rules and the
    limits into [julia.md](../../documentation/package/domain/julia/julia.md).
  - Run `test_julia()`, `test_fsm()`, `test_process()` and `test_formula()` once.
    `test_file_project` errors for Julia on `main` before this plan
    ([strict-document-types.md](../pending/strict-document-types.md), step 8), so its result
    is compared with the result on `main`.
  - `test_position_navigation(julia_example; check_reaches_all = true)` has 28
    failures on `main`. The count must not grow.
  - Move this plan to `plan/done/`.

## 7. Related plans

- [strict-document-types.md](../pending/strict-document-types.md): the new fields use the
  declared types of the domain: `JuliaDocument` for the subject, and `String` for
  a text. The owner's remark of 2026-10-13 says that a node of another domain can
  sit in a Julia comment. The owner's answer to Q1 keeps a `String` for now.
- [bound-julia-code-stores-each-name-once.md](../pending/bound-julia-code-stores-each-name-once.md):
  a comment binds no name. The bound document must keep the comments, or its
  print loses them.
- [julia-syntax-navigation.md](../pending/julia-syntax-navigation.md): the comment leaves and
  the text of a docstring are `bound`, so a caret goes into their characters. The
  other leaves of the domain stay opaque.

## 8. Questions for the owner

1. **Q1. What does a comment hold?** **Decided by the owner, 2026-10-13: (a)**,
   "a plain string for now".
   - (a) Its text, a `String`, as a docstring holds now. A save writes text, and a
     load reads text. A later plan can widen the field.
   - (b) A document of any domain, as the remark of 2026-10-13 says. A JSON object
     or a reference in a comment then needs a form in the `.jl` file that a load
     reads back. That is the same question as the reference from a Julia file to a
     node of another file, which the owner deferred on 2026-10-13.
2. **Q2. How does a module end?** **Decided by the owner, 2026-10-13: (a)**, "the
   comment is a normal comment, no magic auto comment".
   - (a) The printer writes `end`. A `# module Name` in a file is an end-of-line
     comment like any other, so the print holds only what the file holds. A module
     made in the editor ends with a bare `end`.
   - (b) The printer writes `end # module Name` as now. The parser drops an
     end-of-line comment equal to ` module Name` on that `end`. A different
     comment, such as `# module` with no name, then prints after the printed one.
3. **Q3. What does the commit do with a comment typed into an expression hole?**
   **Decided by the owner, 2026-10-13: (b).** The owner wrote: "you can create
   broken Julia in million ways, it's not a problem", and confirmed (b).
   - (a) The commit keeps a comment only when the hole is an element of a
     statement list. Elsewhere it keeps the expression and drops the comment, as
     now. The commit then must read the place of the hole, and no gesture of the
     domain reads a place today.
   - (b) The commit keeps what the person typed. A comment in an argument hole then
     prints as broken Julia, and a save writes it.
