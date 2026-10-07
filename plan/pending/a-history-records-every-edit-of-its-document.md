# A history records every edit of its document

> **Status:** design to decide. Nothing of it is built. The owner chose on
> 2026-10-07 that this is a plan of its own (Q10 of the navigator plan).

## 1. The goal

One undo history for each document, which records every edit of the document
whatever view makes it: the tab of a file, the page of a navigator, a duplicate
tab, a second view of the same document. Ctrl+Z in any of these views takes back
the last edit of that document.

## 2. What exists (facts, 2026-10-07)

- An `UndoBuffer` is a document in the tree, a layer around the document whose
  steps it keeps (`get_edited_field(::UndoBuffer) = :content`).
- The buffer records nothing by itself. `UndoBufferToAnyProjection` records an
  operation when the operation passes through its reader: the answer of its
  content to a gesture, or an operation with a route (`_record_operation`).
- A file tab of the application is the file, then a history, then the content:
  the `wrap` of the open of a file goes around the content that the file holds
  (`make_file_tab`: `FileType(path, wrap(read_document_file(path)))`).
- A navigator prints its page directly through the recursion. So an edit on a
  page below the root of its content never passes through the reader of a
  history in the content, and no history records it. "Open as a page" in a new
  tab gives a navigator on the content of a file tab, and its page edits have no
  undo.
- A duplicate tab shares the content of its source; its edits pass through the
  history of the duplicate only when the duplicate has a history of its own.
- The navigator plan builds an interim (step 6, option (a) of Q10): the open of a
  linked file puts a history around a navigator around the file, so that one tab
  has undo on every page. The other cases above keep the gap.

## 3. The model (tentative, to discuss)

A history belongs to a document, not to a place in a view. When the editor
evaluates an edit, it gives the edit to the history of the document that holds
the edited part, and Ctrl+Z in a view takes back the last edit of the history of
the document that the view edits.

The questions that the model raises:

1. **Where a history lives.** A layer document in the tree, as now, which the
   editor finds above the edited part by the path of the edit; or a table beside
   the documents, keyed by the document, which every view of the document finds.
2. **How the editor finds it.** The path of an edit starts at the root of the
   editor; a page of a navigator is reached through the content of the navigator,
   so the path passes the layer of the history when the history is a layer above
   the content. The editor can walk the path of each edit and record it in the
   nearest history on the way, in place of the reader of the history.
3. **What is an edit.** The operations that a history records now, and not the
   view state (`ReplaceViewStateOperation`), the selection or the pointer.
4. **A selection after an undo.** A step keeps the selection of the view that
   made it; another view of the same document undoes it with its own selection.
5. **A duplicate tab and a second view.** One history for the document, or one
   for each tab.
6. **The window history.** The `undo` wrapper keeps a history of the window (a
   splitter, a tab that opens); it stays a history of its own document, the pane
   tree.

## 4. Steps

To write after the owner decides the questions of §3.
