# Unit tests for the plot arithmetic every plotted notation shares. Everything
# here is a pure function over numbers and vectors, so these run headless and
# fast — no documents, no projection, no backend.
#
# The load-bearing property is decimation *exactness*: decimate_minmax must
# produce a polyline that covers every pixel column the full data covers, and
# reach the same vertical extent in each. If that ever stops holding, a zoomed
# out chart is no longer showing the data, it is showing a sample of it.

using Test

"""
    test_plot_geometry()

Axis scaling, tick selection, decimation, folding and histogram binning.
"""
function test_plot_geometry()
    @testset "plot geometry" begin
        @testset "axis scale" begin
            s = PlotModule.AxisScale(0.0, 10.0, 100.0, 300.0)
            @test PlotModule.to_pixel(s, 0.0) ≈ 100.0
            @test PlotModule.to_pixel(s, 10.0) ≈ 300.0
            @test PlotModule.to_pixel(s, 5.0) ≈ 200.0
            @test PlotModule.to_data(s, 200.0) ≈ 5.0
            @test PlotModule.get_axis_span(s) ≈ 200.0

            # A y axis passes bottom as p0 and top as p1: no flip flag needed.
            y = PlotModule.AxisScale(0.0, 1.0, 300.0, 100.0)
            @test PlotModule.to_pixel(y, 0.0) ≈ 300.0
            @test PlotModule.to_pixel(y, 1.0) ≈ 100.0

            # Degenerate range maps to the middle instead of dividing by zero.
            d = PlotModule.AxisScale(5.0, 5.0, 0.0, 100.0)
            @test PlotModule.to_pixel(d, 5.0) ≈ 50.0

            l = PlotModule.AxisScale(1.0, 1000.0, 0.0, 300.0; log=true)
            @test PlotModule.to_pixel(l, 1.0) ≈ 0.0
            @test PlotModule.to_pixel(l, 10.0) ≈ 100.0
            @test PlotModule.to_pixel(l, 1000.0) ≈ 300.0
            @test PlotModule.to_data(l, 200.0) ≈ 100.0
        end

        @testset "bounds and padding" begin
            @test PlotModule.get_column_bounds([3.0, 1.0, 2.0]) == (1.0, 3.0)
            @test PlotModule.get_column_bounds([NaN, 2.0, Inf]) == (2.0, 2.0)
            @test PlotModule.get_column_bounds(Float64[]) === nothing
            @test PlotModule.get_column_bounds([NaN, NaN]) === nothing

            @test PlotModule.merge_bounds((1.0, 2.0), (0.0, 5.0)) == (0.0, 5.0)
            @test PlotModule.merge_bounds(nothing, (0.0, 5.0)) == (0.0, 5.0)
            @test PlotModule.merge_bounds((1.0, 2.0), nothing) == (1.0, 2.0)
            @test PlotModule.merge_bounds(nothing, nothing) === nothing

            lo, hi = PlotModule.pad_range(0.0, 10.0; fraction=0.1)
            @test lo ≈ -1.0 && hi ≈ 11.0
            # A constant series still gets a window to draw in.
            lo, hi = PlotModule.pad_range(5.0, 5.0)
            @test lo < 5.0 < hi
            # include_zero pulls the near end to the origin instead of padding it.
            lo, hi = PlotModule.pad_range(2.0, 10.0; fraction=0.1, include_zero=true)
            @test lo == 0.0 && hi ≈ 10.8
        end

        @testset "ticks" begin
            @test PlotModule.compute_nice_number(0.9, true) ≈ 1.0
            @test PlotModule.compute_nice_number(23.0, true) ≈ 20.0
            @test PlotModule.compute_nice_number(7.3, false) ≈ 10.0

            ticks = PlotModule.compute_nice_ticks(0.0, 100.0, 6)
            @test all(t -> t % 20 == 0, ticks)
            @test first(ticks) >= 0.0 && last(ticks) <= 100.0
            @test 3 <= length(ticks) <= 12

            # Ticks are clipped to the range rather than expanding it, so the
            # count has to come out near the target instead of a third of it.
            for (lo, hi, target) in ((-1.08, 1.08, 5), (0.0, 2.16, 5), (0.0, 3.0, 7))
                ts = PlotModule.compute_nice_ticks(lo, hi, target)
                @test length(ts) >= target - 2
            end

            # Every tick lands inside the requested range, whatever the range.
            for (lo, hi) in ((0.0, 1.0), (-5.0, 5.0), (1e-4, 3e-4), (0.0, 1e7))
                ts = PlotModule.compute_nice_ticks(lo, hi, 5)
                @test !isempty(ts)
                @test all(t -> lo - 1e-9 <= t <= hi + 1e-9, ts)
            end

            lts = PlotModule.log_ticks(1.0, 1000.0)
            @test 1.0 in lts && 10.0 in lts && 100.0 in lts && 1000.0 in lts
            @test all(t -> 1.0 <= t <= 1000.0, lts)

            @test PlotModule.format_tick(0.0) == "0"
            @test PlotModule.format_tick(20.0, 20.0) == "20"
            @test occursin("e", PlotModule.format_tick(1.0e-7))
            @test occursin("e", PlotModule.format_tick(5.0e8))
        end

        @testset "visible range" begin
            x = collect(0.0:1.0:100.0)
            i0, i1 = PlotModule.get_visible_range(x, 10.0, 20.0)
            # One index of slack each way so the entering/leaving segments draw.
            @test i0 <= 11 && i1 >= 21
            @test x[i0] <= 10.0 && x[i1] >= 20.0

            # Fully outside the data, on both sides.
            i0, i1 = PlotModule.get_visible_range(x, 500.0, 600.0)
            @test i1 - i0 <= 1
            @test PlotModule.get_visible_range(Float64[], 0.0, 1.0) == (1, 0)
            # Unsorted columns cannot be searched, so the whole column is in range.
            @test PlotModule.get_visible_range(x, 10.0, 20.0; sorted=false) == (1, length(x))
        end

        @testset "decimation is exact" begin
            n = 100_000
            x = collect(range(0.0, 1.0; length=n))
            y = sin.(range(0.0, 40π; length=n))
            width = 400
            xs = PlotModule.AxisScale(0.0, 1.0, 0.0, width)
            ys = PlotModule.AxisScale(-1.0, 1.0, 200.0, 0.0)

            pts = PlotModule.decimate_minmax(x, y, xs, ys, 1, n)
            # Bounded by pixels, not by data: at most four points per column.
            @test length(pts) <= 4 * (width + 2)
            @test length(pts) < n ÷ 10

            # Same pixel columns covered, and the same vertical extent in each,
            # as drawing every single sample would have produced.
            full = Dict{Int,Tuple{Int,Int}}()
            for i in 1:n
                px = round(Int, PlotModule.to_pixel(xs, x[i]))
                py = round(Int, PlotModule.to_pixel(ys, y[i]))
                lo, hi = get(full, px, (py, py))
                full[px] = (min(lo, py), max(hi, py))
            end
            dec = Dict{Int,Tuple{Int,Int}}()
            for (px, py) in pts
                lo, hi = get(dec, px, (py, py))
                dec[px] = (min(lo, py), max(hi, py))
            end
            @test keys(dec) == keys(full)
            @test all(dec[k] == full[k] for k in keys(full))

            # x is monotone, so the decimated points come out in draw order.
            @test issorted([p[1] for p in pts])

            # Non-finite samples are skipped, not mapped to garbage pixels.
            y2 = copy(y); y2[10] = NaN; y2[20] = Inf
            @test !isempty(PlotModule.decimate_minmax(x, y2, xs, ys, 1, n))
            @test isempty(PlotModule.decimate_minmax(x, y, xs, ys, 5, 4))
        end

        @testset "step and pins" begin
            pts = [(0, 10), (10, 20), (20, 5)]
            post = PlotModule.step_points(pts, :steps_post)
            @test (10, 10) in post   # held the old value until the new x
            pre = PlotModule.step_points(pts, :steps_pre)
            @test (0, 20) in pre     # jumped to the new value at the old x
            mid = PlotModule.step_points(pts, :steps_mid)
            @test (5, 10) in mid && (5, 20) in mid
            @test PlotModule.step_points(pts, :linear) == pts

            segs = PlotModule.build_pins_segments(pts, 30)
            @test length(segs) == 3
            @test all(s -> s[2] <= s[3], segs)
            @test segs[1] == (0, 10, 30)
        end

        @testset "folding" begin
            n = 50_000
            x = rand(n); y = rand(n)
            xs = PlotModule.AxisScale(0.0, 1.0, 0.0, 200.0)
            ys = PlotModule.AxisScale(0.0, 1.0, 200.0, 0.0)
            bands = PlotModule.fold_scatter(x, y, xs, ys, 4, 1, n)
            # Bounded by the plot area, and merging equally-dense neighbours
            # brings it well under one band per grid cell.
            @test !isempty(bands)
            @test length(bands) < (200 ÷ 4 + 2)^2
            @test all(b -> b[3] > 0 && b[4] > 0, bands)
            @test all(b -> 1 <= b[5] <= 8, bands)
            # The whole cloud is covered: every point falls inside some band.
            covered = sum(b[3] * b[4] for b in bands)
            @test covered > 0
            # A uniform cloud has more than one density level.
            @test length(unique(b[5] for b in bands)) > 1

            # Bars already wide enough pass through untouched.
            wide = PlotModule.fold_bins([0, 10, 20], [10, 20, 30], [1.0, 2.0, 3.0], 2)
            @test length(wide) == 3
            @test all(b -> b[3] == b[4], wide)
            # Sub-pixel bars merge into envelopes carrying the local min and max.
            narrow = PlotModule.fold_bins(collect(0:99), collect(1:100),
                                                   Float64.(1:100), 10)
            @test length(narrow) < 100
            @test all(b -> b[3] <= b[4], narrow)
            @test minimum(b[3] for b in narrow) == 1.0
            @test maximum(b[4] for b in narrow) == 100.0

            @test PlotModule.label_step(10, 1000, 40) == 1
            @test PlotModule.label_step(10_000, 800, 40) > 100
            @test PlotModule.label_step(0, 100, 10) == 1
        end

        @testset "strips" begin
            # Equal adjacent values coalesce; the window bounds the result.
            codes = [1, 1, 1, 2, 2, 3, 1]
            @test PlotModule.strip_runs(codes, 1, 7) ==
                  [(1, 3), (4, 5), (6, 6), (7, 7)]
            @test PlotModule.strip_runs(codes, 3, 5) == [(3, 3), (4, 5)]
            @test PlotModule.strip_runs([7, 7, 7], 1, 3) == [(1, 3)]
            @test PlotModule.strip_runs(Int[], 1, 0) == Tuple{Int,Int}[]
            # Out-of-range windows clamp rather than throw.
            @test PlotModule.strip_runs(codes, 0, 100) ==
                  [(1, 3), (4, 5), (6, 6), (7, 7)]

            # Segments already wide enough pass through with their own code.
            wide = PlotModule.fold_strips([0, 10, 20], [10, 20, 30], [1, 2, 3], 2)
            @test wide == [(0, 10, 1), (10, 20, 2), (20, 30, 3)]

            # Sub-pixel segments fold, and the fold takes the state that holds
            # it longest rather than the first or last one in the run.
            folded = PlotModule.fold_strips([0.0, 0.1, 0.8], [0.1, 0.8, 1.0],
                                                     [1, 2, 1], 1)
            @test length(folded) == 1
            @test folded[1][3] == 2

            # A wide segment never inherits the sliver in front of it: the
            # accumulating group closes before it, so it keeps its own left
            # edge and its own code (where fold_bins would have absorbed it).
            mixed = PlotModule.fold_strips([0.0, 0.4, 50.0], [0.4, 50.0, 90.0],
                                                    [1, 2, 3], 1)
            @test length(mixed) == 3
            @test mixed[2] == (0, 50, 2)
            @test mixed[3] == (50, 90, 3)

            # A dense toggle stays bounded by the pixel width and dithers the
            # two states instead of collapsing to one.
            n = 10_000
            lefts = collect(range(0.0; step = 800 / n, length = n))
            rights = lefts .+ (800 / n)
            dither = PlotModule.fold_strips(lefts, rights,
                                                     [isodd(i) ? 1 : 2 for i in 1:n], 1)
            @test length(dither) <= 801
            @test length(unique(s[3] for s in dither)) == 2
            # Every span is at least one pixel wide and they tile in order.
            @test all(s -> s[2] > s[1], dither)
            @test issorted([s[1] for s in dither])

            # A zero-width segment still yields a drawable span.
            @test PlotModule.fold_strips([5.0], [5.0], [4], 1) == [(5, 6, 4)]
            @test PlotModule.fold_strips(Float64[], Float64[], Int[], 1) ==
                  Tuple{Int,Int,Int}[]
        end

        @testset "histograms" begin
            edges, counts = PlotModule.compute_bin_values([0.0, 1.0, 2.0, 3.0, 4.0], 4)
            @test length(edges) == 5 && length(counts) == 4
            @test sum(counts) == 5
            @test issorted(edges)
            # A constant column still produces a usable window.
            e2, c2 = PlotModule.compute_bin_values([7.0, 7.0, 7.0], 3)
            @test length(e2) == 4 && sum(c2) == 3

            vals = [1.0, 2.0, 3.0, 4.0]
            edges = [0.0, 1.0, 2.0, 3.0, 4.0]
            @test PlotModule.compute_histogram_values(edges, vals, false, false) == vals
            cum = PlotModule.compute_histogram_values(edges, vals, true, false)
            @test cum == [1.0, 3.0, 6.0, 10.0]
            cdf = PlotModule.compute_histogram_values(edges, vals, true, true)
            @test cdf[end] ≈ 1.0 && issorted(cdf)
            pdf = PlotModule.compute_histogram_values(edges, vals, false, true)
            @test sum(pdf) ≈ 1.0    # unit bin widths, so the density sums to 1
        end
    end
end
