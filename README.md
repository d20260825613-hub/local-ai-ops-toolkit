# Local AI & Ops Toolkit

一套跑在**真实弱机**上的本地 AI 与运维工具：Windows 笔记本，i5-8300H / 16 GB 内存 / **GTX 1050 Ti 4 GB 显存**，
C 盘常年告急，网络在国内（GitHub、HuggingFace、npm 官方源**全部直连不通**），并且**没有管理员权限**可用。

所有脚本只写 D 盘，只用用户级权限（UAC 需要提权的部分会明确说明并给出一键脚本），
每一处系统改动都配了还原脚本。仓库里的每个数字都是这台机器上实测出来的，不是理论值。

> 中文为主，关键部分附英文说明。Written and verified by a coding agent (DeepSeek Harness) on the actual machine.

---

## 一、这个仓库解决的四件事

| # | 问题 | 方案 | 目录 |
|---|---|---|---|
| 1 | 4 GB 显存的机器要同时服务**两个** llama.cpp 模型（一个给游戏 Mod，一个给聊天客户端），还要保证玩游戏时不掉帧 | 常驻守护脚本 + 显存门槛 + 闲置休眠 + 游戏检测 | [`LocalAI-Watchdog.ps1`](LocalAI-Watchdog.ps1) |
| 2 | 想在本机跑「新必应 / Sydney」复刻模型，但官方方案要 8 GB 显存 | 走 GGUF + llama.cpp 混合卸载路线，全流程自动化（下载校验 → 人格注入 → 接入 Chatbox → 性能标定） | [`sydney/`](sydney) |
| 3 | Windows「有时候没声音 / 突然没声音」 | 关快速启动 + 音频服务崩溃自愈 + 停用 Nahimic + 45 秒轮询守护 | [`audio/`](audio) |
| 4 | 国内网络下什么都装不上（npm / pip / HuggingFace / GitHub 全被墙） | 镜像优先的安装器 + 把镜像写进用户环境变量，一次配好永久生效 | [`tools/`](tools) |

---

## 二、目录结构

```
LocalAI-Watchdog.ps1        双模型服务守护：显存门槛、闲置休眠、游戏让路、优先级
Install-Startup.ps1         注册开机自启（计划任务，失败则回退到注册表 Run 键）
Apply-GameTweaks.ps1        游戏向系统微调（关 GameDVR、开游戏模式），可一键还原
Revert-GameTweaks.ps1       还原上面那一项
AI-Start.cmd / AI-Stop.cmd / AI-Status.cmd   手动启停与状态查看
run-watchdog-hidden.vbs     无窗口启动守护脚本
config.sample.json          守护脚本配置样例（端口、模型、显存门槛、游戏关键词）
本地AI自启说明.txt            面向使用者的中文说明

sydney/                     新必应（Sydney）复刻模型的一键部署
  download-model.mjs          8 连接并行 + 分片续传 + SHA-256 校验的 GGUF 下载器
  finish-download.mjs         把剩下的分片用 6 路子区间并行补齐，再合并校验
  build-sydney-server.mjs     生成"人格注入版"Jinja 对话模板与启动脚本
  sydney_template.jinja       已把人格提示词内置进 system 消息的对话模板
  sydney_system.txt           模型作者提供的人格提示词（Apache-2.0，见文末出处）
  add-chatbox-provider.mjs    把本地模型写进 Chatbox 的自定义提供方配置
  bench2.ps1 / bench-sweep.ps1 显存/速度标定脚本（枚举 ngl、KV 量化、上下文长度）
  Start-Sydney.cmd / Stop-Sydney.ps1   手动启停
  Sydney使用说明.txt            使用者文档（含实测速度与显存策略）

audio/                      Windows 音频故障修复与守护
  Repair-WindowsAudio.ps1     五项修复：快速启动、服务恢复、设备省电、独占模式、Nahimic
  AudioGuard.ps1              45 秒轮询：服务挂了 / 默认端点死了就自动重启音频栈（1 小时限 3 次）
  List-AudioEndpoints.ps1     列出所有输出端点、状态与关键属性（无需管理员）
  Get-AudioDefault.ps1        Core Audio (COM) 版默认设备读取
  Fix-Audio-AllInOne.ps1      自提权一键修复 + 安装守护
  Revert-Audio.ps1            全部还原
  声音问题修复说明.txt           诊断过程、结论与手动补项

tools/                      国内网络下的工具链安装器
  Install-AgentTools.ps1      git / aria2 / ffmpeg / pandoc / yt-dlp / jq / uv（GitHub 反代来源）
  Install-AgentTools2.ps1     uv + 便携版 Python（npmmirror 的 python-build-standalone）
  Install-AgentTools3.ps1     venv + 14 个常用 Python 库 + Playwright Chromium
  shot.py                     Playwright 截图小工具（用来验证网页界面）
  Build-Repos.ps1             把散落各处的自写脚本整理成 git 仓库

dsh/                         DeepSeek Harness 的无人值守启动
  start-dsh.cmd               启动前先探测 3080 端口，避免起第二个实例；输出写入日志
  start-dsh-hidden.vbs        无窗口包装，供注册表 Run 键调用
```

---

## 三、设计要点（为什么是这么写的）

### 1. 4 GB 显存是硬约束，一切围绕它让路
模型 5.24 GB > 显存 4 GB，装不下整个模型，只能部分卸载到 GPU。实测结论：

| 配置 | 生成速度 | 说明 |
|---|---|---|
| 手动 `-ngl 26`，显存只剩 87 MiB | **2.15 tok/s** | 显存余量太小，WDDM 开始换页，速度崩掉 |
| `-ngl auto -fit on -fitt 350`（留 350 MiB 余量） | **5.1 tok/s** | 让 llama.cpp 自己决定卸载层数 |
| 同上 + 关掉动态壁纸（多出约 300 MiB） | **6.2 tok/s** | 壁纸也是显存大户 |
| 同上 + 上下文 2048 + KV 量化为 q8_0 | **6.7–7.0 tok/s** | 上下文砍半换来的层数 |
| 同上 + `--no-mmap` | 5.8 tok/s | **反而更慢**，NVMe 上 mmap 更快 |
| 再加 `-t 4` 限制线程 | 6.6 tok/s | 无收益，内存带宽才是瓶颈 |

**结论：留足显存余量比多塞几层更重要。** 这是本仓库最有价值的一条经验。
`-ngl auto -fit on -fitt <余量>` 让 llama.cpp 自己找平衡点，比手工调参靠谱得多。

### 2. "慢"的主因往往不是生成速度，而是**重新加载**
守护脚本最初给模型设了 120 秒闲置休眠。用户抱怨"回复太久"，实测发现：
每次休眠后再开口，都要先**重新加载模型 14 秒**，再重新计算整段系统提示词 3.6 秒。
把休眠延长到 1800 秒，并确认 prompt cache 命中后，同一段对话的后续回复首字降到 **0.4 秒**。
主观感受的提升远大于生成速度从 4.5 提到 6.8。

**教训：先量清楚时间花在哪，再优化。**

### 3. 两个模型服务不可能同时占显存
守护脚本用三层策略保证不互相挤爆：
- **显存门槛**：启动前查 `nvidia-memory.free`，不足 3000 MiB 就推迟（不硬上、不炸显存）
- **闲置休眠**：`--sleep-idle-seconds`，没人用就释放显存
- **游戏让路**：非 AI 游戏前台 → 停掉全部模型服务；AI 游戏（其 Mod 依赖模型）前台 → 只停另一个

### 4. 国内网络：镜像不是可选项，是唯一通路
实测可用的通道与不可用的：

| 可用 | 用途 |
|---|---|
| `registry.npmmirror.com` | npm 包、git-for-windows、python-build-standalone 二进制 |
| `pypi.tuna.tsinghua.edu.cn` / `mirrors.aliyun.com` | pip |
| `hf-mirror.com` | HuggingFace 模型与数据集 |
| `gh-proxy.com`（快）/ `ghfast.top` / `ghproxy.net`（慢） | GitHub 文件与 API 反代 |
| `gitee.com` / `modelscope.cn` | 备用 |

| 不可用 | 现象 |
|---|---|
| `registry.npmjs.org` | 连接超时 |
| `github.com` 直连、`raw.githubusercontent.com` | 连接被重置 |
| `huggingface.co` | 连接失败 |
| `copilot.microsoft.com` / `sydney.bing.com` | TLS 握手直接失败（所以"真·新必应"装不进来，只能复刻） |

`tools/Install-AgentTools*.ps1` 把上述镜像写成**用户环境变量**（`PIP_INDEX_URL`、`UV_DEFAULT_INDEX`、
`NPM_CONFIG_REGISTRY`、`HF_ENDPOINT`、`PLAYWRIGHT_DOWNLOAD_HOST`、`HF_HOME=D:\hf-cache` ……），
一次配好，之后所有工具自动走镜像，并且缓存全部落在 D 盘。

### 5. 一切可回滚
- 系统级改动（快速启动、服务恢复、Nahimic、设备省电）→ `audio/Revert-Audio.ps1`
- 游戏微调 → `Revert-GameTweaks.ps1`
- 第三方客户端配置改动 → 改动前先备份到 `D:\ai\backup\`
- 需要管理员权限的操作集中在一个脚本里，一次 UAC 完成，不需要用户手工敲命令

### 6. 只用用户级权限
实测：`sc failure`、写 `HKLM`、注册 `RunLevel Highest` 的计划任务，在非提权进程里全部被拒。
因此本仓库的策略是：**能不提权就不提权**（便携版 Python、便携 Git、全部装 D 盘、注册表 Run 键自启），
确实需要提权的（音频修复、Windows 音频服务）做成"双击一次 → 点'是'"的一键脚本。

---

## 四、快速使用

```powershell
# 1) 本地 AI 守护（需要一份 config.json，可复制 config.sample.json 后按机器修改）
powershell -ExecutionPolicy Bypass -File .\Install-Startup.ps1     # 注册开机自启
.\AI-Start.cmd                                                       # 手动启动一次
.\AI-Status.cmd                                                      # 看状态

# 2) 新必应（Sydney）复刻
node .\sydney\download-model.mjs        # 下载 GGUF（并行 + 校验）
node .\sydney\build-sydney-server.mjs   # 生成人格模板与启动脚本
node .\sydney\add-chatbox-provider.mjs  # 接入 Chatbox（需先关闭 Chatbox）
.\sydney\Start-Sydney.cmd               # 起服务（默认 127.0.0.1:8081）

# 3) 音频修复（会弹一次 UAC）
.\audio\修复声音.cmd          # 或 audio\Fix-Audio-AllInOne.ps1
.\audio\Revert-Audio.cmd      # 还原

# 4) 国内网络工具链
powershell -ExecutionPolicy Bypass -File .\tools\Install-AgentTools.ps1
powershell -ExecutionPolicy Bypass -File .\tools\Install-AgentTools2.ps1
powershell -ExecutionPolicy Bypass -File .\tools\Install-AgentTools3.ps1
```

---

## 五、实测数据汇总（GTX 1050 Ti 4 GB / i5-8300H / 16 GB）

| 项目 | 数值 |
|---|---|
| Sydney 9B Q4_K_M 生成速度 | 6.7–7.0 tok/s（约 55% 层在 GPU） |
| 同模型提示词处理 | 约 90 tok/s |
| 首条回复延迟 | 约 3.6 s（系统提示词 ~320 token 需预填充） |
| 同对话后续回复首字 | 约 0.4 s（prompt cache 命中） |
| 3B 模型（游戏 Mod 用）生成速度 | 约 26 tok/s |
| 模型冷加载时间 | 约 14 s（9B Q4_K_M，NVMe） |
| GGUF 下载 | 8 连接并行约 7 MB/s；单连接掉到 0.3 MB/s 时用 6 路子区间补齐 |

---

## 六、许可与出处

- 本仓库脚本：MIT。
- `sydney/sydney_system.txt` 与量化模型来自 [Atonelia/Qwen3.5-Sydney-9B-GGUF](https://huggingface.co/Atonelia/Qwen3.5-Sydney-9B-GGUF)（Apache-2.0），
  上游项目为 [3121455692atou-sudo/sydney-webui](https://github.com/3121455692atou-sudo/sydney-webui)；
  此处按其许可转载人格提示词，模型文件本身不随仓库分发（5.24 GB，用脚本下载）。
- 推理引擎：[llama.cpp](https://github.com/ggml-org/llama.cpp)（MIT）。
- 音频修复中的端点属性 ID 来自 Windows Core Audio 的公开文档与社区整理。

## 七、已知限制

- 4 GB 显存跑 9B 模型只能部分卸载，速度上限就在 7 tok/s 左右；想更快需要换更小的模型或量化。
- 音频修复里的"独占模式"开关写在受保护的注册表项里，脚本无法修改，需要从系统"声音"设置界面手动取消。
- 守护脚本按进程名/路径关键词识别游戏，冷门游戏需要往 `config.json` 里补关键词。
