// Reference positions from OMNeT++'s own ForceDirectedGraphLayouter, for the
// scenarios the Julia port is asserted against. See README.md to build it.
//
// `mct` is pinned so the run never stops on the clock: OMNeT++ draws a random
// wall-clock limit and the Julia port leaves it at infinity, because a picture
// must not depend on how fast the machine is.
#include "layout/forcedirectedgraphlayouter.h"
#include <cstdio>
using namespace omnetpp::layout;

static void dump(const char *name, ForceDirectedGraphLayouter &l, int n)
{
    l.execute();
    printf("%s = [", name);
    for (int i = 0; i < n; i++) {
        double x, y;
        l.getNodePosition(i, x, y);
        printf("%s(%.6f, %.6f)", i ? ", " : "", x, y);
    }
    printf("]\n");
}

static void chain(ForceDirectedGraphLayouter &l, int n)
{
    for (int i = 0; i < n-1; i++)
        l.addEdge(i, i+1, 0);
}

int main()
{
    BasicGraphLayouterEnvironment env;
    env.addParameter("mct", 1e12);
    {   // 1. a chain of eight, nothing fixed, no box; seed 1 does not pre-embed
        ForceDirectedGraphLayouter l; l.setEnvironment(&env); l.setSeed(1); l.setSize(0,0,0);
        for (int i = 0; i < 8; i++) l.addMovableNode(i, 40, 20);
        chain(l, 8);
        dump("chain", l, 8);
    }
    {   // 2. a 3 by 3 mesh in a 600 by 400 box
        ForceDirectedGraphLayouter l; l.setEnvironment(&env); l.setSeed(1); l.setSize(600,400,20);
        const int n = 3;
        for (int i = 0; i < n*n; i++) l.addMovableNode(i, 40, 20);
        for (int r = 0; r < n; r++) for (int c = 0; c < n; c++) {
            int i = r*n + c;
            if (c < n-1) l.addEdge(i, i+1, 0);
            if (r < n-1) l.addEdge(i, i+n, 0);
        }
        dump("mesh", l, n*n);
    }
    {   // 3. a chain of eight with the first one fixed
        ForceDirectedGraphLayouter l; l.setEnvironment(&env); l.setSeed(1); l.setSize(0,0,0);
        l.addFixedNode(0, 120, 70, 40, 20);
        for (int i = 1; i < 8; i++) l.addMovableNode(i, 40, 20);
        chain(l, 8);
        dump("pinned", l, 8);
    }
    {   // 4. a chain of eight, nodes 2..5 anchored to one point, 50 apart
        ForceDirectedGraphLayouter l; l.setEnvironment(&env); l.setSeed(1); l.setSize(0,0,0);
        for (int i = 0; i < 8; i++) {
            if (i >= 2 && i <= 5) l.addAnchoredNode(i, "rte", 50.0*(i-2), 0, 40, 20);
            else l.addMovableNode(i, 40, 20);
        }
        chain(l, 8);
        dump("anchored", l, 8);
    }
    {   // 5. seed 3, which turns the pre-embedding on: the star-tree and heap
        //    passes only run on this path
        ForceDirectedGraphLayouter l; l.setEnvironment(&env); l.setSeed(3); l.setSize(0,0,0);
        for (int i = 0; i < 8; i++) l.addMovableNode(i, 40, 20);
        chain(l, 8);
        dump("preembedded", l, 8);
    }
    {   // 6. two separate triangles, seed 3: a pre-embedding per connected part,
        //    packed by the heap embedding of the part graph
        ForceDirectedGraphLayouter l; l.setEnvironment(&env); l.setSeed(3); l.setSize(0,0,0);
        for (int i = 0; i < 6; i++) l.addMovableNode(i, 40, 20);
        int pairs[6][2] = {{0,1},{1,2},{2,0},{3,4},{4,5},{5,3}};
        for (auto &p : pairs) l.addEdge(p[0], p[1], 0);
        dump("parts", l, 6);
    }
    return 0;
}
