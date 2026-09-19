# C7 com.android.phone Restart Result

## Execution

- Target: main-user `com.android.phone`, PID 3333, UID 1001, SELinux `u:r:radio:s0`.
- Package: `com.android.phone`, code path `/system/priv-app/TeleService`.
- Write: exactly one `kill -TERM 3333`.
- Old process death: 15:46:17.387.
- New main-user process: PID 14820; start 15:46:17.414 (~27 ms), bound 15:46:17.472 (~85 ms after death).
- A second PID 14997 is the user-999 instance (`u999_radio`), not the main UID-1001 telephony process.

## Rebuild evidence

- Phone/Subscription rebuild: YES. PhoneFactory recreated both phones; SubscriptionInfoUpdater removed and re-added slot0 and slot1 records, then restored subIds 1 and 11.
- DNC/TNF rebuild: YES. DNC-0 and DNC-1 were created; TelephonyNetworkFactory[0]/[1] registered; TNF[1] changed subId -1 -> 11.
- IWLAN rebind: YES. IWlanDataService and IWlanNetworkService reconnected for both transports/slots; QualifiedNetworksService was present.
- New IMS request: NO. No qti.cne IMS request, TNF[1] IMS capability request, or DNC-1 IMS request was observed.

## Final state after 120 seconds

- PS/WLAN: UNKNOWN.
- `mIsIwlanPreferred`: false.
- UDP/4500: absent.
- XFRM/ePDG: absent.
- IMS: NOT_REGISTERED (0).
- Transport: UNKNOWN (-1).
- VOICE/IWLAN: unavailable.
- WFC: unavailable.
- C7 result: FAIL.

## Protected surfaces

The restart necessarily rebuilt shared slot0 Phone/Subscription objects, so there was a brief framework-level interruption. Every post-restart probe that returned state showed the slot0 mapping gate intact. Final slot0 remained subId 1 / slot 0 / MCCMNC 46011. wlan0 and tun0 remained UP; no VPN/TUN loss was observed.

No additional write, Full soft stack, SIGKILL, force-stop, UICC action, radio reset, modem reset, SSR, qcrild restart, airplane toggle, or reboot was executed.