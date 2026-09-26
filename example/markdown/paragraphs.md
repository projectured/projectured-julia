# Only what changes is drawn again

This page is a Markdown file, open in ProjecturEd. Each paragraph is a block of its own, and each block has its own chain of projections: the words are broken into lines at the width of the pane, and the lines are laid out as graphics.

Type into this paragraph. The red box shows what the editor paints again after each key: this paragraph, and nothing else. The paragraphs below it keep their place, so the editor does not paint them again.

When a paragraph grows by one line, the paragraphs below it move down, and the red box reaches them too. When it shrinks, they move up again, and the box covers the rows they leave.

The editor finds this without a comparison of pixels. Every value on the screen is a reactive cell, and a key changes only the cells that depend on the text it edits. The backend then paints the graphics whose cells changed, and the graphics that moved.

Move the caret with the arrow keys. The red box covers the old place and the new place of the caret, and nothing else.
