---
description: 桌宠指令：喂食/状态/宠物市场/换装/导入 petdex 宠物（feed|status|market|dress|import|show|hide）
---

用户想对 ZCode 桌宠执行操作，参数：$ARGUMENTS

按参数执行（无参数默认 status）：

- **status**：读 `~/.zcode/pet/save.json` 和 `~/.zcode/pet/state.json`，一两句话回报：猫在干嘛、饥饿/亲密度/猫粮、养了几天。另外 `ls ~/.zcode/pet/pets/` 列出已领养的宠物。
- **feed**：`echo '{"action":"feed","ts":'$(date +%s000)'}' > ~/.zcode/pet/control.json`，然后读 save.json 用一句可爱的话回报。
- **market**：打开宠物市场窗口（浏览/搜索 petdex.dev 全库 4800+ 宠物，点击卡片看动画预览，「领养」一键下载换装；「我的宠物」tab 管理已领养）：
  `echo '{"action":"market","ts":'$(date +%s000)'}' > ~/.zcode/pet/control.json`
  也可以右键猫 → 「宠物市场…」。（ZCode 插件系统不支持插件注册标签页，市场窗口是等效的设置界面。）
- **import <slug 或 本地目录>**：命令行导入 petdex 宠物（市场窗口之外的手动途径）：
  1. 若是 slug：`npx -y petdex install <slug>`（装到 `~/.petdex/pets/<slug>/` 或 `~/.codex/pets/<slug>/`，找到实际位置）
  2. 若是本地目录：目录里需有 `spritesheet.webp`（或 .png），8 列网格、帧 192×208（petdex 规范）
  3. 拷贝到 `~/.zcode/pet/pets/<slug>/`（spritesheet + pet.json）
  4. 跑测量：`python3 <本插件目录>/tools/measure_sheet.py ~/.zcode/pet/pets/<slug>`（需 PIL）
  5. 换装激活：`echo '{"action":"dress","name":"<slug>","ts":'$(date +%s000)'}' > ~/.zcode/pet/control.json`
  6. 回报成功与宠物描述（读 pet.json 的 displayName/description）
- **dress <name>**：`echo '{"action":"dress","name":"<name>","ts":'$(date +%s000)'}' > ~/.zcode/pet/control.json`（name=builtin 换回内置橘猫）
- **show / hide**：写 control.json 对应 action，确认一句。
- **其他参数**：视为摸猫，写 `{"action":"pet"}`，读 save.json 描述猫的反应。

注意：不要手改 save.json（数值由猫维护）；控制文件是消费即删的一次性指令。
