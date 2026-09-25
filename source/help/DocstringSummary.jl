# Fragment of `HelpModule` — the first paragraph of the docstring of a type.

"""
    compute_docstring_summary(T::Type) -> String

The first paragraph of the docstring of `T`, on one line, or `""` when `T` has
none.

The text is the Markdown the docstring was written in. A block that is indented
or fenced is code, such as the signature a docstring starts with, and a line that
starts with `#` is a heading. Neither is a paragraph, so both are skipped. The
inline marks stay as they are written. The docstring of the type comes before
the docstrings of its constructors.
"""
function compute_docstring_summary(@nospecialize(T::Type))
    for text in _find_docstring_texts(T)
        paragraph = _find_first_paragraph(text)
        isempty(paragraph) || return paragraph
    end
    ""
end

# The raw texts of the docstrings of `T`: the one of the type first, then the
# ones of its constructors in the order they were written. A docstring is kept in
# the table of the module that wrote it, so every module with docstrings is read.
function _find_docstring_texts(@nospecialize(T::Type))
    body = Base.unwrap_unionall(T)
    body isa DataType || return String[]
    binding = Base.Docs.Binding(body.name.module, body.name.name)
    texts = String[]
    for m in Base.Docs.modules
        multidoc = get(Base.Docs.meta(m), binding, nothing)
        multidoc === nothing && continue
        for signature in sort(multidoc.order; by = s -> s === Union{} ? 0 : 1)
            push!(texts, join(map(string, collect(multidoc.docs[signature].text))))
        end
    end
    texts
end

# The first paragraph of a Markdown text, its lines joined by one space. Code
# and headings before it are skipped; a blank line or a fence ends it.
function _find_first_paragraph(text::AbstractString)
    paragraph = String[]
    fenced = false
    for line in split(text, '\n')
        stripped = strip(line)
        if startswith(stripped, "```")
            isempty(paragraph) || break
            fenced = !fenced
            continue
        end
        fenced && continue
        if isempty(stripped)
            isempty(paragraph) || break
            continue
        end
        is_code_or_heading = startswith(line, "    ") || startswith(line, "\t") ||
                             startswith(stripped, "#")
        isempty(paragraph) && is_code_or_heading && continue
        push!(paragraph, String(stripped))
    end
    join(paragraph, " ")
end
