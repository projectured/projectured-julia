"""
    EssentialsModule

The few names of the kernel and the platform that most users call: show a value
in a window, open an editor on a document, make a document from text and draw
it, and make a view with no window. `Projectured`, each integration and each
backend re-export them, so the package that a user names gives them. A program
that needs more names loads `ProjecturedPlatform`.
"""
module EssentialsModule

using ..BackendModule
using ..DisplayModule
using ..EditorModule
using ..NaturalModule
using ..ProjectionModule
using ..StyleModule

# Show a value in a window; open an editor on a document; make a document from
# text and draw it; make a view with no window, and an image of it.
export EditorDisplay, display_in_editor, close_display_editor!, refresh_display_editor!,
       Editor, build_editor, run_editor!,
       parse_natural_text, NaturalToGraphics, FontFileMeasure,
       print_document, write_image

end # module EssentialsModule
