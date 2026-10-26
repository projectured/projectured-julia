# An address holds its pieces

Status: DONE, 2026-10-25. Landed on main at `1ea4f4411`.

## The ask

The owner, 2026-10-25, after the landing of the link slice: "Why doesn't a URL
represents by pieces? Scheme, host, port, etc?" Then, to the proposal of a `Url`
that holds its pieces as fields, with its text as a projection: "Yes, write plan
for URL in pieces".

The owner, 2026-10-25, about the model of the edit, to the proposal that a typed
edit reads the whole address again: "Yes, I agree with the recommended type in
model".

## What is there

On main at `514007226`:

- `@document struct Url address::String end` in the link slice
  (`source/platform/link/LinkDocument.jl`). The address is one text, a leaf: no
  view can select its host, no filter can find the links to one host, and no
  operation can change one piece.
- The readers of the text: `is_absolute_url` and `find_url_file_path` match a
  regular expression on it (`UrlInterface.jl`), and `make_target_open_operation`
  gives it to `OpenPageOperation` as a target text. The labels, the tooltip, the
  title and the description of `OpenUrlOperation` show it (`LinkDocument.jl`,
  `OpenUrlOperation.jl`). The page `UrlView` draws it in a `WidgetLabel`
  (`UrlViewToWidget.jl`). The navigator gives it to `open_url!`
  (`NavigatorPageOpen.jl`).
- The producers make a `Url` from a text: `Url(link.url)` of Markdown,
  `Url(reference.target)` of rst, and `find_web_url(text)`.
- No view edits the address. A `Url` in a document draws as a link, whose click
  opens it.
- A save writes the field `address`.
- The link slice stands before the syntax slice in the include order of
  `ProjecturedPlatform`, so it can not use the syntax pipeline now. Only the
  navigator, which stands after both, uses the link slice.

## The model

### The pieces

A `Url` holds the seven pieces of RFC 3986 as fields, each one as it was
written: not decoded, not changed to lower case, with no default port added.

| Field | Holds | When absent |
| --- | --- | --- |
| `scheme` | `https`, `mailto`, `file` | `nothing`: a relative address |
| `userinfo` | `user:secret` | `nothing` |
| `host` | `julialang.org`, `[::1]`, `""` | `nothing`: no `//` part |
| `port` | `8080`, as text | `nothing` |
| `path` | `/docs/guide`, `someone@example.org` | never: it is `""` when empty |
| `query` | `lang=en` | `nothing` |
| `fragment` | `install` | `nothing` |

`nothing` and `""` are different, as RFC 3986 makes them: `guide.md?` has an
empty query, and `guide.md` has no query. The `//` part is there when `host` is
not `nothing`.

| Address | Pieces that are not `nothing` |
| --- | --- |
| `https://julialang.org` | scheme `https`, host `julialang.org`, path `""` |
| `http://u:p@[::1]:8080/a?b#c` | scheme `http`, userinfo `u:p`, host `[::1]`, port `8080`, path `/a`, query `b`, fragment `c` |
| `mailto:someone@example.org` | scheme `mailto`, path `someone@example.org` |
| `file:///tmp/a%20b.txt` | scheme `file`, host `""`, path `/tmp/a%20b.txt` |
| `#install` | path `""`, fragment `install` |
| `guide.md?` | path `guide.md`, query `""` |
| `ug:cha:queueing` | scheme `ug`, path `cha:queueing` |
| `1x:y` | path `1x:y`, because `1x` is no scheme |

An address with no host, such as `mailto:`, `urn:` or `data:`, needs no special
case: RFC 3986 reads all of them with the same grammar, and the text after the
scheme is the path.

### The read and the print

- **`Url(text)` reads a text into pieces, and never fails.** It uses the
  regular expression of RFC 3986, appendix B, which matches every text. The
  scheme is limited to its grammar, a letter and then letters, digits, `+`, `-`
  or `.`, so a text before a colon that is no scheme stays in the path. In the
  `//` part, the userinfo is the text before the last `@`, the port is the text
  after the last `:` that stands after any `]`, and the host is the rest.
- **`format_url(url)` prints the pieces**, by the rule of RFC 3986, section
  5.3: `scheme:` when there is a scheme, `//` when there is a host, `userinfo@`,
  the host, `:port`, the path, `?query` and `#fragment`.
- **The print of a read gives the same text**: `format_url(Url(text)) == text`
  for every text. The read keeps each piece as written, so this holds for a
  valid address and for an address that is not valid. This plan checks no
  validity.

### The edit

- **`make_url_text_operation(url, text)`** reads `text` and answers one
  `CompoundOperation` that writes each piece that changes, and `nothing` when no
  piece changes. It writes the fields of the same `Url`, so a `Link` that holds
  the `Url` keeps it.
- **`make_url_piece_operation(url, piece, text)`** prints the address with the
  one piece changed, and then calls `make_url_text_operation`. So a piece that
  gets a delimiter of another piece moves the text into that piece: a host
  `julialang.org/docs` becomes the host `julialang.org` and the path `/docs`. A
  piece of the `//` part on an address with no host makes the host `""`.
- **A write of one field with `ReplaceReferencedValueOperation` stays
  possible**, as on any document. It can give pieces whose print reads back to
  other pieces. The `Url` keeps the pieces as written, the open uses
  `format_url`, and the next edit of the text reads them again. The guide says
  so, and points a program and the assistant to `make_url_piece_operation`.

### The views

- **The text line.** `UrlToSyntax` prints a `Url` as one line of syntax: a leaf
  for each piece that is there, and a leaf for each delimiter (`:`, `//`, `@`,
  `:`, `?`, `#`). The host draws strong, and the other pieces and the
  delimiters draw muted, as the address bar of a browser draws them. A selection
  in a leaf of a piece names the field, such as `.host{3}`.
- **A typed edit reads the whole address again**, as the address bar of a
  browser does. Any edit in the line, in a piece or on a delimiter, becomes an
  edit of the text at the same place, then `make_url_text_operation`, then a
  `ReplaceSelectionOperation` that puts the caret at the same place in the new
  text. So `/docs` typed after the host goes into the path, `?` starts a query,
  a Backspace that removes `//` makes the host a part of the path, and a paste
  of a whole address fills every piece. One edit is one undo step.
- **The page.** `UrlView` shows the text line, the list of the pieces with
  their names, with "none" for an absent piece, and the button that opens the
  address.
- **A `Url` in a document still draws as a link**, and a click opens it. The
  page of the `Url` edits it, as a browser opens a link from a page and edits
  the address in its address bar.

## Decisions

The owner decided the model of the edit: a typed edit reads the whole address
again. The other decisions are my recommendations, which the owner did not
decide.

- **Each piece holds its text as written.** A browser keeps a normalized
  address: a host in lower case, no default port, its own escapes. That changes
  what a person wrote at the next save. A comparison of two addresses that are
  equal in meaning is a separate function, which this plan does not add.
- **The port is text, not a number.** `08080`, an empty port after `:` and a
  port that is not valid must print back as written.
- **The path and the query are one text each.** The segments of a path and the
  pairs `name=value` of a query are a split of that text, and the pairs are a
  convention of HTML forms, not of RFC 3986. A list of segments or of pairs
  gives the same problem of delimiters one level lower. A later plan can give
  them a view, as `URLSearchParams` of a browser does.
- **A typed edit reads the whole address again**, and not a gesture for each
  delimiter key. The owner agreed, 2026-10-25. The read handles a paste, a
  delete over a delimiter and a typed delimiter with one rule, and the pieces
  stay the stored structure.
- **The link slice moves after the syntax slice** in the include order, and uses
  the syntax and the text slices. No slice between the two uses the link slice,
  and the syntax slice uses no slice that comes after it.
- **The constructor `Url(text)` stays**, so Markdown, rst and `find_web_url`
  do not change. The struct has seven fields, so a one-argument constructor does
  not collide with the constructor of `@document`.
- **A saved `Url` with the field `address` does not load.** A saved file needs
  no compatibility before a release.

## Steps

1. [x] **The pieces.** `Url` holds the seven fields; `Url(text)` reads, and
   `format_url` prints. `make_url_text_operation` and
   `make_url_piece_operation`. The readers of `address` use the pieces or
   `format_url`: `is_absolute_url` reads the scheme, and `find_url_file_path`
   reads the scheme `file`, in any case, and the path. Test, in `test_link()`:
   the table of addresses above, and more, with their pieces and the same text
   back; the two operations write only the pieces that change; a save keeps the
   pieces. `test_markdown()` and `test_rst()` read `format_url` where they read
   `address`.
   **Done 2026-10-25.** What the step found and decided:
   - The fields have defaults, so `@document` makes the keyword constructor
     `Url(; scheme, …)`; `Url(text)` is an outer constructor of one argument
     beside it. `find_web_url` reads the pieces too: a scheme and a host, or the
     scheme `mailto`.
   - `make_url_piece_operation` also puts a `/` before a path that does not start
     with one when the address has a host, because RFC 3986 needs it there: a
     port on `guide.md` gives `//:8080/guide.md`.
   - `find_url_file_path` reads the path only, so `file:///a?b` names `/a`, and
     the scheme in any case.
   - The test reads 2,000 random texts of the characters `:/?#@[]a1.%` and
     prints each back as the same text.
   - Pass: `test_link()` 2,092 of 2,092, the link tests of Markdown and rst, and
     `test_navigator()`.
2. [x] **The text line.** The link slice moves after the syntax slice
   (`ProjecturedPlatform.jl` and the row `link` of `PLATFORM_SLICE_EDGES`).
   `UrlToSyntax` and its reader. Test, in an editor with a `HeadlessBackend`:
   `/docs` typed after the host goes into the path; `?` starts a query; a
   Backspace over `//` joins the host to the path; a paste fills the pieces; the
   caret stays where the person typed; one undo step takes an edit back.
   `test_platform_slice_edges()` passes.
   **Done 2026-10-25.** What the step found and decided:
   - `UrlToSyntax` is a `@projection_template` with a `SyntaxConcatenation` thunk,
     so a leaf comes and goes with its piece. Only the reader of a typed edit is
     written by hand. The syntax stage gives it the edit as
     `.children[i].value{start:stop}`, leaf `i` of the line, and a delimiter is a
     leaf too, so the reader finds the place in the text from the lengths of the
     leaves before it (`_get_url_segments`, in the order of the template).
   - The answer is the writes of `make_url_text_operation` and a
     `ReplaceSelectionOperation` in one `CompoundOperation`. The writes carry the
     `Url`, so a reroot leaves them, and only the caret path gets the steps
     before the line.
   - The caret goes into the first piece whose text holds the place, its ends
     included: a letter typed at the end of the host stays in the host, and `/`
     goes into the path.
   - The host draws in `typed_text` of the syntax theme, and the other pieces and
     the delimiters in `label_text`: the theme has no strong style.
   - The undo test takes the inverse as the editor does, member by member while
     the writes run (`evaluate_invertible_operation!`).
   - Pass: `test_link()` 2,100 of 2,100, `test_platform_slice_edges()`.
3. [x] **The page.** `UrlView` shows the text line, the list of the pieces and
   the button. Test: an edit on the page changes the list, and the button opens
   the new address. A live SDL check: the page of a `Url` takes typed text, the
   pieces follow, and the button answers `OpenUrlOperation` with the new address.
   **Done 2026-10-25.** What the step found and decided:
   - The page holds a syntax theme and makes `UrlToSyntax` at print time, because
     only the algebra holds a projection. Its IO map, `UrlViewToWidgetIoMap`,
     holds the IO map of the line. The page puts the output of the line among its
     parts, as the navigator does with its path view, and two maps and the reader
     of a typed edit send a path in the line through the line.
   - The list shows "empty" for a piece with no text, beside "none" for an absent
     piece, so a person sees the difference that the model makes.
   - The label and the enabled state of the button follow the address.
   - An editor with no window makes no click of a press and a release, so the
     test sends a `MouseClick` and then real `KeyPress` events. The live check
     sent a real press and release.
   - The live SDL check opened the page of a `Url` from the explorer. A press at
     the end of the host put the caret at `.host{13}`, and SDL text events typed
     `/docs?lang=en`: the line, the list, the tree row and the address of the
     navigator showed `https://julialang.org/docs?lang=en`, and the button
     answered `OpenUrlOperation` with it.
   - Pass: `test_link()` 2,104 of 2,104, `test_widget_link()`,
     `test_navigator()`, `test_explorer()`, `test_platform_slice_edges()`, and
     the link tests of Markdown and rst.
4. [x] **The guides.** `link.md` describes the pieces, the read and the print,
   the edit and the text line. Move this plan to `plan/done/`.
   **Done 2026-10-25.** `link.md` describes the pieces with the table of
   addresses, the read, the print, the two edits, the page and the text line, the
   new design decisions and the limits. The index of the package guides names
   the pieces and the text line. No other guide named the field `address`.

## Not in this plan

- A list of the segments of a path, or of the pairs of a query.
- A check of validity, and a comparison of two addresses that are equal in
  meaning.
- A resolve of a relative address against a base address (RFC 3986, section
  5.2).
- A natural row and a clipboard text for a `Url`.

## Open items

None.
