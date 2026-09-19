import sys
from pathlib import Path

from dex_scan import Dex, jtype, load_dexes, method_sig


INVOKE_OPS = set(range(0x6E, 0x73)) | set(range(0x74, 0x79))
FIELD_OPS = set(range(0x52, 0x6E))


def u2(data, off):
    return int.from_bytes(data[off:off + 2], "little")


def insn_size(code_units, i):
    op = code_units[i] & 0xff
    if op == 0x00:
        hi = code_units[i] >> 8
        if hi == 0:
            return 1
        if hi == 1:
            return 2 + code_units[i + 1] * 2
        if hi == 2:
            return 4 + code_units[i + 1] * 2
        if hi == 3:
            return 2 + code_units[i + 1] * 4
        return 1
    one = {
        0x01, 0x04, 0x07, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e,
        0x0f, 0x10, 0x11, 0x12, 0x1d, 0x1e, 0x21, 0x27,
        0x28,
    } | set(range(0x7b, 0x90)) | set(range(0xb0, 0xd0))
    two = {
        0x02, 0x05, 0x08, 0x13, 0x15, 0x16, 0x19, 0x1a,
        0x1c, 0x1f, 0x20, 0x22, 0x23, 0x29,
    } | set(range(0x2d, 0x3e)) | set(range(0x44, 0x6e)) | set(range(0x90, 0xb0)) | set(range(0xd0, 0xe3))
    three = {
        0x03, 0x06, 0x09, 0x14, 0x17, 0x1b, 0x24, 0x25,
        0x26, 0x2a, 0x2b, 0x2c,
    } | set(range(0x6e, 0x73)) | set(range(0x74, 0x79))
    five = {0x18}
    if op in one:
        return 1
    if op in two:
        return 2
    if op in three:
        return 3
    if op in five:
        return 5
    return 1


def code_refs(dx, m):
    off = m.get("code_off") or 0
    if not off:
        return []
    data = dx.data
    insns_size = int.from_bytes(data[off + 12:off + 16], "little")
    p = off + 16
    code_units = [u2(data, p + i * 2) for i in range(insns_size)]
    refs = []
    i = 0
    while i < insns_size:
        op = code_units[i] & 0xff
        try:
            if op in INVOKE_OPS and i + 1 < insns_size:
                idx = code_units[i + 1]
                if idx < len(dx.methods):
                    tm = dx.methods[idx]
                    refs.append((i, "invoke", jtype(tm["class"]), method_sig(tm)))
            elif op in FIELD_OPS and i + 1 < insns_size:
                idx = code_units[i + 1]
                if idx < len(dx.fields):
                    f = dx.fields[idx]
                    refs.append((i, "field", jtype(f["class"]), f"{jtype(f['type'])} {f['name']}"))
            elif op == 0x1a and i + 1 < insns_size:
                idx = code_units[i + 1]
                if idx < len(dx.strings):
                    refs.append((i, "string", "", dx.strings[idx]))
            elif op == 0x1b and i + 2 < insns_size:
                idx = code_units[i + 1] | (code_units[i + 2] << 16)
                if idx < len(dx.strings):
                    refs.append((i, "string", "", dx.strings[idx]))
        except Exception as exc:
            refs.append((i, "error", "", repr(exc)))
        i += insn_size(code_units, i)
    return refs


def main():
    target_dir = Path(sys.argv[1])
    class_terms = [x.lower() for x in sys.argv[2].split(",")]
    method_terms = [x.lower() for x in sys.argv[3].split(",")]
    files = sorted(list(target_dir.glob("*.jar")) + list(target_dir.glob("*.apk")))
    for f in files:
        for dex_name, data in load_dexes(f):
            dx = Dex(data)
            for cls in dx.classes:
                if not any(t in cls["name"].lower() for t in class_terms):
                    continue
                for m in cls["methods"]:
                    if not any(t in m["name"].lower() for t in method_terms):
                        continue
                    print()
                    print(f"METHOD {f.name} {cls['name']} :: {method_sig(m)}")
                    seen = set()
                    for offset, kind, owner, sig in code_refs(dx, m):
                        key = (offset, kind, owner, sig)
                        if key in seen:
                            continue
                        seen.add(key)
                        if kind == "string" and len(sig) > 160:
                            sig = sig[:157] + "..."
                        print(f"  @{offset:04x} {kind}: {owner} {sig}")


if __name__ == "__main__":
    main()
