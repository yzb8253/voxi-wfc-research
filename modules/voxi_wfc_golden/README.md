# VOXI WFC Golden Recovery v1.1.0-rc6

**STATUS: WRITABLE DEVICE VALIDATION REQUIRED**

这是历史 Golden commit `dfd82415073470691295547d39753f6172054748` 的可写 Magisk candidate。RC1 已在真机完成只读控制层验证；RC6 的 Action 先执行相同的只读 `pre_recovery_self_test`，只有 PASS 才会进入 Golden recovery。RC4 首次可写真机运行在 A0 中暴露了 Magisk BusyBox 对业务变量 `LINES` 的兼容冲突：当变量接收真实 `pm-service 1260 ... /dev/subsys_esoc0` owner 行时 shell 报 `unexpected '1260'`，当次仅执行了 Airplane OFF，未进入 modem/SIM 写路径。RC6 移除该业务变量名并增加 native/A0 诊断 marker，同时保留 RC3/RC4 已完成的 freeze 与 failure-cleanup 安全修复。

## 支持范围

- Xiaomi Mi 10 (`cas`)
- Android 13
- HyperOS `V816.0.4.0.TJJCNXM`
- Fingerprint `Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys`
- Qualcomm X55 / SDX55M
- VOXI 固定映射：slot1 / phoneId1 / subId11 / carrierId28 / MCCMNC23415

任何 build 或 mapping 不匹配都会 fail closed。模块永远不对 slot0 写入。

## 安装与使用

1. 在 Magisk 中安装 `VOXI-WFC-Golden-Recovery-v1.1.0-rc6.zip`。
2. 重启一次。
3. 打开 Wi-Fi。
4. 打开英国全局 VPN。模块会尽力识别 Android VPN，但不会以接口名或普通 default route 作为硬门槛。
5. 打开 Magisk → 模块 → VOXI WFC Golden Recovery RC6 → 操作。
6. Action 会先显示 self-test；只有 `READY_FOR_RECOVERY=YES` 才会执行 A0、P、X55 和 SIM2 Golden recovery。

点击时 Airplane mode 可以是 ON 或 OFF。Wi-Fi 是硬前提；VPN 只做 flexible/advisory detection，不绑定 `tun0` 或普通 Linux default route。模块无法验证出口国家，用户须自行确认英国全局节点。

RC6 针对 RC5 真机验证中发现的自动化缺口做了单点修复：RC5 的 Golden 核心已在真机完整成功（X55/holder/PON/SIM2/WFC/FREEZE_COMMIT 全部 PASS），但进入飞行模式后脚本仅检查了滞后的 `wifi_on` 值，没有真正执行 Wi-Fi enable；当次 Wi-Fi 是用户手动重新打开的。RC6 在 P state 进入飞行模式后无条件执行一次 `svc wifi enable`，并等待真实 `wlan0` UP，随后才开始原有 20 秒 P settle。Golden core、timing、SIM/X55/freeze 逻辑均不变。

只有唯一 native `/vendor/bin/pm-service` owner、X55 ONLINE 和精确平台/VOXI mapping 才会授权恢复。每个可写阶段输出 `RECOVERY_STAGE_BEGIN/END`，未知 owner 永远不会被 kill。

## CLI

```sh
su -c /data/adb/modules/voxi_wfc_golden/bin/goldenctl.sh status
su -c /data/adb/modules/voxi_wfc_golden/bin/goldenctl.sh self-test
su -c /data/adb/modules/voxi_wfc_golden/bin/goldenctl.sh logs
su -c /data/adb/modules/voxi_wfc_golden/bin/goldenctl.sh version
```

`self-test` 保持完全只读。`recover` 为 RC6 Action 使用的可写 candidate；`restore-native` 仅对模块可精确验证的 holder 开放，即使 Wi-Fi/VPN 或 VOXI subscription 暂时不可用，也不扩大其 owner 身份要求。RC6 尚未完成可写真机验证。

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
