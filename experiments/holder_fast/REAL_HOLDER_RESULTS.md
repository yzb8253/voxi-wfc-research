# FAST holder real-device result

Date: 2026-09-25  
Device: Xiaomi 14 Pro (`fd0ff892`)  
ROM: `V816.0.4.0.TJJCNXM`

## Result

`FAST_HOLDER_ONLY=PASS`

- Entry: native pm-service PID 30638, sole esoc owner; X55 `ONLINE/ONLINE`; crash_count 3.
- Native release before FAST acquisition: owner `NONE` + kernel `OFFLINE` in 1629 ms. The vendor property remained stale `ONLINE` and was diagnostic only.
- FAST holder: PID 32311; child PID 32668; child FD9 absent.
- Acquisition: pidfiles ready in 2881 ms; sole owner + kernel X55 ONLINE in a further 1576 ms.
- Stability: 10/10 samples passed at 30, 60, 90, 120, 150, 180, 210, 240, 270, and 300 seconds.
- Throughout stability: main PID unchanged, child PID unchanged, main held FD9, child never held FD9, kernel X55 remained ONLINE, crash_count remained 3.
- TERM release: owner `NONE` 127 ms; kernel X55 `OFFLINE` 127 ms; main shell gone 1801 ms.
- Vendor property did not transition to OFFLINE during the bounded release observation; this is the already-confirmed stale-property behavior while per_mgr is stopped.
- Residual child had no FD9 and received one exact-PID TERM. No SIGKILL or broad kill was used.
- Native restoration: per_mgr start did not reacquire within 15 seconds, so the bounded rollback used one qcrild2 restart (`30774` -> `5737`). Final pm-service PID 4686 was sole owner; X55 `ONLINE/ONLINE`; crash_count 3; primary qcrild PID 1971 unchanged.
- SIM writes: 0. Airplane writes: 0.

## Dummy phase matrix

Five OLD and five FAST `/dev/null` samples established the sleep-phase relationship:

| implementation | phases (seconds) | min | median | max |
|---|---:|---:|---:|---:|
| OLD foreground `sleep 60` | 2, 15, 30, 50, 58 | 971 ms | 28872 ms | 56852 ms |
| FAST background child with FD9 closed + `wait` | 2, 15, 30, 50, 58 | 232 ms | 242 ms | 261 ms |

The OLD latency tracks the remainder of the foreground 60-second sleep. The FAST design removes that wait from FD ownership. On this ROM neither dummy child inherited FD9, and the real FAST child explicitly had no esoc FD9.

## Conclusion

The selected shell-native FAST holder is suitable for an isolated experimental core copy. It preserves long-lived ownership yet releases the esoc owner within the 3-second requirement without SIGKILL. The original v2.6.2 core remains unchanged.
