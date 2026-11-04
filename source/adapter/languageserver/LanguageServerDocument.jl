# Fragment of `LanguageServerModule` — `SourceFile`, a file of a language that a
# language server serves: its text is a `MarkedText`, whose marks the server
# gives through a background cell, and its view is the text with its lines
# numbered, as the view of a Julia file is.

"""
    SOURCE_FILE_LANGUAGES

The language and the command of the language server of each extension of a
source file. The adapter registers each extension as a `SourceFile`.

`clangd` runs with no index in the background, so it writes no index into the
folder of a project. It reads an included header from the open documents first
(`--use-dirty-headers`), so a header that is open shows its text of now.
"""
const SOURCE_FILE_LANGUAGES = let clangd = ["clangd", "--log=error", "--background-index=false",
                                                  "--use-dirty-headers"]
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
    LanguageServerText

A text that a language server colours: the path that the server gets (also the
source of the language, `find_source_file_language`), the `text` of now, and the
answer of the server. A file holds one, and a file that shows more than one
text holds one for each.

`server` holds `nothing` until the owner sets the `LanguageServerConnection` for
the command of the language. `answer` holds the last answer of the server: the
text that it coloured and its marks. `request` is a background cell of the
server, the path and the text of now: a read of it notes a missing answer, and
the editor asks the server after the print and stores the answer in `answer`.
`text` is a cell whose computation `make_language_server_text` sets, so it
follows what it comes from.
"""
@document struct LanguageServerText
    path::String
    text::String
    server::Any = nothing
    answer::Any = nothing
    request::Any = nothing
end

"""
    make_language_server_text(path, text::Function) -> LanguageServerText

A `LanguageServerText` of the file at `path` whose text is `text()`, read inside
a cell, so the text follows what it comes from. The background cell asks the
server for the text of now; one source for each text, so the work of one text
asks only its own server.
"""
function make_language_server_text(path::AbstractString, text::Function)
    path_cell = Cell(String(path))
    text_cell = Cell("")
    set_cell_computation!(text_cell, text)
    server = Cell(nothing)
    answer = Cell(nothing)
    source = BackgroundSource(inputs -> Any[_compute_source_file_answer(input...) for input in inputs];
                              description = "the colours of a source file")
    holder = Ref{Any}(nothing)
    request = make_background_cell(source, () -> (server[], path_cell[], text_cell[]);
                                   apply = (inputs, value) -> StoreLanguageServerAnswerOperation(holder[], value))
    result = LanguageServerText(path_cell, text_cell, server, answer, request)
    holder[] = result
    result
end

"""
    compute_language_server_marks(text::LanguageServerText) -> Vector{TextMark}

The marks of `text`: the stored answer of the server, moved to the text of now
(`compute_moved_text_marks`), so a key moves no colour of the text around it,
and the answer of the new text comes in a later frame. With no server, or a
server that fails, the text has no marks.

It reads the server and the path with tracking, so a new server or a new path
reads the request again. The read of the request notes a missing answer for the
text of now, and the stored answer makes the marks change. The marks read
`answer`, which is final, so they are final while an answer is still to come: a
provisional value that asks again computes again at each read, and the lines of
a text read the marks once for each line.

So a print reads the request with no tracking, through a cell of its own that
reads it as a computation does: a request that computed where it could not ask
computes again and asks, and the marks do not depend on it. A walk of the
documents that starts no background work (`is_background_work_allowed`) reads
the request with tracking: there it can not ask, so the marks take its
provisional state, and the next print computes them again.
"""
function compute_language_server_marks(text::LanguageServerText)
    text.server
    text.path
    request = getfield(text, :request)
    if is_background_work_allowed()
        run_without_cell_tracking(() -> Cell(@computation request[])[])
    else
        request[]
    end
    _compute_source_file_marks(text.answer, text.text)
end

"""
    StoreLanguageServerAnswerOperation(text, answer)

Store `answer`, the answer of the server that the work of the background cell
of `text` gave, in the field `answer` of the `LanguageServerText` `text`. The
editor evaluates it right after it writes the answer into the background cell.
A work that threw gives its exception, and the text then stores no answer.
"""
struct StoreLanguageServerAnswerOperation <: Operation
    text::Any
    answer::Any
end

function evaluate_operation(editor, operation::StoreLanguageServerAnswerOperation)
    answer = operation.answer
    operation.text.answer = answer isa Exception ? nothing : answer
    nothing
end

"""
    SourceFile(filename, content)

A file of a language that a language server serves, such as a C or C++ file.
`content` is a `MarkedText` that holds the text of the file, or a history of it;
the server gives its marks, the names in the colours of their kinds.

`server_text` is the `LanguageServerText` of the text of the file, whose
`server` holds `nothing` until a tab acquires the file, and then the
`LanguageServerConnection` of that editor for the command of the file. Its marks
are the marks of the text (`compute_language_server_marks`). A content that holds
no marked text has no `server_text`.

# Example

    file = SourceFile("/home/me/hello.c", MarkedText(text = "int main() {}"))
"""
@document struct SourceFile <: FileDocument
    filename::String
    content::Any
    server_text::Any = nothing
end

function SourceFile(filename::AbstractString, content::Document)
    marked = _find_marked_text(content)
    marked === nothing && return SourceFile(Cell(String(filename)), Cell(content), Cell(nothing))
    server_text = make_language_server_text(filename, () -> marked.text)
    set_cell_computation!(getfield(marked, :marks), () -> compute_language_server_marks(server_text))
    SourceFile(Cell(String(filename)), Cell(content), Cell(server_text))
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
    language === nothing || file.server_text === nothing ||
        (file.server_text.server = get_language_server!(editor, language.command))
    nothing
end

# The close of the tab: the server forgets the file, on a task, and the file keeps
# its marks.
function release_document!(editor, file::SourceFile)
    invoke(release_document!, Tuple{Any, FileDocument}, editor, file)
    server_text = file.server_text
    server_text === nothing && return nothing
    server = server_text.server
    server_text.server = nothing
    server isa LanguageServerConnection &&
        errormonitor(Threads.@spawn :default close_language_server_document!(server, server_text.path))
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
