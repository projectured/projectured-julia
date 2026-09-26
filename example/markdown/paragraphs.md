# Only what changes is drawn again

This page is a Markdown file, open in ProjecturEd. Each paragraph is a block of its own, with its own chain of projections: its words are broken into lines at the width of the pane, and the lines are laid out as graphics.

Type into this paragraph. The red box shows what the editor paints again after each key: this paragraph, and the status line at the bottom, which says where the caret is.

The paragraphs below it keep their place, so the editor does not paint them again. When the paragraph above grows by one line, they move down, and the red box reaches them too. When it shrinks, they move up again.

The editor finds this without a comparison of pixels. Every value on the screen is a reactive cell, and a key changes only the cells that depend on the text it edits. The backend paints the graphics whose cells changed, and the graphics that moved.

Move the caret with the arrow keys: the red box covers its old place and its new place, and the status line.
