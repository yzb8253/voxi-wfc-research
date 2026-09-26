# Golden Baseline

## Reproducibility anchor

- Commit: `dfd82415073470691295547d39753f6172054748` (`dfd8241`)
- Historical result: 6/6 controlled recovery successes on the original tested device
- Launcher: `experiments/wfc_repeatability_normalization/v262_freeze_run/RUN-X55-WFC-STABLE-v1.cmd`
- Wrapper: `X55-WFC-STABLE-v1.ps1`
- Core: `X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1`

Golden means this exact source epoch and its recorded behavior. It does not mean newest, portable, universally safe or guaranteed.

## Tested environment

Xiaomi Mi 10 (`cas`), Android 13 / HyperOS `V816.0.4.0.TJJCNXM`, Qualcomm X55/SDX55M, VOXI/Vodafone UK (`23415`), Windows PowerShell 5.1, ADB and root. Success was observed on the original device under both single-SIM and dual-SIM configurations.

## Historical host dependency

The Golden source references `C:\Users\ZJH\Desktop\platform-tools\adb.exe`. To reproduce Golden without changing it, provide a compatible path/environment. Editing the source creates a derivative experiment and must be labeled accordingly.

## Reproduction

```powershell
git fetch --all --tags
git worktree add ..\voxi-wfc-golden dfd82415073470691295547d39753f6172054748
& '..\voxi-wfc-golden\experiments\wfc_repeatability_normalization\v262_freeze_run\RUN-X55-WFC-STABLE-v1.cmd'
```

Before running, verify the exact platform and subscription mapping, record a read-only baseline, review `docs/SAFETY.md`, and ensure emergency rollback is understood. Do not modify the Golden worktree.

## Success predicate

Success requires IMS `REGISTERED(2)`, transport `WLAN(2)`, MMTEL voice over IWLAN available, and direct WFC availability true. CNE, NetworkAgent, UDP/4500 and XFRM are supporting signals.

## Provenance rule

Later fixes and experiments do not retroactively alter Golden. If a newer branch is useful, cite both its commit and the Golden commit and state exactly what changed.
