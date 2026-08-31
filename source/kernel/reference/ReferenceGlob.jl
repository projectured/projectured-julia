# Fragment of `ReferenceModule` — the **glob language**: `*`, `?`, `{a-e}`, `{^a-e}`,
# `{38..47}` and backslash escapes, over a single name.
#
# It is a fragment of this module because that is where its only callers are, not because
# it knows anything about references: nothing below mentions a step, a path or a pattern.
# `PatValueGlob` — the pattern node that carries one of these — stays with the rest of the
# pattern AST in `ReferenceCase.jl`, so the AST is readable in one place and the language
# it defers to is readable in another.
#
# One implementation serves the compiled and interpreted readings alike, the same
# arrangement `_type_step_matches` has and for the same reason: two of anything here is
# two things to keep in step.
#
# Nothing says "a glob never crosses a step", because nothing has to — a value pattern is
# only ever handed one name.

"""
    glob_matches(pattern, name) -> Bool

True when `name` matches the glob `pattern` in full. `*` and `{n..m}` backtrack, so a
pattern carrying several of them still answers exactly.
"""
glob_matches(pattern::AbstractString, name::AbstractString) =
    _glob_match(pattern, firstindex(pattern), name, firstindex(name))

function _glob_match(pat::AbstractString, pi::Int, s::AbstractString, si::Int)
    while true
        pi > lastindex(pat) && return si > lastindex(s)
        c = pat[pi]

        if c == '*'
            # Try every split. Which one wins is invisible: a glob answers yes or no and
            # binds nothing, so there is no greediness to choose here.
            npi = nextind(pat, pi)
            k = si
            while true
                _glob_match(pat, npi, s, k) && return true
                k > lastindex(s) && return false
                k = nextind(s, k)
            end

        elseif c == '?'
            si > lastindex(s) && return false
            pi = nextind(pat, pi)
            si = nextind(s, si)

        elseif c == '\\'
            npi = nextind(pat, pi)
            npi > lastindex(pat) && error("glob pattern ends in a backslash: $pat")
            (si > lastindex(s) || pat[npi] != s[si]) && return false
            pi = nextind(pat, npi)
            si = nextind(s, si)

        elseif c == '{'
            close = findnext(isequal('}'), pat, pi)
            close === nothing && error("unterminated `{` in glob pattern: $pat")
            body = pat[nextind(pat, pi):prevind(pat, close)]
            npi = nextind(pat, close)
            occursin("..", body) && return _glob_match_number(body, pat, npi, s, si)
            si > lastindex(s) && return false
            negated = startswith(body, '^')
            negated && (body = body[nextind(body, firstindex(body)):end])
            (_glob_in_set(body, s[si]) == negated) && return false
            pi = npi
            si = nextind(s, si)

        else
            (si > lastindex(s) || c != s[si]) && return false
            pi = nextind(pat, pi)
            si = nextind(s, si)
        end
    end
end

# `{38..47}` matches a run of digits whose *value* is in the range, so `{8..12}` matches
# "10" and not "1". The range does not imply the run's length, so every length is tried,
# longest first.
function _glob_match_number(body::AbstractString, pat::AbstractString, npi::Int,
                            s::AbstractString, si::Int)
    bounds = split(body, ".."; limit = 2)
    lo = tryparse(Int, bounds[1])
    hi = tryparse(Int, bounds[2])
    (lo === nothing || hi === nothing) &&
        error("`{$body}` in a glob pattern must be a numeric range like {38..47}")
    stop = si
    while stop <= lastindex(s) && isdigit(s[stop])
        stop = nextind(s, stop)
    end
    while stop > si
        value = tryparse(Int, s[si:prevind(s, stop)])
        value !== nothing && lo <= value <= hi && _glob_match(pat, npi, s, stop) && return true
        stop = prevind(s, stop)
    end
    false
end

function _glob_in_set(body::AbstractString, ch::AbstractChar)
    i = firstindex(body)
    while i <= lastindex(body)
        j = nextind(body, i)
        if j <= lastindex(body) && body[j] == '-' && nextind(body, j) <= lastindex(body)
            k = nextind(body, j)
            body[i] <= ch <= body[k] && return true
            i = nextind(body, k)
        else
            body[i] == ch && return true
            i = j
        end
    end
    false
end
