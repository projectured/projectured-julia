"""
The event layer: the events and their constructors, `MouseButtons`, the
`WindowInput`, the reified event patterns and their descriptions, the parser of the
pattern syntax, and `@event_case` with an event type that the layer does not define.
"""

using Test
using ProjecturedKernel.EventModule

# An event type of another module, as a package defines one.
struct EmTestRestEvent <: SyntheticEvent
    x::Int
    y::Int
    time::Float64
end

# The value of the result of `rule` for `value`, with the bound fields in scope: the
# use of `build_event_field_bindings` in a macro on the pattern syntax.
macro em_test_bind_fields(rule, value)
    parsed = parse_event_pattern_rule(rule; scope = __module__)
    event = gensym(:event)
    body = build_event_field_bindings(parsed, event, esc(parsed.result))
    :(let $event = $(esc(value)); $body end)
end

function test_event_module()
@testset "EventModule" begin

    @testset "WindowInput carries the window an event came from" begin
        window_input = WindowInput(:default, KeyDown(:period, ModifierKeys(); time = 0.0))
        @test window_input isa WindowInput
        @test window_input.window_id === :default
        @test window_input.event isa KeyDown
    end

    @testset "the short forms of the constructors" begin
        @test KeyDown(:a, ModifierKeys(); time = 0.0).repeat === false
        @test KeyDown(:a, ModifierKeys(); repeat = true, time = 0.0).repeat === true
        @test KeyPress('a'; time = 0.0).text == "a"
        @test MousePress(:left, 1, 2; time = 0.0).count == 1
        @test MousePress(:left, 1, 2, ModifierKeys(ctrl = true); time = 0.0).count == 1
        @test MousePress(:left, 1, 2, 2, ModifierKeys(); time = 0.0).count == 2
        @test MouseMove(1, 2; time = 0.0).buttons == MouseButtons()
    end

    @testset "MouseButtons holds every held button" begin
        @test MouseButtons() == MouseButtons(left = false, middle = false, right = false)
        @test MouseButtons(:left) == MouseButtons(left = true)
        both = MouseButtons(:left, :right)
        @test both.left && both.right && !both.middle
        move = MouseMove(3, 4, both, ModifierKeys(); time = 0.0)
        @test move.buttons.left && move.buttons.right
        @test_throws ArgumentError MouseButtons(:none)
        @test isbitstype(MouseButtons)
    end

    @testset "@event_case dispatches on event type" begin
        event = KeyDown(:period, ModifierKeys(ctrl=true); time = 0.0)
        r = @event_case event begin
            KeyDown(:period; ctrl) => :dot_ctrl
            _                      => :fallback
        end
        @test r === :dot_ctrl

        move = MouseDown(:left, 10, 20, ModifierKeys(); time = 0.0)
        r2 = @event_case move begin
            KeyDown(:period; ctrl) => :dot_ctrl
            _                      => :fallback
        end
        @test r2 === :fallback
    end

    @testset "@event_case matches an event type of another module" begin
        rest(event) = @event_case event begin
            EmTestRestEvent(x, y) => (x, y)
            _                     => nothing
        end
        @test rest(EmTestRestEvent(3, 4, 0.0)) == (3, 4)
        @test rest(KeyPress('a'; time = 0.0)) === nothing
        rule = parse_event_pattern_rule(:(EmTestRestEvent(x) => x); scope = @__MODULE__)
        @test rule.type === EmTestRestEvent
        # Without the module of the pattern, the name is not in scope.
        @test_throws ErrorException parse_event_pattern_rule(:(EmTestRestEvent(x) => x))
    end

    @testset "EventPattern matches and describes" begin
        p = KeyDownPattern(:period; modifiers = [:ctrl])
        event = KeyDown(:period, ModifierKeys(ctrl=true); time = 0.0)
        @test matches_event_pattern(p, event)
        @test (@inferred matches_event_pattern(p, event)) === true
        @test describe_event_pattern(p) == "Ctrl+."
    end

    @testset "a description names the modifiers and the event" begin
        @test describe_event_pattern(KeyPressPattern('a')) == "a"
        @test describe_event_pattern(KeyPressPattern('a'; modifiers = [:ctrl])) == "Ctrl+a"
        @test describe_event_pattern(KeyPressPattern(nothing)) == "character"
        @test describe_event_pattern(MousePressPattern(:left)) == "Left click"
        # A button that goes down or up is no click.
        @test describe_event_pattern(MouseDownPattern(:left)) == "Left button down"
        @test describe_event_pattern(MouseUpPattern(:right; modifiers = [:ctrl])) ==
              "Ctrl+Right button up"
        @test describe_event_pattern(MouseDownPattern(nothing)) == "button down"
        @test describe_event_pattern(MouseMovePattern(; modifiers = [:shift])) ==
              "Shift+move pointer"
        @test describe_event_pattern(EventPattern{WindowResize}(NamedTuple(), nothing,
                                                                nothing)) == "window resize"
        @test describe_event_pattern(EventPattern{EmTestRestEvent}(NamedTuple(), nothing,
                                                                   nothing)) ==
              "em test rest event"
        @test describe_event_pattern(KeyPressPattern(nothing; label = "0-9")) == "0-9"
    end

    @testset "the pattern constructors take their options as keywords" begin
        digit = KeyPressPattern(nothing; guard = e -> isdigit(e.char))
        @test matches_event_pattern(digit, KeyPress('5'; time = 0.0))
        @test !matches_event_pattern(digit, KeyPress('z'; time = 0.0))
        shifted = MouseScrollPattern(; modifiers = [:shift])
        @test matches_event_pattern(shifted, MouseScroll(0, 1, 2, 3, ModifierKeys(shift = true); time = 0.0))
        @test !matches_event_pattern(shifted, MouseScroll(0, 1, 2, 3; time = 0.0))
    end

    @testset "a reified pattern rejects a modifier with no name" begin
        @test_throws ArgumentError KeyDownPattern(:s; modifiers = [:control])
        @test_throws ArgumentError EventPattern{KeyDown}(NamedTuple(), [:ctrl, :hyper],
                                                         nothing)
    end

    @testset "the parser builds a pattern and the field bindings" begin
        rule = parse_event_pattern_rule(:(KeyDown(:home; ctrl) => :home))
        @test rule.type === KeyDown
        @test rule.modifiers == [:ctrl]
        pattern = Core.eval(@__MODULE__, build_event_pattern_expr(rule, :nothing))
        @test pattern isa EventPattern{KeyDown}
        @test matches_event_pattern(pattern, KeyDown(:home, ModifierKeys(ctrl = true); time = 0.0))
        @test !matches_event_pattern(pattern, KeyDown(:home, ModifierKeys(); time = 0.0))

        @test @em_test_bind_fields(KeyPress(c) => c, KeyPress('q'; time = 0.0)) === 'q'
        @test @em_test_bind_fields(MousePress(b, x, y) => (b, x, y),
                                   MousePress(:right, 5, 6; time = 0.0)) == (:right, 5, 6)
        # A rule that binds no field leaves the body as it is, the catch-all too.
        @test build_event_field_bindings(rule, :event, :body) === :body
        catch_all = parse_event_pattern_rule(:(_ => 1))
        @test build_event_field_bindings(catch_all, :event, :body) === :body
        @test @em_test_bind_fields(_ => 1, KeyPress('q'; time = 0.0)) == 1
    end

    @testset "the parser names what is wrong" begin
        @test_throws ErrorException parse_event_pattern_rule(:(KeyDown(:a; control) => 1))
        @test_throws ErrorException parse_event_pattern_rule(:(NoSuchEvent(x) => 1))
        @test_throws ErrorException parse_event_pattern_rule(:(KeyDown(a, b, c) => 1))
        @test_throws ErrorException parse_event_pattern_rule(:(KeyDown(:a)))
    end

end
end # test_event_module
