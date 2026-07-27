#!/usr/bin/env python3
"""Verify every Localizable.strings agrees with en.lproj on keys and format specifiers.

Two failure modes this catches, neither of which `swift build` can see:

1. **Key drift.** A key present in en.lproj but missing elsewhere silently renders as the
   raw key string at runtime, because LanguageManager.t() passes `value: key` as the
   fallback. The UI shows "settings.general.cancel" instead of a word, and nothing logs.

2. **Format specifier drift.** LanguageManager.t(_:_:) feeds the looked-up string to
   String(format:arguments:) with CVarArg values. If a translation drops a %@, adds one,
   or swaps %@ for %lld, String(format:) reads arguments that were never pushed — garbage
   output at best, a crash at worst. This is the likeliest defect when translations are
   written in bulk, and it only shows up on the screen that uses that one string.

Usage: python3 scripts/check-localization.py   (exit 0 = clean, 1 = mismatch)
"""

import io
import pathlib
import re
import sys

RESOURCES = pathlib.Path(__file__).resolve().parent.parent / "Sources/DevIslandApp/Resources"
REFERENCE = "en"

# "key" = "value";  — values may contain escaped quotes.
ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')

# printf-style conversions. %% is a literal percent and consumes no argument, so it is
# excluded — a translation may legitimately add or drop one.
SPECIFIER = re.compile(r"%(?:\d+\$)?[-+ #0']*[\d*]*(?:\.[\d*]+)?(?:hh|h|ll|l|q|L|z|j|t)?[@a-zA-Z]")


def parse(path):
    text = io.open(path, encoding="utf-8").read()
    return {m.group(1): m.group(2) for m in ENTRY.finditer(text)}


def specifiers(value):
    """Ordered conversion sequence. Order matters: without positional (%1$@) markers,
    String(format:) binds arguments left to right, so reordering changes meaning."""
    return SPECIFIER.findall(value)


def main():
    bundles = sorted(p.name[: -len(".lproj")] for p in RESOURCES.glob("*.lproj"))
    if REFERENCE not in bundles:
        print(f"FAIL: no {REFERENCE}.lproj in {RESOURCES}")
        return 1

    ref = parse(RESOURCES / f"{REFERENCE}.lproj/Localizable.strings")
    print(f"reference {REFERENCE}.lproj: {len(ref)} keys")

    failures = 0
    for name in bundles:
        if name == REFERENCE:
            continue
        other = parse(RESOURCES / f"{name}.lproj/Localizable.strings")

        missing = sorted(set(ref) - set(other))
        extra = sorted(set(other) - set(ref))
        drift = [
            (k, specifiers(ref[k]), specifiers(other[k]))
            for k in sorted(set(ref) & set(other))
            if specifiers(ref[k]) != specifiers(other[k])
        ]

        status = "ok" if not (missing or extra or drift) else "FAIL"
        print(f"{status:>4}  {name}.lproj: {len(other)} keys")
        for k in missing:
            print(f"        missing key: {k}")
        for k in extra:
            print(f"        extra key:   {k}")
        for k, want, got in drift:
            print(f"        specifier drift on {k}: {REFERENCE}={want} {name}={got}")
        failures += bool(missing or extra or drift)

    if failures:
        print(f"\n{failures} bundle(s) out of sync")
        return 1
    print("\nall bundles in sync")
    return 0


if __name__ == "__main__":
    sys.exit(main())
