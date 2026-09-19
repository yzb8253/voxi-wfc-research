import json
import sys
from pathlib import Path


def load():
    return json.loads(Path("voxi_wfc_research/phase3/private_jars_scan.json").read_text(encoding="utf-8"))


def show_classes(data, queries):
    print("TOTAL_CLASSES", len(data))
    for q in queries:
        print(f"--- {q}")
        for c in data:
            if q.lower() in c["class"].lower():
                print(c["jar"], c["class"], "methods", len(c["methods"]), "fields", len(c["fields"]))


def dump_interfaces(data, names):
    for c in data:
        if any(name in c["class"] for name in names):
            print()
            print("CLASS", c["jar"], c["class"])
            print("  access", ",".join(c["access_flags"]))
            print("  super", c["super"])
            print("  interfaces", ", ".join(c["interfaces"]))
            for f in c["fields"]:
                val = f.get("static_value", "")
                print("  FIELD", ",".join(f["access_flags"]), f["type"], f["name"], val)
            for m in c["methods"]:
                print("  METHOD", ",".join(m["access_flags"]), m["signature"])


def search_methods(data, terms):
    terms_l = [t.lower() for t in terms]
    for c in data:
        hits = []
        for m in c["methods"]:
            hay = (c["class"] + " " + m["signature"]).lower()
            if any(t in hay for t in terms_l):
                hits.append(m)
        if hits:
            print()
            print("CLASS", c["jar"], c["class"])
            for m in hits:
                print("  METHOD", ",".join(m["access_flags"]), m["signature"])


def main():
    data = load()
    mode = sys.argv[1]
    if mode == "classes":
        show_classes(data, sys.argv[2:])
    elif mode == "interfaces":
        dump_interfaces(data, sys.argv[2:])
    elif mode == "methods":
        search_methods(data, sys.argv[2:])
    else:
        raise SystemExit(f"unknown mode {mode}")


if __name__ == "__main__":
    main()
