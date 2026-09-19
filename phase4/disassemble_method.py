import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "phase3"))
from dex_scan import Dex, jtype, uleb  # noqa: E402


FMT = {
    0x0a: "move-result",
    0x0b: "move-result-wide",
    0x0c: "move-result-object",
    0x0e: "return-void",
    0x0f: "return",
    0x10: "return-wide",
    0x11: "return-object",
    0x12: "const/4",
    0x13: "const/16",
    0x14: "const",
    0x1a: "const-string",
    0x1b: "const-string/jumbo",
    0x1c: "const-class",
    0x1f: "check-cast",
    0x20: "instance-of",
    0x21: "array-length",
    0x22: "new-instance",
    0x23: "new-array",
    0x28: "goto",
    0x29: "goto/16",
    0x2a: "goto/32",
    0x32: "if-eq",
    0x33: "if-ne",
    0x34: "if-lt",
    0x35: "if-ge",
    0x36: "if-gt",
    0x37: "if-le",
    0x38: "if-eqz",
    0x39: "if-nez",
    0x3a: "if-ltz",
    0x3b: "if-gez",
    0x3c: "if-gtz",
    0x3d: "if-lez",
    0x52: "iget",
    0x53: "iget-wide",
    0x54: "iget-object",
    0x55: "iget-boolean",
    0x60: "sget",
    0x61: "sget-wide",
    0x62: "sget-object",
    0x63: "sget-boolean",
    0x6e: "invoke-virtual",
    0x6f: "invoke-super",
    0x70: "invoke-direct",
    0x71: "invoke-static",
    0x72: "invoke-interface",
    0x74: "invoke-virtual/range",
    0x75: "invoke-super/range",
    0x76: "invoke-direct/range",
    0x77: "invoke-static/range",
    0x78: "invoke-interface/range",
}


def read_s2(insns, i):
    v = insns[i]
    return v - 0x10000 if v & 0x8000 else v


def method_ref(dx, idx):
    m = dx.methods[idx]
    params = ",".join(jtype(p) for p in m["params"])
    return f"{jtype(m['return'])} {jtype(m['class'])}.{m['name']}({params})"


def field_ref(dx, idx):
    f = dx.fields[idx]
    return f"{jtype(f['type'])} {jtype(f['class'])}.{f['name']}"


def find_method(dx, cls_name, method_name):
    for cls in dx.classes:
        if cls["name"] == cls_name:
            for m in cls["methods"]:
                if m["name"] == method_name:
                    return m
    raise SystemExit(f"method not found: {cls_name}.{method_name}")


def code_units(dx, code_off):
    d = dx.data
    registers_size = dx.u2(code_off)
    ins_size = dx.u2(code_off + 2)
    outs_size = dx.u2(code_off + 4)
    tries_size = dx.u2(code_off + 6)
    debug_info_off = dx.u4(code_off + 8)
    insns_size = dx.u4(code_off + 12)
    start = code_off + 16
    insns = [dx.u2(start + i * 2) for i in range(insns_size)]
    return registers_size, ins_size, outs_size, tries_size, debug_info_off, insns


def dump(dx, m):
    regs, ins_size, outs, tries, dbg, insns = code_units(dx, m["code_off"])
    print(f"{m['name']} code_off=0x{m['code_off']:x} regs={regs} ins={ins_size} outs={outs} tries={tries}")
    i = 0
    while i < len(insns):
        u = insns[i]
        op = u & 0xff
        name = FMT.get(op, f"op_{op:02x}")
        text = ""
        size = 1
        if op in (0x12,):
            a = (u >> 8) & 0x0f
            b = (u >> 12) & 0x0f
            if b & 0x8:
                b -= 0x10
            text = f"v{a}, #{b}"
        elif op in (0x13, 0x1a, 0x1c, 0x22):
            a = (u >> 8) & 0xff
            idx = insns[i + 1]
            size = 2
            if op == 0x1a:
                text = f"v{a}, string@{idx} \"{dx.strings[idx]}\""
            elif op == 0x1c or op == 0x22:
                text = f"v{a}, type@{idx} {jtype(dx.types[idx])}"
            else:
                text = f"v{a}, #{read_s2(insns, i + 1)}"
        elif op in (0x54, 0x63):
            a = (u >> 8) & 0x0f
            b = (u >> 12) & 0x0f
            idx = insns[i + 1]
            size = 2
            if op == 0x63:
                text = f"v{a}, field@{idx} {field_ref(dx, idx)}"
            else:
                text = f"v{a}, v{b}, field@{idx} {field_ref(dx, idx)}"
        elif 0x6e <= op <= 0x72:
            g = (u >> 8) & 0x0f
            count = (u >> 12) & 0x0f
            idx = insns[i + 1]
            regs_word = insns[i + 2]
            regs_list = [regs_word & 0xf, (regs_word >> 4) & 0xf, (regs_word >> 8) & 0xf, (regs_word >> 12) & 0xf, g][:count]
            size = 3
            text = f"{{{', '.join('v'+str(r) for r in regs_list)}}}, method@{idx} {method_ref(dx, idx)}"
        elif 0x74 <= op <= 0x78:
            count = (u >> 8) & 0xff
            idx = insns[i + 1]
            start = insns[i + 2]
            size = 3
            text = f"{{v{start}..v{start+count-1}}}, method@{idx} {method_ref(dx, idx)}"
        elif op in (0x0a, 0x0b, 0x0c, 0x0f, 0x10, 0x11):
            a = (u >> 8) & 0xff
            text = f"v{a}"
        elif 0x32 <= op <= 0x37:
            a = (u >> 8) & 0x0f
            b = (u >> 12) & 0x0f
            off = read_s2(insns, i + 1)
            size = 2
            text = f"v{a}, v{b}, -> {i + off:04x}"
        elif 0x38 <= op <= 0x3d:
            a = (u >> 8) & 0xff
            off = read_s2(insns, i + 1)
            size = 2
            text = f"v{a}, -> {i + off:04x}"
        elif op == 0x28:
            off = (u >> 8) & 0xff
            if off & 0x80:
                off -= 0x100
            text = f"-> {i + off:04x}"
        elif op == 0x29:
            off = read_s2(insns, i + 1)
            size = 2
            text = f"-> {i + off:04x}"
        print(f"{i:04x}: {name:22} {text}")
        i += size


def main():
    apk = Path(sys.argv[1])
    cls_name = sys.argv[2]
    method_name = sys.argv[3]
    with zipfile.ZipFile(apk) as z:
        for name in z.namelist():
            if name.endswith(".dex"):
                dx = Dex(z.read(name))
                try:
                    m = find_method(dx, cls_name, method_name)
                    print(f"dex={name}")
                    dump(dx, m)
                    return
                except SystemExit:
                    pass
    raise SystemExit("not found")


if __name__ == "__main__":
    main()
