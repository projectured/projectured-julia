# Fragment of `ChartModule` — the ticks and the labels of an x axis that shows time.

# The steps of the ticks, each as `(unit, count, approximate length in milliseconds)`,
# from the finest to the coarsest. The length only bounds how many ticks a step makes.
const _TIME_STEPS = let second = 1000.0, minute = 60000.0, hour = 3.6e6, day = 8.64e7
    [(:second, 1, second), (:second, 2, 2second), (:second, 5, 5second), (:second, 10, 10second),
     (:second, 15, 15second), (:second, 30, 30second),
     (:minute, 1, minute), (:minute, 2, 2minute), (:minute, 5, 5minute), (:minute, 10, 10minute),
     (:minute, 15, 15minute), (:minute, 30, 30minute),
     (:hour, 1, hour), (:hour, 3, 3hour), (:hour, 6, 6hour), (:hour, 12, 12hour),
     (:day, 1, day), (:day, 2, 2day), (:week, 1, 7day),
     (:month, 1, 30day), (:month, 3, 91day), (:month, 6, 182day),
     (:year, 1, 365day), (:year, 2, 730day), (:year, 5, 5 * 365day), (:year, 10, 3650day)]
end

# The step after the last of `_TIME_STEPS`: a multiple of 10 years.
_get_long_year_step(k::Int) = (:year, 10k, 10k * 365 * 8.64e7)

# The `DateTime` that holds `milliseconds` of the plot coordinate, inside the years
# that a `DateTime` of the calendar covers sensibly.
get_plot_time(milliseconds::Real) =
    Dates.DateTime(Dates.UTM(Int64(round(clamp(Float64(milliseconds), -6.0e13, 2.5e14)))))

# The first whole unit at or before `time`, aligned so that a step of `count` units
# fits the calendar: the seconds and minutes of the hour, the hours of the day, the
# months of the year, the years that a multiple of `count` divides.
function _floor_time(time::Dates.DateTime, unit::Symbol, count::Int)
    y, mo, d, h, mi, s = Dates.year(time), Dates.month(time), Dates.day(time),
                         Dates.hour(time), Dates.minute(time), Dates.second(time)
    unit === :second && return Dates.DateTime(y, mo, d, h, mi, s - mod(s, count))
    unit === :minute && return Dates.DateTime(y, mo, d, h, mi - mod(mi, count))
    unit === :hour && return Dates.DateTime(y, mo, d, h - mod(h, count))
    unit === :day && return Dates.DateTime(Dates.Date(Dates.UTD(Dates.value(Dates.Date(time)) -
                                                                mod(Dates.value(Dates.Date(time)), count))))
    unit === :week && return Dates.DateTime(Dates.firstdayofweek(Dates.Date(time)))
    unit === :month && return (m = y * 12 + mo - 1; m -= mod(m, count); Dates.DateTime(fld(m, 12), mod(m, 12) + 1))
    Dates.DateTime(y - mod(y, count))
end

_get_time_period(unit::Symbol, count::Int) =
    unit === :second ? Dates.Second(count) : unit === :minute ? Dates.Minute(count) :
    unit === :hour ? Dates.Hour(count) : unit === :day ? Dates.Day(count) :
    unit === :week ? Dates.Week(count) : unit === :month ? Dates.Month(count) : Dates.Year(count)

# The ticks that a step makes inside `lo`..`hi`, as plot coordinates and times.
function _compute_time_ticks(lo::Real, hi::Real, unit::Symbol, count::Int)
    period = _get_time_period(unit, count)
    time = _floor_time(get_plot_time(lo), unit, count)
    times = Dates.DateTime[]
    while get_plot_coordinate(time) <= hi
        get_plot_coordinate(time) >= lo && push!(times, time)
        time += period
    end
    (Float64[get_plot_coordinate(t) for t in times], times)
end

# The form of the label of a tick, and of a readout, by the length of the step in
# milliseconds: `:year`, `:month`, `:day`, `:minute` or `:second`.
function get_time_form(step::Real)
    step >= 360 * 8.64e7 ? :year : step >= 27 * 8.64e7 ? :month : step >= 8.64e7 ? :day :
    step >= 60000 ? :minute : :second
end

const _TIME_FORMATS = (year = "yyyy", month = "yyyy-mm", day = "yyyy-mm-dd",
                       minute = "yyyy-mm-dd HH:MM", second = "yyyy-mm-dd HH:MM:SS")

"""
    format_time_value(milliseconds, form) -> String

A time as the labels of an axis of `form` say it, for the readout of the pointer.
"""
format_time_value(milliseconds::Real, form::Symbol) =
    isfinite(milliseconds) ? Dates.format(get_plot_time(milliseconds), _TIME_FORMATS[form]) : string(milliseconds)

# The labels of ticks. A step of a day or more gives the date in the form of the
# unit. A step below a day gives the time of day, and the first tick of each day
# gives its date too, which the fit of the labels leaves out of the width.
function _format_time_labels(times, unit::Symbol; with_date::Bool = true)
    unit === :year && return String[Dates.format(t, "yyyy") for t in times]
    unit === :month && return String[Dates.format(t, "yyyy-mm") for t in times]
    (unit === :day || unit === :week) && return String[Dates.format(t, "yyyy-mm-dd") for t in times]
    clock = unit === :second ? "HH:MM:SS" : "HH:MM"
    labels = String[]
    previous = nothing
    for t in times
        day = Dates.Date(t)
        push!(labels, Dates.format(t, day == previous || !with_date ? clock : "yyyy-mm-dd " * clock))
        previous = day
    end
    labels
end

"""
    compute_time_ticks(lo, hi, span_px, measure_label_width) -> (ticks, labels)

The ticks of a time axis over `lo`..`hi` milliseconds that span `span_px` pixels:
those of the finest step whose labels fit, each on a whole calendar unit.
`measure_label_width` gives the width in pixels of a label with its gap.
"""
function compute_time_ticks(lo::Real, hi::Real, span_px::Real, measure_label_width)
    span = hi - lo
    local best = (Float64[], String[])
    candidates = Iterators.flatten((_TIME_STEPS, (_get_long_year_step(k) for k in 2:100000)))
    for (unit, count, length_ms) in candidates
        # A step that would make more ticks than the pixels can hold is skipped before it is built.
        span / length_ms > span_px / 4 && continue
        ticks, times = _compute_time_ticks(lo, hi, unit, count)
        labels = _format_time_labels(times, unit)
        best = (ticks, labels)
        isempty(labels) && continue
        widest = maximum(measure_label_width, _format_time_labels(times, unit; with_date = false))
        label_step(length(labels), span_px, widest) == 1 && return best
        length_ms > 4 * span && break
    end
    best
end
