import json
import struct
import sys
import zipfile
from pathlib import Path


ACC = {
    0x1: "public",
    0x2: "private",
    0x4: "protected",
    0x8: "static",
    0x10: "final",
    0x20: "synchronized",
    0x40: "volatile/bridge",
    0x80: "transient/varargs",
    0x100: "native",
    0x200: "interface",
    0x400: "abstract",
    0x800: "strict",
    0x1000: "synthetic",
    0x2000: "annotation",
    0x4000: "enum",
    0x10000: "constructor",
    0x20000: "declared_synchronized",
}


def uleb(data, off):
    result = 0
    shift = 0
    while True:
        b = data[off]
        off += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            return result, off
        shift += 7


def sleb(data, off):
    result = 0
    shift = 0
    size = 32
    while True:
        b = data[off]
        off += 1
        result |= (b & 0x7F) << shift
        shift += 7
        if not (b & 0x80):
            if (shift < size) and (b & 0x40):
                result |= -(1 << shift)
            return result, off


def read_string(data, off):
    _, off = uleb(data, off)
    end = data.index(0, off)
    return data[off:end].decode("utf-8", errors="replace")


def access_flags(flags):
    return [name for bit, name in ACC.items() if flags & bit]


def jtype(desc):
    arrays = 0
    while desc.startswith("["):
        arrays += 1
        desc = desc[1:]
    base = {
        "V": "void",
        "Z": "boolean",
        "B": "byte",
        "S": "short",
        "C": "char",
        "I": "int",
        "J": "long",
        "F": "float",
        "D": "double",
    }.get(desc)
    if base is None:
        if desc.startswith("L") and desc.endswith(";"):
            base = desc[1:-1].replace("/", ".")
        else:
            base = desc
    return base + "[]" * arrays


def parse_encoded_value(data, off):
    b = data[off]
    off += 1
    value_type = b & 0x1F
    arg = b >> 5
    if value_type == 0x1c:
        count, off = uleb(data, off)
        arr = []
        for _ in range(count):
            item, off = parse_encoded_value(data, off)
            arr.append(item)
        return arr, off
    if value_type == 0x1d:
        count, off = uleb(data, off)
        vals = {}
        for _ in range(count):
            name_idx, off = uleb(data, off)
            item, off = parse_encoded_value(data, off)
            vals[str(name_idx)] = item
        return vals, off
    if value_type == 0x1e:
        return None, off
    if value_type == 0x1f:
        return bool(arg), off
    size = arg + 1
    raw = data[off:off + size]
    off += size
    val = None
    if value_type in (0x00, 0x02, 0x03, 0x04, 0x06, 0x10, 0x11):
        signed = value_type not in (0x03, 0x04)
        val = int.from_bytes(raw, "little", signed=False)
        if signed and raw and (raw[-1] & 0x80):
            val -= 1 << (8 * size)
    elif value_type == 0x17:
        val = "string@" + str(int.from_bytes(raw, "little"))
    elif value_type == 0x18:
        val = "type@" + str(int.from_bytes(raw, "little"))
    elif value_type == 0x19:
        val = "field@" + str(int.from_bytes(raw, "little"))
    elif value_type == 0x1a:
        val = "method@" + str(int.from_bytes(raw, "little"))
    elif value_type == 0x1b:
        val = "enum@" + str(int.from_bytes(raw, "little"))
    else:
        val = f"encoded_type_{value_type}_raw_{raw.hex()}"
    return val, off


class Dex:
    def __init__(self, data):
        self.data = data
        self.parse()

    def u4(self, off):
        return struct.unpack_from("<I", self.data, off)[0]

    def u2(self, off):
        return struct.unpack_from("<H", self.data, off)[0]

    def parse(self):
        d = self.data
        self.string_ids_size = self.u4(56)
        self.string_ids_off = self.u4(60)
        self.type_ids_size = self.u4(64)
        self.type_ids_off = self.u4(68)
        self.proto_ids_size = self.u4(72)
        self.proto_ids_off = self.u4(76)
        self.field_ids_size = self.u4(80)
        self.field_ids_off = self.u4(84)
        self.method_ids_size = self.u4(88)
        self.method_ids_off = self.u4(92)
        self.class_defs_size = self.u4(96)
        self.class_defs_off = self.u4(100)

        self.strings = []
        for i in range(self.string_ids_size):
            off = self.u4(self.string_ids_off + i * 4)
            self.strings.append(read_string(d, off))

        self.types = []
        for i in range(self.type_ids_size):
            self.types.append(self.strings[self.u4(self.type_ids_off + i * 4)])

        self.protos = []
        for i in range(self.proto_ids_size):
            off = self.proto_ids_off + i * 12
            shorty = self.strings[self.u4(off)]
            ret = self.types[self.u4(off + 4)]
            params_off = self.u4(off + 8)
            params = []
            if params_off:
                size = self.u4(params_off)
                p = params_off + 4
                for _ in range(size):
                    params.append(self.types[self.u2(p)])
                    p += 2
            self.protos.append((shorty, ret, params))

        self.fields = []
        for i in range(self.field_ids_size):
            off = self.field_ids_off + i * 8
            class_idx = self.u2(off)
            type_idx = self.u2(off + 2)
            name_idx = self.u4(off + 4)
            self.fields.append({
                "class": self.types[class_idx],
                "type": self.types[type_idx],
                "name": self.strings[name_idx],
            })

        self.methods = []
        for i in range(self.method_ids_size):
            off = self.method_ids_off + i * 8
            class_idx = self.u2(off)
            proto_idx = self.u2(off + 2)
            name_idx = self.u4(off + 4)
            shorty, ret, params = self.protos[proto_idx]
            self.methods.append({
                "class": self.types[class_idx],
                "name": self.strings[name_idx],
                "return": ret,
                "params": params,
                "shorty": shorty,
            })

        self.classes = []
        for i in range(self.class_defs_size):
            off = self.class_defs_off + i * 32
            class_idx = self.u4(off)
            access = self.u4(off + 4)
            super_idx = self.u4(off + 8)
            interfaces_off = self.u4(off + 12)
            source_idx = self.u4(off + 16)
            annotations_off = self.u4(off + 20)
            class_data_off = self.u4(off + 24)
            static_values_off = self.u4(off + 28)
            interfaces = []
            if interfaces_off:
                n = self.u4(interfaces_off)
                p = interfaces_off + 4
                for _ in range(n):
                    interfaces.append(self.types[self.u2(p)])
                    p += 2
            cls = {
                "type": self.types[class_idx],
                "name": jtype(self.types[class_idx]),
                "access_flags": access_flags(access),
                "super": None if super_idx == 0xFFFFFFFF else self.types[super_idx],
                "interfaces": interfaces,
                "source": None if source_idx == 0xFFFFFFFF else self.strings[source_idx],
                "fields": [],
                "methods": [],
            }
            static_field_count = 0
            if class_data_off:
                p = class_data_off
                static_fields_size, p = uleb(d, p)
                instance_fields_size, p = uleb(d, p)
                direct_methods_size, p = uleb(d, p)
                virtual_methods_size, p = uleb(d, p)
                static_field_count = static_fields_size
                for kind, count in (("static", static_fields_size), ("instance", instance_fields_size)):
                    field_idx = 0
                    for _ in range(count):
                        diff, p = uleb(d, p)
                        field_idx += diff
                        acc, p = uleb(d, p)
                        f = dict(self.fields[field_idx])
                        f["kind"] = kind
                        f["access_flags"] = access_flags(acc)
                        cls["fields"].append(f)
                for kind, count in (("direct", direct_methods_size), ("virtual", virtual_methods_size)):
                    method_idx = 0
                    for _ in range(count):
                        diff, p = uleb(d, p)
                        method_idx += diff
                        acc, p = uleb(d, p)
                        code_off, p = uleb(d, p)
                        m = dict(self.methods[method_idx])
                        m["kind"] = kind
                        m["access_flags"] = access_flags(acc)
                        m["code_off"] = code_off
                        cls["methods"].append(m)
            if static_values_off and static_field_count:
                vals = []
                p = static_values_off
                n, p = uleb(d, p)
                for _ in range(n):
                    val, p = parse_encoded_value(d, p)
                    vals.append(val)
                for idx, val in enumerate(vals):
                    if idx < len(cls["fields"]):
                        cls["fields"][idx]["static_value"] = val
            self.classes.append(cls)


def load_dexes(path):
    b = Path(path).read_bytes()
    if b[:3] == b"dex":
        return [("classes.dex", b)]
    out = []
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if name.endswith(".dex"):
                out.append((name, z.read(name)))
    return out


def method_sig(m):
    params = ", ".join(jtype(p) for p in m["params"])
    return f"{jtype(m['return'])} {m['name']}({params})"


def main():
    jar_dir = Path(sys.argv[1])
    out_path = None
    args = sys.argv[2:]
    if args and args[0] == "--out":
        out_path = Path(args[1])
        args = args[2:]
    keywords = [s.lower() for s in args]
    results = []
    files = sorted(list(jar_dir.glob("*.jar")) + list(jar_dir.glob("*.apk")))
    for jar in files:
        for dex_name, data in load_dexes(jar):
            dx = Dex(data)
            for cls in dx.classes:
                hay_cls = (cls["name"] + " " + " ".join(cls["interfaces"]) + " " + str(cls["source"])).lower()
                class_hit = any(k in hay_cls for k in keywords)
                method_hits = []
                field_hits = []
                for m in cls["methods"]:
                    hay = (cls["name"] + " " + m["name"] + " " + " ".join(m["params"]) + " " + m["return"]).lower()
                    if class_hit or any(k in hay for k in keywords):
                        method_hits.append({
                            "name": m["name"],
                            "signature": method_sig(m),
                            "return": jtype(m["return"]),
                            "params": [jtype(p) for p in m["params"]],
                            "access_flags": m["access_flags"],
                            "kind": m["kind"],
                            "code_off": m["code_off"],
                        })
                for f in cls["fields"]:
                    hay = (cls["name"] + " " + f["name"] + " " + f["type"]).lower()
                    if class_hit or any(k in hay for k in keywords):
                        item = {
                            "name": f["name"],
                            "type": jtype(f["type"]),
                            "access_flags": f["access_flags"],
                            "kind": f["kind"],
                        }
                        if "static_value" in f:
                            item["static_value"] = f["static_value"]
                        field_hits.append(item)
                if class_hit or method_hits or field_hits:
                    results.append({
                        "jar": jar.name,
                        "dex": dex_name,
                        "class": cls["name"],
                        "descriptor": cls["type"],
                        "source": cls["source"],
                        "access_flags": cls["access_flags"],
                        "super": None if cls["super"] is None else jtype(cls["super"]),
                        "interfaces": [jtype(x) for x in cls["interfaces"]],
                        "fields": field_hits,
                        "methods": method_hits,
                    })
    text = json.dumps(results, ensure_ascii=False, indent=2)
    if out_path:
        out_path.write_text(text, encoding="utf-8")
    else:
        print(text)


if __name__ == "__main__":
    main()
