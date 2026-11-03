# Fragment of `WidgetModule` — the match of a typed query against a text, by its
# letters in order, and the order of the texts that match.
#
# The letters of the query come in the same order in the text, and they need not
# touch; case does not matter. Of the places where they can stand, the match takes
# the best one: a letter at the start of a word counts most, a letter in the name
# part counts more than a letter before it, and a letter right after the one
# before counts more. So `panprog` matches `PaneProgram.jl` at its two words, and
# `pp` matches the two capitals of the name, not two letters of the folder.

const _LETTER_POINTS = 1
const _WORD_START_POINTS = 8
const _NAME_POINTS = 4
const _NEXT_LETTER_POINTS = 5

# A score that no match has.
const _NO_LETTER_SCORE = typemin(Int) ÷ 4

"""
    find_letter_match(query, text; name_start = 1) -> Int | Nothing

The score of the best match of the letters of `query` in `text`, in order and of
any case, or `nothing` when they do not all come in that order. A higher score is
a better match. `name_start` is the index of the character where the name part of
`text` starts, such as the character after the last `/` of a path: a letter from
there on counts more. A letter at the start of a word counts most; a word starts
at the start of the text, after `/`, `\\`, `_`, `-`, `.`, a space or `:`, and at
a capital letter after a small one. An empty query matches every text with the
score 0.
"""
function find_letter_match(query::AbstractString, text::AbstractString; name_start::Integer = 1)
    isempty(query) && return 0
    letters = Char[lowercase(c) for c in query]
    characters = collect(text)
    _has_letters_in_order(letters, characters) || return nothing
    count = length(characters)
    points = Int[_get_letter_points(characters, index, name_start) for index in 1:count]
    before = fill(_NO_LETTER_SCORE, count)
    now = fill(_NO_LETTER_SCORE, count)
    for (number, letter) in enumerate(letters)
        best = _NO_LETTER_SCORE        # the best score of the letter before, left of here
        for index in 1:count
            score = _NO_LETTER_SCORE
            if lowercase(characters[index]) == letter
                if number == 1
                    score = points[index]
                else
                    from = best
                    index > 1 && (from = max(from, before[index - 1] + _NEXT_LETTER_POINTS))
                    from > _NO_LETTER_SCORE && (score = from + points[index])
                end
            end
            number > 1 && (best = max(best, before[index]))
            now[index] = score
        end
        before, now = now, before
    end
    score = maximum(before)
    score > _NO_LETTER_SCORE ? score : nothing
end

# Whether the letters come in this order in the characters, of any case.
function _has_letters_in_order(letters::Vector{Char}, characters::Vector{Char})
    next = 1
    for character in characters
        lowercase(character) == letters[next] || continue
        next += 1
        next > length(letters) && return true
    end
    false
end

# What a letter of the query counts at the character `index`.
function _get_letter_points(characters::Vector{Char}, index::Integer, name_start::Integer)
    points = _LETTER_POINTS
    _is_word_start(characters, index) && (points += _WORD_START_POINTS)
    index >= name_start && (points += _NAME_POINTS)
    points
end

function _is_word_start(characters::Vector{Char}, index::Integer)
    index == 1 && return true
    before, character = characters[index - 1], characters[index]
    before in ('/', '\\', '_', '-', '.', ' ', ':') || (isuppercase(character) && islowercase(before))
end

"""
    find_letter_matches(query, texts; name_start = text -> 1) -> Vector{Int}

The indices of the texts of `texts` that `query` matches by
[`find_letter_match`](@ref), best first: a higher score first, then a shorter
text, then the order of `texts`. `name_start(text)` gives the index of the
character where the name part of a text starts.
"""
function find_letter_matches(query::AbstractString, texts::AbstractVector; name_start = text -> 1)
    isempty(query) && return collect(eachindex(texts))
    found = Tuple{Int,Int,Int}[]
    for index in eachindex(texts)
        text = texts[index]
        score = find_letter_match(query, text; name_start = name_start(text))
        score === nothing || push!(found, (-score, length(text), index))
    end
    sort!(found)
    Int[index for (_, _, index) in found]
end
