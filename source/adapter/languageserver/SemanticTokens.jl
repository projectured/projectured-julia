# Fragment of `LanguageServerModule` — the semantic tokens of a text: the text
# goes to the server as a version of its file, the server answers the kinds of
# the names in it, and the answer becomes the marks of a `MarkedText`.

"""
    SEMANTIC_TOKEN_ROLES

The role of the colour theme for each kind of semantic token of the protocol,
and of the kinds that `clangd` adds (`concept`, `bracket`, `label`). A kind that
is not here, such as `unknown`, gets no mark.
"""
const SEMANTIC_TOKEN_ROLES = Dict{String, Symbol}(
    "namespace" => :module_name, "type" => :type_name, "class" => :type_name,
    "enum" => :type_name, "interface" => :type_name, "struct" => :type_name,
    "concept" => :type_name, "typeParameter" => :type_parameter, "parameter" => :parameter,
    "variable" => :variable, "property" => :field, "enumMember" => :enum_member,
    "event" => :event, "function" => :function_name, "method" => :function_name,
    "macro" => :macro_name, "decorator" => :macro_name, "keyword" => :keyword,
    "modifier" => :keyword, "label" => :symbol_literal, "comment" => :comment,
    "string" => :string_literal, "regexp" => :string_literal, "number" => :number_literal,
    "operator" => :operator, "bracket" => :punctuation)

"""
    compute_semantic_text_marks(connection, path, language, text) -> Vector{TextMark}

The marks of `text`, the text of the file at `path` in `language` (`"c"`,
`"cpp"`, …), from the semantic tokens of the server of `connection`. The server
gets the text as the first version of the file (`didOpen`), or as its next
version (`didChange`), and then the question for its tokens. The marks count
the characters of `text`.

It waits for the server, so call it off the loop of the editor. It holds the
lock of an exchange, so two calls do not mix their messages, and the server
gets the versions of a file in the order of the calls. Throws a
`LanguageServerException` when the server does not start or does not answer.
"""
function compute_semantic_text_marks(connection::LanguageServerConnection, path::AbstractString,
                                     language::AbstractString, text::AbstractString)
    lock(connection.lock) do
        start_language_server!(connection)
        uri = make_file_uri(path)
        version = lock(() -> get(connection.documents, uri, 0) + 1, connection.state_lock)
        if version == 1
            send_language_server_notification!(connection, "textDocument/didOpen", Dict{String, Any}(
                "textDocument" => Dict{String, Any}("uri" => uri, "languageId" => language,
                                                    "version" => version, "text" => text)))
        else
            send_language_server_notification!(connection, "textDocument/didChange", Dict{String, Any}(
                "textDocument" => Dict{String, Any}("uri" => uri, "version" => version),
                "contentChanges" => [Dict{String, Any}("text" => text)]))
        end
        lock(() -> connection.documents[uri] = version, connection.state_lock)
        result = send_language_server_request!(connection, "textDocument/semanticTokens/full",
                                               Dict{String, Any}("textDocument" => Dict("uri" => uri)))
        data = result isa AbstractDict ? get(result, "data", Int[]) : Int[]
        token_types, encoding = lock(() -> (connection.token_types, connection.position_encoding),
                                     connection.state_lock)
        convert_semantic_tokens(data, text, token_types, encoding)
    end
end

"""
    close_language_server_document!(connection, path)

Tell the server of `connection` that the file at `path` is closed, so it drops
its text. Nothing happens when the server does not hold the file, or does not
run.
"""
function close_language_server_document!(connection::LanguageServerConnection, path::AbstractString)
    lock(connection.lock) do
        uri = make_file_uri(path)
        held = lock(() -> pop!(connection.documents, uri, nothing), connection.state_lock)
        (held === nothing || !is_language_server_running(connection)) && return nothing
        try
            send_language_server_notification!(connection, "textDocument/didClose",
                                               Dict{String, Any}("textDocument" => Dict("uri" => uri)))
        catch exception
            exception isa LanguageServerException || rethrow()
        end
        nothing
    end
end

"""
    convert_semantic_tokens(data, text, token_types, encoding) -> Vector{TextMark}

The marks of the semantic tokens `data` of `text`. `data` is the relative
encoding of the protocol: five numbers for each token, the line counted from the
line of the token before, the column (from the column of the token before on
the same line), the length, the index of its kind in `token_types`, and its
modifiers. `encoding` says how a column counts: `"utf-32"` counts characters,
and any other value counts the units of UTF-16. A mark counts the characters of
`text`, a break one, and takes the role of its kind (`SEMANTIC_TOKEN_ROLES`). A
token of a kind with no role, or past the end of the text, gets no mark.

# Example

    convert_semantic_tokens([0, 4, 4, 1, 0], "int main() {", ["variable", "function"], "utf-32")
    # [TextMark(4, 8, ColorRole(:function_name))]
"""
function convert_semantic_tokens(data::AbstractVector, text::AbstractString,
                                 token_types::AbstractVector{<:AbstractString}, encoding::AbstractString)
    lines = split(text, '\n')
    starts = Vector{Int}(undef, length(lines))
    offset = 0
    for k in eachindex(lines)
        starts[k] = offset
        offset += length(lines[k]) + 1
    end
    counts_characters = encoding == "utf-32"
    marks = TextMark[]
    line, column = 0, 0
    for k in 1:5:(length(data) - 4)
        delta_line, delta_column, token_length, kind = data[k], data[k + 1], data[k + 2], data[k + 3]
        line += delta_line
        column = delta_line == 0 ? column + delta_column : delta_column
        line + 1 > length(lines) && break
        index = kind + 1
        role = index <= length(token_types) ? get(SEMANTIC_TOKEN_ROLES, token_types[index], nothing) : nothing
        role === nothing && continue
        text_of_line = lines[line + 1]
        start, stop = counts_characters ? (column, column + token_length) :
            (_convert_utf16_column(text_of_line, column), _convert_utf16_column(text_of_line, column + token_length))
        push!(marks, TextMark(starts[line + 1] + start, starts[line + 1] + min(stop, length(text_of_line));
                              text = ColorRole(role)))
    end
    marks
end

# The count of the characters of `line` before the UTF-16 unit `units`, or the
# length of the line when `units` is past its end.
function _convert_utf16_column(line::AbstractString, units::Integer)
    characters = 0
    counted = 0
    for character in line
        counted >= units && break
        counted += codepoint(character) > 0xffff ? 2 : 1
        characters += 1
    end
    characters
end
