# A real drag moves the slider, and S4 uses the widgets

> **Status:** done. Written and done 2026-09-24.

## 1. The owner's decision (2026-09-24)

> we should press the button and move the slider using the widgets in the script

Then, to the two questions of F5 (`feature-video-screenplays.md`, §2.4):

> for 1, yes
> for 2, keep the way it is

1. Yes to the fix of the slider.
2. The name field of S4 stays a write from the evaluator
   (`name.content = "Ada Lovelace"`).

## 2. The fault (F5)

The probe `build/suites/s4/probe_drag.jl` sends real mouse events to the slider
of S4 in its own pane.

- The slider takes the knob only on a `MousePress`. The gesture recognizer makes
  a `MousePress` after the `MouseUp`, and only when the up is less than 5 px and
  0.3 s from the down. A real drag makes no `MousePress`, so the value stays.
- A real click takes the knob after the button is already up. The knob stays
  held, and a move with no button moves it.

## 3. The design

1. **The slider takes the knob on `MouseDown`**, writes the value while the knob
   is held, and lets go on `MouseUp`. A `MousePress` sets the value and does not
   take the knob. So a click made by a script, which sends only a `MousePress`,
   still sets the value, and the `MousePress` that follows a real click writes
   the value that the knob already has.
2. **S4 uses real events.** Each press of the button is a `MouseDown` and a
   `MouseUp`. The slider moves by a drag: a `MouseDown` on the knob at 0.3,
   moves with the left button along the track, and a `MouseUp` at 0.8. The form
   `slider.value = 0.8` goes. The take gets the warm-up and the faster typing of
   S1, which compile the path of the first click before the take.

Out of scope, recorded in F5: a layout routes a `MouseDown`, a `MouseMove` and a
`MouseUp` only to the child under the pointer. A drag that leaves the slider
loses its moves, and an up off the slider leaves the knob held. A composite
offers a drag event to each child when none is under the pointer; a layout does
not.

## 4. Steps

- [x] Step 1: the slider reads a real drag, with a test of a drag, a click, and
      a move with no button after the click. **Done.** `test_widget_slider_drag()`
      passes 14 of 14, and `test_widget_button_behavior()` still passes. The
      probe in the application, wall clock: a real drag from 849 to 969 moves
      the value from 0.3 to 0.8 and lets go; a real click at x = 900 sets 0.5125
      and leaves the knob free, so a move with no button changes nothing. The
      first real click on the button is still lost, because it is the first
      click after the typing and it takes longer than 0.3 s; the second and the
      third count.
- [x] Step 2: S4 with real presses and a real drag, recorded and given to the
      owner. **Done.** `build/video/widget_tool_v2.mp4`: 91.2 s, exactly its
      schedule, 1.2 MB, wall clock. The warm-up clicks and drags too, so the first
      click of the take counts: the last frame says "Pressed 3 times", the knob
      is at 0.8, and the table shows 3, 0.8 and "Ada Lovelace". The drag moves
      4 px a frame, and the slider area changes on each frame from 84.73 s to
      85.70 s. The take of 2026-09-23 was 166.9 s; the faster typing of S1
      makes the difference.
