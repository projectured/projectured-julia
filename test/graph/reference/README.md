# Reference positions from OMNeT++

`SpringEmbedderLayout` and `ForceDirectedLayout` are ports. The test asserts
what they draw against what the original draws, and these programs are what
produce the numbers the test asserts.

Each links against the layout library of an OMNeT++ checkout, builds the same
graph the Julia test builds, and prints the placed centre of every node. Paste
the output into the matching `@testset` in
[../projection/GraphTest.jl](../projection/GraphTest.jl).

## Build and run

With `OMNETPP` set to an OMNeT++ source tree that has been built:

```bash
OMNETPP=$HOME/workspace/omnet-cpp
for name in springembedder forcedirected; do
    g++ -std=c++17 -O2 -I$OMNETPP/src -I$OMNETPP/include $name.cc \
        -L$OMNETPP/lib -lopplayout -loppcommon -Wl,-rpath,$OMNETPP/lib \
        -o /tmp/$name
    /tmp/$name
done
```

## Why the numbers are checked in rather than computed

A test that needed a built OMNeT++ would not run in this repository's test
environment, and a port whose parity is never asserted stops being a port the
first time somebody tunes a constant. Checked-in numbers keep the assertion
where it belongs and keep the way to re-derive it next to them.

Regenerate them whenever the layouter changes over there — a difference is
either a fix worth carrying across, or a bug in the port.
