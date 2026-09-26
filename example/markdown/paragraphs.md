# Only what changes is drawn again

This page is a Markdown file, open in ProjecturEd. The red boxes show what the editor paints again in a frame. The pixels outside them stay as they were.

Every value on the screen is a reactive cell: a text, a color, a place. A key, a click or a move of the pointer writes a few cells, and only the cells that read them are computed again.

When the pointer moves onto a button, the editor writes one cell of that button, which says that the pointer is on it. The button that the pointer left changes one cell too. Only these two buttons are painted again.

Before each frame, the backend walks the tree of graphics. It keeps the place of each graphic from the last paint, and it finds three kinds of change: a graphic whose cells changed, a graphic that moved, and a graphic that came into the view or left it.

Each change adds two rectangles to a set: where the graphic was, and where it is now. The set drops a rectangle only when another one covers it fully. The backend paints each rectangle under its own clip, into a picture of the window that it keeps, and it copies only these rectangles to the screen.

A container does not read the size of its children, so a change in one part of the window does not paint the other parts again. When a folder in the navigator opens, the navigator is painted again, and this page is not.

The caret is a graphic too. When it moves by a line or by a word, the red box covers its old place and its new place, and nothing else.

Each paragraph has its own chain of projections, which breaks its words into lines at the width of the pane. A key paints only its own paragraph again.

When the paragraph above grows by one line, this paragraph moves down, and it is painted again. When the paragraph above shrinks, this one moves up again.
