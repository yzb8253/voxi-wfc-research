import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "phase3"))
from dex_scan import Dex, jtype  # noqa: E402
from method_refs import code_refs  # noqa: E402


def main() -> None:
    apk = Path(sys.argv[1])
    terms = tuple(term.lower() for term in sys.argv[2:])
    hits = 0
    with zipfile.ZipFile(apk) as archive:
        for dex_name in (name for name in archive.namelist() if name.endswith(".dex")):
            dex = Dex(archive.read(dex_name))
            for cls in dex.classes:
                for method in cls["methods"]:
                    for offset, kind, owner, signature in code_refs(dex, method):
                        haystack = f"{owner} {signature}".lower()
                        if any(term in haystack for term in terms):
                            hits += 1
                            print(
                                f"{dex_name}\t{cls['name']}\t{method['name']}\t"
                                f"@{offset:04x}\t{kind}\t{owner}\t{signature}"
                            )
    print(f"MATCH_COUNT={hits}")


if __name__ == "__main__":
    main()
