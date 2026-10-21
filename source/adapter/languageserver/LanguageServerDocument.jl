# Fragment of `LanguageServerModule` — `SourceFile`, a file of a language that a
# language server serves: its text is a `MarkedText`, whose marks the server
# gives through a background cell, and its view is the text with its lines
# numbered, as the view of a Julia file is.

"""
    SOURCE_FILE_LANGUAGES

The language and the command of the language server of each extension of a
source file. The adapter registers each extension as a `SourceFile`.

`clangd` runs with no index in the background, so it writes no index into the
folder of a project.
"""
const SOURCE_FILE_LANGUAGES = let clangd = ["clangd", "--log=error", "--background-index=false"]
    Dict{String, @NamedTuple{language::String, command::Vector{String}}}(
        ".c" => (language = "c", command = clangd),
        ".h" => (language = "cpp", command = clangd),
        ".cc" => (language = "cpp", command = clangd),
        ".cpp" => (language = "cpp", command = clangd),
        ".cxx" => (language = "cpp", command = clangd),
        ".hh" => (language = "cpp", command = clangd),
        ".hpp" => (language = "cpp", command = clangd),
        ".hxx" => (language = "cpp", command = clangd))
end

"""
    find_source_file_language(path) -> NamedTuple or nothing

The language and the command of the server of the file at `path`, by its
extension (`SOURCE_FILE_LANGUAGES`), or `nothing` for an extension that no
server serves.
"""
find_source_file_language(path::AbstractString) =
    get(SOURCE_FILE_LANGUAGES, lowercase(splitext(path)[2]), nothing)

"""
    SourceFile(filename, content)

A file of a language that a language server serves, such as a C or C++ file.
`content` is a `MarkedText` that holds the text of the file, or a history of it;
the server gives its marks, the names in the colours of their kinds.

`server` holds `nothing` until a tab acquires the file, and then the
`LanguageServerConnection` of that editor for the command of the file. `answer`
is a background cell of the last answer of the server: the text that it
coloured and its marks. The marks of the text are that answer, moved to the
text of now (`compute_moved_text_marks`), so a key moves no colour of the text
around it, and the answer of the new text comes in a later frame. With no
server, or a server that fails, the text has no marks.

# Example

    file = SourceFile("/home/me/hello.c", MarkedText(text = "int main() {}"))
"""
@document struct SourceFile <: FileDocument
    filename::String
    content::Any
    server::Any = nothing
    answer::Any = nothing
end

function SourceFile(filename::AbstractString, content::Document)
    path = Cell(String(filename))
    server = Cell(nothing)
    marked = _find_marked_text(content)
    marked === nothing && return SourceFile(path, Cell(content), server, Cell(nothing))
    # One source for each file, so the work of one file asks only its own server.
    source = BackgroundSource(inputs -> Any[_compute_source_file_answer(input...) for input in inputs];
                              description = "the colours of a source file")
    answer = make_background_cell(source, () -> (server[], path[], marked.text))
    set_cell_computation!(getfield(marked, :marks), () -> _compute_source_file_marks(answer[], marked.text))
    SourceFile(path, Cell(content), server, answer)
end

# The marked text of the content of a file: the content, or what its history holds.
_find_marked_text(content::MarkedText) = content
_find_marked_text(content::UndoBuffer) = _find_marked_text(content.content)
_find_marked_text(content) = nothing

# The work of the background cell, off the loop: the answer of the server for one
# text, or `nothing` with no server, or when the server fails.
function _compute_source_file_answer(server, path::AbstractString, text::AbstractString)
    server isa LanguageServerConnection || return nothing
    language = find_source_file_language(path)
    language === nothing && return nothing
    try
        (text = String(text), marks = compute_semantic_text_marks(server, path, language.language, text))
    catch exception
        exception isa LanguageServerException || rethrow()
        nothing
    end
end

_compute_source_file_marks(answer::Nothing, text::AbstractString) = TextMark[]
_compute_source_file_marks(answer, text::AbstractString) =
    compute_moved_text_marks(answer.marks, answer.text, text)

parse_file_content(::Type{<:SourceFile}, text::AbstractString) = MarkedText(text = String(text))
emit_text(file::SourceFile) = _find_marked_text(get_file_content(file)).text
# A source file holds no document of a domain, so nothing in it is a reference.
get_file_domain(::Type{<:SourceFile}) = Union{}

# The open of a tab acquires the file: it watches the file on disk, as every file
# does, and takes the server of the editor for the command of the file. It starts
# no process; the first work of the background cell does.
function acquire_document!(editor, file::SourceFile)
    invoke(acquire_document!, Tuple{Any, FileDocument}, editor, file)
    language = find_source_file_language(file.filename)
    language === nothing || (file.server = get_language_server!(editor, language.command))
    nothing
end

# The close of the tab: the server forgets the file, on a task, and the file keeps
# its marks.
function release_document!(editor, file::SourceFile)
    invoke(release_document!, Tuple{Any, FileDocument}, editor, file)
    server = file.server
    file.server = nothing
    server isa LanguageServerConnection &&
        errormonitor(Threads.@spawn :default close_language_server_document!(server, file.filename))
    nothing
end

# ── The view ────────────────────────────────────────────────────────────────

make_graphics_projection(::Type{SourceFile}; measure, appearance) =
    FileToContent(; content = make_source_file_code_projection(; measure, appearance),
                  accepts = content -> _find_marked_text(content) !== nothing)

"""
    make_source_file_code_projection(; measure, appearance) -> Projection

The view of the text of a source file: `MarkedTextToText`, `TextLineNumbering`
and `TextBlockToScrollLayout`, whose `ScrollLayout` the scroll pane of a file
tab takes apart. Its recursion prints the marks of the gutter, and the text that
a history holds.
"""
function make_source_file_code_projection(; measure, appearance)
    text_theme = get_scaled_theme!(appearance, TextTheme)
    line_spacing = make_style_field(TextTheme, text_theme, LineSpacing; name = :code_line_spacing)
    code = ChainingProjection(
        MarkedTextToText(; theme = text_theme, appearance),
        TextLineNumbering(; theme = text_theme),
        TextBlockToScrollLayout(; measure, theme = text_theme, line_spacing))
    RecursiveProjection(TypeDispatchingProjection(
        # A history prints what it holds, the text, through this recursion.
        UndoBuffer => UndoBufferToAnyProjection(),
        MarkedText => code,
        TextGutter => TextGutterToGraphics(),
        TextBlock => TextToGraphics(; measure, theme = text_theme),
        GraphicsCanvas => GraphicsToGraphics()))
end
