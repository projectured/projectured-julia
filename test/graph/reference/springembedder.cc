// Reference positions from the original's own BasicSpringEmbedderLayout, for the
// four scenarios the Julia port is asserted against.
#include "layout/basicspringembedderlayout.h"
#include <cstdio>
#include <string>
using namespace omnetpp::layout;

static void chain(BasicSpringEmbedderLayout &l, int n)
{
    for (int i = 0; i < n-1; i++)
        l.addEdge(i, i+1, 0);
}

static void dump(const char *name, BasicSpringEmbedderLayout &l, int n)
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

int main()
{
    BasicGraphLayouterEnvironment env;
    {   // 1. a 4 by 4 mesh, nothing fixed, no box
        BasicSpringEmbedderLayout l; l.setEnvironment(&env); l.setSeed(1); l.setSize(0,0,0);
        const int n = 4;
        for (int i = 0; i < n*n; i++) l.addMovableNode(i, 40, 20);
        for (int r = 0; r < n; r++) for (int c = 0; c < n; c++) {
            int i = r*n + c;
            if (c < n-1) l.addEdge(i, i+1, 0);
            if (r < n-1) l.addEdge(i, i+n, 0);
        }
        dump("mesh", l, n*n);
    }
    {   // 2. a chain of eight with the first one fixed
        BasicSpringEmbedderLayout l; l.setEnvironment(&env); l.setSeed(1); l.setSize(0,0,0);
        l.addFixedNode(0, 120, 70, 40, 20);
        for (int i = 1; i < 8; i++) l.addMovableNode(i, 40, 20);
        chain(l, 8);
        dump("pinned", l, 8);
    }
    {   // 3. a chain of eight, nodes 2..5 anchored to one point, 50 apart
        BasicSpringEmbedderLayout l; l.setEnvironment(&env); l.setSeed(1); l.setSize(0,0,0);
        for (int i = 0; i < 8; i++) {
            if (i >= 2 && i <= 5) l.addAnchoredNode(i, "rte", 50.0*(i-2), 0, 40, 20);
            else l.addMovableNode(i, 40, 20);
        }
        chain(l, 8);
        dump("anchored", l, 8);
    }
    {   // 4. a chain of eight in a 600 by 400 box with a 20 border
        BasicSpringEmbedderLayout l; l.setEnvironment(&env); l.setSeed(1); l.setSize(600,400,20);
        for (int i = 0; i < 8; i++) l.addMovableNode(i, 40, 20);
        chain(l, 8);
        dump("boxed", l, 8);
    }
    return 0;
}
