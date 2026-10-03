# Show a value in a window.
using ProjecturedPlatform: EditorDisplay, display_in_editor, close_display_editor!,
    refresh_display_editor!
# Open an editor on a document.
using ProjecturedKernel: Editor, build_editor, run_editor!
# Make a document from text, and draw it.
using ProjecturedPlatform: parse_natural_text, NaturalToGraphics, FontFileMeasure
# Make a view with no window, and write it as an image.
using ProjecturedKernel: print_document, write_image

export EditorDisplay, display_in_editor, close_display_editor!, refresh_display_editor!,
       Editor, build_editor, run_editor!,
       parse_natural_text, NaturalToGraphics, FontFileMeasure,
       print_document, write_image
