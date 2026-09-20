# L1.5 Executor Build Report

Date: 2026-09-20
Branch baseline: `voxi-wfc-auto-recovery` at `527b1b59380e46f13a71704162cc55ba1d78ea43`

## Toolchain

- Git: 2.55.0.windows.3
- JDK: Eclipse Temurin OpenJDK 21.0.12.1 LTS
- javac/jar: 21.0.12.1
- Android build-tools: 37.0.0, downloaded from the official Google Android repository
- Official build-tools archive SHA-1: `e9c97e26b5b5678002e9d3fed632c841ae62d99f` (matched repository metadata)
- D8: 9.2.4-dev, build `084a89126ae0596c599143df57a654646af28313`

## Build

- `javac --release 8`: PASS (deprecation warnings only)
- D8 `--min-api 26`: PASS
- Final JAR packaging with JDK `jar`: PASS
- Artifact: `build/slot1-sim-power-helper.jar` (locally generated and git-ignored)
- JAR SHA256: `be877b6e9694b4100f2487dc892803de6399c89588f194a1e54d4c3ae3173a31`
- JAR entries: `META-INF/MANIFEST.MF`, `classes.dex`

The build driver was corrected to use the JDK `jar` tool for the final archive because Windows PowerShell `Compress-Archive` rejects a `.jar` destination extension.
