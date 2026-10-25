# An item of a study holds elements, and a study deletes items

Status: obsolete, 2026-10-25. Implemented on the branch `research-elements` on
2026-10-22, and dropped when the local main was rebased onto the remote main. The
remote rewrote the study as a quiet outline (`67db30f43`): every item has
`elements`, the outline slice has `add_element!`, and the menu of a row deletes an
item and refuses one that other items hold. The owner kept the remote version. Not
on main from this plan: the verbs `delete_attachment!` and `delete_study_item!`,
and the × beside a card with the holders in its tooltip.

## 1. The request

The person types the statement of a question, but also wants to add content to
it: "like markdown, an image, a table etc. what about the other elements?" Then:
"I would rather make it generic not markdown necessarily, just some elements".
And: "can I delete from the study?"

Decided in the conversation of 2026-10-22:

- Every item of a study holds a list of elements. An element is a document of
  any domain. No domain is special.
- A delete of an item that other items hold is refused, and the refusal names
  the holders (option (a)). To withdraw a claim that other items rest on, the
  person records a decision that rejects it.

Open: the name of the field. This plan uses `attachments`.

## 2. The facts

- The card of an item puts a nested `Document` directly in its rows, with a
  `_ResearchSlot` from the field to its place
  ([ResearchToWidget.jl](../../source/domain/research/ResearchToWidget.jl), the loop
  over `_RESEARCH_CONTENT_FIELDS`). The renderer draws it through the view of its
  own domain, and an edit in it edits the document itself.
- `DocumentInsertion("")` is the placeholder "insert a new … here". The natural
  renderer draws it with `DocumentInsertionToSyntaxLeaf`. The person types the
  kind with completion from `get_insertion_aliases`, and Return replaces it with
  `make_insertion_document(T)`. The dashboard uses it for the content of a new
  card ([Dashboard.jl:81](../../source/platform/explorer/Dashboard.jl#L81)).
- `make_delete_research_item_operation(study, item)` exists. It refuses an item
  that other items hold with "H1 is held by X1, N1, E1, D2", and it takes the id
  out of `folded`.
- `WidgetButton` has the fields `enabled` and `tooltip`.
- `collect_study_blocks` writes a node of a text format as a file of the study
  folder, and every other node inside `study.pred`.

## 3. The design

### 3.1 Elements

- Every `ResearchItem` type gets the field `attachments::Any = CellVector{Any}()`.
  The study itself has `report` and gets no such field.
- The card draws each element as one more row after the content fields, with a
  "×" at its right. A "+ element" button at the end of the card appends a
  `DocumentInsertion("")`. Both act on the item itself (`root = item`), so the
  card still needs no study.
- A placeholder that the person does not fill stays a `DocumentInsertion`. It
  saves and loads as one, and "×" removes it.
- The save puts an element of a text format in its own file of the folder, by
  the rule that exists, under the name `q1-attachments-1.md`. Every other element
  stays inside `study.pred`. Done with no change of the code: `collect_study_blocks`
  walks every field of an item, so the name is the field name, `attachments`, and
  the number counts the blocks of the whole study.

### 3.2 Delete

- The button column of each row of the outline gets a "×" with the tooltip
  "Delete H1".
- The button is disabled while other items hold the item, and its tooltip then
  names the holders: "H1 is held by X1, E1, D2".
- Changed during the work: `enabled` is no cell computation. The holder walk reads
  every text cell of the study, so a computed `enabled` would compute again for
  each key that a person types, once for each item. The outline finds the holders
  in `run_without_cell_tracking` when it builds, and a change of a list of the
  study starts a build. A link changes with a list in every view and verb. The
  tooltip, a function, and the press find the holders again, so an item that a
  link made in another way holds is not deleted: the press answers `nothing`.
- The verb `delete_study_item!(study, id)` goes through the history, as every
  other verb of the domain. It throws the same refusal.

### 3.3 Verbs

- `add_attachment!(study, id, document)` appends an element to an item.
- `delete_attachment!(study, id, index)` removes one.
- `delete_study_item!(study, id)` removes an item.

Each one has a docstring on `function f end` with "Use it to", an example and
"See also", and is in `RESEARCH_ASSISTANT_API`.

## 4. The steps

Do the work in a worktree on a branch `research-elements`.

1. [x] The field and the edits. Add `attachments` to the nine item types, and
   `make_add_attachment_operation` and `make_delete_attachment_operation` in
   `ResearchEdits.jl`. Check that a `.pred` file without the field loads with an
   empty list, because the omnet corpora hold such files. Tests in
   `ResearchEditsTest.jl` and `ResearchDocumentTest.jl`.
   Done: the field is `attachments::CellVector = CellVector()`, before `status`
   (before `author` on a decision). No saved study is in either repository, so
   no old file needs the check. An item that an attachment holds has the item of
   the attachment as a holder, by the walk that exists.
2. [x] The card. Draw the elements with "×" and the "+ element" button, with the
   slots for `attachments[k]`. Tests in `ResearchToWidgetTest.jl`. Check in a
   live SDL window that the completion and Return turn the placeholder into a
   document.
   Done: each element stands in a row with its "×", inside a constraint, as a
   card stands in a row of the outline; "+ element" is the last row of the card.
   The check is the picture and the headless test of section 5.
3. [x] Delete in the outline. Add the "×" of a row, disabled with the holders in
   its tooltip. Tests in `ResearchToWidgetTest.jl`.
   Done: "×" is the last button of the column, after the add buttons. Steps 2 and
   3 are one commit, because their tests share one hunk of the test file.
4. [x] The three verbs. Tests in `ResearchAssistantApiTest.jl`. Run
   `test_referenced_document_editor()`, because a new docstring can move the
   rank of `search_api`.
   Done: `test_referenced_document_editor()` passes, 111 of 111. The docstring
   of `delete_study_item!` says to delete only when the person asks, as the one
   of `record_decision!` does. A text given to `add_attachment!` becomes a
   `PrimitiveString`.
5. [x] The save and the guide. A round trip of a study with elements in `.pred`
   and in the folder. Update [research.md](../../documentation/package/domain/research/research.md).
   Done: the round trip holds a Markdown paragraph, which gets the file
   `r1-attachments-1.md`, and a `PrimitiveString`, a `DocumentInsertion` and an
   item of the study, which stay in `study.pred`; the item loads as the same
   item. No code of the save changed, so `test_file_project()` did not run.
6. [x] omnet-julia. Run `test_study_verbs()` and `test_study_runs()`.
   Done: in a scratch environment with omnet-julia `main` and the packages of
   this worktree, 55 of 55 and 10 of 10, the counts of `main`. omnet-julia needs
   no change.

The tests at the end: `test_research()` 299 of 299 (232 before),
`test_research_combinations()` 19 of 19, `test_referenced_document_editor()` 111
of 111. The naming check passes; the documentation check finds the 3 faults that
`main` has.

The tests of the change: `test_research()`, `test_research_combinations()`, and
`test_file_project()` for step 5.

## 5. Facts found during the work

- The Markdown domain has no short name "markdown". The person types
  `markdown paragraph` or `markdown root`; "markdown" alone is ambiguous between
  the Markdown types, and Return then makes nothing.
- "+ element" does not put the caret into the new placeholder. The button is a
  sibling of the new element in the card, so a selection path that it makes can
  not reach the element as the operation passes up. The insert itself carries the
  item, so it needs no path. No view in the code puts the caret into a part that a
  button adds: the workflow cards and the dashboard leave it too.
- A click on the placeholder selects its prompt text, "Insert a new" or "here",
  except at the one place between them, which selects `value{0}`. Right and End
  stay in the prompt. So a person types the name after a click at that place.
- The live check of step 2 is a picture of the card and the outline from the SDL
  backend offscreen, and the headless test that clicks "+ element", clicks the
  name, types `markdown paragraph` and Return through the readers of the editor.
  A live window takes the keyboard focus from the person.
- Changed after the landing, by the decision of the owner (2026-10-22): "+ element"
  adds a `DocumentNothing`, not a `DocumentInsertion`. A click anywhere on it
  selects it. Insert turns it into a `DocumentInsertion` with the caret at
  `value{0}`, by the gesture that every `DocumentNothing` has, and a paste puts a
  copied document in its place. So the narrow place of the click is gone.

## 6. Not in this plan

- The paste of a document into the list of elements.
- The reuse of an id after a delete. `make_research_id` answers one more than
  the highest number of the kind, so a delete of H3, the highest, gives H3 again.
