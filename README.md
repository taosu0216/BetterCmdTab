# BetterCmdTab（内部魔改版）

这是 [@taosu0216](https://github.com/taosu0216) fork 的 [rokartur/BetterCmdTab](https://github.com/rokartur/BetterCmdTab)，在上面做了两个改动：

- **默认中文** — 写死 `AppleLanguages = zh-Hans`，界面和 Cmd-Tab 面板默认走中文。
- **没有窗口的行也能点"退出 App"** — 原版逻辑是一行只要拿不到真实窗口（比如缩略图截图还没加载出来），整条 hover 操作栏（关闭/最小化/退出全部）都会消失。改成"退出 App"只要进程在跑就能点，"关闭/最小化/最大化"这些依赖真实窗口的操作才继续要求有窗口。

这个 fork **不跟上游同步**，以后每次都是本地分支 force push 上来的，不用管上游有没有新提交，也不用处理冲突。想要上游最新功能就直接用 [rokartur/BetterCmdTab](https://github.com/rokartur/BetterCmdTab)。

下面就是同事在自己电脑上从零跑起来的全部步骤。

## 0. 前置要求

- macOS 13.0（Ventura）或更新，跟原作者电脑同型号的话直接照抄这套流程就行
- Xcode 16 及以上，安装好 macOS 26 SDK（App Store 装 Xcode 会自带对应 SDK）
- 一个能访问 GitHub 的网络环境（拉依赖包要用）

## 1. Clone 代码

```bash
git clone https://github.com/taosu0216/BetterCmdTab.git
cd BetterCmdTab
```

## 2. 初始化依赖

项目用的是 Swift Package Manager，依赖三个第一方包（`BetterSettings`、`BetterUpdater`、`BetterShortcuts`），不需要手动装任何东西——Xcode 打开项目或者用命令行构建时会自动联网拉取解析：

```bash
xcodebuild -resolvePackageDependencies
```

（这一步其实第 4 步 `xcodebuild build` 也会顺带做，单独跑只是想提前把网络问题暴露出来，跑起来卡住基本就是拉包的网络问题。）

## 3. 打开项目（可选，用 Xcode 图形界面时）

```bash
open BetterCmdTab.xcodeproj
```

左上角 scheme 选择 **`BetterCmdTab Debug`**，目标选 `My Mac`。不用这一步的话直接跳到第 4 步用命令行构建。

## 4. 构建二进制包

命令行构建：

```bash
xcodebuild -scheme "BetterCmdTab Debug" -configuration Debug build
```

构建产物在 Xcode 的 DerivedData 里：

```bash
open ~/Library/Developer/Xcode/DerivedData/BetterCmdTab-*/Build/Products/Debug/"BetterCmdTab Debug.app"
```

或者在 Xcode 里直接点 Run（▶）也会构建并启动，效果一样。

想要 Release 版本（体积更小、走 Liquid Glass 路径）：

```bash
xcodebuild -scheme "BetterCmdTab" -configuration Release build
```

## 5. 给权限

第一次启动，App 需要两个权限。**这两个权限缺一个都不会报错，只会"表现得很奇怪"**，容易误以为是 bug：

| 权限 | 在哪开 | 缺了会怎样 |
|---|---|---|
| **辅助功能（Accessibility）** | 系统设置 → 隐私与安全性 → 辅助功能 | 没这个权限，Cmd-Tab 的核心控制器根本不会启动，按 ⌘Tab 会一直是 macOS 原生切换器，没有任何提示 |
| **屏幕录制（Screen Recording）** | 系统设置 → 隐私与安全性 → 屏幕录制 | 只影响"窗口预览"布局：拿不到真实窗口截图，会自动退化成显示一个个大图标，看起来像没截到图但其实就是缺这个权限 |

操作方式：在对应权限列表里找到这个 App（首次启动系统一般会自动弹出授权提示，找不到就手动点 `+` 把 App 加进去），打开开关。

**开完权限之后，一定要把 App 完全退出再重新打开**——正在跑的进程不会自动感知到刚授予的权限。

### 权限相关的坑（踩过的，务必注意）

macOS 的权限系统（TCC）**是绑定在 App 的代码签名/身份上的，不是绑定在路径或名字上**。这意味着：

- 每次用 Xcode 重新构建，都会重新做一次 ad-hoc 签名。正常情况下（bundle id、可执行文件名都没变）签名身份是稳定的，权限不会掉。
- 但如果改了 **bundle identifier**、显示名，或者**包内可执行文件名**（`CFBundleExecutable`），哪怕二进制内容完全一样，macOS 也会当成一个全新的、没授权过的 App。
- 典型症状：Cmd-Tab 明明已经生效了，结果重新构建/改名之后突然又变回了原生切换器，去辅助功能设置里看，开关变成未勾选（或者多出来一条一模一样名字但状态不同的记录）。

**遇到这种情况**：重新去辅助功能（和屏幕录制,如果要用预览的话）里把开关勾上，退出重开就好了，别的都不用动。如果是故意要改名字（比如想跟自己电脑上已经装的另一个 BetterCmdTab 区分开、避免权限互相干扰），**只改外部的 bundle id / 显示名，别动包内可执行文件名**，这样能避免每次重新构建都要重新走一遍授权。

## 6. 启用

权限给完、App 重新打开之后，直接按 `⌘Tab` 就应该能看到新版切换器弹出来了，代替了 macOS 原生的那个。想验证有没有真的接管成功：

```bash
pgrep -fl "BetterCmdTab"
```

能看到进程在跑，同时按 ⌘Tab 弹出来的不是系统原生样式，就是启用成功了。

之后不用做任何额外操作——正常用就行，改设置在菜单栏图标的 Settings 里。

## 遇到问题怎么办

- **⌘Tab 完全没反应，还是原生切换器** → 先查辅助功能权限有没有开，开了的话退出重开一次 App。
- **切换器弹出来了，但全是大图标看不到窗口内容** → 去开屏幕录制权限，退出重开。
- **之前明明好用，重新构建一次就又失效了** → 大概率是上面说的签名/权限绑定问题，重新授权一次就行，不是代码坏了。
