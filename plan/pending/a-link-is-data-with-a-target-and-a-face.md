# A link is data with a target and a face

Status: PENDING, 2026-10-25. Not started.

## The ask

The owner, 2026-10-25: "So I was thinking about generalizing the WidgetLink. The
link would have at least two fields, one that the link refers to and one that
the link displays. The former can be any document even DocumentLocator, the
latter can also be any document but it's usually nothing or just a string. If
it's nothing then it's derived from what the link refers to. Then we also need a
URL document which a widget link could also use as the referenced content."

The answers of the owner in the discussion that followed, 2026-10-25:

- "the link can contain the document it refers to directly, there's no
  ownership here. It's an object graph which can be saved to disk."
- "A Link can also be data, but WidgetLink would usually not be saved into a
  file like any other widget is not saved either. Any domain can have its own
  link type. Like a link in markdown, or in HTTP, url is also an example.
  WidgetLink is one way to give it appearance and behavior but there could be
  other ways too."
- A `WidgetLink` holds a face and a behaviour, and no link: "The WidgetLink
  containing a Link looks weird. Why not just the face and the behaviour?"
- The behaviour is the target, not a general action: the owner agreed to that
  proposal.
- A click on a web address opens the system browser at once, and "Open as a
  page" shows the page of the address: the owner agreed to that proposal.
- A search stops at a link and finds a target where its own document holds it:
  the owner agreed to that proposal.

## What is there

On main at `bae6d5010`:

- `WidgetLink(content, target; icon, tooltip)` in the widget slice. `content`
  is the text. `target` is a `DocumentLocator` or a `Reference`, a path from the
  link. A click and Return answer `OpenPageOperation(..., :here)`, and Ctrl and
  a click and a middle click answer `:new_tab` (`_make_target_open` in
  `OpenPageOperation.jl`). A press selects nothing, and an open from a page
  moves no selection.
- The views that make links build each `WidgetLink` from a text and a target:
  the page of a section and of its search, the page of a folder, the Tasks pane,
  the first cell of a roster row, the page of a step and of the work of an
  agent. The research cards show their links as chips of the remote outline.
- `MarkdownLink(content, url)` and `RstReference(text, target)` are links of
  their domains. Their view draws them in the text pipeline, and a click answers
  `OpenPageOperation(...; target = <text>)`. `find_navigator_target(content,
  text)` resolves the text: `#install` names a heading, `guide.md` names a file.
  A web address names nothing, so a click on it does nothing.
- No document names an address outside the editor, and no operation opens one.

## The model

### A link is data

A link is a value that refers to a target and has a face. Each domain has its
own link type, and the platform adds a general one. A link type answers three
functions, the interface of a link:

| Function | Answers | Default |
| --- | --- | --- |
| `is_link(x)` | whether `x` is a link | `false` |
| `get_link_target(link)` | what the link refers to: a document, a place (`DocumentLocator`), or a `Url` | none: each link type defines it |
| `get_link_content(link)` | the face that the link carries: `nothing`, a string, or any document | `nothing` |

A link holds its target directly, as any field holds a document: an edge of the
object graph, not ownership. A save writes the graph, so a target that the file
owns at another place is a marker under the link.

A search does not go through a link into its target. The walk of the documents
(`walk_document`, which `search_documents` and `search_references` use) asks a
document which of its fields it enters, `is_field_walked(document, name)`, true
by default, and `Link` answers `false` for `target`. The walk still enters the
content of a link, so a search finds the alias of a link. A save does not use
this walk: the `.pred` file walks its own fields, and it writes a target that
only a link holds under the link.

### A view gives a link its face

A view that shows a link uses three functions, with defaults from the target:

| Function | Answers | Default |
| --- | --- | --- |
| `format_link_label(link)` | the text of the face | the content when it is a string; else the name of the target as the tree shows it (`format_tree_node_label`), of the node that a place reaches now, or the address of a `Url` |
| `describe_link(link)` | the words of the tooltip | the name and the place of the target, or the address of a `Url` |
| `is_link_broken(link)` | whether the target is gone | `true` for a place that reaches no node, else `false` |

The icon of a derived face is the icon of the target
(`get_document_decoration(target).icon`).

### A general link

`Link(target; content = nothing)` is a document that any document can hold. It
answers the interface from its two fields. Its view, `LinkToWidget`, draws it as
a `WidgetLink` with the face and the target that the interface gives. So a link
in a note, on a dashboard or in a list shows as the name and the icon of what it
names, and follows a rename.

### A URL

`Url(address)` is a document for an address, as the web writes it.

- An absolute address names a place outside the editor: `https://`, `mailto:`.
  A `file:` address names a file.
- A relative address, such as `#install` or `guide.md`, names a place that the
  page resolves against itself, as a browser resolves a relative link against
  the page: `find_navigator_target`, as now.
- A `Url` is a link to itself: `get_link_target(url) = url`, and its face is its
  address. So an address shows as a link wherever it stands.
- Its page, for "Open as a page", shows the address and the command "Open in the
  browser".

`OpenUrlOperation(url)` opens an absolute address outside the editor. The editor
evaluates it with `open_url!(backend, address)`. The SDL backend calls
`SDL_OpenURL`, which opens the system browser or mail tool. A backend that has
no system to open it in, as the one of the tests, opens nothing and answers
`false`, and the editor writes a line to the log.

### The widget: a face and a behaviour

`WidgetLink(content, target; icon, tooltip, enabled)` knows no link type.

- The face is `content`: a string, or a document that the recursion draws. A
  document face draws as its own view, with the line under it while the pointer
  is on the link.
- The behaviour is the target. `make_target_open_operation(target, place)` makes
  the open of each kind of target:

  | Target | Open |
  | --- | --- |
  | a document | `OpenPageOperation(document, EmptyReference(), place)` |
  | a `DocumentLocator` | `OpenPageOperation(start, reference, place)` |
  | a `Reference` | `OpenPageOperation(nothing, reference, place)`, a path from the link |
  | a relative `Url` | `OpenPageOperation(nothing, EmptyReference(), place; target = address)` |
  | a `file:` `Url` | `OpenFileOperation(path; file_wrap = Navigator)` |
  | another absolute `Url` | `OpenUrlOperation(url)`, for `:here` and `:new_tab` both |

- `enabled = false` draws the link muted, answers no click, and shows no line,
  as a disabled button does. A view sets it from `is_link_broken`.
- The widget keeps a document target as `DocumentLocator(document,
  EmptyReference())`. A walk over the output of a view gives each widget its
  part of the selection and of the mouse target, and it must not reach the
  target, which is a document of the input.

### Markdown and rst

`MarkdownLink` and `RstReference` answer the interface: the target is
`Url(<text>)`, and the content is their text. `find_navigator_target` answers a
`Url` for an absolute web address, and the navigator and the editor open it with
`OpenUrlOperation`. So a click on a web link of a page opens the browser. Their
view stays the text pipeline.

## Decisions

- **The link holds its target, and the widget holds a locator.** The owner
  decided that a link holds its target directly. My decision: `WidgetLink` keeps
  a document target as a locator with an empty path, because the walks over the
  output of a view write the selection and the mouse target of each node that
  they reach, and an input document must not get them from a widget.
- **A name that a page resolves is a relative `Url`.** My decision. A browser
  resolves `href="#install"` against the page in the same way, so markdown and
  rst need no kind of target of their own.
- **The browser opens through the backend.** My decision. The clipboard reaches
  the system through a hook in a module, which is global state. The backend of
  the editor is the editor's own, and SDL has `SDL_OpenURL`.
- **A field that the walk does not enter.** My decision, and a new seam of the
  kernel: `is_field_walked(document, name)` in the document layer. The walk
  already leaves out `selection` and `mouse_target` by name. The other way,
  `is_walk_opaque(::Link)`, would also hide the content of a link from a search.
- **A new platform slice `link`, after `tree` and before `pane`.** My decision.
  The derived face needs `format_tree_node_label` of the tree slice, the
  navigator needs `Url`, and the slice adds the methods of
  `make_target_open_operation` for a `Url` to the generic of the widget slice.

## Steps

Work in a new worktree from main, with a commit for each step.

1. [x] **The widget.** `WidgetLink` takes a document as a target, keeps it as a
   locator, and gets `enabled`. `make_target_open_operation(target, place)` is a
   generic of the widget slice, with the methods of the table above but the
   ones for a `Url`. A document as content draws through the recursion. Test:
   `test_widget_link()` with new cases, `test_open_page_operation()`.
   **Done 2026-10-25.** What the step found and decided:
   - `make_target_open_operation` opens any object as its page by default, so a
     document needs no method of its own. A locator with an empty reference
     opens as the object that it names would. So a `Url` that a link keeps as a
     locator still opens outside the editor in step 3.
   - A face that is a document prints through the recursion, and the link keeps
     the child for itself: it gives the face no event, so a press on the face is
     a press on the link, and the link stays the innermost part under the
     pointer. The line lies at the bottom of the face. Such a face gives no
     baseline.
   - `enabled` takes a `Bool` or a function. A link that is not enabled draws in
     the muted color, has no hand pointer and no line, opens nothing, and is no
     stop of Tab.
   - Pass: `test_widget_link()` 48 of 48, `test_open_page_operation()` 93 of 93,
     `test_widget_button_behavior()`, `test_roster_table()` 34 of 34,
     `test_explorer()` 294 of 294, and the naming guard.
2. [ ] **The link slice.** `is_field_walked` in `source/kernel/document/`
   (check its line in `SEALING.md` first), and the walk that asks it.
   `source/platform/link/`: the interface, `Link`, its view `LinkToWidget`, and
   the default face. Test: a kernel case of the walk that leaves out a field; a
   new `test/platform/link/LinkTest.jl` with `test_link()`, listed in the
   platform suite: the derived face and icon, a rename that the face follows, a
   broken place, a click that opens the target, a search of a note that finds
   the alias of its link and reads nothing of the large collection that the
   link names, and a save and load of a document that holds a `Link` to a node
   of the same file, of another file, and to a node that only the link holds.
3. [ ] **The URL.** `Url`, its page, `OpenUrlOperation`, `open_url!` for the SDL
   backend and the default, and the methods of `make_target_open_operation` for
   a `Url`. Test: `test_link()` cases for each kind of address, and
   `test_navigator()`.
4. [ ] **Markdown and rst.** `MarkdownLink` and `RstReference` answer the
   interface, and `find_navigator_target` answers a `Url` for a web address.
   Test: `test_markdown()` and `test_rst()`, with a click on a web link that
   answers `OpenUrlOperation`.
5. [ ] **The guides and a live check.** A guide `documentation/package/platform/link/link.md`,
   and updates of `widget.md`, `navigator.md`, `markdown.md` and `rst.md`. In a
   live SDL window: a `Link` on a page shows the name and the icon of its
   target; a click on a web link of a markdown page opens the browser. Move this
   plan to `plan/done/`.

## Not in this plan

- An edit of a link: a command that makes a link, or that changes its target.
- The links that point to a document ("what links here").
- The title of a web page as the face of its `Url`, which a read outside the
  editor would give.
- A view that shows any value that `is_link` answers as a link, in a roster cell
  or a tree.

## Open items

None.
