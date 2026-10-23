# Fragment of `OutlineModule` — the rows of an outline that show their date.

"""
    compute_shown_dates(days) -> Vector{Bool}

For each row of an outline, in the order of the rows, whether it shows its date:
the first row that has a day, and each row whose day differs from the day of the
last row above it that has one. `days` holds the day of each row, as any value
that compares with `==`, such as the text `"2026-10-23"`, or `nothing` for a row
with no time, which shows no date and leaves the day of the rows above it.
"""
function compute_shown_dates(days::AbstractVector)
    shown = falses(length(days))
    last_day = nothing
    for (index, day) in enumerate(days)
        day === nothing && continue
        shown[index] = last_day === nothing || day != last_day
        last_day = day
    end
    collect(shown)
end
