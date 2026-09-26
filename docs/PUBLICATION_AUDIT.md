# Publication Audit

## Status

`PUBLICATION_STATUS=BLOCKED_PRIVACY_HISTORY`

本轮只审计仓库和 Git 历史，没有连接手机、没有运行 ADB、没有执行任何 phone write。

## 未发现

- Private keys
- GitHub token
- AWS token
- SIM authentication credentials
- 未脱敏 ICCID / IMSI / IMEI（按上下文与长度规则扫描）

## 发现并需要处理

- 历史快照中的 persistent Xiaomi identifier
- 原始网络采集中的 MAC / BSSID
- 原始网络采集中的 public IP
- 上述数据仍存在于 Git history

具体敏感值不在本报告中复述。详细路径级结论见 [Publication Safety Audit](PUBLICATION_SAFETY_AUDIT.md)。

## 决策

当前不得将 repository 改为 public。仅删除工作树文件无法清除历史对象；而改写历史会改变研究 provenance 和 Golden commit identity，并且不在本轮授权范围内。

建议保留当前 provenance 仓库为 private，另行创建经过脱敏、只包含选定源码和证据的 public mirror。这样可以保留 Golden commit 的内部可追溯性，同时降低公开原始采集数据的风险。

## 本地 Golden worktree

本地 `voxi_wfc_golden_6of6/` 是约 42 MB 的复现副本，未加入 Git。Golden 仅通过 commit SHA 引用。
