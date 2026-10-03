function test_gesture_pattern()
@testset "GestureCase" begin

# ── type-only dispatch ──────────────────────────────────────────────────
let classify(e) = @gesture_case e begin
        KeyDown     => :keydown
        KeyPress    => :keypress
        MouseClick  => :press
        MouseScroll => :scroll
        _           => :other
    end
    @test classify(KeyDown(:a, ModifierKeys(); time = 0.0)) == :keydown
    @test classify(KeyPress('a'; time = 0.0)) == :keypress
    @test classify(MouseClick(:left, 1, 2; time = 0.0)) == :press
    @test classify(MouseScroll(0, -1, 3, 4; time = 0.0)) == :scroll
    @test classify(MouseMove(1, 2; time = 0.0)) == :other
end

# ── literal field match and binding ─────────────────────────────────────
let nav(e) = @gesture_case e begin
        KeyDown(:home) => :home
        KeyDown(key)   => key
    end
    @test nav(KeyDown(:home, ModifierKeys(); time = 0.0)) == :home
    @test nav(KeyDown(:left, ModifierKeys(); time = 0.0)) == :left   # bound key returned
end

# binding several positional fields
let at(e) = @gesture_case e begin
        MouseClick(:left, x, y) => (x, y)
    end
    @test at(MouseClick(:left, 12, 34; time = 0.0)) == (12, 34)
    @test at(MouseClick(:right, 12, 34; time = 0.0)) === nothing   # button literal mismatch
end

# char binding works regardless of modifiers (capitals carry shift)
let typed(e) = @gesture_case e begin
        KeyPress(c) => c
    end
    @test typed(KeyPress('a'; time = 0.0)) == 'a'
    @test typed(KeyPress('A', ModifierKeys(shift=true); time = 0.0)) == 'A'
end

# ── exact modifier matching ─────────────────────────────────────────────
let chord(e) = @gesture_case e begin
        KeyDown(:period; ctrl)      => :ctrl_period
        KeyDown(:home; ctrl, alt)   => :ctrl_alt_home
    end
    @test chord(KeyDown(:period, ModifierKeys(ctrl=true); time = 0.0)) == :ctrl_period
    # exact: ctrl+shift must NOT match the ctrl-only rule
    @test chord(KeyDown(:period, ModifierKeys(ctrl=true, shift=true); time = 0.0)) === nothing
    @test chord(KeyDown(:home, ModifierKeys(ctrl=true, alt=true); time = 0.0)) == :ctrl_alt_home
    @test chord(KeyDown(:home, ModifierKeys(ctrl=true); time = 0.0)) === nothing  # missing alt
end

# a modifier flag on an event type with no `modifiers` field reads its modifiers
# through `get_modifier_keys`: a window event holds none
let resized(e) = @gesture_case e begin
        WindowResize(; ctrl) => :ctrl_resize
        WindowResize()       => :resize
    end
    @test resized(WindowResize(10, 20; time = 0.0)) == :resize
end

# omitting the `;` block leaves modifiers unconstrained
let any_mod(e) = @gesture_case e begin
        KeyDown(:tab) => :tab
    end
    @test any_mod(KeyDown(:tab, ModifierKeys(); time = 0.0)) == :tab
    @test any_mod(KeyDown(:tab, ModifierKeys(ctrl=true, shift=true); time = 0.0)) == :tab
end

# ── when-guards (with bound variables) ──────────────────────────────────
let arrows(e) = @gesture_case e begin
        when(KeyDown(k; alt), k in (:up, :down, :left, :right)) => (:arrow, k)
        KeyDown(k; alt) => (:other, k)
    end
    @test arrows(KeyDown(:up, ModifierKeys(alt=true); time = 0.0)) == (:arrow, :up)
    @test arrows(KeyDown(:tab, ModifierKeys(alt=true); time = 0.0)) == (:other, :tab)
    @test arrows(KeyDown(:up, ModifierKeys(); time = 0.0)) === nothing   # alt required
end

# ── first match wins, fallthrough to nothing ────────────────────────────
let order(e) = @gesture_case e begin
        KeyDown(key)        => :specific
        KeyDown(:ignored)   => :unreachable
    end
    @test order(KeyDown(:x, ModifierKeys(); time = 0.0)) == :specific
end

let m(e) = @gesture_case e begin
        MouseScroll(dx, dy) => (dx, dy)
    end
    @test m(MouseScroll(2, -3, 0, 0; time = 0.0)) == (2, -3)
    @test m(KeyDown(:a, ModifierKeys(); time = 0.0)) === nothing   # no rule, no catch-all
end

# wildcard field ignores a slot
let scroll_dir(e) = @gesture_case e begin
        MouseScroll(_, dy) => dy
    end
    @test scroll_dir(MouseScroll(99, -1, 0, 0; time = 0.0)) == -1
end

# interpolated value compared against a runtime binding
let want = :delete
    del(e) = @gesture_case e begin
        KeyDown(^(want)) => :matched
        _                => :no
    end
    @test del(KeyDown(:delete, ModifierKeys(); time = 0.0)) == :matched
    @test del(KeyDown(:backspace, ModifierKeys(); time = 0.0)) == :no
end

end
end

export test_gesture_pattern
