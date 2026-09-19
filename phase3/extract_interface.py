import json
import sys
from pathlib import Path

data = json.loads(Path("voxi_wfc_research/phase3/private_jars_scan.json").read_text(encoding="utf-8"))
terms = [t.lower() for t in sys.argv[1:]]
for c in data:
    if not any(t in c["class"].lower() for t in terms):
        continue
    print()
    print("CLASS", c["jar"], c["class"])
    print("SUPER", c["super"])
    print("INTERFACES", ", ".join(c["interfaces"]))
    for f in c["fields"]:
        if f["name"].startswith("TRANSACTION_") or f["name"] == "DESCRIPTOR":
            print("FIELD", ",".join(f["access_flags"]), f["type"], f["name"], f.get("static_value", ""))
    for m in c["methods"]:
        print("METHOD", ",".join(m["access_flags"]), m["signature"])
