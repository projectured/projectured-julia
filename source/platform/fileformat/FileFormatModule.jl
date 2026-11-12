"""
    FileFormatModule

The functions `import_document` and `export_document` read a document from a file
and write it to a file, and two editor operations call them.

What a natural notation *is* lives in the natural slice (`NaturalModule`): a
domain declares the rung it starts at, the format it is written in, the
extension that names that format back, and how to read the text in again.
This module is the file half alone: it picks a parser by the extension of a
path, and it writes what `print_natural_text` produced.

Unlike the binary format ([`SerializationModule`](@ref)), this is portable
and editable outside ProjecturEd, but lossy with respect to editor-only state:
selection and collapse are not represented, and a document carrying an *insertion
placeholder* has no valid natural-text form, so its export will not re-parse.
Round-trip on real data documents; not on editor scaffolding.
"""
module FileFormatModule

using ..AgentModule: run_on_editor_task!
using ..ArrangementModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EditorModule
using ..EventModule
using ..GestureBindingModule
using ..GestureModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionModule
using ..ProjectionAlgebraModule
using ..ReferenceModule
using ..RosterModule
using ..SelectionModule: get_selection
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..ToolModule
using ..TooltipModule
using ..TreeModule

# Imported to extend: this module adds a method to each of them.
import ..DocumentModule: get_document_title, get_edited_field, has_document_duplicate, is_field_walked
import ..DomainModule: get_document_decoration, accepts_pasted_document, make_document_view, acquire_document!,
                       release_document!
import ..SerializationModule: pred_arguments, make_pred_document, find_held_file
import ..TreeModule: get_tree_children_steps
using ..TextModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..OperationModule: evaluate_operation, make_inverse_operation
import ..RosterModule: get_item_facets, compute_item_facet
import ..ProjectionModule: print_document, read_intent, map_reference_forward,
                           map_reference_backward

export import_document, export_document,
       ImportDocumentOperation, ExportDocumentOperation
export write_document_file, read_document_file, make_document_for, make_document_seed,
       make_file_tab, make_file_tab_content
export export_document
export SaveFileOperation, record_saved_state!, has_unsaved_edits, ReloadFileOperation,
       save_file_to_disk!, reload_file_from_disk!,
       compute_file_text, compute_file_text_hash, compute_file_stamp, read_file_content_again,
       make_unread_file, ensure_file_text_cell!, demand_file_text, is_file_stale, ApplyFileTextOperation
export get_file_icon, make_file_note
export FileToContent
export FileView, make_file_view, FileViewToWidget, KeepFileEditsOperation, receive_file_change!
export OpenFileList, get_session_open_file_list, find_open_file_document, open_file_document!,
       collect_open_file_paths, find_shown_file_path, add_open_file!, remove_open_file!,
       OpenFileListToWidget


include("NaturalFormat.jl")
include("DocumentFile.jl")
include("FileView.jl")
include("FileViewToWidget.jl")
include("OpenFileList.jl")
include("OpenFileListToWidget.jl")
include("FileToContent.jl")

end # module
