# Changelog

## v1.1

- Added manual, F1-only Deep Recover with one false call, mandatory F8 confirmation, and one true call.
- Kept Magisk Action conservative: healthy is zero-write and F1 only displays the manual command.
- Updated direct health to REGISTERED + WLAN + VOICE/IWLAN + WFC availability.
- Reclassified IMS NetworkAgent, qti.cne, UDP/4500, XFRM, and MMTEL READY as supporting evidence.
- Added XFRM and corrected qti.cne request reporting to the read-only probe.
- Added a complete fixed dual-SIM gate to the deep-remove helper.
- Added a shared recovery lock and complete Deep Recover operation logging.

## v1.0

- Initial validated inactive/apps-disabled Safe Recover.
