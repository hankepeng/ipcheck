# IP 质量体检脚本

一键检测本机出口 IP 的**地理位置、运营商、ASN、IP 类型、原生 IP 判定**，以及**流媒体 & AI 服务解锁**情况，支持 **IPv4 / IPv6 双栈**。

## 一键脚本

```bash
bash <(curl -Ls https://raw.githubusercontent.com/hankepeng/ipcheck/main/ipcheck.sh)
```

指定协议检测：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/hankepeng/ipcheck/main/ipcheck.sh) -4
bash <(curl -Ls https://raw.githubusercontent.com/hankepeng/ipcheck/main/ipcheck.sh) -6
```

## 功能

### IP 质量信息（IPv4 / IPv6 均支持）
- 地理位置、运营商 ISP、ASN、反向解析、时区
- IP 类型（住宅 / 移动 / 机房 IDC / 代理）
- 原生 IP 判定

### 流媒体 & AI 服务解锁
- TikTok
- Disney+
- Netflix
- YouTube Premium
- Amazon Prime Video
- Reddit
- ChatGPT

## 使用说明

运行后进入交互菜单：

```
1) 检测 IPv4
2) 检测 IPv6
3) 同时检测 IPv4 + IPv6
0) 退出
```

每次检测结束会生成一段「**纯文本结果汇总**」，方便直接复制分享。结果带颜色标识：绿=解锁、黄=部分/限制、红=否/失败。

## 依赖

- `curl`
- 支持 `-P` 的 `grep`（GNU grep，绝大多数 Linux 自带）

## 运行环境

- Linux / macOS（bash）
- Windows 需通过 **Git Bash** 或 **WSL** 运行

> 提示：`raw.githubusercontent.com` 在大陆部分网络下可能无法直连，请在海外 VPS 或已配置代理的环境运行一键命令。
