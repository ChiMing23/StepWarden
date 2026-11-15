# 自动发布配置说明

本目录里的 3 个文件，需要放到**插件仓库根目录**（也就是 `StepWarden.toc` 所在的那一层）。

---

## 一、仓库最终结构

```
StepWarden/                  ← 仓库根 = 插件根，不要多套一层文件夹
├── .gitignore                 ← 本目录提供
├── .pkgmeta                   ← 本目录提供
├── .github/
│   └── workflows/
│       └── release.yml        ← 本目录提供
├── StepWarden.toc
├── Core.lua
├── Stats.lua
├── Comm.lua
├── Panel.lua
├── Main.lua
├── README.md
├── LICENSE
├── CHANGELOG.md               ← .pkgmeta 会读取它作为平台更新日志
└── Media/
    └── *.tga（5 张）
```

> `.pkgmeta` 里的 `package-as: StepWarden` 决定打出来的 zip 顶层文件夹名，
> 所以仓库根必须是插件根，否则要多套一层目录再配 `move-folders`。

---

## 二、第一次配置

```bash
cd "E:\World of Warcraft\_forever_\Interface\AddOns\StepWarden"
git init
git remote add origin https://github.com/<你的账号>/StepWarden.git
```

然后把本目录的 `.gitignore`、`.pkgmeta`、`.github/` 复制进去，
再把 `CHANGELOG.md` 也复制到仓库根，接着：

```bash
git add -A
git commit -m "V1.0.1 首发"
git push -u origin main
```

---

## 三、以后每次发版

```bash
# 1. 改 TOC 里的 ## Version（例如改成 V1.0.2）
# 2. 在 CHANGELOG.md 顶部加一段
git add -A
git commit -m "V1.0.2"
git tag v1.0.2
git push origin main --tags
```

`v*` 标签推上去后，Action 自动用 BigWigsMods/packager 打包成
`StepWarden-1.0.2.zip` 并挂到 GitHub Release，不需要本地再手工打包。

---

## 四、想同时发到 CurseForge / WoWAce

改 `release.yml` 里的 `args` 这一行：

```yaml
args: -g -p 1234567 -w 89012
```

- `-g` GitHub Release（默认已开，只需 `GITHUB_TOKEN`）
- `-p <数字ID>` CurseForge，需要仓库 Secrets 里配置 `CF_API_KEY`
- `-w <数字ID>` WoWAce / wago.io，需要配置 `WAGO_API_TOKEN`

Secrets 位置：GitHub 仓库 → Settings → Secrets and variables → Actions。
没配的项目 packager 会跳过，不会让整个流程失败。

---

## 五、三个必须知道的坑

**① TOC 版本号不会被自动改**
TOC 里写的是静态 `## Version: V1.0.1`，packager 不会替换它。
所以每次发版要**手动同步 TOC 和 tag**，否则包内显示的版本和 Release 标题对不上。

想全自动可以把 TOC 那行改成 `## Version: @project-version@`，
但这样在**未打包**状态（直接放游戏目录）下，游戏会显示 `@project-version@` 原样，很难看。不建议。

**② `## Interface: 16001, 120105` 里的 16001 平台不认识**
`120105` 是正式服 12.1.5 的合法编号，平台能正常识别。
`16001` 是无限服私有版本号，官方体系里不存在，平台会当作 unknown 自动忽略——**不影响发布**，
但别指望它能出现在「怀旧服」分类里。

**③ 手工打的 zip 和自动发布并存**
现在项目目录里的 `StepWarden-1.0.1.zip` 仍然可以手工上传，两者不冲突。
自动发布只是省去「每次改完手动重打包」这一步。

---

## 六、本地预览打包结果（可选）

如果本机装了 Lua 和 packager 想先看效果，可以只打 GitHub 那一路：

```bash
# 需要 Lua 5.1 + release.sh（BigWigsMods/packager 仓库）
./release.sh -g
```

更简单的做法是直接推一个 tag 到测试仓库，看 Actions 的输出日志。