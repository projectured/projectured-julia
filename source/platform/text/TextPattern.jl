# Fragment of `TextModule` — the pattern of a highlight or a filter, made from the
# fields that a person edits: the text of the pattern, whether it is a regular
# expression, and whether case matters.

# The characters that a regular expression gives a meaning of its own.
const _REGEX_SPECIAL_CHARACTERS = raw"\^$.|?*+()[]{}"

"""
    make_text_pattern(pattern::AbstractString, regex::Bool, case_insensitive::Bool)
        -> Regex or nothing

The `Regex` that a highlight or a filter matches. `regex` false takes `pattern` as
literal text, so `a.b` and `f(x)` match as written; `regex` true takes it as the
source of a regular expression. `case_insensitive` adds the flag `i`.

An empty pattern gives `nothing`, and so does a pattern that does not compile:
while a person types a regular expression, most prefixes do not compile, such as
an open `(` before its `)`. A text then shows no highlight and keeps every line,
and no error leaves the computation that reads the pattern.

# Example

    make_text_pattern("f(x)", false, false)     # matches the text f(x)
    make_text_pattern("^a.*z\$", true, true)    # a regular expression, any case
    make_text_pattern("(", true, false)         # nothing
"""
function make_text_pattern(pattern::AbstractString, regex::Bool, case_insensitive::Bool)
    isempty(pattern) && return nothing
    source = regex ? String(pattern) : _escape_regex(pattern)
    flags = case_insensitive ? "i" : ""
    try
        Regex(source, flags)
    catch exception
        exception isa ErrorException || rethrow()
        nothing
    end
end

# `text` with a backslash before each character that a regular expression gives
# a meaning of its own, so the expression matches the text as written.
_escape_regex(text::AbstractString) =
    join(character in _REGEX_SPECIAL_CHARACTERS ? "\\" * character : string(character)
         for character in text)
