# TWO-MINUTE WFC RECOVERY ANALYSIS

## 1. 当前目标与范围

目标是从污染状态稳定恢复 VOXI WFC，并把正常成功路径控制在 120 秒内；不再把 OLD/FAST holder 的几秒差异作为主研究方向。本轮只分析代码和已有日志，没有调用 ADB，也没有修改 OLD/FAST core、SIM power 逻辑、安全门、cleanup 或 frozen-healthy 行为。

基线为 `3382e3b9a64fb470a879f4428008732e1adc18ac`。本地扫描到 6 个 Holder A/B wrapper 日志、15 个 X55 core 日志和 54 个 aggressive/lightweight 文件。只有 6 个 A/B 日志能通过 `CORE_LOG` 与同一轮 core 日志严格关联，因此统计只使用这 6 个样本；其他历史文件不混入同一分布。

结论先行：5 个成功样本总耗时 104.247–115.008 秒，目标已在正常路径上实现。唯一 NO_CNE 样本为 313.998 秒。现有证据不能安全地在 SIM ON 后 5、8、10、12、15 或 20 秒确认死亡路径；`INSUFFICIENT_EVIDENCE`。可测试但尚不可投入生产的最早保守候选，是墙钟约 30 秒且连续至少 3 个 dead sample、跨度至少 10 秒。

## 2. 成功/失败样本表

下表时间均为日志可见的上界。`CNE/IMS/WFC` 来自一次 status probe，因此相同时间不代表这些内部事件真正同时发生。

| Variant | 结果 | crash_count | X55 offline ms | holder→online ms | PON ms | OFF req ms | OFF hold ms | ON req ms | UICC READY 上界（ON后ms） | 首次 CNE/IMS/WFC 可见（ON后ms） | core ms | wrapper ms | cleanup ms |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| FAST | SUCCESS | 0 | 3715 | 5162 | 104 | 107 | 3604 | 117 | 2013 | 19635 | 60533 | 104247 | — |
| FAST | SUCCESS | 0 | 4068 | 5562 | 128 | 153 | 3750 | 148 | 2014 | 16027 | 61946 | 111062 | — |
| FAST | SUCCESS | 0 | 3746 | 5399 | 135 | 137 | 3712 | 130 | 2009 | 21794 | 66998 | 115008 | — |
| OLD | NO_CNE | 4 | 4303 | 6049 | 137 | 118 | 3816 | 103 | 2009 | 未出现 | 187154 | 313998 | 86029 |
| OLD | SUCCESS | 0 | 4250 | 5901 | 131 | 139 | 3731 | 139 | 2005 | 16145 | 62415 | 111607 | — |
| OLD | SUCCESS | 0 | 3914 | 5678 | 155 | 160 | 3801 | 157 | 2002 | 16593 | 63570 | 114420 | — |

不要从 FAST 3/3、OLD 2/3 推断 FAST 更可靠。失败样本同时具有 `crash_count=4`、较长同-boot modem epoch 等混杂因素；其余 5 个样本均为 `crash_count=0`。OLD/FAST core 的唯一行为差异仍只是 holder 实现。

### SIM ON 后的探针事实

- 5/5 成功样本在约 9.6–10.6 秒的第一次探针仍为：IMS NOT_REGISTERED、CNE `NO/NO/null/null`、无 NetworkAgent、无 ePDG/XFRM、WFC unavailable。
- 一个成功样本在约 14.6 秒仍全部为空，约 19.6 秒才第一次显示健康。
- 最晚成功样本在约 16.1 秒仍全部为空，约 21.8 秒才第一次显示健康。
- 失败样本在约 9.8、14.9、19.9、26.1、31.0、36.0、41.0、45.9、50.9、53.8 秒的探针均为 `NO/NO/null/null`。
- 代码中的 `MaxSeconds=30` 是 sleep budget，不是墙钟 deadline。每次 `wfcctl status` 约 1.9–3.2 秒，不计入 `$elapsed`，所以失败样本的“30 秒窗口”实际为 53.899 秒。

## 3. NO_CNE 最早分叉点

### 已观测事件链

```text
SIM POWER ON request completes
  → ~2.0 s: SIM reports READY; sub11 remains slot1/ACTIVE/UICC enabled
  → MMTEL remains READY
  → success only: Qualcomm/QNS/CNE demand becomes visible
  → current CNE request (satisfied may still be null)
  → ePDG/XFRM and IMS REGISTERED/WLAN
  → VOICE/IWLAN + WFC AVAILABLE
```

失败样本完成了 SIM/UICC 恢复，MMTEL 也一直 READY，但在整个观测期没有 CNE registration/request、IMS NetworkAgent、ePDG、XFRM 或 IMS registration。它卡在“MMTEL/订阅已恢复”与“QNS/CNE 产生 IMS data demand”之间。

### 最早可见差异

功能链上的最早成功特异信号是新的 CNE registration/request；但现有 probe 把 CNE、IMS、ePDG/XFRM 和 WFC 打包读取，粒度约 2–3 秒，所以无法证明它们内部的精确先后。第一条内部 Qualcomm/QNS 事件在现有日志中不可观测。

更早的相关差异是失败样本在 SIM cycle 前已有 `crash_count=4`，成功样本都是 0。该值在 shutdown/OFFLINE/ONLINE 全程稳定，没有新增 crash。因此它是“同一 boot 内累积 epoch/residue”的候选标记，不是已证明根因。

### 各候选截止点

| SIM ON 后 | 结论 |
|---:|---|
| 5/8/10/12 秒 | 不能终止；所有成功样本在首个约 10 秒探针仍完全 dead-looking。 |
| 15 秒 | 不能终止；成功样本到约 16.1 秒仍可为 `NO/NO/null/null`。 |
| 20 秒 | `INSUFFICIENT_EVIDENCE`；最晚成功只知道在 16.1–21.8 秒之间转变，没有 20 秒精确样本。 |
| 30 秒墙钟 | 可以作为下一轮验证的保守候选，但当前只有 1 个失败样本，尚不能作为生产规则。 |

所以对“A. NO_CNE 最早能多早确认？”的当前答案是：**早于 30 秒为 `INSUFFICIENT_EVIDENCE`；30 秒仅为待证候选，不是已确认合同。**

## 4. 已证实与 hypothesis

### 已证实

- SIM/UICC 在成功和失败样本中都于 SIM ON 后约 2 秒的 snapshot 显示 READY、slot1/sub11、UICC enabled。
- X55 OFFLINE→ONLINE、PON_SUCCESS、holder ownership 和 crash_count 稳定门在失败轮均通过。
- MMTEL READY 不能预测 CNE demand 或 WFC 成功。
- `CNE satisfied != null` 不是 WFC 健康硬条件：一个成功样本健康时为 `request=265, satisfied=null`。
- 10 秒时 `NO/NO/null/null` 不是失败信号；16 秒时仍为空也可能在约 22 秒健康。
- 314 秒主要不是恢复等待本身，而是失败后的两层 cleanup/normalization。

### 尚未证明

- `crash_count>0` 是否提高 NO_CNE 概率。
- qcrild2 在 SIM ON 后是否稳定、是否存在内部 QMI/DSD epoch 差异；当前日志没有 post-SIM PID/start-time 采样。
- QNS initial query、qualified-network callback、CNE callback registration 或 native IMS demand 中谁是第一条缺失事件。
- 30 秒连续 dead fingerprint 是否足以零误杀地确认 NO_CNE；样本量仅 1 个失败。
- FAST holder 是否改变成功率；当前 A/B 数据被 boot/epoch 和 crash_count 混杂。

## 5. EARLY-FAIL classifier 设计（未接生产）

`early_fail_classifier.ps1` 是纯函数、离线设计，没有手机命令。

### RECOVERY_PROGRESSING

任一出现即判 progressing：

- current-table CNE request/satisfied 非 null；
- CNE registered/active=YES；
- IMS REGISTERING/REGISTERED；
- Transport WLAN、VOICE/IWLAN 或 WFC available；
- IMS NetworkAgent、UDP/4500 或 XFRM 出现。

### NO_CNE_SUSPECTED

墙钟 15–30 秒，且 mapping/subscription/UICC、qcrild2、native X55/ownership 均稳定，MMTEL READY，但所有上述 progress signal 仍为空。该分类只能记录，不能提前终止。

### NO_CNE_CONFIRMED（候选实验规则）

仅在墙钟至少 30 秒，并满足：

- 至少 3 个连续 dead sample；
- 首末 dead sample 跨度至少 10 秒；
- exact VOXI mapping、ACTIVE、UICC enabled；
- qcrild2 identity/start-time 未变；
- holder/X55/owner/crash_count 无异常；
- MMTEL READY；
- connectivity **current table** request/satisfied 仍为 null；
- CNE registered/active=NO；
- IMS/NetworkAgent/ePDG/XFRM/WFC 全无进展。

该规则目前仍是待证候选。生产接入前至少需要覆盖成功的慢尾样本和多个独立 NO_CNE 样本。

### INSUFFICIENT_EVIDENCE

任何字段缺失、parser/boundary 错误、mapping/UICC/qcrild2/native identity 不确定、MMTEL 未 ready、少于 3 个样本，或时间不足，都 fail closed 到此分类。

## 6. 314 秒失败路径拆解

唯一失败样本：

| 阶段 | 实测约耗时 | 性质 |
|---|---:|---|
| wrapper safety + A0/P0 + pre-core health | 41.8 s | 大部分是安全门和既有 preflight；不能无证据删除。 |
| core start → SIM ON | 42.8 s | 包含 core preconditions、OFFLINE、holder ONLINE、PON settle 10 s、X55-only health 与 SIM snapshots。 |
| SIM ON → wait result | 53.9 s | 名义 30 s sleep budget + 10 次约 2 s probe；纯观测墙钟膨胀约 24 s。 |
| failure final probe | ~4.0 s | 确认 CNE/WFC 失败。 |
| core transactional cleanup | 86.0 s | 两个 native takeover 等待（含一次 restart）后仍失败，安全地保留 holder。 |
| engine post-core health/current-CNE | ~3.4 s | 只读确认。 |
| wrapper final A0 normalization | 78.5 s | OLD holder TERM 43.83 s；其后 owner-none 2.16 s、qcrild2 PID change 1.26 s、pm reacquire/X55 online 5.91 s、post-light 5.31 s，另含 gate/采样开销。 |
| 总计 | 313.998 s | 与日志一致。 |

core cleanup 与 wrapper normalization 在该失败形态下形成重复安全恢复：前者等待 native pm-service 在 holder 存活时直接取得 ownership，失败后保留 holder；后者随后用已验证 qcrild2 reacquire 流程成功恢复 A0。不能简单删除前者，因为它属于原 core fail-safe；但 vNext 可以在独立实验副本中验证“保持 holder → 直接进入现有严格 split/reacquire”是否能替代重复等待。

### 理论失败下限

- **保守（不改 core 控制流）**：约 210–240 秒。廉价 probe 可省约 20–24 秒，FAST holder 可减少最终 normalization，但 86 秒 core cleanup 仍存在，无法接近 120 秒。
- **中等（新实验 core 在 NO_CNE 后保留 holder，跳过重复 takeover 等待，只运行一次现有严格 split/qcrild2 reacquire）**：约 130–150 秒。写操作集合不增加，但控制流变化必须单独审计和真机验证。
- **激进但仍限定在已验证 primitive 内**：约 115–130 秒。需要低扰动墙钟 classifier、取消重复 full snapshot/health bundle、直接使用 FAST holder normalization，并证明省略 X55-only 重 probe 或与其他等待并行不会改变成功率。本轮禁止实施；目前不能保证 ≤120 秒。

硬约束是：当前从入口到 SIM ON 已约 85 秒；若保留 30 秒墙钟确认，只剩约 5 秒完成安全退出，而已验证的 FAST split/reacquire + post-light 本身约 19 秒。因此在当前架构下，**失败路径 ≤120 秒客观上不可保证**。

## 7. 可移出关键路径的纯观测

可在未来实验副本中评估：

- 用 current-table CNE + 核心 IMS 字段的轻量探针替代每轮完整 `wfcctl status` 输出；
- full lifecycle dumps、历史 isub/phone 列表和大日志在 run 结束后采集；
- qcrild2 PID/start-time、owner、X55、crash_count 用一次合并 root read 获取；
- final forensic bundle 只在 UNKNOWN、新 failure class 或安全门失败时生成。

不能删：exact mapping/UICC gate、current-table boundary validity、holder/owner identity、X55 ONLINE/OFFLINE、crash_count 单调性、PON_SUCCESS、单次 SIM OFF/ON、最终四项健康判定、失败时的安全 ownership 恢复。

## 8. ≤120 秒 vNext 成功预算

这是成功路径预算，不宣称失败路径也可保证：

| 阶段 | 预算 |
|---|---:|
| platform safety + A0/P0 | 42 s |
| X55 shutdown | 5 s |
| holder→ONLINE + PON verify | 7 s |
| PON settle | 10 s |
| X55-only health observation | 9 s |
| SIM OFF/3 s hold/ON + lifecycle snapshot | 12 s |
| SIM ON→progress/final health | 22 s |
| 抖动余量 | 13 s |
| **总计** | **120 s** |

该预算不压缩 PON 10 秒、SIM OFF 3 秒或成功样本的 16–22 秒恢复尾部。优化重点应是探针开销和失败后的重复 cleanup，而不是再缩正常等待。

## 9. 下一轮最小实验

先不改变 recovery。运行固定 core 的诊断旁路，采样点为 SIM ON 后约 10、16、22、28、30 秒；记录真实 device/host timestamp 和 observation epoch。每个采样只读：

- exact sub11 slot/ACTIVE/UICC；
- qcrild2 PID、start-time、cmdline；
- CNE registered/active；
- connectivity current-table request/satisfied；
- IMS state/transport/VOICE-IWLAN/WFC；
- IMS NetworkAgent、UDP/4500、XFRM、MMTEL；
- holder PID/FD9、owner、vendor/kernel X55、crash_count；
- QNS/ANM 的 IMS qualified/preferred transport（仅存在廉价只读入口时）。

实验目标不是提前终止，而是收集至少 10 个 success（包含慢于 20 秒者）和至少 3 个独立 NO_CNE。然后离线回放 candidate classifier，要求 success 误杀为 0，缺字段一律 `INSUFFICIENT_EVIDENCE`。只有满足后，才能提出单独的生产接入变更。

## 10. 风险与回滚

- 离线 parser/classifier 无手机访问，风险为 0；删除新增目录即可回滚。
- 下一轮 sidecar 必须只读，不改变 core deadline、SIM cycle 或 cleanup；停止 sidecar 即回滚。
- 若将 classifier 接入实验 core，必须是新副本，保留原 OLD/FAST core hash；任何 UNKNOWN 都走原 30 秒路径。
- 若实验“直接 strict split/reacquire”，必须保持 holder 直到 exact gate PASS，禁止 SIGKILL、第二次 SIM cycle、额外服务 restart；任何 gate 失败回到原 fail-safe，并保存现场。

## 工具与测试

- `analyze_recovery_logs.ps1`：离线扫描三类目录并关联 A/B→core，输出 sanitized 时间线。
- `early_fail_classifier.ps1`：纯函数设计，不含设备命令。
- `test_two_minute_analysis.ps1`：PS5.1 parser、8 个 classifier fixture、1 个 synthetic timeline parser fixture，并扫描禁止的手机写 primitive。

静态测试结果：parser fixture 1/1 PASS，classifier fixtures 8/8 PASS，`PHONE_WRITES=0`。
