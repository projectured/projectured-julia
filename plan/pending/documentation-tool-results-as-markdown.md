# Documentation tool results drawn as Markdown documents

> **Status:** in progress, in the worktree `projectured-julia-markdown-tool-results`
> on the branch `markdown-tool-results`. Written 2026-09-25.

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
3. **The four questions of §5 take the recommendation.** The owner, after the
   plan: "I agree with your recommendation", "implement in worktree".

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

**Part 2: the table.** Two new document types.

```julia
@document struct MarkdownTableRow <: MarkdownDocument
    elements::CellVector        # of MarkdownParagraph, one per column
end

@document struct MarkdownTable <: MarkdownDocument
    alignments::Vector{Symbol}  # :default, :left, :center or :right, one per column
    header::MarkdownTableRow
    rows::CellVector            # of MarkdownTableRow
end
```

- **A table entry is a `MarkdownParagraph`.** A paragraph already holds a run of
  inlines, and the page already draws a paragraph with line breaks at its width.
  So a table adds no type for one entry, and the word "cell" stays the reactive
  `Cell` (Question 3 of §5).
- **The parser.** A line with a pipe, followed by a delimiter row
  (`|---|:--:|`), starts a table. The rows end at a blank line or at a line
  with no pipe. The entries split at each `|` that is not escaped (`\|`) and
  not inside a code span. A table can interrupt a paragraph, as in GitHub
  Markdown, so `_is_block_start` knows it.
- **`:source`.** A `@projection_template` rule for each type: `| ` before each
  entry, ` |` at the end of a row, and the delimiter row made from
  `alignments` after the header.
- **`:rendered` (syntax).** The `:source` rules, as the code block shares its
  rules now. The page route below is the one that draws a table as a grid.
- **The page.** The `:markdown_page` row gets
  `MarkdownTable => MarkdownTableToWidgetTable()`, chained to the widget
  renderer. `WidgetTable` is the one table of the widget layer. Its
  `column_headers` are the entries of `header`, its `rows` are the `elements`
  of each row, and `cell_policy = :wrap`. The reference map moves the head
  only: `header.elements[j] + rest ↔ column_headers[j] + rest`, and
  `rows[i].elements[j] + rest ↔ rows[i][j] + rest`. The entry vectors are
  shared, not copied, as `MarkdownRootToVerticalLayout` shares the elements of
  a page. `WidgetTable` has no alignment for a column, so each column draws at
  the left (Question 4 of §5).
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

- [ ] **Step 0. The baseline.** On the base commit, run `test_markdown()`,
  `test_assistant_mvp()`, `test_conversation_serialization()`, the MCP tests of
  `McpTest.jl`, `test_search_answer()` and `test_example` for the Markdown
  examples. Also write the census of block types that `parse_markdown` makes
  for each guide under `documentation/`. Keep the counts and the census in
  `/var/tmp`. A test that counts the cells of a document changes its pass
  count when §3.3 adds a field.
- [ ] **Step 1. `Tool.result_mime_type`** (§3.1). `Tool.jl`,
  `DefaultTools.jl`, the `Tool` section of
  [agent.md](../../documentation/package/kernel/agent.md). Test: a new
  assertion in the kernel tool tests that the five documentation tools declare
  `"text/markdown"` and `execute_julia_code` declares `"text/plain"`.
- [ ] **Step 2. The Markdown parser, part 1** (§3.5): continuation lines,
  indented code blocks, admonitions. `MarkdownParser.jl`. Test: a new
  `MarkdownParserTest.jl` with `test_markdown_parser()`, called from
  `test_markdown()`. Its inputs are excerpts of the real outputs: a hit list of
  `search_api`, the `# Example` of `ConcreteReference`, and the docstring of
  `make_child_context`. Assert the block types and the text of each block. Also
  parse every guide under `documentation/`, compare the census of block types
  with the census on the base commit, and read each change.
- [ ] **Step 3. The Markdown table, part 2** (§3.5). `MarkdownDocument.jl`,
  `MarkdownParser.jl`, `MarkdownToSyntax.jl`, a new
  `MarkdownTableToWidgetTable` in `MarkdownToLayout.jl` or its own file,
  `MarkdownModule.jl`, the examples. Tests: the table of
  `kernel/selection.md` in `test_markdown_parser()`; parse, print and parse
  again gives the same tree; no guide under `documentation/` keeps a paragraph
  that starts with `|`; a table on a page draws a `WidgetTable` with the
  entries as its documents; `test_example` for the new examples.
- [ ] **Step 4. `EvaluatorForm.output`** (§3.3). `Evaluator.jl`,
  `AssistantTurn.jl`. Test in `ConversationSerializationTest.jl`: a form whose
  `result` is a `MarkdownRoot` and whose `output` holds a table gives
  `build_messages` a `tool_result` equal to `output`.
- [ ] **Step 5. The assistant parses a Markdown result** (§3.2).
  `AssistantTurn.jl`. Test in `AssistantMvpTest.jl` with a scripted model and a
  tool that declares `"text/markdown"`: the result is a `MarkdownRoot`, the
  history holds the text of the tool, an error result stays a `TextBlock`, and a
  tool that declares `"text/plain"` keeps a `TextBlock`.
- [ ] **Step 6. Check in the real editor.** Run the application offscreen with
  a scripted model that calls `read_resource` for a guide with a table and
  `search_api` with one clear hit. Read the scene and write an image. Check that
  the table draws as a grid and the page breaks its lines at the width of the
  section. Measure the drain and the first frame as §3.6 says, and give the
  numbers to the owner.
- [ ] **Step 7. The documents.**
  [assistant.md](../../documentation/package/assistant/assistant.md) (a turn,
  step 5, and the view),
  [markdown.md](../../documentation/package/markdown/markdown.md) (the new
  blocks, and the Limits),
  [mcp.md](../../documentation/package/mcp/mcp.md) (the declaration is not on
  the wire), and [transcript.md](../../documentation/package/conversation/transcript.md)
  if it names the kind of a result.

## 5. The four questions, decided

The owner took each recommendation on 2026-09-25 (§1, decision 3).

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

## 6. Limits

- `read_resource` declares one media type for every resource (§3.1).
- An MCP client does not get the declaration (§3.1).
- A guide read shows an `<img …>` line as text, because the tool output does
  not say where the guide is, and a relative image path needs that place.
- The signature at the top of a docstring draws as prose, because the
  documentation tool writes it with no indent.
- The printed page is not the text of the tool (§3.3), so a `.md` file saved
  from a tab still changes its form.
