#!/usr/bin/env python3
"""Release-safety guard for App Store review.

Scans every Swift file compiled into the shipping app (the app target and the SkyCore
library, not tests) for code that App Review's automated checks treat as suspicious:
screenshot/demo modes with canned data, launch-argument or environment switches,
simulator-only behaviour, private API access and runtime tricks, and dynamic code loading.

Such code is only allowed inside `#if DEBUG ... #endif`, so it never compiles into a
Release build. Exits non-zero, listing each offending line, if anything is found outside
a DEBUG block.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHIPPED = [ROOT / "StellarNavigator", ROOT / "SkyCore" / "Sources"]

RULES = [
    (r"screenshot|snapshot", "screenshot/snapshot code"),
    (r"\bdemo\b|demoMode|sampleData|fakeData|\bmock|\bstub", "demo/mock/fake data"),
    (r"fastlane|UITest|XCUI|XCTest", "UI-test or screenshot-automation hook"),
    (r"ProcessInfo|CommandLine\.arguments|launchArguments|launchEnvironment|getenv\(",
     "behaviour switched by launch arguments or environment"),
    (r"targetEnvironment\(simulator\)|TARGET_OS_SIMULATOR|SIMULATOR_", "simulator-only behaviour"),
    (r"dlopen|dlsym|NSClassFromString|NSSelectorFromString|performSelector|objc_getClass|"
     r"method_exchangeImplementations|class_replaceMethod|\b_UI[A-Z]|valueForKey\(\"_",
     "private API or runtime trick"),
    (r"JSContext|\beval\(|Bundle\(path:", "dynamic code loading"),
]
COMPILED = [(re.compile(p, re.IGNORECASE), why) for p, why in RULES]


def violations(path):
    debug_depth = 0       # >0 while inside an #if DEBUG block
    stack = []            # one entry per open #if: True if it is a DEBUG block
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        s = line.strip()
        if s.startswith("#if"):
            is_debug = bool(re.match(r"#if\s+DEBUG\b", s))
            stack.append(is_debug)
            debug_depth += is_debug
            continue
        if s.startswith("#else") or s.startswith("#elseif"):
            # The #else of an #if DEBUG compiles into Release.
            if stack and stack[-1]:
                debug_depth -= 1
                stack[-1] = False
            continue
        if s.startswith("#endif"):
            if stack:
                debug_depth -= stack.pop()
            continue
        if debug_depth > 0:
            continue
        code = re.sub(r"//.*", "", line)          # ignore comments
        for rx, why in COMPILED:
            if rx.search(code):
                yield n, why, s


def main():
    found = 0
    files = sorted(p for d in SHIPPED for p in d.rglob("*.swift"))
    for f in files:
        for n, why, src in violations(f):
            found += 1
            print(f"{f.relative_to(ROOT)}:{n}: {why} outside #if DEBUG\n    {src}")
    if found:
        print(f"\n{found} problem(s). Move this code inside `#if DEBUG ... #endif` "
              "so it is not compiled into Release builds.")
        return 1
    print(f"Release code check passed ({len(files)} shipped Swift files).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
