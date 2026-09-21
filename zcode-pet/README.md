# zcode-pet 🐱

> ZCode 桌宠：矢量橘猫镜像 agent 状态 + 宠物市场（petdex.dev 4800+ 只一键领养）

ZCode 桌宠插件：一只精细矢量橘猫悬浮在屏幕右下角，实时反映你的 agent 在干什么——思考时挠头+问号、跑命令时小跑、等你确认时挥手+系统通知、出错时哭+气泡、任务完成时跳跃庆祝并掉落猫粮。带喂食养成（饥饿值/亲密度/装饰解锁），支持导入 [petdex.dev](https://petdex.dev) 的 3300+ 宠物换装。

## 工作原理

```
ZCode hooks（7 个事件，旁观者模式，零干扰）
   └─ pet-bridge.mjs ──原子写──▶ ~/.zcode/pet/state.json
                                     │ 300ms 轮询
                                     ▼
                     zcode-pet-bin（AppKit 悬浮窗，swiftc 单文件编译）
                     WKWebView 渲染 pet.html：手绘 SVG 猫 + CSS 动画
                     精灵图模式：petdex spritesheet 逐帧播放
```

渲染层是 WKWebView 加载 `app/pet.html`——纯手绘 SVG 橘猫（渐变毛色、眼睛双高光、腮红、条纹、脚趾线）+ 13 种 CSS 关键帧动画（呼吸/眨眼/尾巴摆/跳跃挤压伸展等）。逻辑层（状态机/养成/通知）在 Swift。

> 技术备注：CLI 进程里 WKWebView 的 `loadFileURL(file://)` 会被静默挂起，必须读 HTML 字符串走 `loadHTMLString(_:baseURL:)`；透明背景用 `setValue(false, forKey: "drawsBackground")`。

| hook 事件 | 猫的状态 |
|---|---|
| SessionStart | 打招呼 → 蹲坐 |
| UserPromptSubmit | 挠头思考 + 问号（气泡显示 prompt 摘要） |
| PreToolUse / PostToolUse | 干活：Bash=小跑、Read/Grep=看书、Search=举放大镜、其他=敲键盘 |
| PostToolUseFailure | 哭 + 蓝色泪滴（气泡显示错误） |
| PermissionRequest | 举手跳 + 系统通知"猫在喊你确认" |
| Stop（有工具调用） | 跳跃庆祝 + 星星 + 掉落猫粮 + 可选完成通知 |
| 5 分钟无事件 | 睡觉 zZ |

## 安装

### 方式一：plugins.dirs 直载（开发用，改代码即生效）

`~/.zcode/cli/config.json`：

```json
{
  "plugins": {
    "dirs": ["/path/to/zcode-pet/zcode-pet"],
    "enabledPlugins": { "zcode-pet@inline": true }
  }
}
```

重启 ZCode 会话后 hooks 生效；第一次事件会自动用 swiftc 编译宠物 App（约 5 秒，一次性）。

### 方式二：本地市场（UI 安装）

插件市场 → 添加 → 添加插件市场 → 粘贴本仓库根目录（含 `marketplace.json`）→ 安装 zcode-pet。

## 依赖

- macOS + swiftc（Xcode Command Line Tools 自带）
- node（ZCode 已自带）
- 换装导入可选：`npx petdex`（拉取 petdex 宠物包）

## 使用

- **拖动**猫到任意位置（记住位置）
- **单击**摸头（亲密度 +1，60 秒冷却）；**双击**喂食（饥饿 +25，消耗 1 猫粮）
- **右键**菜单：摸摸 / 喂食 / 换装 / **宠物市场…** / 状态气泡 / 通知开关 / 隐藏 / 退出
- `/pet` 命令：`/pet feed`（喂）、`/pet status`（状态报告）、`/pet market`（打开宠物市场）、`/pet show|hide`、`/pet import <slug|目录>`、`/pet dress <name|builtin>`
- 猫粮来源：任务完成掉落 1-3 个（上限 9）
- 亲密度解锁：10 蝴蝶结 → 50 铃铛 → 100 皇冠
- 饥饿 <30 时猫头顶出现红色警示；每小时 -2

## 宠物市场（petdex.dev 全库）

右键猫 →「宠物市场…」或 `/pet market` 弹出设置窗口（ZCode 插件系统不支持插件注册 UI 标签页，此窗口是等效的设置界面）：

- **市场 tab**：拉取 petdex 官方 manifest（4800+ 只社区宠物，免认证公开 CDN），网格浏览 + 按名字/slug 搜索 + 按 类型（角色/生物/物品）过滤，卡片懒加载，滚动无限加载
- **详情预览**：点击卡片弹出大图，按官方帧率播放 idle 动画，显示描述/作者
- **领养**：一键下载精灵图 + 元数据 → 自动识别 petdex 网格规范（8 列 × 192×208 帧，v1=9 行 / v2=11 行）→ 自动换装生效，已领养显示角标
- **我的宠物 tab**：内置橘猫 + 已领养列表，点击即切换

精灵图动画严格按 petdex 官方状态表播放：idle=6帧/1.1s、running-right=8帧/1.06s、waving=4帧/0.7s、jumping=5帧/0.84s、failed=8帧/1.22s、waiting=6帧/1.01s、running=6帧/0.82s、review=6帧/1.03s（未用帧位留空不播放）。

## 命令行导入（市场窗口之外的手动途径）

petdex.dev 有 4800+ 社区宠物。导入后可随时与内置 SVG 猫互切（推荐直接用上面的市场窗口，无需命令行）：

```bash
npx petdex install boba            # 装到 ~/.petdex/pets/boba/
mkdir -p ~/.zcode/pet/pets
cp -r ~/.petdex/pets/boba ~/.zcode/pet/pets/
python3 tools/measure_sheet.py ~/.zcode/pet/pets/boba   # 自动测网格写 grid.json
```

然后在 ZCode 里 `/pet dress boba`（或右键猫 → 换装）。`/pet dress builtin` 切回矢量橘猫。

精灵图测量优先 petdex 官方规范（8 列 × 192×208 帧整数倍），不匹配时按透明沟检测、再回退宽高比推断。

## 数据文件（~/.zcode/pet/）

`state.json`（当前状态）/ `events.jsonl`（事件日志，64KB 封顶）/ `save.json`（养成存档）/ `prefs.json`（窗口位置/通知开关/当前宠物）/ `control.json`（命令通道）/ `pet.pid` / `pets/`（导入的宠物包，各含 pet.json + spritesheet + grid.json）

## 卸载

右键猫 → 退出；config.json 里删掉 dirs 条目；删 `~/.zcode/pet/` 目录。

## 开发

```bash
cd app
./build.sh -f          # 强制重新编译（不加 -f 时二进制存在则跳过）
# 手动冒烟桥接：
printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Bash"}' | node ../hooks/pet-bridge.mjs
# 手动驱动状态看动画：
python3 -c "import json,time; json.dump({'status':'error','session':'t','ts':time.time()}, open('$HOME/.zcode/pet/state.json','w'))"
```

- **改猫的样子/动画**：编辑 `app/pet.html`（SVG 结构 + CSS），保存后右键猫 → 重载（或 `echo '{"action":"reload"}' > ~/.zcode/pet/control.json`），无需重新编译。
- **改市场窗口**：编辑 `app/settings.html` + `main.swift` 里的 `MarketController`（JS↔Swift 桥：`webkit.messageHandlers.pet` ↔ `window.__onHostMsg`）。
- **改逻辑**（状态机/养成）：编辑 `app/main.swift`，`./build.sh -f` 后杀进程重启。
- 运行日志：`/tmp/pet_dbg2.log`（启动/页面加载事件）。
- 旧版像素猫渲染器（v0.1）见 git history。
