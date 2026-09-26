# Documentation tool results drawn as Markdown documents

> **Status:** done on 2026-09-25. Steps 0 to 5 and 7 landed at `8ece1ad1`, and
> Step 8 at `9b45cea5`. The owner dropped the timing of Step 6. Written 2026-09-25.

The assistant pane draws the answer of a documentation tool as plain text. The
answer is Markdown: a guide, a module, a type, a function, a list of search hits.
This plan makes the pane draw it as a Markdown document, through the Markdown
projection, while the model goes on to get the text that the tool wrote.

## 1. The owner's decisions (2026-09-25)

> I was specifically talking about the MCP tools and resources which return
> guides, search documentation and search api
>
> yes, I vote for B
>
> write plan

1. **The scope is the documentation tools**: `list_resources`, `read_resource`,
   `search_guides`, `search_api` and `read_function_documentation`. These are the
   tools of the tool set of the editor, which the MCP server also publishes.
   `execute_julia_code` keeps its text result.
2. **Option B: a tool declares the format of its result.** The assistant does not
   keep a list of tool names. The rejected option A was a list of tool names in
   the assistant, as `get_evaluation_kind_label` keeps for its labels.
3. **Questions 1 to 4 of §5 take the recommendation.** The owner, after the
   plan: "I agree with your recommendation", "implement in worktree".
4. **The branch lands before the layout range, and the grid in the transcript
   waits for it** (2026-09-25, after Step 6): "I agree with you, land now,
   I'll notify when they are done". The plan
   [layout-sizing-model.md](layout-sizing-model.md) is in progress on the branch
   `layout-range`; its Step 5a makes a card pass its range on to its content,
   which is the width a table in the transcript needs. Step 8 below follows
   when the owner says that plan is done.

## 2. What exists

- **A tool answers a `String`.** `Tool(name, description, parameters, handler)`
  has no format ([Tool.jl:18-23](../../source/kernel/tool/Tool.jl#L18-L23)).
  A `Resource` has `mime_type`, and every resource is `"text/markdown"` by
  default ([Tool.jl:40](../../source/kernel/tool/Tool.jl#L40)).
- **Eight calls construct a `Tool`**, and each gives the four positional
  arguments: [McpTest.jl:713](../../test/projectured/editor/McpTest.jl#L713),
  [:750](../../test/projectured/editor/McpTest.jl#L750),
  [:754](../../test/projectured/editor/McpTest.jl#L754),
  [OllamaTest.jl:21](../../test/ollama/OllamaTest.jl#L21),
  [AnthropicTest.jl:63](../../test/anthropic/AnthropicTest.jl#L63),
  [AssistantMvpTest.jl:306](../../test/projectured/editor/AssistantMvpTest.jl#L306),
  [FaultExamples.jl:193](../../example/fault/FaultExamples.jl#L193), and the six
  calls of `register_default_tools!`
  ([DefaultTools.jl:124-229](../../source/kernel/tool/DefaultTools.jl#L124-L229)).
  omnet-julia and inet-julia construct no `Tool`.
- **The MCP server sends a tool result as `TextContent`**
  ([Mcp.jl:171](../../source/mcp/Mcp.jl#L171)). MCP gives a text content no
  media type. A resource goes out with its `mime_type`
  ([Mcp.jl:198-201](../../source/mcp/Mcp.jl#L198-L201)).
- **A tool result becomes a text document.** `_handle_agent_event!` puts
  `make_evaluator_result_text(ev.output)`, a `TextBlock`, into the `result` of an
  `EvaluatorForm` part
  ([AssistantTurn.jl:740](../../source/assistant/AssistantTurn.jl#L740)). The
  function gets the tool set as `set`, so `find_tool(set, call.name)` gives the
  `Tool` ([ToolSet.jl:126](../../source/kernel/tool/ToolSet.jl#L126)).
- **The view draws any document in `result`.** The result section embeds
  `ef.result` and recurses through the projection chain of that document
  ([ConversationToWidget.jl:312-316](../../source/conversation/ConversationToWidget.jl#L312-L316)).
  The assistant tab draws the conversation with `NaturalToGraphics`
  ([Application.jl:171-172](../../example/projectured/Application.jl#L171-L172)),
  and a `MarkdownRoot` has the `:markdown_page` row: a stack of blocks whose
  prose breaks its lines at the page width
  ([MarkdownModule.jl:78-85](../../source/markdown/MarkdownModule.jl#L78-L85)).
- **Prose from the model is already a Markdown document.**
  `parse_natural_text(:md, …)` reads it when the Markdown parser is loaded
  ([AssistantTurn.jl:871](../../source/assistant/AssistantTurn.jl#L871)).
- **The model gets the result document printed back to text.**
  `_eval_result(ef) = _content_to_string(ef.result)`
  ([AssistantTurn.jl:165](../../source/assistant/AssistantTurn.jl#L165)) feeds
  the `tool_result` block of every round
  ([AssistantTurn.jl:523](../../source/assistant/AssistantTurn.jl#L523)) and
  `format_conversation`
  ([AssistantTurn.jl:573](../../source/assistant/AssistantTurn.jl#L573)).
  `EvaluatorForm` already keeps the text of the call in `source` for the same
  reason: a projection is not reversible in general
  ([Evaluator.jl:16-22](../../source/conversation/Evaluator.jl#L16-L22)).
- **The Markdown parser reads a subset of Markdown.** `_parse_blocks` knows ATX
  headings, fenced code blocks, block quotes, flat lists, thematic breaks and
  paragraphs ([MarkdownParser.jl:114-165](../../source/markdown/MarkdownParser.jl#L114-L165)).
  It joins the lines of a paragraph with a space
  ([MarkdownParser.jl:162](../../source/markdown/MarkdownParser.jl#L162)).
  90 of the 112 guides in `documentation/` hold a table, and 29 hold an HTML
  block. §3.5 lists what the tools write.
- **No test covers the Markdown parser by itself**
  ([markdown.md, Limits](../../documentation/package/markdown/markdown.md)).
  `test_markdown()` runs the layering guard, `test_markdown_page_wrap()` and
  `test_markdown_embed_card()`.

## 3. The design

### 3.1 A tool declares the media type of its result

`Tool` gets a fifth field, `result_mime_type::String`. The name follows
`Resource.mime_type`, and the value is a media type as MCP spells it.

```julia
struct Tool
    name::String
    description::String
    parameters::Vector{NamedTuple}
    handler::Function
    result_mime_type::String
end

Tool(name, description, parameters, handler; result_mime_type = "text/plain") =
    Tool(String(name), String(description), parameters, handler, String(result_mime_type))
```

- The four positional arguments stay, so no caller of §2 changes.
- `register_default_tools!` gives `result_mime_type = "text/markdown"` to the
  five documentation tools. `execute_julia_code` keeps `"text/plain"`.
- `read_resource` declares `"text/markdown"` because every registered resource
  is Markdown. A resource of another type makes this declaration wrong for that
  read. That case does not exist now, and §5 records it.
- **The handler contract does not change.** `handler(target, args) -> String`
  stays. The rejected alternative was a handler that answers a text and a media
  type. The MCP server, the Anthropic adapter, the Ollama adapter and
  `call_tool` all read the handler, so that change touches four places for one
  case that does not exist.
- **The MCP wire does not change.** A `TextContent` has no media type. The
  declaration is a fact of the tool layer, and each front end reads it or not.

### 3.2 The assistant reads the declaration

`_handle_agent_event!(ev::AgentToolResult, …)` makes the result document so:

1. If the call is `execute_julia_code` and the value is a `Document`, the result
   is the value, as now.
2. If `ev.is_error` is false, the tool declares `"text/markdown"`, and
   `has_natural_parser(:md)` is true, the result is
   `parse_natural_text(:md, ev.output)`. If the parse throws, go to 3.
3. Else the result is `make_evaluator_result_text(ev.output)`, as now.

The assistant maps one media type to one natural format, `"text/markdown"` to
`:md`, in one small function beside `_fence_extension`. The natural seam gets no
media type: that is a new mechanism, and one mapping does not need it.

An error result stays text, because an error text is a stack trace and not a
page.

### 3.3 The model gets the text that the tool wrote

`EvaluatorForm` gets a field `output::String`: the text the tool answered, kept
as it arrived. It has the same contract as `source`.

- `_eval_result(ef)` answers `ef.output` when it is not empty, and
  `_content_to_string(ef.result)` when it is empty.
- `_handle_agent_event!` sets `output = ev.output` for each result that it makes
  from the text of the tool: the text result and the Markdown result. A live
  `Document` result keeps `output` empty, so the model sees what it sees now.
- The keyword constructor gets `output::AbstractString = ""`. The other callers
  of `EvaluatorForm` do not change.

**Why the field is necessary.** The printed page is not the text that the tool
wrote: a paragraph comes back as one line, and §3.5 lists the other changes. The
model must get the tool result that it asked for, and every round sends the
history again, so a changed text is a changed prompt.

### 3.4 The view

No change is expected in the conversation package. The result section embeds
`ef.result`, and `NaturalToGraphics` draws a `MarkdownRoot` through the
`:markdown_page` row, and a table through `WidgetTable` (§3.5). Step 6 checks
this in the real editor, with the width that the section card offers.

A resource read starts folded (`_collapse_tool_default`), and a search result
starts open, as now.

*Found in Step 6.* The transcript does not reach the `:markdown_page` row. The
renderer of the transcript (`_conversation_widget_graphics` in
`example/conversation/ConversationProjectionExample.jl`) has an extra row,
`MarkdownDocument => make_markdown_rendered_projection_example(…)`, which draws
every Markdown document through the rendered syntax. So a result draws as
rendered Markdown, as the prose of the model does, and a table draws as its
source with pipes.

A row `MarkdownRoot => MarkdownRootToVerticalLayout → VerticalLayoutToGraphicsCanvas`
before it was tried, and removed. The table became a `WidgetTable`, but its
columns got no width: the transcript offers the content of a part no width (a
`Content` placement), a `Fill` column of a grid then gets 0 pixels, and the
entries were cut away. The prose around it wrapped at the 800-pixel fallback
of `WordWrapping`. A fallback width for the table would be a second number that
nobody chose, which `layout-rules.md` §1 forbids, and `Content` columns would
make a wide table leave the card. [layout-sizing-model.md](layout-sizing-model.md)
gives the content its width; then the row can be added (§5, question 5).

### 3.5 The Markdown domain reads what the tools write

**The survey (2026-09-25).** A script called the five tools on a `ToolSet` with
the default tools, and gave `parse_markdown` each of 16 outputs: the resource
list, the guide catalogue, a whole guide (`kernel/selection`), one section, the
module list, a module, a type, a function, and three `detail` levels of
`search_guides` and `search_api`. The script, the 16 dumps and the analysis
files are in `/var/tmp/projectured-tool-outputs-2026-09-25/`.
`print_natural_text(parse_markdown(text)) == text` holds for 2 of the 16. The
parser reads these constructs wrong:

| Construct | Where the tools write it | What `parse_markdown` makes |
| --- | --- | --- |
| Table | a guide, a section of a guide; 90 of 112 guides | one paragraph of pipes |
| List item, then an indented line with no marker | every hit of `search_api` at the default `detail`; the fragment list of a module | a list of one item, then a paragraph, for each item |
| Indented code block (4 spaces) | the `# Example` of a docstring: a type, a module, a function, `search_api` with one clear hit | one paragraph, with the lines joined and the indent lost |
| Admonition (`!!! warning "…"` and an indented body) | a docstring; 1 in `source/`, 0 in the guides | one paragraph |

The tools write no nested list, no hard line break and no math. A guide read
gives its HTML as text: 29 guides start with an `<img …>` line.

**Part 1: the parser only.** No new document type.

1. **A list item takes its continuation lines.** A line that is not blank and
   does not start a block continues the paragraph of the item above it, with or
   without an indent.
2. **An indented code block.** After a blank line, or at the start, a run of
   lines indented by 4 spaces or a tab becomes
   `MarkdownCodeBlock("", text)` with the indent removed. A blank line inside
   the run stays in the block. An indented line can not interrupt a paragraph or
   a list item, because rule 1 takes it first. The block prints back fenced
   (Question 1 of §5).
3. **An admonition becomes a quote.** A `!!! kind "title"` line and its
   indented body become a `MarkdownQuote`. The first block of the quote is a
   paragraph that holds the title in a `MarkdownStrong`. The body is parsed as
   blocks, with the indent removed, so rule 2 does not read it as code
   (Question 2 of §5).

*Implemented, and found on the way:*

- A list marker comes before an indented code block, so an indented list line
  after a blank line stays a list, as it was. A fence comes before both.
- A line that `_is_block_start` took for a block start, but that no branch
  read (a fence line with a backtick in its info string, as ```` ```a`b ````),
  made an empty paragraph and did not move the parse on: the parse did not end.
  The first line of a paragraph is now always taken.
- A hit of `search_api` is a list item of two source lines, a signature and a
  sentence. Markdown joins the two lines of one item with a space, so the page
  draws them as one line of prose. That is the Markdown of the text as the tool
  wrote it; a separate line needs a change of the tool text, which the model
  also reads, and it is not part of this plan.

**Part 2: the table.** Two new document types.

```julia
@document struct MarkdownTableRow <: MarkdownDocument
    elements::CellVector        # of MarkdownParagraph, one per column
end

@document struct MarkdownTable <: MarkdownDocument
    alignments::Any             # Vector{Symbol}: :default, :left, :center or :right
    header::MarkdownTableRow
    rows::CellVector            # of MarkdownTableRow
end
```

*Implemented:* `alignments` is an `Any` field, as `GridLayout.column_align` and
`WidgetTable.column_cell_policies` are. `@document` can put a reactive
collection in place of a field declared `Vector{…}`
(`get_cell_layout_field_type(Val(:Vector))`), and every walker would then see
the alignments as children.

- **A table entry is a `MarkdownParagraph`.** A paragraph already holds a run of
  inlines, and the page already draws a paragraph with line breaks at its width.
  So a table adds no type for one entry, and the word "cell" stays the reactive
  `Cell` (Question 3 of §5).
- **The parser.** A line with a pipe, followed by a delimiter row
  (`|---|:--:|`), starts a table. The rows end at a blank line or at a line
  with no pipe. The entries split at each `|` that is not escaped (`\|`). A
  table can interrupt a paragraph, as in GitHub Markdown, so the check for a
  continuation line knows it.
  *Implemented:* a code span does not protect a `|`. GitHub Markdown splits the
  row first and reads the inlines after, so a pipe inside a code span must be
  escaped there too, and the parser does the same. A row with fewer entries gets
  empty ones, and the entries past the last column are dropped.
- **`:source`.** A `@projection_template` rule for each type: `| ` before each
  entry, ` |` at the end of a row, and the delimiter row made from
  `alignments` after the header.
- **`:rendered` (syntax).** The `:source` rules, as the code block shares its
  rules now. The page route below is the one that draws a table as a grid.
- **The page.** *Implemented differently from the first design, which was a
  `:markdown_page` row `MarkdownTable => MarkdownTableToWidgetTable()`.* The
  renderer prints a block of the page as a child, and a child print does not
  reduce the output of a projection to a fixpoint. So a row whose output is a
  widget gives the page a widget, not graphics. `MarkdownRootToVerticalLayout`
  already swaps a file block for an embed card, and the renderer then draws the
  card; it swaps a table for a `WidgetTable` (`_make_page_table`) in the same
  place, made once for the table and found again. `WidgetTable` is the one
  table of the widget layer. Its
  `column_headers` are the entries of `header`, its `rows` are the `elements`
  of each row, and `cell_policy = :wrap`. The reference map moves the head
  only: `header.elements[j] + rest ↔ column_headers[j] + rest`, and
  `rows[i].elements[j] + rest ↔ rows[i][j] + rest`. The entry vectors are
  shared, not copied, as `MarkdownRootToVerticalLayout` shares the elements of
  a page. `WidgetTable` has no alignment for a column, so each column draws at
  the left (Question 4 of §5). *Implemented:* the columns are `Fill`, so they
  share the width of the page equally, and `:wrap` breaks the lines of an entry
  at the edge of its column. The selection of the widget table is the
  selection of the table, mapped as the embed card maps its own.
- **The examples.** `atomic_documents()` gets one small example for each new
  type, so `CatalogCoverageTest` and `test_example` cover them.

The pending [layout-sizing-model.md](layout-sizing-model.md) changes how a grid
gives width to its columns. The table does not wait for it: `WidgetTable`
already breaks the lines of an entry.

### 3.6 Size and time

The survey measured the parse only. The largest output, the guide catalogue, is
41,670 bytes, 223 lines and 1,016 nodes, and `parse_markdown` reads it in
1.7 ms after a warm-up. A whole guide (`kernel/selection`, 25,131 bytes, 481
lines) is 964 nodes.

The parse is not the cost to watch. The first print of about 1,000 nodes into
the page, and its first frame, run on the editor task in the drain. A resource
read starts folded, and nobody checked yet whether a folded card prints its
content. Step 6 measures the drain and the first frame with a whole guide,
folded and open. A timing run needs the owner's word and an idle machine.

## 4. Steps

Do the work in a git worktree, not in the main checkout. Commit each step.
Before a step changes a kernel file, check [SEALING.md](../../SEALING.md) for
that file. All files of `tool/` are `⬜` on 2026-09-25.

- [x] **Step 0. The baseline.** *Done 2026-09-25 on `8939434d`, in the main
  checkout: `/var/tmp/markdown-tool-results-baseline/` holds `test-counts.tsv`,
  `failures.txt`, `guide-census.tsv` and the reusable `census.jl`. Three tests
  fail on the base commit: `test_catalog_coverage` (2, 18 types with no catalog
  entry), `test_example(markdown_rendered_example)` (8 in `TypeinTest.jl:555`, and
  86 broken), and `test_assistant_mvp` (4, in "the assistant card fills its
  page"). The census: 229 top-level paragraphs of the guides and the dumps start
  with `|`.* On the base commit, run `test_markdown()`,
  `test_assistant_mvp()`, `test_conversation_serialization()`, the MCP tests of
  `McpTest.jl`, `test_search_answer()` and `test_example` for the Markdown
  examples. Also write the census of block types that `parse_markdown` makes
  for each guide under `documentation/`. Keep the counts and the census in
  `/var/tmp`. A test that counts the cells of a document changes its pass
  count when §3.3 adds a field.
- [x] **Step 1. `Tool.result_mime_type`** (§3.1). *Done: `test_search_answer()`
  75 pass (68 on the base, and 7 new).* `Tool.jl`,
  `DefaultTools.jl`, the `Tool` section of
  [agent.md](../../documentation/package/kernel/agent.md). Test: a new
  assertion in the kernel tool tests that the five documentation tools declare
  `"text/markdown"` and `execute_julia_code` declares `"text/plain"`.
- [x] **Step 2. The Markdown parser, part 1** (§3.5). *Done with Step 3 in one
  commit, because the table changes the continuation check that Step 2 adds.
  `test_markdown_parser()` 40 pass. The census of the guides and the dumps
  against the base: the 229 paragraphs of pipes are 229 tables; the lists are
  533, not 840, because a continuation line no longer ends a list; one new
  quote (the admonition of dump 08); two new code blocks (the `# Example` of
  dump 07, and the indented `evaluate_reference` line of
  `package/clipboard/clipboard.md`, which is a code block).* continuation lines,
  indented code blocks, admonitions. `MarkdownParser.jl`. Test: a new
  `MarkdownParserTest.jl` with `test_markdown_parser()`, called from
  `test_markdown()`. Its inputs are excerpts of the real outputs: a hit list of
  `search_api`, the `# Example` of `ConcreteReference`, and the docstring of
  `make_child_context`. Assert the block types and the text of each block. Also
  parse every guide under `documentation/`, compare the census of block types
  with the census on the base commit, and read each change.
- [x] **Step 3. The Markdown table, part 2** (§3.5). *Done: `test_markdown()`
  all pass (the page table test 27); `test_catalog(domain = :markdown)` 26812
  pass, against 23912 on the base, with the two new examples;
  `test_example(markdown_example)` 3911 pass as on the base; the rendered example
  and `test_catalog_coverage` fail as on the base, with the same messages. The
  table is drawn in `MarkdownRootToVerticalLayout`, not by a new projection;
  §3.5 says why.* `MarkdownDocument.jl`,
  `MarkdownParser.jl`, `MarkdownToSyntax.jl`, a new
  `MarkdownTableToWidgetTable` in `MarkdownToLayout.jl` or its own file,
  `MarkdownModule.jl`, the examples. Tests: the table of
  `kernel/selection.md` in `test_markdown_parser()`; parse, print and parse
  again gives the same tree; no guide under `documentation/` keeps a paragraph
  that starts with `|`; a table on a page draws a `WidgetTable` with the
  entries as its documents; `test_example` for the new examples.
- [x] **Step 4. `EvaluatorForm.output`** (§3.3). *Done with Step 5 in one
  commit, because both change `AssistantTurn.jl`.
  `test_conversation_serialization()` 44 pass (41 on the base, and 3 new).* `Evaluator.jl`,
  `AssistantTurn.jl`. Test in `ConversationSerializationTest.jl`: a form whose
  `result` is a `MarkdownRoot` and whose `output` holds a table gives
  `build_messages` a `tool_result` equal to `output`.
- [x] **Step 5. The assistant parses a Markdown result** (§3.2). *Done:
  `test_assistant_mvp()` 123 pass and the 4 fails of the base; the MCP tests of
  `McpTest.jl` 694 pass; `test_declared_api()` 117 pass. The error case throws
  an `ArgumentError`, because the loop marks an error by its text (§6).*
  `AssistantTurn.jl`. Test in `AssistantMvpTest.jl` with a scripted model and a
  tool that declares `"text/markdown"`: the result is a `MarkdownRoot`, the
  history holds the text of the tool, an error result stays a `TextBlock`, and a
  tool that declares `"text/plain"` keeps a `TextBlock`.
- [x] **Step 6. Check in the real editor.** *The owner dropped the timing on
  2026-09-25 ("drop it"): the parse of the largest answer is 1.7 ms, and a
  resource read starts folded. The check of the drawing is done,
  and the timing is not. A scripted model called `read_resource` for the
  section of `kernel/selection` with the table, and `search_api` for
  `evaluate_reference`, through `_run_agent_loop!`; the assistant row of
  `make_application_content_projections()` drew the conversation, and
  `write_image` wrote it. No real pointer pressed anything. Both results are
  `MarkdownRoot`s, the resource read starts folded, and the heading, the
  paragraphs, the code spans, the links and the search hit draw as rendered
  Markdown. The table draws as its source (§3.4). The timing needs the owner's
  word and an idle machine.* (The plan text:) Run the application offscreen with
  a scripted model that calls `read_resource` for a guide with a table and
  `search_api` with one clear hit. Read the scene and write an image. Check that
  the table draws as a grid and the page breaks its lines at the width of the
  section. Measure the drain and the first frame as §3.6 says, and give the
  numbers to the owner.
- [x] **Step 7. The documents.** *Done: the five guides below. The naming
  guard (`julia test/suite/naming.jl`) passes.*
  [assistant.md](../../documentation/package/assistant/assistant.md) (a turn,
  step 5, and the view),
  [markdown.md](../../documentation/package/markdown/markdown.md) (the new
  blocks, and the Limits),
  [mcp.md](../../documentation/package/mcp/mcp.md) (the declaration is not on
  the wire), and [transcript.md](../../documentation/package/conversation/transcript.md)
  if it names the kind of a result.

- [x] **The landing (2026-09-25).** Rebased on `88b2fac9`. Every test of the
  steps passes again, and `test_evaluator_duplicate()` (new on `main`) passes
  31; the duplicate of a form copies `output` with the other fields
  (`copy_document_fields`). The fails are the 14 of the base. The Markdown
  catalog is 26692 on the branch and 23581 on `main`: the six table examples
  add 3213, and `markdown/image/syntax` and `markdown/link/syntax` lose 102. The
  loss is the order of two equally short paths to `:syntax` (bridge 4, the
  one-leaf fallback of `JuliaToSyntax`, and bridge 5, `MarkdownToSyntax`), which
  `path_sequences` in `example/projectured/Catalog.jl` collects by walking a
  `Dict{DataType,Int}`: `main` lists the template first and the branch the leaf.
  The drawing of an image or a link does not change.
- [x] **Step 8. The grid table in the transcript, and the alignment of a
  column.** After Step 5 of [layout-sizing-model.md](layout-sizing-model.md)
  lands, when the owner says so:
  - Add `MarkdownRoot => ChainingProjection(MarkdownRootToVerticalLayout(),
    VerticalLayoutToGraphicsCanvas())` before the `MarkdownDocument` row of
    `_conversation_widget_graphics`, and draw the Step 6 image again: the table
    is a grid whose columns share the width of the section.
  - Pass `column_align` through `WidgetTable` to its `GridLayout`, moved by one
    column for a row-header strip as the policies are, and fill it from
    `MarkdownTable.alignments`. The `WidgetTable` printer is the function that
    Step 5a of the layout plan changes, so this waits for it.
  - Read the new names of the range: Step 5b of the layout plan removes
    `with_available_size`, which `MarkdownTableTest.jl` uses.

  *The owner said the layout changes are on `main` (2026-09-25). Implemented:*
  - *Step 5b of the layout plan renamed the call in `MarkdownTableTest.jl`
    itself (`with_exact_size`).*
  - *`WidgetTable` gets `column_align::Any` (a `Vector{Symbol}` of `:left`,
    `:center` and `:right`; a column past its end is `:left`), after
    `column_cell_policies`. The keyword constructor and the string shim take
    `column_align = Symbol[]` and refuse any other side; the positional calls
    (`CellTableToWidgetTable`, `_make_page_table`) pass one more cell. The grid
    printer passes `_wt_grid_column_align` to its `GridLayout`, with the
    row-header strip at the left. A table whose rows are a list places its cells
    itself (`WidgetTableList.jl`), so it adds `_wt_align_offset` to the x of a
    body cell and of a header cell; the field means the same in both forms.*
  - *`_make_page_table` fills `column_align` from `alignments`, with `:default`
    at the left (`_make_column_align`).*
  - *The row of the chat pane is the one that Step 6 tried.*

  *Tests (2026-09-25), against a baseline of `ae39586c` in
  `/var/tmp/markdown-table-grid-baseline/`:* `test_widget_table_column_align()`
  13 pass (both forms of a table, and a side that is none of the three);
  `test_markdown()` 113 (109 on the base); `test_assistant_mvp()` 127 and the 4
  fails of the base; `test_conversation_serialization()` 44; the other
  `WidgetTable` tests as on the base; `test_example(assistant_example)` and
  `test_example(conversation_widget_example)` with the fails of the base (2 and
  1060, the same places). The Markdown catalog is 26692 against 27217: the order
  of the two equal paths to `:syntax` changed again, now for the paragraph, the
  list and the table as well (see the landing note above).

  *Found in the check of the image: the bottom of a glyph is cut.* The TrueType
  measure answers the em size as the height of a line, and a `GraphicsText`
  box is `font_line_height`, the ascent and the descent, which is taller
  (`source/style/TrueType.jl`, "Vertical metrics"). A container that cuts at the
  measured height cuts the descenders of the last line: the grid of a
  `WidgetTable` cuts each cell, so the entries of a table are cut on `main`
  since the first landing, in a tab too ("Tvpe", "meanina"); and with the row
  in the chat pane, the stack of the page cuts each block, so every paragraph of
  the chat pane is cut, the prose of the model too. Without the row, the chat
  pane draws a whole page as one tree and nothing is cut. The row is therefore
  its own commit, and it lands only on the owner's word (§5, question 6).

  *Corrected on 2026-09-25, after a check of the graphics tree
  (`/var/tmp/text-height/cut_texts.jl`):* the paragraphs in the middle of a page
  are whole in both routes. What is cut is each table entry, by the viewport of
  its grid cell, and the last line of a result, by the viewport of the card body,
  in the old route as well. So the row added the cut table entries to the chat
  pane, and not every paragraph. The plan
  [a-line-of-text-sits-on-one-baseline.md](a-line-of-text-sits-on-one-baseline.md)
  holds the fix.

## 5. The questions

The owner took the recommendation of questions 1 to 4 on 2026-09-25 (§1,
decision 3). Question 5 came from Step 6, and the owner decided it on 2026-09-25.

1. **An indented code block prints back fenced.** A `.md` file that a tab
   saves changes an indented block to a fenced one. 3 guides have one. A saved
   file already changes now, because a paragraph comes back as one line. The
   alternative is a field on `MarkdownCodeBlock` that says which form it had.
   **Decided: the fenced form, no new field.**
2. **An admonition becomes a quote.** The alternative is a new block,
   `MarkdownAdmonition(kind, title, elements)`, with its own rules and example.
   One docstring uses it, and no guide does. **Decided: a quote.**
3. **A table entry is a `MarkdownParagraph`.** The alternative is a new type
   for one entry. Its natural name contains "cell", and that word is the
   reactive `Cell` in this project. **Decided: a paragraph.**
4. **The alignment of a column is kept but not drawn.** `alignments` makes the
   delimiter row print back the same, and `WidgetTable` draws every column at
   the left. **Decided: accept now, and draw it when `WidgetTable` gets
   an alignment for a column.**

5. **A grid table in the transcript** (found in Step 6, §3.4). **Decided: wait
   for the layout range (§1, decision 4), then Step 8.**
   The options: wait for [layout-sizing-model.md](layout-sizing-model.md) to
   give the content of a part its width, then add the page row for
   `MarkdownRoot` to the renderer of the transcript; or add the row now with a
   fallback width for a table that is offered none. *Recommendation: wait,
   because the fallback is a number that the sizing plan removes.*

6. **The row of the chat pane, while the text height is short** (found in
   Step 8). **Decided by the owner on 2026-09-25: "land all commits on main".**
   The row lands, and the short text height is its own work. The options: land the row now, and every paragraph in
   the chat pane loses the bottom of its last line until the height is fixed;
   or keep the row back, keep the tables of the chat pane as their source, and
   fix the height first, as its own plan: the text reports
   `font_line_height` and not the em size, a change of every text height in the
   editor. *Recommendation: keep the row back, and plan the height.*

## 6. Limits

- A table entry, and the last line of a result in the chat pane, lose the part
  of g, p and y below the baseline. `measure_truetype_text` answers 20 as the
  height of any text of `font_ubuntu_regular_20`, the em size, while the text
  it draws is `font_line_height`, 23 (an ascent of 19 and a descent of 4). The
  viewport of a grid cell and the viewport of a card body end at the height the
  text reports. The fix is the plan
  [a-line-of-text-sits-on-one-baseline.md](a-line-of-text-sits-on-one-baseline.md).

- `read_resource` declares one media type for every resource (§3.1).
- An MCP client does not get the declaration (§3.1).
- In the transcript, a table draws as its source with pipes, not as a grid
  (§3.4). On a page that has a width, such as a guide in a tab, it is a grid.
- The heading that `search_api` writes for one clear hit is a level-1 heading,
  so the transcript draws it large.
- The agent loop marks a result as an error by its text (`_is_error_output` in
  `AgentLoop.jl`: the text contains "Error" or "ERROR"). A tool that throws
  `error("…")` with a message that has neither word gives a result that is not
  an error, so a Markdown tool draws its stack trace as a page. The rule is the
  kernel's, and this plan does not change it.
- A guide read shows an `<img …>` line as text, because the tool output does
  not say where the guide is, and a relative image path needs that place.
- The signature at the top of a docstring draws as prose, because the
  documentation tool writes it with no indent.
- The printed page is not the text of the tool (§3.3), so a `.md` file saved
  from a tab still changes its form.
