# VOXI WFC Golden Recovery v1.0.1

**STATUS: UNTESTED PORT OF VALIDATED GOLDEN**

这是历史 Golden commit `dfd82415073470691295547d39753f6172054748` 的独立 Magisk 手机端移植。Golden 本身有真实成功证据，但本模块是新的执行实现，在完成真机验证前不能标记为 VALIDATED。

## 支持范围

- Xiaomi Mi 10 (`cas`)
- Android 13
- HyperOS `V816.0.4.0.TJJCNXM`
- Fingerprint `Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys`
- Qualcomm X55 / SDX55M
- VOXI 固定映射：slot1 / phoneId1 / subId11 / carrierId28 / MCCMNC23415

任何 build 或 mapping 不匹配都会 fail closed。模块永远不对 slot0 写入。

## 安装与使用

1. 在 Magisk 中安装 `VOXI-WFC-Golden-Recovery-v1.0.1.zip`。
2. 重启一次。
3. 打开 Wi-Fi。
4. 打开英国全局 VPN。模块会尽力识别 Android VPN，但不会以接口名或普通 default route 作为硬门槛。
5. 打开 Magisk → 模块 → VOXI WFC Golden Recovery → 操作。
6. 等待终端显示 `FINAL_RESULT=WFC_HEALTHY_FREEZE` 或安全失败。

点击时 Airplane mode 可以是 ON 或 OFF；模块会按 Golden 顺序自动构建 A0 与 P。Wi-Fi 是硬前提；VPN 只做 flexible/advisory detection，不绑定 `tun0` 或普通 Linux default route。模块无法验证出口国家，用户须自行确认英国全局节点。AnyWhere/location spoofing 不是要求。

## CLI

```sh
su -c /data/adb/modules/voxi_wfc_golden/bin/goldenctl.sh status
su -c /data/adb/modules/voxi_wfc_golden/bin/goldenctl.sh recover
su -c /data/adb/modules/voxi_wfc_golden/bin/goldenctl.sh restore-native
su -c /data/adb/modules/voxi_wfc_golden/bin/goldenctl.sh logs
su -c /data/adb/modules/voxi_wfc_golden/bin/goldenctl.sh version
```

成功后模块保留 Golden frozen healthy state：`vendor.per_mgr` stopped、模块 holder 持有 `/dev/subsys_esoc0`、X55 ONLINE、WFC HEALTHY。需要返回原生 ownership 时使用 `restore-native`。

## 安全边界

- 原子 recovery lock，禁止重复点击并发执行。
- 最多 2 次 Golden attempt。
- 每次最多一次 slot1 SIM OFF 和一次正常 SIM ON。
- 中断时最多一次 guarded slot1 emergency ON。
- 新 `PON_SUCCESS` 未确认时禁止 SIM cycle。
- 未知 holder/owner 不会被 kill。
- 失败时尝试 transactional native cleanup；takeover 未确认时保留 holder。
- `service.sh` 不自动恢复、不操作 modem/SIM/airplane。
- 日志仅保存精选状态，不保存 IMEI/IMSI/ICCID/EID、号码、Wi-Fi/VPN 凭据或 token。
