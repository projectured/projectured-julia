# Fragment of `ToolModule` — what a search query says, read once before a search
# runs: keywords with their classes, a regular expression, or a description.

"""
    SearchTerm(written, forms)

One thing a search looks for. `written` holds the alternatives as the query wrote
them, and `forms` holds every spelling that counts as a match of one of them.

Only a written alternative can earn a name match; a form counts in prose. A
regular expression is one term, and its one alternative is the pattern.
"""
struct SearchTerm
    written::Vector{Union{String,Regex}}
    forms::Vector{Union{String,Regex}}
end

"""
    KeywordQuery(must, should, must_not)

A keyword query, read: the terms a hit must hold, the terms that rank it, and the
terms a hit must not hold. [`parse_keyword_query`](@ref) makes one from text.
"""
struct KeywordQuery
    must::Vector{SearchTerm}
    should::Vector{SearchTerm}
    must_not::Vector{SearchTerm}
end

# A sentence that says what the model wants to do. Its words rank a hit as
# keywords do, and its meaning ranks it when a meaning model is present.
struct _DescriptionQuery
    text::String
end

# The words a person says to join the words they mean. In a heading they score
# as loudly as the subject does — "change the layout" scored `the` five points
# against every heading holding it — and they name nothing, so an optional one
# is dropped. A required or a forbidden one is what the person asked for, and it
# stays.
const _STOP_WORDS = Set([
    "the", "a", "an", "and", "or", "of", "in", "on", "to", "for", "with", "from",
    "by", "as", "is", "are", "be", "it", "its", "this", "that", "these", "those",
    "at", "into", "how", "what", "when", "which", "do", "does", "can", "me",
    "my", "you", "your", "all", "any", "some", "one", "up", "out",
])

# The words of a text: lower case, split at every character that is not a
# letter, a digit or `_`, and two characters or longer.
_split_query_words(text::AbstractString) =
    String[word for word in split(lowercase(text), r"[^a-z0-9_]+") if length(word) >= 2]

# The words of a description, without the joining words. A text of nothing but
# joining words keeps them, because it still has to search for something.
function _query_terms(text::AbstractString)
    words = _split_query_words(text)
    kept = filter(word -> !(word in _STOP_WORDS), words)
    isempty(kept) ? words : kept
end

# Each word becomes the forms it could be written in, and a score counts the best
# of them once. A person asks to "plot the vectors" and the verb is called
# `plot_vector`; a person asks about "a result" and the column is `results`. The
# fold is one `s` either way, which is the whole of the difference that was
# costing a round.
function _term_forms(term::AbstractString)
    forms = String[String(term)]
    length(term) > 3 && endswith(term, "s") && push!(forms, String(term[1:end-1]))
    length(term) > 2 && !endswith(term, "s") && push!(forms, String(term) * "s")
    forms
end

_make_word_term(word::AbstractString) =
    SearchTerm(Union{String,Regex}[String(word)], Union{String,Regex}[_term_forms(word)...])

# A phrase matches as written, and with its spaces written as `_`, which is how
# a name spells the same words.
function _make_phrase_term(phrase::AbstractString)
    spellings = unique([String(phrase), replace(phrase, ' ' => '_')])
    SearchTerm(Union{String,Regex}[spellings...], Union{String,Regex}[spellings...])
end

# One term whose alternatives are the given terms.
function _join_terms(terms::Vector{SearchTerm})
    length(terms) == 1 && return only(terms)
    SearchTerm(unique(reduce(vcat, [term.written for term in terms])),
               unique(reduce(vcat, [term.forms for term in terms])))
end

# Split `text` at `separator` where it stands outside double quotes. A quote that
# is never closed runs to the end.
function _split_outside_quotes(is_separator::Function, text::AbstractString)
    pieces = String[]
    current = IOBuffer()
    quoted = false
    for character in text
        if character == '"'
            quoted = !quoted
            write(current, character)
        elseif !quoted && is_separator(character)
            piece = String(take!(current))
            isempty(piece) || push!(pieces, piece)
        else
            write(current, character)
        end
    end
    piece = String(take!(current))
    isempty(piece) || push!(pieces, piece)
    pieces
end

# The terms one alternative of a piece holds, each with whether it only joins
# other words. A phrase is one term, and it never only joins: the quotes say the
# person meant it. A plain alternative is one term per word.
function _read_alternative(alternative::AbstractString)
    if startswith(alternative, '"')
        phrase = join(split(lowercase(strip(alternative, '"'))), ' ')
        length(phrase) >= 2 || return Tuple{SearchTerm,Bool}[]
        return Tuple{SearchTerm,Bool}[(_make_phrase_term(phrase), false)]
    end
    Tuple{SearchTerm,Bool}[(_make_word_term(word), word in _STOP_WORDS)
                           for word in _split_query_words(alternative)]
end

# The terms of one piece go into a class: a plain piece of several words is one
# term per word, and a piece with alternatives is one term.
_add_piece_terms!(class::Vector{SearchTerm}, terms::Vector{SearchTerm}, alternative_count::Int) =
    alternative_count == 1 ? append!(class, terms) : push!(class, _join_terms(terms))

"""
    parse_keyword_query(text) -> KeywordQuery

Read a keyword query. The query is split at white space outside double quotes,
and each piece is read by its form:

| form          | the term                                          |
| ---           | ---                                               |
| `word`        | ranks a hit, and does not filter                  |
| `+word`       | must match, or the hit is dropped                 |
| `-word`       | must not match, or the hit is dropped             |
| `a\\|b`        | matches when one of its alternatives matches      |
| `"two words"` | matches the words together, in that order         |

A word matches without case, as a substring, with or without a final `s`. A
forbidden word matches only where a word starts, so `-row` drops `rows` and
`table_row` and keeps `arrow`. A phrase also matches with its spaces written as
`_`, so `"replace selection"` finds `replace_selection`.

A plain piece of several words, as `OperationModule.Replace`, is one term per
word. A piece with `|` is one term, and each of its words and phrases is an
alternative. A word shorter than two characters is dropped. An optional word
that only joins the others — `the`, `of`, `how` — is dropped, unless the query
holds nothing else.
"""
function parse_keyword_query(text::AbstractString)
    must = SearchTerm[]
    should = SearchTerm[]
    must_not = SearchTerm[]
    joining = SearchTerm[]
    for piece in _split_outside_quotes(isspace, text)
        class = startswith(piece, '+') ? must : startswith(piece, '-') ? must_not : should
        body = class === should ? piece : piece[nextind(piece, 1):end]
        alternatives = _split_outside_quotes(==('|'), body)
        read = reduce(vcat, [_read_alternative(one) for one in alternatives];
                      init = Tuple{SearchTerm,Bool}[])
        isempty(read) && continue
        terms = SearchTerm[term for (term, _) in read]
        if class === should
            kept = SearchTerm[term for (term, joins) in read if !joins]
            if isempty(kept)
                _add_piece_terms!(joining, terms, length(alternatives))
                continue
            end
            terms = kept
        end
        _add_piece_terms!(class, terms, length(alternatives))
    end
    isempty(must) && isempty(should) && append!(should, joining)
    KeywordQuery(must, should, must_not)
end

# Does `form` occur in `text` where a word starts? A word character is a letter or
# a digit; `_` separates the words of a name.
function _occurs_at_word_start(form::AbstractString, text::AbstractString)
    for range in findall(form, text; overlap = true)
        start = first(range)
        start == firstindex(text) && return true
        before = text[prevind(text, start)]
        (isletter(before) || isdigit(before)) || return true
    end
    false
end

_has_term(term::SearchTerm, text::AbstractString) =
    any(form -> occursin(form, text), term.forms)

_has_term_at_word_start(term::SearchTerm, text::AbstractString) =
    any(form -> _occurs_at_word_start(form, text), term.forms)

"""
    is_keyword_match(query, texts...) -> Bool

Whether a hit whose texts are `texts` passes the filter of `query`: one of the
texts holds every term the query requires, and none holds a term it forbids.
Each text is lower case already.

**A forbidden word matches only where a word starts.** Matching is by substring,
and a forbidden substring removes hits that nobody sees: `-test` would drop every
entry that says `invokelatest`. A required word matches anywhere, because an
extra hit there costs only rank.
"""
function is_keyword_match(query::KeywordQuery, texts::AbstractString...)
    for term in query.must
        any(text -> _has_term(term, text), texts) || return false
    end
    for term in query.must_not
        any(text -> _has_term_at_word_start(term, text), texts) && return false
    end
    true
end

# The terms a hit is scored on. A forbidden term scores nothing: it only filters.
_get_scored_terms(query::KeywordQuery) = vcat(query.must, query.should)
_get_scored_terms(pattern::Regex) =
    SearchTerm[SearchTerm(Union{String,Regex}[pattern], Union{String,Regex}[pattern])]
_get_scored_terms(query::_DescriptionQuery) =
    SearchTerm[_make_word_term(word) for word in _query_terms(query.text)]

# What a text is folded by before it is matched. Keywords match without case; a
# pattern matches the text as it is, and its own `i` flag ignores case.
_get_query_fold(::KeywordQuery) = lowercase
_get_query_fold(::_DescriptionQuery) = lowercase
_get_query_fold(::Regex) = identity

# Whether a hit with these folded texts passes the filter of the query. Only a
# keyword query filters.
_is_passing(query::KeywordQuery, texts::AbstractString...) = is_keyword_match(query, texts...)
_is_passing(query, texts::AbstractString...) = true

# The reason a read query can not search, or `nothing`.
function _find_query_refusal(query::KeywordQuery)
    isempty(query.must) && isempty(query.should) || return nothing
    isempty(query.must_not) && return "Provide a search query (two or more characters)."
    "Provide a word to look for. A `-word` only removes hits."
end
_find_query_refusal(::Regex) = nothing
_find_query_refusal(query::_DescriptionQuery) =
    isempty(_split_query_words(query.text)) ?
        "Provide a search query (two or more characters)." : nothing

# The mode a search was asked for, as a tool argument spells it. A missing mode is
# the default.
_get_search_mode_name(mode) =
    mode === nothing || isempty(strip(string(mode))) ? "keywords" : lowercase(strip(string(mode)))

# What a query says, read the way `mode` asks. The answer is a `KeywordQuery`, a
# `Regex`, a `_DescriptionQuery`, or a `String` that says why the query can not be
# read — a search answers that text instead of throwing, so a model reads it and
# corrects its call. A `Regex` is a pattern whatever the mode, because its type
# already says so.
_read_search_query(query::Regex, mode) = query

function _read_search_query(query::AbstractString, mode)
    name = _get_search_mode_name(mode)
    name == "keywords" && return parse_keyword_query(query)
    name == "description" && return _DescriptionQuery(String(query))
    if name == "regex"
        return try
            Regex(String(query))
        catch err
            "Invalid regex: " * sprint(showerror, err)
        end
    end
    "Unknown search mode " * repr(name) *
        ". The modes are \"keywords\", \"regex\" and \"description\"."
end
