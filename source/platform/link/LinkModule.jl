"""
    LinkModule

A link as data: a value that refers to a target and has a face. Each domain has
link types of its own, such as a link of Markdown, and this slice gives the general
`Link`, which any document can hold. A link type answers `is_link`,
`get_link_target` and `get_link_content`. A view gives a link its face with
`format_link_label`, `describe_link` and `is_link_broken`, which take their
defaults from the target, and draws it as a `WidgetLink`: a face and a target. A
link holds its target directly, as an edge of the graph of the documents, and a
walk of the documents does not go through a `Link` into its target.

A `Url` is an address and a link to itself: a relative address opens through the
page of its link, and an absolute one outside the editor, through
`OpenUrlOperation`, which the editor evaluates with `open_url!` of its backend.

`LinkInterface.jl` holds the functions of a link and their defaults,
`LinkDocument.jl` the general `Link`, the `Url` and its page `UrlView`,
`OpenUrlOperation.jl` the open of an address outside the editor,
`UrlInterface.jl` what an address names, `LinkToWidget.jl` the view that draws a
link as a `WidgetLink`, and `UrlViewToWidget.jl` the page of an address.
"""
module LinkModule

using ..CellModule
using ..DocumentModule
using ..DomainModule
using ..GestureBindingModule
using ..GestureModule
using ..IoMapModule
using ..LayoutModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule
using ..TreeModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_edited_field, is_field_walked
import ..DomainModule: get_document_decoration, make_document_view
import ..OperationModule: describe_operation, is_self_contained_operation
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward
import ..TreeModule: format_tree_node_label
import ..WidgetModule: make_graphics_projection, make_target_open_operation

export is_link, get_link_target, get_link_content, format_link_label, describe_link, is_link_broken
export Link, LinkToWidget
export Url, UrlView, UrlViewToWidget, is_absolute_url, find_url_file_path, find_web_url, OpenUrlOperation, open_url!

include("LinkInterface.jl")
include("LinkDocument.jl")
include("OpenUrlOperation.jl")
include("UrlInterface.jl")
include("LinkToWidget.jl")
include("UrlViewToWidget.jl")

end # module
