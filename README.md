# zcode-pet 🐱

ZCode 桌宠插件：一只精细矢量橘猫悬浮在屏幕右下角，实时反映你的 agent 在干什么——思考时挠头、跑命令时小跑、等你确认时挥手+系统通知、出错时哭、任务完成时跳跃庆祝掉猫粮。带喂食养成（饥饿/亲密度/装饰解锁），内置宠物市场可一键领养 [petdex.dev](https://petdex.dev) 的 4800+ 只社区宠物。

```
ZCode hooks（7 事件，旁观者模式）
   └─▶ state.json ─300ms 轮询─▶ 悬浮窗（WKWebView 矢量猫 + 精灵图双渲染引擎）
```

## 安装

**方式一（推荐）：从 marketplace 安装**

```bash
zcode plugins install --marketplace https://github.com/wsdone/zcode-pet zcode-pet
```

**方式二：本地市场**

插件市场 → 添加 → 添加插件市场 → 粘贴本仓库（含 `marketplace.json`）→ 安装 zcode-pet。

**方式三：开发直载** —— `~/.zcode/cli/config.json`：

```json
{ "plugins": { "dirs": ["/path/to/zcode-pet/zcode-pet"], "enabledPlugins": { "zcode-pet@inline": true } } }
```

依赖：macOS + swiftc（Xcode CLT 自带）。首次事件自动编译悬浮窗（约 5 秒，一次性）。

## 功能一览

| | |
|---|---|
| 🐱 矢量橘猫 | 手绘 SVG + CSS 动画（呼吸/眨眼/摆尾/挤压跳跃），13 种状态 |
| 🪟 状态镜像 | 思考/干活(Bash 小跑、Read 看书、Search 放大镜)/等你确认/出错/庆祝/睡觉 |
| 🔔 通知 | 需要确认时系统通知「猫在喊你确认」 |
| 🍚 养成 | 喂食/摸头/亲密度解锁配饰（蝴蝶结→铃铛→皇冠）/猫粮掉落 |
| 🛒 宠物市场 | `/pet market`：搜索浏览 petdex.dev 全库、动画预览、一键领养换装 |
| 🎨 精灵图引擎 | petdex 官方规范（8 列×192×208），逐行帧率播放，`/pet import` 手动导入 |

详细文档见 [`zcode-pet/README.md`](zcode-pet/README.md)。

## License

MIT
