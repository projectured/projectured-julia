"""
    test_display()

Run this package's whole suite: the layering guard and a value shown in an
editor.
"""
const test_display = TestSuite("ProjecturedPlatform", [
    test_editor_display,
])

export test_display, test_editor_display
