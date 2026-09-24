# X55 VOXI Passive Monitor

Canonical read-only monitoring and research-classification tool recovered from Computer A.

## Current version

- Script: `X55-VOXI-PassiveMonitor-v1.2.ps1`
- Launcher: `Run-X55-VOXI-PassiveMonitor-v1.2.cmd`
- Script SHA-256: `7C73BEEA75226DC0FB5B03B595E55FA71684694D6AD2EFD9F3D5F1A099CE5BC4`
- Launcher SHA-256: `0C248D779971C26B618E662181B16F3C52A0178FE2DAF8222E59AE617B560991`

The files above preserve the original Computer A bytes. Earlier v1.0 and v1.1 files are under `legacy/`.

## Scope

The monitor observes IMS, IWLAN, QNS, qti.cne, ePDG, XFRM, SIM/slot state, and X55-related state. It does not automatically modify location, Anywhere, VPN, airplane mode, SIM power, or modem state.

It can assist with experimental labels such as `PRE-P1`, `P1-F`, `P1-CAND`, `P1-S`, `P2`, and `HEALTHY`. These labels are research heuristics, not Qualcomm-defined states.

`networkMode=19` does not yet have a fully proven exact semantic interpretation. A QIms field showing `registered=1` is not, by itself, proof of final SIP IMS registration. Confirm actual IMS registration, transport, voice-over-IWLAN availability, and WFC availability separately.

Do not edit the recovered v1.2 source and present it as the original. Any future changes should use a new version and retain these exact files.
