"""
    test_undo()

Run this package's whole suite: the layering guard and every undo test.
"""
const test_undo = TestSuite("ProjecturedPlatform", [
    test_undo_buffer,
])

export test_undo, test_undo_buffer
