# StepWarden

**A pedometer for Azeroth. Because nobody else was going to build one.**

Blizzard never shipped a step counter. StepWarden fills that gap: it measures your
movement speed every 0.2 seconds, turns distance into steps, steps into invented
calories, and calories into a leaderboard your guild will argue about at 22:00.

---

## What it tracks

| Feature | What it does |
| --- | --- |
| **Steps** | Movement speed integrated over time. Roughly 176 steps per minute at run speed. |
| **Mounted steps** | Ground mounts count too, converted with a per-race mount stride (143–185 steps/min). |
| **Transport rides** | Flight paths, boats and teleports are logged separately. Flight paths accrue distance, not steps. |
| **Virtual calories** | Steps × a per-race coefficient. Tauren burn the most, Goblins the least. The numbers are invented. The bragging rights are real. |
| **Nightly ranking** | Settles at 22:00. Whoever walked the most takes the day. |
| **Likes** | A like button on every ranking row, with an optional whisper to the recipient. |
| **On-screen widget** | A draggable counter showing today's steps, no command required. |
| **Bilingual UI** | 中文 / English, switchable in Settings and applied instantly. |

## Install

### CurseForge App
Search for **StepWarden** and hit Install.

### Manual
1. Download the latest file from the **Files** tab.
2. Extract the `StepWarden` folder into `Interface/AddOns/`.
3. **Fully exit the game client, then launch it again.**

> `/reload` is not enough. The client only scans `Interface/AddOns/` at startup,
> so a newly installed or renamed addon stays invisible until you restart.

## Commands

| Command | Action |
| --- | --- |
| `/step` | Open the main panel |
| `/step opt` | Open settings |
| `/step mini` | Toggle the on-screen widget |
| `/step alpha 0.85` | Panel background opacity, 0.3 – 1.0 |
| `/step reset` | Clear today's data |
| `/step clear` | Clear the friend cache |
| `/step wipe` | Clear everything |
| `/step test` | Settle the ranking right now |
| `/step lang zh` or `/step lang en` | Switch interface language |
| `/step help` | List all commands |

Aliases: `/azs`, `/azerothsteps`

## Compatibility

- Retail **12.1.5** (`Interface 120105`)
- Client **1.60.1** (`Interface 16001`)
- Both clients use the same files — one download covers both
- No third-party libraries, pure native API

## How it actually works

- Steps are sampled every 0.2 s; a single sample is capped at 0.5 s so a frame stutter can't inflate the number.
- Ranking syncs over `SendAddonMessage` in guild, party and raid channels.
- Everything lives in `SavedVariables` under `AzerothStepsDB` — character names and a few counters. Nothing leaves your machine.

## Known limitations

- **Calories are fiction.** Race coefficients are eyeballed from body mass. Do not cite them in a medical journal.
- **Rankings are local.** Only same-faction, same-guild players who also run StepWarden can appear. Cross-faction and offline players are silently dropped. This is a client API limit, not laziness.
- **Flight paths don't count steps.** You're sitting on a bird. The bird is doing the flapping.
- **Alts count separately.** Each character keeps its own tally, so your "ranking" may include you twice.

## Currency of the realm

This addon is free and always will be. It collects no data, sends nothing to any server, and contains no telemetry.

## License

MIT — by **ChiMing**

---

## 中文说明

**艾泽拉斯的计步器。**
暴雪没做过步数统计，这个插件补上了：每 0.2 秒采样一次移动速度，把距离折算成步数，再把步数折算成虚拟卡路里，最后变成一个每晚 22:00 结算的好友排名。

主要功能：步数与骑乘计步、飞行点/船只/传送计数、按种族折算卡路里、每晚 22:00 排名结算、排行榜点赞（可开关私信）、前台常驻挂件、中英双语热切换。

命令：`/step` 打开面板 · `/step opt` 设置 · `/step mini` 开挂件 · `/step reset` 清今日 · `/step help` 全部命令

兼容正式服 12.1.5 与 1.60.1 客户端，同一份文件通用，无第三方依赖。

> 首次安装或改过插件目录名之后，**必须完全退出客户端再启动**。只按 `/reload`
> 不会让游戏重新扫描 AddOns 目录。

---

## CurseForge 上架填写清单

给作者自己看的，发布时不用粘进描述框。

| 字段 | 建议值 |
| --- | --- |
| **Project name** | `StepWarden` |
| **Summary**（≤200 字符） | `A pedometer for Azeroth — tracks daily steps, mount rides and invented calories, with a friend ranking that settles at 22:00.` |
| **Category** | Addons → *Miscellaneous* |
| **Game version** | World of Warcraft（12.1.5）+ 若平台支持则勾选 Classic-like 1.60.1 |
| **License** | MIT |
| **Description** | 本文件从 `# StepWarden` 到 `MIT — by ChiMing` 的部分 |
| **Changelog** | `CHANGELOG.md` 里对应版本那一节 |
| **Files 上传** | `StepWarden-v1.0.1.zip`，勾选 Release 类型 |
| **Screenshots** | 建议补：主面板、设置面板、排行榜、前台挂件各一张 |

> 注意：CurseForge 的 Description 框按 Markdown 渲染，但不吃自定义 HTML 和 CSS。
> 本文件已按此约束写成纯 Markdown，可直接整段粘贴。
