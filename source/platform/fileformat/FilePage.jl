# Fragment of `FileFormatModule` — the page of a file in a tab: the file in its
# scroll pane, and a band above it while the file and its copy on disk disagree.
# The band is a document of the page, and each of its buttons answers an
# operation.

"""
    FilePage(content)
    FilePage(; content, band = nothing)

What a tab shows for a file: `content`, the file in its scroll pane, and `band`,
a [`FileBand`](@ref) that stands above the content, or `nothing`. The band stays
at the top of the tab while a long file scrolls. The watch of the file, in the
file-change slice, writes the band when the file changed on disk under edits
that are not saved, and when a save would write over a newer file.

A walk from the tab reaches the file through `content` (`get_edited_field`),
and the tab takes its title from the file. [`make_file_tab_content`](@ref) makes
the page of a file.

# Example

    page = FilePage(WidgetScrollPane(make_file_tab("notes.txt")))
"""
@document struct FilePage
    content::Any
    band::Any = nothing
end

get_edited_field(::FilePage) = :content
get_document_title(page::FilePage) = get_document_title(page.content)

"""
    find_page_file(page) -> FileDocument or nothing

The file document that `page` shows: the first file document on the walk from its
content through the fields that a person edits, or `nothing`.
"""
function find_page_file(page::FilePage)
    node = page.content
    for _ in 1:16
        is_file_document(node) && return node
        field = get_edited_field(node)
        field === nothing && return nothing
        node = getproperty(node, field)
    end
    nothing
end

"""
    FileBand(; message, choices = Pair{String,Any}[])

A band above a file: `message`, one sentence, and `choices`, each the label of a
button and the operation that a click on it answers. A [`FilePage`](@ref) holds
it, and `FilePageToWidget` draws it.

# Example

    FileBand(; message = "notes.txt changed on disk.",
               choices = ["Load it" => load, "Keep mine" => keep])
"""
@document struct FileBand
    message::String = ""
    choices::Any = Pair{String,Any}[]
end
