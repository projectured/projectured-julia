# Video time for an animated take

> **Status:** in progress. Written 2026-09-24.

While a form of S1 is typed, the animation stutters (F10 of
`feature-video-screenplays.md`). The video backend takes one frame for each
1/30 s of wall clock, and when the work between two frames takes longer, it
copies the last frame into the missed slots. A key makes that work long.

## 1. The owner's decision (2026-09-24)

> yes, fix the recording for this example, but note that other examples may not
> need this mechanism, if they do not animate or there are no background changes
> like the assistant writing it's response, it may be unnecessary to record 30
> frames every second

So video time is an option of a take, off by default, and S1 turns it on. A take
that waits for work outside the loop, such as the answer of a model, keeps the
wall clock. Fewer frames for a take that does not move is noted, and not part of
this plan.

## 2. The design

1. **The video backend keeps video time when asked.** `VideoBackend(…;
   video_time = true)`: frame `n` is at `n / fps` seconds. Each call of
   `write_to_devices` writes the next frame and copies none; `read_from_devices`
   fires an entry when the video time reaches it; `wait_for_input` does not
   sleep, so the loop makes frames as fast as it can. The editor loop writes a
   frame on every pass (`print!`), so the video time moves on by itself.
2. **The editor's clock takes the time of the frame from the backend.** The loop
   sets `editor.clock` through `get_frame_clock_time(backend, wall_time)`, a new
   function of the editor layer (`EditorLoop.jl`) that answers the wall time;
   the video backend answers the video time when it keeps it. The backend
   interface is sealed, so the function is not a method of it.
3. **The recorder passes the option.** `record_application_video(…;
   video_time = false)`.
4. **S1 turns it on**, and its first form reads the editor's clock:
   `clock = editor.clock`, in place of the wall clock, whose heartbeat follows
   real time.

## 3. Steps

- [x] Step 1: the backend, the loop and the recorder, with a test that the
      editor's clock follows the video time. **Done.** The test
      (`ApplicationVideoTest.jl`) notes the editor's clock with two `await`
      entries, 1 s apart, and counts the frames: 18 of 18. Two facts from the
      test:
      - An `await` entry with a cap of 0 s ends before it asks its predicate,
        because `_wait_for_entry!` checks the cap first. A note that must run
        needs a cap above 0.
      - Escape quits the application window. A take that ends on Escape is
        shorter than its schedule, in both clocks.
- [ ] Step 2: S1 in video time, recorded and given to the owner.
