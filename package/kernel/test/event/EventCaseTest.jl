function test_event_case()
@testset "EventCase" begin

# ── type-only dispatch ──────────────────────────────────────────────────
let classify(e) = @event_case e begin
        KeyDown     => :keydown
        KeyPress    => :keypress
        MousePress  => :press
        MouseScroll => :scroll
        _           => :other
    end
    @test classify(KeyDown(:a, Modifiers())) == :keydown
    @test classify(KeyPress('a')) == :keypress
    @test classify(MousePress(:left, 1, 2)) == :press
    @test classify(MouseScroll(0, -1, 3, 4)) == :scroll
    @test classify(MouseMove(1, 2)) == :other
end

# ── literal field match and binding ─────────────────────────────────────
let nav(e) = @event_case e begin
        KeyDown(:home) => :home
        KeyDown(key)   => key
    end
    @test nav(KeyDown(:home, Modifiers())) == :home
    @test nav(KeyDown(:left, Modifiers())) == :left   # bound key returned
end

# binding several positional fields
let at(e) = @event_case e begin
        MousePress(:left, x, y) => (x, y)
    end
    @test at(MousePress(:left, 12, 34)) == (12, 34)
    @test at(MousePress(:right, 12, 34)) === nothing   # button literal mismatch
end

# char binding works regardless of modifiers (capitals carry shift)
let typed(e) = @event_case e begin
        KeyPress(c) => c
    end
    @test typed(KeyPress('a')) == 'a'
    @test typed(KeyPress('A', Modifiers(shift=true))) == 'A'
end

# ── exact modifier matching ─────────────────────────────────────────────
let chord(e) = @event_case e begin
        KeyDown(:period; ctrl)      => :ctrl_period
        KeyDown(:home; ctrl, alt)   => :ctrl_alt_home
    end
    @test chord(KeyDown(:period, Modifiers(ctrl=true))) == :ctrl_period
    # exact: ctrl+shift must NOT match the ctrl-only rule
    @test chord(KeyDown(:period, Modifiers(ctrl=true, shift=true))) === nothing
    @test chord(KeyDown(:home, Modifiers(ctrl=true, alt=true))) == :ctrl_alt_home
    @test chord(KeyDown(:home, Modifiers(ctrl=true))) === nothing  # missing alt
end

# omitting the `;` block leaves modifiers unconstrained
let any_mod(e) = @event_case e begin
        KeyDown(:tab) => :tab
    end
    @test any_mod(KeyDown(:tab, Modifiers())) == :tab
    @test any_mod(KeyDown(:tab, Modifiers(ctrl=true, shift=true))) == :tab
end

# ── when-guards (with bound variables) ──────────────────────────────────
let arrows(e) = @event_case e begin
        when(KeyDown(k; alt), k in (:up, :down, :left, :right)) => (:arrow, k)
        KeyDown(k; alt) => (:other, k)
    end
    @test arrows(KeyDown(:up, Modifiers(alt=true))) == (:arrow, :up)
    @test arrows(KeyDown(:tab, Modifiers(alt=true))) == (:other, :tab)
    @test arrows(KeyDown(:up, Modifiers())) === nothing   # alt required
end

# ── first match wins, fallthrough to nothing ────────────────────────────
let order(e) = @event_case e begin
        KeyDown(key)        => :specific
        KeyDown(:ignored)   => :unreachable
    end
    @test order(KeyDown(:x, Modifiers())) == :specific
end

let m(e) = @event_case e begin
        MouseScroll(dx, dy) => (dx, dy)
    end
    @test m(MouseScroll(2, -3, 0, 0)) == (2, -3)
    @test m(KeyDown(:a, Modifiers())) === nothing   # no rule, no catch-all
end

# wildcard field ignores a slot
let scroll_dir(e) = @event_case e begin
        MouseScroll(_, dy) => dy
    end
    @test scroll_dir(MouseScroll(99, -1, 0, 0)) == -1
end

# interpolated value compared against a runtime binding
let want = :delete
    del(e) = @event_case e begin
        KeyDown(^(want)) => :matched
        _                => :no
    end
    @test del(KeyDown(:delete, Modifiers())) == :matched
    @test del(KeyDown(:backspace, Modifiers())) == :no
end

end
end

export test_event_case
