# Fragment of `ToolModule` — the docstring of a type or a module: its first
# paragraph, which a list of types and a card of a tab show as its description,
# and its whole text, which the page of a type in the help shows.

"""
    compute_docstring_summary(T::Type) -> String
    compute_docstring_summary(m::Module) -> String

The first paragraph of the docstring of `T` or `m`, on one line, or `""` when
there is none.

The text is the Markdown the docstring was written in. A block that is indented
or fenced is code, such as the signature a docstring starts with, and a line that
starts with `#` is a heading. Neither is a paragraph, so both are skipped. The
inline marks stay as they are written. The docstring of a type comes before
the docstrings of its constructors.
"""
function compute_docstring_summary(@nospecialize(subject::Union{Type, Module}))
    for text in _find_docstring_texts(subject)
        paragraph = _find_first_paragraph(text)
        isempty(paragraph) || return paragraph
    end
    ""
end

"""
    find_docstring_text(T::Type) -> String or nothing
    find_docstring_text(m::Module) -> String or nothing

The whole docstring of `T` or `m`, as the Markdown it was written in, or
`nothing` when there is none. The docstring of a type comes before the
docstrings of its constructors, so a constructor speaks for a type that has no
docstring of its own.
"""
function find_docstring_text(@nospecialize(subject::Union{Type, Module}))
    for text in _find_docstring_texts(subject)
        isempty(strip(text)) && continue
        # The line breaks around the text go, and the indent of a signature stays.
        return String(rstrip(lstrip(==('\n'), text)))
    end
    nothing
end

# The raw texts of the docstrings of a type: the one of the type first, then the
# ones of its constructors in the order they were written. A docstring is kept in
# the table of the module that wrote it, so every module with docstrings is read.
function _find_docstring_texts(@nospecialize(T::Type))
    body = Base.unwrap_unionall(T)
    body isa DataType || return String[]
    _find_docstring_texts(Base.Docs.Binding(body.name.module, body.name.name))
end

# The raw text of the docstring of a module: a package module documents itself,
# and a submodule is documented in the module that holds it.
_find_docstring_texts(m::Module) = _find_docstring_texts(Base.Docs.Binding(parentmodule(m), nameof(m)))

function _find_docstring_texts(binding::Base.Docs.Binding)
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

"""
    strip_code_marks(text) -> String

`text` with no Markdown code mark, the backtick, so a view that shows a docstring
to a person shows `<:` as `<:` and `name` as `name`.
"""
strip_code_marks(text::AbstractString) = replace(String(text), '`' => "")
