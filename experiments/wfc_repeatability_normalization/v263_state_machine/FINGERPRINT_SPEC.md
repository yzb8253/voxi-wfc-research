# v2.6.3 canonical fingerprints

Base commit: `89f2c86d48c91a974988d9bf67415f592da6f50d`

The state machine intentionally does not compare complete snapshot JSON. PIDs, timestamps, request IDs, owner-line formatting, uptime, and historical diagnostic text are excluded.

## Common identity gate

- rooted Xiaomi `cas` device;
- VOXI subId 11, slot 1, phoneId 1, carrierId 28, MCC 234, MNC 15;
- active subscription and UICC applications enabled;
- primary qcrild is init-owned `qcrild`;
- slot2 qcrild is init-owned `qcrild -c 2`;
- pm-proxy and mdm_helper exist;
- no module lock.

## A canonical fingerprint

- airplane OFF;
- wlan0 up and a VPN network visible;
- vendor.per_mgr running;
- init-owned pm-service is sole `/dev/subsys_esoc0` owner;
- no live temporary holder;
- vendor and kernel X55 ONLINE, crash count zero;
- RIL data technology LTE;
- `mIsIwlanPreferred=false`;
- no current qti.cne IMS request.

## P canonical fingerprint

Same native and identity fingerprint as A, plus:

- airplane ON;
- wlan0 up and VPN visible;
- RIL technology IWLAN;
- PS/WLAN HOME;
- access network IWLAN;
- `mIsIwlanPreferred=true`;
- no current qti.cne IMS request before recovery.

## Known A residue

Only this non-canonical A state is eligible for automatic normalization:

- airplane OFF;
- vendor.per_mgr stopped and pm-service absent;
- the exact recorded holder is sole `/dev/subsys_esoc0` owner;
- vendor and kernel X55 ONLINE;
- crash count zero.

Normalization reuses the two helpers validated in the v2.6.2 repeatability run. It first starts per_mgr while preserving the holder. If native dual ownership does not form, it releases only the exact holder, requires owner NONE and clean X55 OFFLINE, then restarts only vendor.qcrild2 once and requires pm-service native reacquisition.

All other A and P fingerprints fail closed.

The exact intermediate state produced when the make-before-break helper cannot form dual ownership is also recognized for crash-safe resume: per_mgr running, pm-service present but not owner, exact holder sole owner, vendor X55 OFFLINE, kernel X55 ONLINE, and crash count zero. This state skips the already completed make-before-break attempt and enters only the verified qcrild2 reacquire helper.

## W health predicate

W is not normalized. Success requires:

- IMS registration raw state 2;
- registration transport raw value 2 (WLAN);
- MMTEL VOICE/IWLAN available;
- Wi-Fi Calling available;
- existing `goldenStrong=true`.

Once true, the state is frozen. W diffs are audit-only and never trigger cleanup.
