D:\ai —— 本地AI 开机自启 + 游戏让路 说明
================================================================

一、这套东西干了什么
----------------------------------------------------------------
1. 每次开机登录后，自动在后台（无窗口）拉起：
   - llama.cpp 本地模型服务（127.0.0.1:8080，Qwen2.5-3B）
   - Chatbox 聊天窗口
   入口：计划任务 LocalAI-Autostart（没有权限时自动退回注册表 Run 项）
   实现：D:\ai\LocalAI-Watchdog.ps1（常驻守护，每 10 秒判断一次）

2. 显存只有 4GB，所以谁在玩谁优先：
   - 检测到"非 AI 游戏"在跑（CS1.6、欧卡2、SCP 等）→ 自动停掉主模型服务（8080），
     4GB 显存全给游戏；游戏关掉后自动把模型服务拉回来。
   - 《不存在的莉莉丝》算"AI 游戏"（游戏里的 Mod 要用本地模型），
     所以玩它时模型服务不会被关；它是**在前台**时才会把 Sydney（8081）停掉腾显存，
     只在后台挂着不影响 Sydney。
   - 停服务、降优先级都按端口认进程（8080 / 8081），所以停主模型不会连带停 Sydney，
     你手动起的别的 llama-server 也不会被误杀。

3. 任何游戏在前台时 → 暂停动态壁纸（Wallpaper Engine + Lively），
   退出游戏后自动恢复（省 GPU、省显存、涨帧数）。

4. 游戏运行期间 → 把模型服务优先级降到 BelowNormal，不跟游戏抢 CPU
   （只降 8080 那个；Sydney 保持它自己的 --prio -1）。用 -DryRun 跑的时候日志里写的是
   "[dry-run] ... would change to ..."，不会谎报已经改过。

5. config.json 必须"能用"才会启动：缺 llamaServer/model/host/port、端口不是 1-65535、
   pollSeconds/logKeepDays 不是正整数、可执行文件或模型文件不存在、JSON 里写注释，
   都会直接报错退出（退出码 1），不会拿着空参数硬启动再报"成功"。
   配置里的中文关键词用记事本存成 ANSI（GBK）也能正确读出来。

二、想改规则就改这个文件
----------------------------------------------------------------
D:\ai\config.json

常用开关：
  "pauseAiWhenOtherGameRuns" : true   ← 非AI游戏时停主模型（false = 永不停）
  "pauseWallpaperDuringGame" : true   ← 游戏时暂停动态壁纸
  "lowerAiPriorityDuringGame": true   ← 游戏时降 AI 优先级
  "startChatbox"             : true   ← 开机是否一起开 Chatbox
  "pollSeconds"              : 10     ← 检测间隔（秒）
  "aiStartCooldownSeconds"   : 90     ← 主模型启动失败后的冷却（秒）
  "sydneyStartCooldownSeconds": 30    ← Sydney 自己的冷却，不写就用上面那个值
  "gamePathKeywords"         : 游戏目录关键字（装了新游戏盘就加一条）
  "gameExeNames"             : 认不出来的游戏，直接写 exe 名，例如 "cs2"
  "aiGameKeywords"           : 需要本地AI的游戏（玩了也不关模型）

改完不用重启，下一轮（10 秒内）自动生效。
如果配置写坏了（比如只留了一个 `{}`），脚本会打印 config invalid 的原因并退出，
不会拿着空参数假装启动成功——这时候修好 config.json 再跑一次就行。

三、手动控制
----------------------------------------------------------------
D:\ai\AI-Start.cmd    立刻强制启动 AI（即使正在玩游戏）；失败会明确报错，不再假装 Done
D:\ai\AI-Stop.cmd     立刻停掉主模型服务（腾显存）——只停 8080，不动 Sydney
D:\ai\AI-Status.cmd   看当前状态（模式、检测到的游戏、模型进程，并标出各自端口）
sydney\Stop-Sydney.cmd 只停 Sydney（8081）
桌面上原来的「启动本地AI.cmd」也能用，不冲突。

彻底关掉自启：
  schtasks /end    /tn LocalAI-Autostart
  schtasks /change /tn LocalAI-Autostart /disable

四、日志
----------------------------------------------------------------
D:\ai\logs\watchdog-YYYYMMDD.log   守护日志（决策变化才记，30 分钟一次心跳）
D:\ai\logs\llama-server.err.log    模型服务日志
D:\ai\state.json                   当前状态快照

五、游戏向系统微调（可一键还原）
----------------------------------------------------------------
D:\ai\Apply-GameTweaks.ps1   关闭 Xbox GameDVR 后台录制 + 打开游戏模式
D:\ai\Revert-GameTweaks.ps1  还原（原值存在 backup\registry-backup.json）

六、还建议手动做的两件事
----------------------------------------------------------------
1. C 盘只剩 3.5GB，Windows 会因此变慢、更新容易失败。建议清理到 15GB 以上。
2. NVIDIA 控制面板 → 管理 3D 设置 → 电源管理模式选"最高性能优先"，
   并关掉"后台应用最大帧率"。
