"""
    EssentialsModule

The few names of the kernel and the platform that most users call: show a value
in a window, open an editor on a document, make a document from text and draw
it, and make a view with no window. `Projectured`, each integration and each
backend re-export them, so the package that a user names gives them. A program
that needs more names loads `ProjecturedPlatform`.
"""
module EssentialsModule

# Show a value in a window.
using ..DisplayModule: EditorDisplay, display_in_editor, close_display_editor!,
    refresh_display_editor!
# Open an editor on a document.
using ..EditorModule: Editor, build_editor, run_editor!
# Make a document from text, and draw it.
using ..NaturalModule: parse_natural_text, NaturalToGraphics
using ..StyleModule: FontFileMeasure
# Make a view with no window, and write it as an image.
using ..ProjectionModule: print_document
using ..BackendModule: write_image

export EditorDisplay, display_in_editor, close_display_editor!, refresh_display_editor!,
       Editor, build_editor, run_editor!,
       parse_natural_text, NaturalToGraphics, FontFileMeasure,
       print_document, write_image

end # module EssentialsModule
