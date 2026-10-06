# Only what changes is drawn again

This page is a Markdown file, open in ProjecturEd. The red boxes show what the editor paints again in a frame. The pixels outside them stay as they were.

Every value on the screen is a reactive cell: a text, a color, a place. A key, a click or a move of the pointer writes a few cells, and only the cells that read them are computed again.

When the pointer moves onto a button, the editor writes one cell of that button, which says that the pointer is on it. The button that the pointer left changes one cell too. Only these two buttons are painted again.

Before each frame, the backend compares the tree of graphics with the last paint. It finds a graphic that draws something else, one that moved, and one that came into the view or left it.

Each change adds two rectangles to a set: where the graphic was, and where it is now. The set drops a rectangle only when another one covers it fully. The backend paints each rectangle under its own clip, into a picture of the window that it keeps, and it copies only these rectangles to the screen.

A container does not read the size of its children. When a folder in the Files pane opens, the rows below it move down, so they are painted again, and the rows above it are not. When the Files pane scrolls, every row moves, so all of the Files pane is painted again, but this page is not.

The caret is a graphic too. When it moves by a line or by a word, the red box covers its old place and its new place, and nothing else.

Each paragraph has its own chain of projections, which breaks its words into lines at the width of the pane. A key paints only its own paragraph again.

When the paragraph above grows by one line, this paragraph moves down, and it is painted again. When the paragraph above shrinks, this one moves up again.
