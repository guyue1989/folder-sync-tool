# 文件夹同步工具

一款基于 HarmonyOS NEXT 的文件夹同步应用，支持增量/全量同步、双向同步、自动定时同步，并可关闭到状态栏后台常驻运行，适用于手机、平板和 MateBook（2in1）等设备。

- 包名：`com.niangao.foldersync`

## 功能特性

### 核心同步

- **两种同步模式**
  - 增量同步：仅复制新增或修改的文件（基于修改时间和大小比较）
  - 全量同步：无条件复制所有源文件
- **三种同步方向**
  - 源 → 目标：单向同步
  - 目标 → 源：反向单向同步
  - 双向同步：先源→目标，再目标→源，两端保持一致
- **删除多余文件**：可选删除目标中存在但源中不存在的文件；先删文件、再按目录深度从最深到最浅删除空目录，避免对目录误用 `unlink`
- **差异扫描**：仅预览差异，不执行实际同步
- **取消支持**：同步过程中可随时取消

### 自动同步

- 开启后按设定间隔（10~300 秒）自动检查源和目标的差异
- 检测到差异时自动触发同步
- 关闭到状态栏后仍持续运行（见"后台常驻"）

### 后台常驻（关闭到状态栏）

- 点击窗口关闭按钮不会退出应用，而是隐藏到状态栏（`hideAbility()`），同步继续运行
- 通过长时任务保活进程，避免系统挂起导致定时器停摆：优先申请 `TASK_KEEPING`（PC/2in1 后台计算类型，无进度义务），被拒时回退 `DATA_TRANSFER`
- 状态栏左键单击图标即可回到主界面（经 `statusBarView` 面板中转拉起单例主 Ability）
- 右键菜单提供"回到主界面"，系统菜单可正常"退出"

### 任务管理

- 将当前同步配置保存为命名任务
- 支持加载、执行、重命名、删除任务
- 同步日志记录最近 100 次操作，包含状态、文件数、大小、错误详情

### 文件夹授权

- 通过系统 `DocumentViewPicker` 选择文件夹并授权访问
- **授权持久化**：选择文件夹时通过 `fileShare.persistPermission`（读写双模式）保存授权，应用启动时用 `fileShare.activatePermission` 重新激活，重启后无需重新授权
- 支持移动硬盘等外部存储设备
- 常用目录快捷选择（下载、文档、图片、视频、音乐）

### 其他

- 移动硬盘检测：扫描常见挂载路径，列出可用外部存储
- 自检测试：在应用沙箱内创建测试文件并执行同步，验证功能正常
- 路径诊断：检测指定路径的各种访问方式可用性
- 主题切换：浅色 / 深色 / 跟随系统

## 技术架构

| 项目 | 说明 |
|------|------|
| 平台 | HarmonyOS NEXT |
| 语言 | ArkTS（Stage 模型） |
| SDK | 6.1.0（API 23） |
| 设备类型 | phone、tablet、2in1 |
| 构建工具 | Hvigor |

> 状态栏常驻与长时任务（`taskKeeping`）主要面向 PC/2in1 设备。

### 使用的 Kit

| Kit | 用途 |
|-----|------|
| `@kit.CoreFileKit` | 文件 I/O（`fileIo`）、系统文件夹选择器（`picker`）、授权持久化（`fileShare`） |
| `@kit.ArkTS` | `taskpool` 并发文件复制 |
| `@kit.AbilityKit` | 应用生命周期、`hideAbility`/`showAbility`、`wantAgent`、主题控制 |
| `@kit.ArkData` | `preferences` 持久化设置、任务和日志存储 |
| `@kit.BackgroundTasksKit` | 后台长时任务保活（`backgroundTaskManager`） |
| `@kit.DeskTopExtensionKit` | 状态栏图标（`statusBarManager`）与 `statusBarView` 面板扩展 |
| `@kit.ImageKit` | 状态栏图标 PixelMap 解码 |
| `@kit.BasicServicesKit` | `emitter` 事件、`BusinessError` |

### 项目结构

```
entry/src/main/
├── ets/
│   ├── entryability/
│   │   └── EntryAbility.ets        # 应用入口 + 状态栏图标 + 隐藏/恢复 + 后台保活
│   ├── statusbar/
│   │   ├── TrayPanelAbility.ets    # statusBarView 扩展：左键单击图标拉起主界面
│   │   └── TrayRaise.ets           # 面板 → 拉起主 Ability 的静态桥接
│   ├── pages/
│   │   ├── Index.ets               # 主页面（完整 UI + 同步编排 + 自动同步定时器）
│   │   └── TrayPanelPage.ets       # 空面板页，onPageShow 触发窗口恢复
│   ├── service/
│   │   ├── FileSyncService.ets     # 同步引擎（扫描、比较、复制、删除文件/目录）
│   │   ├── SyncTaskManager.ets     # 任务与日志持久化管理
│   │   ├── UriPermission.ets       # fileShare 授权持久化与激活
│   │   └── FolderBrowser.ets       # 目录浏览工具
│   └── components/
│       └── FolderPickerDialog.ets  # 自定义文件夹选择弹窗
├── resources/
│   ├── base/element/color.json     # 浅色主题颜色
│   └── dark/element/color.json     # 深色主题颜色
└── module.json5                    # 模块配置、权限与扩展 Ability 声明
```

### 核心服务

**FileSyncService** — 同步引擎
- `scanDirectory`：递归扫描目录（含子目录，带 `isDirectory` 标记），每 50 个条目让出主线程保持界面流畅
- `compareFiles`：比较源和目标文件列表，输出待复制、待更新、待删除列表
- `sync`：完整同步流程（扫描 → 比较 → 复制 → 可选删除）
- `copyFile`：通过 `taskpool` 并发复制，64KB 缓冲区流式读写
- `removeEntry`：按类型删除条目——文件用 `unlinkSync`，目录用 `rmdirSync`（先删文件、目录最深优先）
- `cancel`：设置取消标志，扫描/比较/复制/删除循环中检查

**UriPermission** — 授权持久化
- `persist`：`fileShare.persistPermission`，以 `READ_MODE | WRITE_MODE` 保存选择器授权
- `activate`：`fileShare.activatePermission`，启动时一次性激活本次要用的所有目录

**SyncTaskManager** — 任务与日志
- 基于 `preferences` 的 JSON 序列化持久化
- 任务字段：名称、源/目标路径、模式、方向、删除选项、创建时间
- 日志字段：状态（success/partial/failed/cancelled）、文件数、大小、耗时、错误

## 权限说明

| 权限 | 用途 |
|------|------|
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 允许应用在后台持有长时任务，关闭到状态栏后继续同步 |
| `ohos.permission.FILE_ACCESS_PERSIST` | 允许持久化文件选择器授权，重启后自动恢复文件夹访问 |
| `ohos.permission.PREPARE_APP_TERMINATE` | 配合生命周期处理关闭/退出行为 |

## 使用说明

1. 设置源文件夹和目标文件夹（手动输入路径或点击"选择文件夹"授权）
2. 选择同步模式和方向
3. 根据需要开启"删除多余文件"
4. 点击"开始同步"执行一次性同步，或开启"自动同步"持续监控
5. 可将常用配置保存为任务，下次一键加载
6. 点击窗口关闭按钮会隐藏到状态栏，同步继续；单击状态栏图标或右键"回到主界面"恢复窗口

> **注意**：重新安装或重新构建应用会清除已持久化的文件夹授权，需重新选择文件夹。系统选择器授权的文件夹路径不推荐自行拼接 URI，应用内部统一转换为纯文件系统路径访问。
