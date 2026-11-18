"""Syntax-check every addon Lua file + the secure snippet with Lua 5.1, and test Geometry."""
import pathlib, sys
from lupa import lua51

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1])
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
check = lua.eval("function(src, name) local f, err = loadstring(src, name); return f ~= nil, err end")

VALID_ESCAPES = set("abfnrtv\\\"'\n0123456789")


def bad_escapes(src):
    r"""Backslash escapes in quoted strings that Lua 5.1 silently drops: "Interface\Buttons" loads
    as "InterfaceButtons", so a texture path written with single backslashes just doesn't show.
    Yields (line, escape)."""
    i, line = 0, 1
    while i < len(src):
        c = src[i]
        if c == "\n":
            line += 1
        if src.startswith("--", i):  # comment: skip to the end of the line
            while i < len(src) and src[i] != "\n":
                i += 1
            continue
        if src.startswith("[[", i) or src.startswith("[=", i):  # long string: no escapes
            level = 0
            while src[i + 1 + level] == "=":
                level += 1
            close = "]" + "=" * level + "]"
            end = src.find(close, i + 2 + level)
            end = len(src) if end < 0 else end
            line += src.count("\n", i, end)
            i = end + len(close)
            continue
        if c in "\"'":
            j = i + 1
            while j < len(src) and src[j] != c and src[j] != "\n":
                if src[j] == "\\":
                    if j + 1 < len(src) and src[j + 1] not in VALID_ESCAPES:
                        yield line, "\\" + src[j + 1]
                    j += 2
                    continue
                j += 1
            i = j + 1
            continue
        i += 1


ok = True
for p in sorted(root.rglob("*.lua")):
    src = p.read_text(encoding="utf-8")
    good, err = check(src, "@" + str(p.relative_to(root)))
    if good:
        bad = list(bad_escapes(src))
        if bad:
            good, err = False, "; ".join(f"line {n}: {esc} is dropped by Lua (write \\\\ for a backslash)" for n, esc in bad)
    print(("OK   " if good else "FAIL ") + str(p.relative_to(root)) + ("" if good else f"  {err}"))
    ok &= bool(good)

# Extract the snippet string by running Snippets.lua with a fake ns, then compile its body.
snip = lua.eval("""function(src)
  local ns = {}
  local f = assert(loadstring(src)); f(nil, ns)
  return ns.Snippets
end""")((root / "Jest/Secure/Snippets.lua").read_text(encoding="utf-8"))
for name in ("OnClick", "OnPage"):
    good, err = check("local self, button, down = ...\n" + snip[name], "@snippet." + name)
    print(("OK   " if good else "FAIL ") + "snippet " + name + ("" if good else f"  {err}"))
    ok &= bool(good)

# Geometry: compare against the snippet's formula and expected directions.
geo = lua.execute((root / "Jest/UI/Geometry.lua").read_text(encoding="utf-8"))
cases = [  # dx, dy, n, dz, expected
    (0, 100, 8, 28, 1), (100, 100, 8, 28, 2), (100, 0, 8, 28, 3), (100, -100, 8, 28, 4),
    (0, -100, 8, 28, 5), (-100, -100, 8, 28, 6), (-100, 0, 8, 28, 7), (-100, 100, 8, 28, 8),
    (5, 5, 8, 28, None), (0, 100, 4, 28, 1), (100, 0, 4, 28, 2), (-1, 100, 8, 28, 1),
    (100, 0, 12, 28, 4), (0, 29, 8, 28, 1),
]
for dx, dy, n, dz, want in cases:
    got = geo.SliceAt(dx, dy, n, dz)
    if got != want:
        ok = False
        print(f"FAIL SliceAt({dx},{dy},{n},{dz}) = {got}, want {want}")
# Round trip: every slice centre maps back to its own index.
for n in range(1, 13):
    for i in range(1, n + 1):
        x, y = geo.SlicePosition(i, n, 110)
        if geo.SliceAt(x, y, n, 28) != i:
            ok = False
            print(f"FAIL round-trip n={n} i={i}")
print("Geometry tests", "passed" if ok else "had failures")
sys.exit(0 if ok else 1)
