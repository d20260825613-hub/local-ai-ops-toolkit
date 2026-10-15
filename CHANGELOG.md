# Changelog

本仓库此前没有版本号文件（无 `package.json`、无 `CHANGELOG.md`），因此从本条目开始记录。
日期为本地时间（Asia/Shanghai）。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [Unreleased] - 2026-10-15

针对一次完整代码审计（17 个 `.ps1` + 5 个 `.mjs`，实测喂畸形输入）修复了 3 项高危、
9 项中危与 3 项低危问题，并新增一个纯 PowerShell 5.1 的自检脚本。审计清单见
`D:/repos/gh-audit/_audit/local-ai-ops-toolkit.json`。

### 新增
- `tools/selftest.ps1`：轻量自检（88 项断言，不需要管理员、不启停任何服务、不改系统设置，
  全部在 `%TEMP%\laot-selftest-*` 下跑完即删）。运行方式见 README 第四节。
- `tools/lib/LaotLib.psm1`：守护脚本与自检共用的纯函数（配置读取/校验、端口过滤、
  显存门槛、冷却、参数拼装），保证"被测代码 = 实际运行代码"。
- `tools/portfilter.ps1`：按端口挑选 llama-server；默认只报告，加 `-Stop` 才真的停。
- `audio/lib/AudioBackup.ps1`：音频修复前的原值备份读写、StartType 反查、
  混合编码日志修复。
- `audio/audio-backup.json`（首次运行修复脚本时生成）：还原所需的原始设置。
- 配置项 `sydneyStartCooldownSeconds`（缺省回退到 `aiStartCooldownSeconds`）。

### 修复（高危）
- **假成功**：`config.json` 只校验 JSON 合法性，空文件 / `{}` / `null` / `true` / 数字 /
  字符串都会以一条**空参数**命令行"成功"启动 llama-server 并汇报 AI-ON。
  现在必填字段（`llamaServer`/`model`/`host`/`port`）、`port` 范围、`pollSeconds`、
  `logKeepDays`、可执行文件/模型文件是否存在、`sydney` 段落、JSON 注释全部校验，
  任一项不合法即打印原因并以退出码 1 结束，什么都不启动。
- **`audio/Get-AudioDefault.ps1` 一运行即 0xC0000005**：手写的 Core Audio COM 互操作
  （x64 下 `PROPVARIANT` 应为 24 字节、联合体在偏移 8，脚本只声明了 16 字节；接口签名
  与真实 vtable 不符）导致访问违例。已改为 WinRT `MediaDevice` + MMDevices 注册表
  （只读，与 `List-AudioEndpoints.ps1`/`AudioGuard.ps1` 同一路线），实测退出码 0。
- **误杀 Sydney**：`Get-LlamaProcesses` 只按进程名筛选，`Stop-AiStack`/`Set-AiPriority`
  会把 8081 的 Sydney（以及任何手动起的 llama-server）一起停掉/降优先级，与 README
  承诺相反。现在所有停服/降优先级路径都按 `--port <端口>` 整词匹配；`AI-Stop.cmd`
  从 `taskkill /IM llama-server.exe`（全杀）改为只停主端口，并带上 `--port=8080`
  这类写法的兼容。

### 修复（中危）
- `Stop-Wallpapers` 每次触发都因 `$script:PathCache` 在定义前被引用而抛异常，导致本轮
  后半段（优先级、状态输出、state.json）全部跳过。状态变量统一上移到文件顶部，
  并给辅助函数调用加了 try/catch。
- `-DryRun` 下仍记录 `model service priority -> X`，谎报了一次未发生的改动；
  现在 DryRun 只写 `[dry-run] ... would change to ...`，赋值失败的 catch 也不再静默。
- 主模型与 Sydney 共用 `aiStartCooldownSeconds`，导致 Sydney 在同一轮及随后 90 秒内
  必定被挡。新增 `sydneyStartCooldownSeconds`，`Start-SydneyServer` 不再嵌套在
  `Start-AiStack` 尾部，`Stop-SydneyServer` 不再重置"上次启动尝试"时间。
- `nvidia-smi` 不可用/输出异常时显存门槛被静默跳过。现在会写一条
  `VRAM check unavailable (...), starting anyway` 的 WARN，并把"探测失败"与
  "显存充足"两种语义分开（`Test-LaotVramGate`）。
- `config.json` 强制按 UTF-8 读取，记事本存成 ANSI/GBK 的中文游戏关键词会静默乱码，
  导致"AI 游戏反而被停模型"。现在先看 BOM，无 BOM 时试 UTF-8，失败回退 ANSI 代码页。
- `audio/repair-log.txt` 被两个写入者以 UTF-8(BOM) 与 UTF-16LE 混写，47% 是 NUL 字节。
  现在日志只由 PowerShell 以 `Add-Content -Encoding UTF8` 写；`RunElevated-AudioFix.cmd`
  不再用 `>` 重定向；已存在的坏文件由 `Repair-LaotLogEncoding` 修回可读 UTF-8
  （仓库里那份已修复，2735 → 1616 字节，NUL 1285 → 0）。
- `audio/Revert-Audio.ps1` 无法还原 Nahimic 的原始启动类型（无条件写成 Automatic）和
  快速启动原值（无条件写成 1）。现在修复前把原值写进 `audio/audio-backup.json`，
  还原按备份回写；备份缺失时不再猜值。
- 所有 `.cmd` 启动器硬编码 `D:\ai\...`，从仓库直接运行时静默失败且 `AI-Start.cmd`
  仍打印 "Done"。现在一律先按 `%~dp0` 定位，再回退 `D:\ai`；找不到目标时打印部署提示
  并返回退出码 2；`AI-Start.cmd` 检查退出码，失败不再报成功。
- README 声称 `Install-AgentTools*.ps1` 把镜像"写成用户环境变量、永久生效"，实际只设了
  当前进程的 `$env:`，脚本退出即失效，且 `HF_*`/`NPM_CONFIG_REGISTRY`/`PIP_INDEX_URL`
  从未写入。现在用 `[Environment]::SetEnvironmentVariable(..., 'User')` 真正持久化
  （只写有变化的项，记录在 `D:\tools\mirror-env.json`），README 同步说明生效范围与撤销方法。

### 修复（低危）
- `audio/Revert-Audio.ps1` 只还原一个硬编码端点的独占模式；现在按修复时记录的实际
  写入清单逐条回写。
- `sydney/parse-timings.mjs`、`add-chatbox-provider.mjs`、`build-sydney-server.mjs`
  缺输入时以裸栈崩溃。现在做参数个数/文件存在/长度/JSON 合法性前置校验，打印"你该做什么"
  并以退出码 2 结束；`add-chatbox-provider.mjs` 写配置前先生成 `.bak-before-sydney` 备份。
- `LocalAI-Watchdog.ps1` 中"函数体引用其后才初始化的顶层 `$script:` 变量"的写法已消除
  （所有状态变量集中在文件顶部状态区）。

### 兼容性
- 全部脚本仍只用 **Windows PowerShell 5.1** 语法（无 `??`、无三元、无 `-Parallel`）。
- 含非 ASCII 的 `.ps1`/`.psm1` 一律保存为 **UTF-8 with BOM**（5.1 对无 BOM 文件按 ANSI
  解读，会造成中文乱码甚至语法错误）；纯 ASCII 的脚本保持无 BOM。
