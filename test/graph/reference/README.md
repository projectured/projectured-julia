# Reference positions from the C++ original

`SpringEmbedderLayout` and `ForceDirectedLayout` are ports. The test asserts
what they draw against what the original draws, and these programs are what
produce the numbers the test asserts.

Each links against the layout library of a checkout of the original, builds the
same graph the Julia test builds, and prints the placed centre of every node.
Paste the output into the matching `@testset` in
[../projection/GraphProjectionTest.jl](../projection/GraphProjectionTest.jl).

## Build and run

With `SIMULATOR` set to a source tree of the original that has been built:

```bash
SIMULATOR=$HOME/workspace/simulator
for name in springembedder forcedirected; do
    g++ -std=c++17 -O2 -I$SIMULATOR/src -I$SIMULATOR/include $name.cc \
        -L$SIMULATOR/lib -lopplayout -loppcommon -Wl,-rpath,$SIMULATOR/lib \
        -o /tmp/$name
    /tmp/$name
done
```

## Why the numbers are checked in rather than computed

A test that needed the built original would not run in this repository's test
environment, and a port whose parity is never asserted stops being a port the
first time somebody tunes a constant. Checked-in numbers keep the assertion
where it belongs and keep the way to re-derive it next to them.

Regenerate them whenever the layouter changes over there — a difference is
either a fix worth carrying across, or a bug in the port.
