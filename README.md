# StepWarden · 艾泽拉斯足迹

<p align="center"><img src="docs/logo.png" width="150" alt="StepWarden"></p>

<p align="center">
在艾泽拉斯数步数、计交通工具、折算虚拟卡路里，每晚 22:00 在好友之间结算排名。<br>
Tracks your daily steps, rides and virtual calories across Azeroth, and settles a friend ranking at 22:00.
</p>

<p align="center">
<code>## Interface: 16001, 120105</code><br>
无限服 1.60.1 与正式服 12.1.5 共用同一份文件，无需分别下载。
</p>

[功能](#功能) · [安装](#安装) · [命令](#命令) · [原理](#原理) · [English](#english) · [更新日志](CHANGELOG.md)

---

## 功能

| 模块 | 说明 |
|---|---|
| **步数** | 客户端没有原生步数接口，用移动速度对时间积分推算。跑步约 176 步/分钟 |
| **骑乘** | 骑地面坐骑同样计步，按种族坐骑步距换算（143 ~ 185 步/分钟） |
| **交通工具** | 飞行点 / 船只 / 传送分别计数；飞行点只累计距离，不计步数 |
| **虚拟卡路里** | 按种族系数折算，牛头人最高、地精最低。数字是编的，认真你就输了 |
| **好友排名** | 每晚 22:00 结算，按步数排序。只覆盖同阵营、同公会、且装了本插件的人 |
| **点赞** | 排行榜每行有点赞按钮，可选是否向对方发送私信 |
| **前台挂件** | 不发命令也能在屏幕上看到当天步数，可拖动、可隐藏、可调透明度 |
| **中英双语** | 设置面板可切换中文 / English，切换后当场生效 |

## 安装

1. 从 [Releases](https://github.com/ChiMing23/StepWarden/releases) 下载最新的 `StepWarden-x.x.x.zip`
2. 解压后得到 `StepWarden/` 文件夹，放进 `Interface/AddOns/`
3. **完全退出游戏客户端，再重新启动**

> 不要只用 `/reload`。游戏只在启动时扫描 AddOns 目录，改名或首次安装后重载界面是看不到它的。

## 命令

| 命令 | 作用 |
|---|---|
| `/step` | 打开主面板 |
| `/step opt` | 打开设置 |
| `/step mini` | 开关前台挂件 |
| `/step alpha 0.85` | 面板背景透明度，范围 0.3 ~ 1.0 |
| `/step reset` | 清空今日数据 |
| `/step clear` | 清空好友缓存 |
| `/step wipe` | 清空全部数据（今日 + 好友） |
| `/step test` | 立刻结算一次排名 |
| `/step lang zh\|en` | 切换界面语言 |
| `/step help` | 显示命令列表 |

别名：`/azs`、`/azerothsteps`

## 原理

- **步数**：每 0.2 秒采样一次移动速度，超过阈值才累计，并限制单次采样最大 0.5 秒，避免掉帧时数字暴涨
- **卡路里**：`步数 × 种族系数`。系数按体型设定，牛头人 0.085、地精 0.020
- **排名**：通过 `SendAddonMessage` 在公会 / 小队 / 团队频道同步。跨阵营、离线、未装插件的人都收不到
- **存档**：所有数据写在 `SavedVariables` 里的 `AzerothStepsDB`，只存角色名与两项计数，不上传任何服务器

## 兼容

- 正式服 **12.1.5**（Interface `120105`）
- 无限服 **1.60.1**（Interface `16001`）
- 不依赖任何第三方库，纯原生 API

## 许可

MIT License · 作者 **ChiMing**

---

## English

**StepWarden** counts the steps you actually walk in Azeroth — because Blizzard never gave us an API for that.

| Module | What it does |
|---|---|
| **Steps** | No native step API exists, so movement speed is integrated over time. About 176 steps/min at run speed |
| **Mounts** | Ground mounts count too, converted by per-race mount stride (143 ~ 185 steps/min) |
| **Transport** | Flight paths, boats and teleports are counted separately; flight paths accrue distance, not steps |
| **Virtual calories** | Multiplied by a per-race coefficient. The numbers are made up. The bragging rights are real |
| **Ranking** | Settles at 22:00 server time. Only covers same-faction, same-guild players who also run the addon |
| **Likes** | Every ranking row has a like button, with an optional whisper |
| **Widget** | A draggable on-screen counter, no command required |
| **Bilingual** | Switch between 中文 and English in settings, applied instantly |

### Install

1. Grab the latest `StepWarden-x.x.x.zip` from [Releases](https://github.com/ChiMing23/StepWarden/releases)
2. Extract `StepWarden/` into `Interface/AddOns/`
3. **Fully exit the game client, then relaunch**

> `/reload` is not enough. The client only scans the AddOns folder at startup, so a freshly added or renamed addon won't appear until you restart.

### Commands

`/step` opens the panel · `/step opt` settings · `/step mini` toggle widget · `/step reset` clear today · `/step help` all commands

### Compatibility

Retail **12.1.5** (`120105`) and the 1.60.1 client (`16001`) share the same files. No third-party libraries.

### License

MIT · by **ChiMing**
