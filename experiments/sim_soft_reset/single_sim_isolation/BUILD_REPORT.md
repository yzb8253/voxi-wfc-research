# Single-SIM Helper Build Report

Date: 2026-09-20

- Fixed target: slot 1 / phoneId 1 / subId 11 / carrierId 28 / MCCMNC 23415.
- Protection condition: slot0 has no active subscription and SIM state is ABSENT.
- JDK: Temurin 21.0.12.1.
- Android build-tools/D8: 37.0.0.
- javac --release 8: PASS.
- D8 min API 26: PASS.
- Source/static write-path audit: PASS.
- DEX class and API-symbol inspection: PASS.
- Artifact: `experiments/sim_soft_reset/single_sim_isolation/build/single-sim-slot1-power-helper.jar`.
- Size: 11534 bytes.
- SHA256: `90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39`.
- Provenance: Computer A existing audited artifact, independently re-hashed before Git tracking.
- Purpose: fixed single-SIM slot1 power helper.
- Safety gate: consumers must require the exact path, size, and SHA-256 above; hash mismatch is fail-closed.
- Repository handling: the global `*.jar` ignore remains unchanged; only this exact audited artifact is force-tracked.
- Rollback arm lifetime: 15 minutes.
- Watchdog deadline: 90 seconds after POWER_DOWN.
