"""
The gesture layer: the gestures and their constructors, the reified patterns and
their descriptions, the parser of the pattern syntax, and `@gesture_case` with a
gesture type that the layer does not define.
"""

using Test
using ProjecturedKernel.EventModule
using ProjecturedKernel.GestureModule

# A gesture type of another module, as a package defines one.
struct GmTestRestGesture <: Gesture
    x::Int
    y::Int
    time::Float64
end

# The value of the result of `rule` for `value`, with the bound fields in scope: the
# use of `build_gesture_field_bindings` in a macro on the pattern syntax.
macro gm_test_bind_fields(rule, value)
    parsed = parse_gesture_pattern_rule(rule; scope = __module__)
    event = gensym(:event)
    body = build_gesture_field_bindings(parsed, event, esc(parsed.result))
    :(let $event = $(esc(value)); $body end)
end

function test_gesture_module()
@testset "GestureModule" begin

    @testset "the short forms of the constructors" begin
        @test MouseClick(:left, 1, 2; time = 0.0).count == 1
        @test MouseClick(:left, 1, 2, ModifierKeys(ctrl = true); time = 0.0).count == 1
        @test MouseClick(:left, 1, 2, 2, ModifierKeys(); time = 0.0).count == 2
        @test MouseDwell(1, 2; time = 0.0).modifiers == ModifierKeys()
        @test MouseDwell(1, 2; time = 0.0) isa Gesture
        @test get_event_time(MouseDwell(1, 2; time = 3.0)) === 3.0
    end

    @testset "@gesture_case dispatches on event type" begin
        event = KeyDown(:period, ModifierKeys(ctrl=true); time = 0.0)
        r = @gesture_case event begin
            KeyDown(:period; ctrl) => :dot_ctrl
            _                      => :fallback
        end
        @test r === :dot_ctrl

        move = MouseDown(:left, 10, 20, ModifierKeys(); time = 0.0)
        r2 = @gesture_case move begin
            KeyDown(:period; ctrl) => :dot_ctrl
            _                      => :fallback
        end
        @test r2 === :fallback
    end

    @testset "@gesture_case matches an event type of another module" begin
        rest(event) = @gesture_case event begin
            GmTestRestGesture(x, y) => (x, y)
            _                     => nothing
        end
        @test rest(GmTestRestGesture(3, 4, 0.0)) == (3, 4)
        @test rest(KeyPress('a'; time = 0.0)) === nothing
        rule = parse_gesture_pattern_rule(:(GmTestRestGesture(x) => x); scope = @__MODULE__)
        @test rule.type === GmTestRestGesture
        # Without the module of the pattern, the name is not in scope.
        @test_throws ErrorException parse_gesture_pattern_rule(:(GmTestRestGesture(x) => x))
    end

    @testset "GesturePattern matches and describes" begin
        p = KeyDownPattern(:period; modifiers = [:ctrl])
        event = KeyDown(:period, ModifierKeys(ctrl=true); time = 0.0)
        @test matches_gesture_pattern(p, event)
        @test (@inferred matches_gesture_pattern(p, event)) === true
        @test describe_gesture_pattern(p) == "Ctrl+."
    end

    @testset "a description names the modifiers and the event" begin
        @test describe_gesture_pattern(KeyPressPattern('a')) == "a"
        @test describe_gesture_pattern(KeyPressPattern('a'; modifiers = [:ctrl])) == "Ctrl+a"
        @test describe_gesture_pattern(KeyPressPattern(nothing)) == "character"
        @test describe_gesture_pattern(KeyDownPattern(:tab)) == "Tab"
        @test describe_gesture_pattern(KeyDownPattern(:home; modifiers = [:ctrl, :alt])) ==
              "Ctrl+Alt+Home"
        @test describe_gesture_pattern(MouseClickPattern(:left)) == "Left click"
        # A button that goes down or up is no click.
        @test describe_gesture_pattern(MouseDownPattern(:left)) == "Left button down"
        @test describe_gesture_pattern(MouseUpPattern(:right; modifiers = [:ctrl])) ==
              "Ctrl+Right button up"
        @test describe_gesture_pattern(MouseDownPattern(nothing)) == "button down"
        @test describe_gesture_pattern(KeyUpPattern(:home)) == "release Home"
        @test describe_gesture_pattern(KeyUpPattern(:a; modifiers = [:ctrl])) ==
              "release Ctrl+A"
        @test describe_gesture_pattern(GesturePattern{KeyChord}(NamedTuple(), nothing,
                                                            nothing)) == "key chord"
        @test describe_gesture_pattern(MouseMovePattern(; modifiers = [:shift])) ==
              "Shift+move pointer"
        @test describe_gesture_pattern(GesturePattern{WindowResize}(NamedTuple(), nothing,
                                                                nothing)) == "window resize"
        @test describe_gesture_pattern(GesturePattern{GmTestRestGesture}(NamedTuple(), nothing,
                                                                     nothing)) ==
              "gm test rest gesture"
        @test describe_gesture_pattern(KeyPressPattern(nothing; label = "0-9")) == "0-9"
        @test describe_gesture_pattern(MouseDwellPattern()) == "pointer dwells"
        @test matches_gesture_pattern(MouseDwellPattern(), MouseDwell(3, 4; time = 0.0))
    end

    @testset "a pattern checks the event, the key, the button and the modifiers" begin
        # A pattern that names no modifiers takes any; one that names them takes
        # exactly those.
        press = KeyPressPattern('n')
        @test matches_gesture_pattern(press, KeyPress('n', ModifierKeys(shift = true);
                                                       time = 0.0))
        @test !matches_gesture_pattern(press, KeyPress('x'; time = 0.0))
        @test !matches_gesture_pattern(press, KeyDown(:n, ModifierKeys(); time = 0.0))
        down = KeyDownPattern(:period; modifiers = [:ctrl])
        @test !matches_gesture_pattern(down, KeyDown(:period,
                                                      ModifierKeys(ctrl = true, alt = true);
                                                      time = 0.0))
        @test !matches_gesture_pattern(down, KeyDown(:home, ModifierKeys(ctrl = true);
                                                      time = 0.0))
        # A click pattern reads the button and not the position.
        click = MouseClickPattern(:left)
        @test matches_gesture_pattern(click, MouseClick(:left, 10, 20; time = 0.0))
        @test matches_gesture_pattern(click, MouseClick(:left, 99, 5; time = 0.0))
        @test !matches_gesture_pattern(click, MouseClick(:right, 10, 20; time = 0.0))
    end

    @testset "the pattern constructors take their options as keywords" begin
        digit = KeyPressPattern(nothing; guard = e -> isdigit(e.char))
        @test matches_gesture_pattern(digit, KeyPress('5'; time = 0.0))
        @test !matches_gesture_pattern(digit, KeyPress('z'; time = 0.0))
        shifted = MouseScrollPattern(; modifiers = [:shift])
        @test matches_gesture_pattern(shifted, MouseScroll(0, 1, 2, 3, ModifierKeys(shift = true); time = 0.0))
        @test !matches_gesture_pattern(shifted, MouseScroll(0, 1, 2, 3; time = 0.0))
    end

    @testset "a reified pattern rejects a modifier with no name" begin
        @test_throws ArgumentError KeyDownPattern(:s; modifiers = [:control])
        @test_throws ArgumentError GesturePattern{KeyDown}(NamedTuple(), [:ctrl, :hyper],
                                                            nothing)
    end

    @testset "the parser builds a pattern and the field bindings" begin
        rule = parse_gesture_pattern_rule(:(KeyDown(:home; ctrl) => :home))
        @test rule.type === KeyDown
        @test rule.modifiers == [:ctrl]
        pattern = Core.eval(@__MODULE__, build_gesture_pattern_expr(rule, :nothing))
        @test pattern isa GesturePattern{KeyDown}
        @test matches_gesture_pattern(pattern, KeyDown(:home, ModifierKeys(ctrl = true); time = 0.0))
        @test !matches_gesture_pattern(pattern, KeyDown(:home, ModifierKeys(); time = 0.0))

        @test @gm_test_bind_fields(KeyPress(c) => c, KeyPress('q'; time = 0.0)) === 'q'
        @test @gm_test_bind_fields(MouseClick(b, x, y) => (b, x, y),
                                   MouseClick(:right, 5, 6; time = 0.0)) == (:right, 5, 6)
        # A rule that binds no field leaves the body as it is, the catch-all too.
        @test build_gesture_field_bindings(rule, :event, :body) === :body
        catch_all = parse_gesture_pattern_rule(:(_ => 1))
        @test build_gesture_field_bindings(catch_all, :event, :body) === :body
        @test @gm_test_bind_fields(_ => 1, KeyPress('q'; time = 0.0)) == 1
    end

    @testset "the parser names what is wrong" begin
        @test_throws ErrorException parse_gesture_pattern_rule(:(KeyDown(:a; control) => 1))
        @test_throws ErrorException parse_gesture_pattern_rule(:(NoSuchEvent(x) => 1))
        @test_throws ErrorException parse_gesture_pattern_rule(:(KeyDown(a, b, c) => 1))
        @test_throws ErrorException parse_gesture_pattern_rule(:(KeyDown(:a)))
    end

end
end # test_gesture_module
