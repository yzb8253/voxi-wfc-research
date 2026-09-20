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
- Artifact: build/single-sim-slot1-power-helper.jar (git-ignored).
- SHA256: 90d6f55fbe1f941c1e3eee1aa1f93b569fa3ae4084b93c5560082a38aaaf5c39
- Rollback arm lifetime: 15 minutes.
- Watchdog deadline: 90 seconds after POWER_DOWN.