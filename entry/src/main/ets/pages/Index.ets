import { FileSyncService, SyncProgress, SyncResult, SyncMode, SyncDirection, CompareResult, FileInfo } from '../service/FileSyncService';
import { SyncTaskManager, SyncTask, SyncLog, NewLogInput } from '../service/SyncTaskManager';
import { UriPermission } from '../service/UriPermission';
import { fileIo, picker } from '@kit.CoreFileKit';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

interface StandardDir {
  name: string;
  path: string;
}

@Entry
@Component
struct Index {
  @State sourcePath: string = '';
  @State targetPath: string = '';
  @State sourcePathUri: string = '';
  @State targetPathUri: string = '';
  @State sourcePermissionLost: boolean = false;
  @State targetPermissionLost: boolean = false;
  @State syncMode: SyncMode = 'incremental';
  @State syncDirection: SyncDirection = 'sourceToTarget';
  @State deleteExtra: boolean = false;
  @State isSyncing: boolean = false;
  @State progressPhase: string = '';
  @State progressCurrent: number = 0;
  @State progressTotal: number = 0;
  @State progressFile: string = '';
  @State progressPercentage: number = 0;
  @State hasResult: boolean = false;
  @State resultTotalFiles: number = 0;
  @State resultSyncedFiles: number = 0;
  @State resultSkippedFiles: number = 0;
  @State resultFailedFiles: number = 0;
  @State resultSyncedSize: number = 0;
  @State resultErrors: string[] = [];
  @State showTaskPanel: boolean = false;
  @State showLogPanel: boolean = false;
  @State tasks: SyncTask[] = [];
  @State selectedTaskId: string = '';
  @State isInitialized: boolean = false;
  @State standardDirs: StandardDir[] = [];
  @State autoSync: boolean = false;
  @State autoSyncInterval: number = 30;
  @State isAutoSyncing: boolean = false;
  @State lastSyncTime: number = 0;
  @State showAutoSyncPanel: boolean = false;
  @State themeMode: string = 'system';
  @State saveTaskFeedback: string = '';
  @State editingTaskId: string = '';
  @State editingTaskName: string = '';

  private syncService: FileSyncService = new FileSyncService();
  private taskManager: SyncTaskManager = new SyncTaskManager();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private autoSyncTimer: number = -1;
  private prefsStore: preferences.Preferences | null = null;

  async aboutToAppear(): Promise<void> {
    await this.activatePersistedUri();
    await this.taskManager.init(this.context);
    this.tasks = this.taskManager.getTasks();
    this.loadStandardDirectories();
    await this.loadSettings();
    this.isInitialized = true;
  }

  // A persisted grant is still unusable until it is reactivated into memory on every start.
  // Activate the stored source/target URIs before loadSettings probes accessibility.
  private async activatePersistedUri(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, 'sync_settings');
      const savedSourceUri = await store.get('sourcePathUri', '') as string;
      const savedTargetUri = await store.get('targetPathUri', '') as string;
      const uris: string[] = [];
      if (UriPermission.isUri(savedSourceUri)) {
        uris.push(savedSourceUri);
      }
      if (UriPermission.isUri(savedTargetUri) && uris.indexOf(savedTargetUri) < 0) {
        uris.push(savedTargetUri);
      }
      if (uris.length > 0) {
        await UriPermission.activate(uris);
      }
    } catch (e) {
      console.error(`Failed to activate URI permission: ${JSON.stringify(e)}`);
    }
  }

  async aboutToDisappear(): Promise<void> {
    this.stopAutoSync();
    await this.saveSettings();
  }

  private async loadSettings(): Promise<void> {
    try {
      this.prefsStore = await preferences.getPreferences(this.context, 'sync_settings');
      const savedSource = await this.prefsStore.get('sourcePath', '') as string;
      const savedTarget = await this.prefsStore.get('targetPath', '') as string;
      const savedSourceUri = await this.prefsStore.get('sourcePathUri', '') as string;
      const savedTargetUri = await this.prefsStore.get('targetPathUri', '') as string;
      const savedMode = await this.prefsStore.get('syncMode', 'incremental') as string;
      const savedDirection = await this.prefsStore.get('syncDirection', 'sourceToTarget') as string;
      const savedDeleteExtra = await this.prefsStore.get('deleteExtra', false) as boolean;
      const savedAutoSync = await this.prefsStore.get('autoSync', false) as boolean;
      const savedInterval = await this.prefsStore.get('autoSyncInterval', 30) as number;
      const savedLastSync = await this.prefsStore.get('lastSyncTime', 0) as number;
      const savedTheme = await this.prefsStore.get('themeMode', 'system') as string;

      if (savedSourceUri !== '') {
        this.sourcePathUri = savedSourceUri;
        const plainPath = this.convertUriToPath(savedSourceUri);
        this.sourcePath = plainPath;
        const listable = this.checkDirectoryListable(plainPath);
        this.sourcePermissionLost = !listable;
        console.log(`Source: listable=${listable}, path=${plainPath}`);
      } else if (savedSource !== '') {
        this.sourcePath = savedSource;
        this.sourcePermissionLost = true;
      }
      if (savedTargetUri !== '') {
        this.targetPathUri = savedTargetUri;
        const plainPath = this.convertUriToPath(savedTargetUri);
        this.targetPath = plainPath;
        const listable = this.checkDirectoryListable(plainPath);
        this.targetPermissionLost = !listable;
        console.log(`Target: listable=${listable}, path=${plainPath}`);
      } else if (savedTarget !== '') {
        this.targetPath = savedTarget;
        this.targetPermissionLost = true;
      }

      this.syncMode = savedMode as SyncMode;
      this.syncDirection = savedDirection as SyncDirection;
      this.deleteExtra = savedDeleteExtra;
      this.autoSync = savedAutoSync;
      this.autoSyncInterval = savedInterval;
      this.lastSyncTime = savedLastSync;
      this.themeMode = savedTheme;
      this.applyTheme(savedTheme);

      if (this.autoSync && this.sourcePath !== '' && this.targetPath !== '' &&
        !this.sourcePermissionLost && !this.targetPermissionLost) {
        this.startAutoSync();
      }
    } catch (e) {
      console.error(`Failed to load settings: ${JSON.stringify(e)}`);
    }
  }

  private async saveSettings(): Promise<void> {
    if (this.prefsStore === null) {
      return;
    }
    try {
      await this.prefsStore.put('sourcePath', this.sourcePath);
      await this.prefsStore.put('targetPath', this.targetPath);
      await this.prefsStore.put('sourcePathUri', this.sourcePathUri);
      await this.prefsStore.put('targetPathUri', this.targetPathUri);
      await this.prefsStore.put('syncMode', this.syncMode);
      await this.prefsStore.put('syncDirection', this.syncDirection);
      await this.prefsStore.put('deleteExtra', this.deleteExtra);
      await this.prefsStore.put('autoSync', this.autoSync);
      await this.prefsStore.put('autoSyncInterval', this.autoSyncInterval);
      await this.prefsStore.put('lastSyncTime', this.lastSyncTime);
      await this.prefsStore.put('themeMode', this.themeMode);
      await this.prefsStore.flush();
    } catch (e) {
      console.error(`Failed to save settings: ${JSON.stringify(e)}`);
    }
  }

  private loadStandardDirectories(): void {
    const dirs: StandardDir[] = [];

    const dirPaths: string[][] = [
      ['下载', '/storage/Users/currentUser/Download'],
      ['文档', '/storage/Users/currentUser/Documents'],
      ['图片', '/storage/Users/currentUser/Pictures'],
      ['视频', '/storage/Users/currentUser/Videos'],
      ['音乐', '/storage/Users/currentUser/Music']
    ];

    for (let i = 0; i < dirPaths.length; i++) {
      const entry = dirPaths[i];
      const dirName = entry[0];
      const dirPath = entry[1];
      try {
        fileIo.accessSync(dirPath);
        fileIo.listFileSync(dirPath);
        dirs.push({ name: dirName, path: dirPath } as StandardDir);
      } catch (e) {
        // skip inaccessible directory
      }
    }

    this.standardDirs = dirs;
  }

  private applyTheme(mode: string): void {
    try {
      if (mode === 'light') {
        this.context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (mode === 'dark') {
        this.context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        this.context.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (e) {
      console.error(`Failed to apply theme: ${JSON.stringify(e)}`);
    }
  }

  private startAutoSync(): void {
    this.stopAutoSync();
    if (!this.autoSync || this.sourcePath === '' || this.targetPath === '' ||
      this.sourcePermissionLost || this.targetPermissionLost) {
      return;
    }
    const intervalMs = this.autoSyncInterval * 1000;
    this.autoSyncTimer = setInterval(() => {
      this.checkAndAutoSync();
    }, intervalMs);
    console.log(`Auto-sync started, checking every ${this.autoSyncInterval} seconds`);
    this.checkAndAutoSync();
  }

  private stopAutoSync(): void {
    if (this.autoSyncTimer !== -1) {
      clearInterval(this.autoSyncTimer);
      this.autoSyncTimer = -1;
    }
  }

  private async takeSourceSnapshot(): Promise<string> {
    try {
      const scanPath = this.sourcePathUri !== '' ? this.sourcePathUri : this.sourcePath;
      const files = await this.syncService.scanDirectory(scanPath);
      let snapshot = '';
      for (let i = 0; i < files.length; i++) {
        const f = files[i];
        snapshot += `${f.relativePath}:${f.size}:${f.mtime}|`;
      }
      return snapshot;
    } catch (e) {
      console.error(`Failed to take source snapshot: ${JSON.stringify(e)}`);
      return '';
    }
  }

  private async takeTargetSnapshot(): Promise<string> {
    try {
      const scanPath = this.targetPathUri !== '' ? this.targetPathUri : this.targetPath;
      const files = await this.syncService.scanDirectory(scanPath);
      let snapshot = '';
      for (let i = 0; i < files.length; i++) {
        const f = files[i];
        snapshot += `${f.relativePath}:${f.size}:${f.mtime}|`;
      }
      return snapshot;
    } catch (e) {
      console.error(`Failed to take target snapshot: ${JSON.stringify(e)}`);
      return '';
    }
  }

  private async checkAndAutoSync(): Promise<void> {
    if (this.isSyncing || this.isAutoSyncing || this.sourcePath === '' || this.targetPath === '' ||
      this.sourcePermissionLost || this.targetPermissionLost) {
      return;
    }

    try {
      const snapshots = await Promise.all([
        this.takeSourceSnapshot(),
        this.takeTargetSnapshot()
      ]);
      const sourceSnapshot = snapshots[0];
      const targetSnapshot = snapshots[1];

      if (sourceSnapshot === '' || targetSnapshot === '') {
        return;
      }

      if (sourceSnapshot !== targetSnapshot) {
        console.log('Auto-sync: source and target differ, starting sync...');
        await this.performAutoSync();
      }
    } catch (e) {
      console.error(`Auto-sync check failed: ${JSON.stringify(e)}`);
    }
  }

  private async performAutoSync(): Promise<void> {
    this.isAutoSyncing = true;
    this.progressPhase = 'scanning';
    this.progressFile = '自动同步中...';
    this.progressPercentage = 0;

    const self = this;
    this.syncService.setProgressCallback((p: SyncProgress) => {
      self.progressPhase = p.phase;
      self.progressCurrent = p.current;
      self.progressTotal = p.total;
      self.progressFile = p.currentFile;
      self.progressPercentage = p.percentage;
    });

    const startTime = Date.now();

    try {
      let actualSource = this.sourcePathUri !== '' ? this.sourcePathUri : this.sourcePath;
      let actualTarget = this.targetPathUri !== '' ? this.targetPathUri : this.targetPath;

      if (this.syncDirection === 'targetToSource') {
        const temp = actualSource;
        actualSource = actualTarget;
        actualTarget = temp;
      }

      const result = await this.syncService.sync(
        actualSource,
        actualTarget,
        this.syncMode,
        this.deleteExtra
      );

      if (this.syncDirection === 'bidirectional') {
        const reverseResult = await this.syncService.sync(
          actualTarget,
          actualSource,
          this.syncMode,
          false
        );
        result.syncedFiles += reverseResult.syncedFiles;
        result.totalFiles += reverseResult.totalFiles;
        result.syncedSize += reverseResult.syncedSize;
        result.failedFiles += reverseResult.failedFiles;
        for (let i = 0; i < reverseResult.errors.length; i++) {
          result.errors.push(reverseResult.errors[i]);
        }
      }

      this.hasResult = true;
      this.resultTotalFiles = result.totalFiles;
      this.resultSyncedFiles = result.syncedFiles;
      this.resultSkippedFiles = result.skippedFiles;
      this.resultFailedFiles = result.failedFiles;
      this.resultSyncedSize = result.syncedSize;
      this.resultErrors = result.errors;

      const endTime = Date.now();
      this.lastSyncTime = endTime;
      await this.saveSettings();

      const logInput: NewLogInput = {
        taskId: 'auto',
        taskName: '自动同步',
        startTime: startTime,
        endTime: endTime,
        mode: this.syncMode,
        totalFiles: result.totalFiles,
        syncedFiles: result.syncedFiles,
        skippedFiles: result.skippedFiles,
        failedFiles: result.failedFiles,
        totalSize: result.totalSize,
        syncedSize: result.syncedSize,
        errors: result.errors,
        status: result.failedFiles > 0 ? (result.syncedFiles > 0 ? 'partial' : 'failed') : 'success'
      };
      this.taskManager.addLog(logInput);

      if (result.syncedFiles > 0) {
        this.progressFile = `自动同步完成：${result.syncedFiles} 个文件已同步`;
      } else {
        this.progressFile = '自动同步完成：没有需要同步的文件';
      }
      this.progressPhase = 'complete';
    } catch (e) {
      console.error(`Auto-sync failed: ${JSON.stringify(e)}`);
      this.progressFile = '自动同步失败';
      this.progressPhase = 'complete';
    }

    this.isAutoSyncing = false;
  }

  build() {
    Stack() {
      Column() {
        this.HeaderBar()

        Scroll() {
          Column() {
            Column() {
              this.SourceSelector()
            }.margin({ bottom: 16 }).width('100%')

            Column() {
              this.TargetSelector()
            }.margin({ bottom: 16 }).width('100%')

            if (this.standardDirs.length > 0) {
              Column() {
                this.StandardDirSelector()
              }.margin({ bottom: 16 }).width('100%')
            }

            Column() {
              this.SyncOptions()
            }.margin({ bottom: 16 }).width('100%')

            Column() {
              this.AutoSyncSection()
            }.margin({ bottom: 16 }).width('100%')

            Column() {
              this.ThemeSection()
            }.margin({ bottom: 16 }).width('100%')

            Column() {
              this.QuickActions()
            }.margin({ bottom: 16 }).width('100%')

            Column() {
              this.ProgressSection()
            }.margin({ bottom: 16 }).width('100%')

            Column() {
              this.ResultSection()
            }.margin({ bottom: 16 }).width('100%')

            this.SyncButton()
          }
          .width('100%')
          .padding(16)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_gray'))

      if (this.showTaskPanel) {
        Column() {
          this.TaskPanel()
        }
        .width('100%')
        .height('100%')
        .padding({ top: 56 })
        .backgroundColor($r('app.color.bg_gray'))
      }
      if (this.showLogPanel) {
        Column() {
          this.LogPanel()
        }
        .width('100%')
        .height('100%')
        .padding({ top: 56 })
        .backgroundColor($r('app.color.bg_gray'))
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  HeaderBar() {
    Row() {
      Text('文件夹同步工具')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Button('任务')
        .fontSize(14)
        .height(36)
        .onClick(() => {
          this.showTaskPanel = !this.showTaskPanel;
          this.showLogPanel = false;
        })

      Button('日志')
        .fontSize(14)
        .height(36)
        .margin({ left: 8 })
        .onClick(() => {
          this.showLogPanel = !this.showLogPanel;
          this.showTaskPanel = false;
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_bg'))
    .shadow({ radius: 2, color: 'rgba(0,0,0,0.1)', offsetY: 1 })
  }

  @Builder
  SourceSelector() {
    Column() {
      Text('源文件夹路径')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 8 })

      TextInput({ text: this.sourcePath, placeholder: '输入或粘贴源文件夹完整路径' })
        .fontSize(14)
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(8)
        .onChange((value: string) => {
          this.sourcePath = value;
        })

      if (this.sourcePermissionLost) {
        Text('⚠ 权限已失效，请点击"选择文件夹"重新授权')
          .fontSize(12)
          .fontColor($r('app.color.danger_color'))
          .margin({ top: 4 })
          .width('100%')
      } else if (this.sourcePath !== '') {
        Text('如需重新授权，请点击右侧"选择文件夹"')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
          .width('100%')
      }

      Row() {
        Blank().layoutWeight(1)

        Button('选择文件夹')
          .fontSize(12)
          .height(32)
          .onClick(() => {
            this.selectSourceFolder();
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
  }

  @Builder
  TargetSelector() {
    Column() {
      Text('目标文件夹路径')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 8 })

      TextInput({ text: this.targetPath, placeholder: '输入或粘贴目标文件夹完整路径（支持移动硬盘）' })
        .fontSize(14)
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(8)
        .onChange((value: string) => {
          this.targetPath = value;
        })

      if (this.targetPermissionLost) {
        Text(' 权限已失效，请点击"选择文件夹"重新授权')
          .fontSize(12)
          .fontColor($r('app.color.danger_color'))
          .margin({ top: 4 })
          .width('100%')
      } else if (this.targetPath !== '') {
        Text('如需重新授权，请点击右侧"选择文件夹"')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
          .width('100%')
      }

      Row() {
        Blank().layoutWeight(1)

        Button('选择文件夹')
          .fontSize(12)
          .height(32)
          .onClick(() => {
            this.selectTargetFolder();
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
  }

  @Builder
  StandardDirSelector() {
    Column() {
      Text('常用目录（点击设为源或目标）')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 8 })

      ForEach(this.standardDirs, (dir: StandardDir) => {
        Row() {
          Column() {
            Text(dir.name)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Text(dir.path)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)

          Button('源')
            .fontSize(12)
            .height(28)
            .onClick(() => {
              this.sourcePath = dir.path;
            })

          Button('目标')
            .fontSize(12)
            .height(28)
            .margin({ left: 8 })
            .onClick(() => {
              this.targetPath = dir.path;
            })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(8)
  }

  @Builder
  SyncOptions() {
    Column() {
      Text('同步选项')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 12 })

      Row() {
        Text('同步模式')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Select([
          { value: '增量同步' },
          { value: '全量同步' }
        ])
          .selected(this.syncMode === 'incremental' ? 0 : 1)
          .value(this.syncMode === 'incremental' ? '增量同步' : '全量同步')
          .width(120)
          .onSelect((index: number) => {
            this.syncMode = index === 0 ? 'incremental' : 'full';
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius({ topLeft: 8, topRight: 8 })

      Divider().margin({ left: 12, right: 12 })

      Row() {
        Text('同步方向')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Select([
          { value: '源 → 目标' },
          { value: '目标 → 源' },
          { value: '双向同步' }
        ])
          .selected(this.syncDirection === 'sourceToTarget' ? 0 :
            (this.syncDirection === 'targetToSource' ? 1 : 2))
          .value(this.syncDirection === 'sourceToTarget' ? '源 → 目标' :
            (this.syncDirection === 'targetToSource' ? '目标 → 源' : '双向同步'))
          .width(120)
          .onSelect((index: number) => {
            this.syncDirection = index === 0 ? 'sourceToTarget' :
              (index === 1 ? 'targetToSource' : 'bidirectional');
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.card_bg'))

      Divider().margin({ left: 12, right: 12 })

      Row() {
        Text('删除目标中多余文件')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.deleteExtra })
          .onChange((isOn: boolean) => {
            this.deleteExtra = isOn;
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius({ bottomLeft: 8, bottomRight: 8 })

      Text(this.getModeDescription())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  AutoSyncSection() {
    Column() {
      Row() {
        Text('自动同步')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.autoSync })
          .onChange((isOn: boolean) => {
            this.autoSync = isOn;
            if (isOn) {
              this.startAutoSync();
            } else {
              this.stopAutoSync();
            }
            this.saveSettings();
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius({ topLeft: 8, topRight: 8 })

      if (this.autoSync) {
        Divider().margin({ left: 12, right: 12 })

        Row() {
          Text('检查间隔')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))

          Blank()

          Text(`${this.autoSyncInterval} 秒`)
            .fontSize(14)
            .fontColor($r('app.color.primary_color'))
            .margin({ right: 8 })

          Button('−')
            .fontSize(24)
            .width(48)
            .height(48)
            .fontColor($r('app.color.button_text'))
            .backgroundColor($r('app.color.card_bg'))
            .border({ width: 2, color: $r('app.color.button_border') })
            .borderRadius(8)
            .onClick(() => {
              if (this.autoSyncInterval > 10) {
                this.autoSyncInterval -= 10;
                this.startAutoSync();
                this.saveSettings();
              }
            })

          Button('+')
            .fontSize(24)
            .width(48)
            .height(48)
            .fontColor($r('app.color.button_text'))
            .backgroundColor($r('app.color.card_bg'))
            .border({ width: 2, color: $r('app.color.button_border') })
            .borderRadius(8)
            .margin({ left: 8 })
            .onClick(() => {
              if (this.autoSyncInterval < 300) {
                this.autoSyncInterval += 10;
                this.startAutoSync();
                this.saveSettings();
              }
            })
        }
        .width('100%')
        .height(48)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.card_bg'))

        Divider().margin({ left: 12, right: 12 })

        Row() {
          Text(this.isAutoSyncing ? '正在同步...' : (this.lastSyncTime > 0 ? `上次同步: ${this.taskManager.formatTime(this.lastSyncTime)}` : '等待检测变化'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)

          if (this.autoSyncTimer !== -1) {
            Text('监控中')
              .fontSize(12)
              .fontColor($r('app.color.success_color'))
          }
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius({ bottomLeft: 8, bottomRight: 8 })
      }
    }
    .width('100%')
  }

  @Builder
  ThemeSection() {
    Column() {
      Text('显示模式')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 12 })

      Row() {
        Text('浅色')
          .fontSize(14)
          .fontColor(this.themeMode === 'light' ? $r('app.color.primary_color') : $r('app.color.text_secondary'))
          .fontWeight(this.themeMode === 'light' ? FontWeight.Bold : FontWeight.Normal)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .height(40)
          .borderRadius(6)
          .border({
            width: this.themeMode === 'light' ? 1 : 0,
            color: $r('app.color.primary_color')
          })
          .onClick(() => {
            this.themeMode = 'light';
            this.applyTheme('light');
            this.saveSettings();
          })

        Text('深色')
          .fontSize(14)
          .fontColor(this.themeMode === 'dark' ? $r('app.color.primary_color') : $r('app.color.text_secondary'))
          .fontWeight(this.themeMode === 'dark' ? FontWeight.Bold : FontWeight.Normal)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .height(40)
          .borderRadius(6)
          .border({
            width: this.themeMode === 'dark' ? 1 : 0,
            color: $r('app.color.primary_color')
          })
          .onClick(() => {
            this.themeMode = 'dark';
            this.applyTheme('dark');
            this.saveSettings();
          })

        Text('跟随系统')
          .fontSize(14)
          .fontColor(this.themeMode === 'system' ? $r('app.color.primary_color') : $r('app.color.text_secondary'))
          .fontWeight(this.themeMode === 'system' ? FontWeight.Bold : FontWeight.Normal)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .height(40)
          .borderRadius(6)
          .border({
            width: this.themeMode === 'system' ? 1 : 0,
            color: $r('app.color.primary_color')
          })
          .onClick(() => {
            this.themeMode = 'system';
            this.applyTheme('system');
            this.saveSettings();
          })
      }
      .width('100%')
      .padding(4)
      .backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: $r('app.color.button_border') })
      .borderRadius(8)
    }
    .width('100%')
  }

  @Builder
  QuickActions() {
    Column() {
      Text('快捷操作')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 8 })

      Flex({ wrap: FlexWrap.Wrap }) {
        Button(this.saveTaskFeedback !== '' ? this.saveTaskFeedback : '保存到任务')
          .fontSize(13)
          .height(36)
          .margin({ right: 8, bottom: 8 })
          .enabled(this.sourcePath !== '' && this.targetPath !== '' && this.saveTaskFeedback === '')
          .backgroundColor(this.saveTaskFeedback !== '' ? $r('app.color.success_color') : undefined)
          .onClick(() => this.saveCurrentTask())

        Button('扫描差异')
          .fontSize(13)
          .height(36)
          .margin({ right: 8, bottom: 8 })
          .enabled(this.sourcePath !== '' && this.targetPath !== '' && !this.isSyncing)
          .onClick(() => this.scanDifferences())

        Button('检测移动硬盘')
          .fontSize(13)
          .height(36)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => this.detectStorageDevices())

        Button('自检测试')
          .fontSize(13)
          .height(36)
          .margin({ right: 8, bottom: 8 })
          .backgroundColor($r('app.color.success_color'))
          .enabled(!this.isSyncing)
          .onClick(() => this.runSelfTest())
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(8)
  }

  @Builder
  ProgressSection() {
    if (this.isSyncing || this.progressPhase === 'complete') {
      Column() {
        Text(this.getPhaseText())
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 8 })

        Progress({ value: this.progressPercentage, total: 100, type: ProgressType.Linear })
          .width('100%')
          .color($r('app.color.primary_color'))

        Row() {
          Text(this.progressFile)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`${this.progressCurrent}/${this.progressTotal}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 8 })
        .alignItems(VerticalAlign.Top)

        if (this.isSyncing) {
          Button('取消同步')
            .fontSize(13)
            .height(32)
            .margin({ top: 12 })
            .backgroundColor($r('app.color.danger_color'))
            .onClick(() => {
              this.syncService.cancel();
              this.isSyncing = false;
            })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(8)
    }
  }

  @Builder
  ResultSection() {
    if (this.hasResult) {
      Column() {
        Text('同步结果')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 12 })

        this.ResultRow('总文件数', `${this.resultTotalFiles}`)
        this.ResultRow('已同步', `${this.resultSyncedFiles}`)
        this.ResultRow('已跳过', `${this.resultSkippedFiles}`)
        this.ResultRow('失败', `${this.resultFailedFiles}`)
        this.ResultRow('同步大小', this.taskManager.formatSize(this.resultSyncedSize))

        if (this.resultErrors.length > 0) {
          Text(`错误 (${this.resultErrors.length})`)
            .fontSize(13)
            .fontColor($r('app.color.danger_color'))
            .margin({ top: 12 })

          Column() {
            ForEach(this.resultErrors, (error: string) => {
              Text(error)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 4 })
                .width('100%')
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            })
          }
          .width('100%')
          .margin({ top: 8 })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(8)
    }
  }

  @Builder
  ResultRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
      Text(value)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(28)
  }

  @Builder
  SyncButton() {
    Button(this.isSyncing ? '同步中...' : '开始同步')
      .width('100%')
      .height(48)
      .fontSize(16)
      .enabled(!this.isSyncing && this.sourcePath !== '' && this.targetPath !== '' &&
        !this.sourcePermissionLost && !this.targetPermissionLost)
      .onClick(() => this.startSync())
  }

  @Builder
  TaskPanel() {
    Column() {
      Row() {
        Text('同步任务')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)

        Button('关闭')
          .fontSize(13)
          .height(32)
          .onClick(() => { this.showTaskPanel = false; })
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })

      if (this.tasks.length === 0) {
        Text('暂无保存的任务，配置好源文件夹和目标文件夹后点击"保存到任务"即可创建')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 32 })
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        List() {
          ForEach(this.tasks, (task: SyncTask) => {
            ListItem() {
              Column() {
                if (this.editingTaskId === task.id) {
                  Row() {
                    TextInput({ text: this.editingTaskName })
                      .fontSize(14)
                      .layoutWeight(1)
                      .height(32)
                      .padding({ left: 8, right: 8 })
                      .backgroundColor($r('app.color.bg_gray'))
                      .borderRadius(6)
                      .onChange((value: string) => {
                        this.editingTaskName = value;
                      })
                      .onSubmit(() => {
                        this.finishRenameTask(task.id);
                      })

                    Button('保存')
                      .fontSize(12)
                      .height(28)
                      .margin({ left: 8 })
                      .onClick(() => {
                        this.finishRenameTask(task.id);
                      })

                    Button('取消')
                      .fontSize(12)
                      .height(28)
                      .margin({ left: 4 })
                      .onClick(() => {
                        this.editingTaskId = '';
                        this.editingTaskName = '';
                      })
                  }
                  .width('100%')
                } else {
                  Row() {
                    Text(task.name)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.primary_color'))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .onClick(() => {
                        this.editingTaskId = task.id;
                        this.editingTaskName = task.name;
                      })

                    Text(this.selectedTaskId === task.id ? '当前' : '')
                      .fontSize(11)
                      .fontColor($r('app.color.success_color'))
                      .margin({ left: 8 })
                  }
                  .width('100%')
                }

                Text(`${task.sourcePath} → ${task.targetPath}`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 4 })
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Row() {
                  Text(task.mode === 'full' ? '全量同步' : '增量同步')
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  Text(' | ')
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  Text(this.getDirectionText(task.direction))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                  if (task.deleteExtra) {
                    Text(' | 删除多余')
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  Blank()
                  Text(`上次: ${this.taskManager.formatTime(task.lastSyncTime)}`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .margin({ top: 4 })

                Row() {
                  Button('加载')
                    .fontSize(12)
                    .height(28)
                    .onClick(() => this.loadTask(task))

                  Button('执行')
                    .fontSize(12)
                    .height(28)
                    .margin({ left: 8 })
                    .onClick(() => this.executeTask(task))

                  Button('重命名')
                    .fontSize(12)
                    .height(28)
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.editingTaskId = task.id;
                      this.editingTaskName = task.name;
                    })

                  Button('删除')
                    .fontSize(12)
                    .height(28)
                    .margin({ left: 8 })
                    .backgroundColor($r('app.color.danger_color'))
                    .onClick(() => {
                      this.taskManager.deleteTask(task.id);
                      this.tasks = this.taskManager.getTasks();
                      if (this.selectedTaskId === task.id) {
                        this.selectedTaskId = '';
                      }
                    })
                }
                .margin({ top: 8 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(this.selectedTaskId === task.id ? $r('app.color.primary_color_light') : $r('app.color.card_bg'))
              .borderRadius(8)
              .margin({ bottom: 8 })
            }
            .width('100%')
          })
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.card_bg'))
    .align(Alignment.Top)
  }

  @Builder
  LogPanel() {
    Column() {
      Row() {
        Text('同步日志')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)

        Button('清空')
          .fontSize(13)
          .height(32)
          .margin({ right: 8 })
          .onClick(() => {
            this.taskManager.clearLogs();
          })

        Button('关闭')
          .fontSize(13)
          .height(32)
          .onClick(() => { this.showLogPanel = false; })
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })

      List() {
        ForEach(this.taskManager.getLogs(), (log: SyncLog) => {
          ListItem() {
            Column() {
              Row() {
                Text(log.taskName)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(log.status === 'success' ? '成功' :
                  (log.status === 'partial' ? '部分成功' :
                    (log.status === 'cancelled' ? '已取消' : '失败')))
                  .fontSize(12)
                  .fontColor(log.status === 'success' ? $r('app.color.success_color') :
                    (log.status === 'cancelled' ? $r('app.color.warning_color') :
                      $r('app.color.danger_color')))
                  .margin({ left: 8 })
              }
              .width('100%')

              Text(`${this.taskManager.formatTime(log.startTime)} | ${log.mode === 'full' ? '全量' : '增量'}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 4 })
                .width('100%')

              Text(`同步 ${log.syncedFiles}/${log.totalFiles} 文件, ${this.taskManager.formatSize(log.syncedSize)}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 2 })
                .width('100%')

              if (log.errors.length > 0) {
                Text(`错误 (${log.errors.length}):`)
                  .fontSize(11)
                  .fontColor($r('app.color.danger_color'))
                  .margin({ top: 6 })
                  .width('100%')

                ForEach(log.errors, (error: string) => {
                  Text(error)
                    .fontSize(10)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                    .width('100%')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                })
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(8)
            .margin({ bottom: 8 })
          }
          .width('100%')
        })
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.card_bg'))
    .align(Alignment.Top)
  }

  private getModeDescription(): string {
    if (this.syncMode === 'full') {
      return '全量同步：复制所有文件，无论目标是否已存在';
    }
    return '增量同步：仅复制新增或修改过的文件（基于修改时间和大小）';
  }

  private getPhaseText(): string {
    if (this.progressPhase === 'scanning') return '正在扫描文件...';
    if (this.progressPhase === 'comparing') return '正在比较差异...';
    if (this.progressPhase === 'syncing') return `正在同步 (${this.progressPercentage}%)`;
    if (this.progressPhase === 'complete') return '同步完成';
    return '';
  }

  private showError(message: string): void {
    this.hasResult = true;
    this.resultTotalFiles = 0;
    this.resultSyncedFiles = 0;
    this.resultSkippedFiles = 0;
    this.resultFailedFiles = 0;
    this.resultSyncedSize = 0;
    this.resultErrors = [message];
  }

  private async selectSourceFolder(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker(this.context);
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      const fileUris: string[] = await docPicker.select(options);
      if (fileUris && fileUris.length > 0) {
        const uri = fileUris[0];
        this.sourcePathUri = uri;
        console.log(`Source: picker returned URI: ${uri}`);

        // Persist immediately: the picker grant is temporary and would be dropped if we waited
        // for a later confirm step. READ and WRITE must both be persisted.
        const persistErr = await UriPermission.persist(uri);
        if (persistErr !== '') {
          console.error(`Source: persistPermission failed: ${persistErr}`);
        }

        const plainPath = this.convertUriToPath(uri);
        this.sourcePath = plainPath;
        this.sourcePermissionLost = false;
        console.log(`Source: selected via picker, path=${plainPath}`);
        this.tryRestartAutoSync();
      }
    } catch (e) {
      console.error(`Failed to select source folder: ${JSON.stringify(e)}`);
    }
    await this.saveSettings();
  }

  private async selectTargetFolder(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker(this.context);
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      const fileUris: string[] = await docPicker.select(options);
      if (fileUris && fileUris.length > 0) {
        const uri = fileUris[0];
        this.targetPathUri = uri;
        console.log(`Target: picker returned URI: ${uri}`);

        // Persist immediately: the picker grant is temporary and would be dropped if we waited
        // for a later confirm step. READ and WRITE must both be persisted.
        const persistErr = await UriPermission.persist(uri);
        if (persistErr !== '') {
          console.error(`Target: persistPermission failed: ${persistErr}`);
        }

        const plainPath = this.convertUriToPath(uri);
        this.targetPath = plainPath;
        this.targetPermissionLost = false;
        console.log(`Target: selected via picker, path=${plainPath}`);
        this.tryRestartAutoSync();
      }
    } catch (e) {
      console.error(`Failed to select target folder: ${JSON.stringify(e)}`);
    }
    await this.saveSettings();
  }

  private tryRestartAutoSync(): void {
    if (this.autoSync && this.sourcePath !== '' && this.targetPath !== '' &&
      !this.sourcePermissionLost && !this.targetPermissionLost && this.autoSyncTimer === -1) {
      this.startAutoSync();
    }
  }

  private convertUriToPath(uri: string): string {
    if (uri.startsWith('file://docs')) {
      return uri.replace('file://docs', '');
    }
    if (uri.startsWith('file://')) {
      return uri.replace('file://', '');
    }
    return uri;
  }

  private isUriPath(path: string): boolean {
    return path.startsWith('file://');
  }

  private checkDirectoryListable(path: string): boolean {
    try {
      fileIo.statSync(path);
    } catch (e) {
      console.error(`checkDirectoryListable: statSync failed for ${path}: ${JSON.stringify(e)}`);
      return false;
    }
    try {
      const entries = fileIo.listFileSync(path);
      console.info(`checkDirectoryListable: ${path} -> ${entries.length} entries`);
      // Listing succeeds => the grant is live. An empty folder is legitimate and must not be
      // treated as lost permission.
      return true;
    } catch (e) {
      console.error(`checkDirectoryListable: listFileSync failed for ${path}: ${JSON.stringify(e)}`);
    }
    return false;
  }

  private async checkPathAccessible(path: string): Promise<boolean> {
    if (path.startsWith('file://')) {
      try {
        const f = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
        fileIo.closeSync(f);
        console.log(`checkPathAccessible: URI accessible via openSync: ${path}`);
        return true;
      } catch (e) {
        console.log(`checkPathAccessible: openSync(URI) failed: ${JSON.stringify(e)}`);
      }

      try {
        fileIo.accessSync(path);
        console.log(`checkPathAccessible: URI accessible via accessSync: ${path}`);
        return true;
      } catch (e) {
      }
      try {
        fileIo.statSync(path);
        console.log(`checkPathAccessible: URI accessible via statSync: ${path}`);
        return true;
      } catch (e) {
      }
      try {
        fileIo.listFileSync(path);
        console.log(`checkPathAccessible: URI accessible via listFileSync: ${path}`);
        return true;
      } catch (e) {
      }
    }

    try {
      fileIo.accessSync(path);
      return true;
    } catch (e) {
    }
    try {
      fileIo.statSync(path);
      return true;
    } catch (e) {
    }
    try {
      fileIo.listFileSync(path);
      return true;
    } catch (e) {
    }

    if (path.startsWith('file://')) {
      let plainPath: string;
      if (path.startsWith('file://docs')) {
        plainPath = path.replace('file://docs', '');
      } else {
        plainPath = path.replace('file://', '');
      }
      try {
        fileIo.accessSync(plainPath);
        console.log(`checkPathAccessible: plain path accessible: ${plainPath}`);
        return true;
      } catch (e) {
      }
      try {
        fileIo.statSync(plainPath);
        console.log(`checkPathAccessible: plain path stat OK: ${plainPath}`);
        return true;
      } catch (e) {
      }
      try {
        fileIo.listFileSync(plainPath);
        console.log(`checkPathAccessible: plain path listable: ${plainPath}`);
        return true;
      } catch (e) {
      }
    }
    return false;
  }

  private async startSync(): Promise<void> {
    if (this.sourcePath === '' || this.targetPath === '') {
      this.showError('请输入源文件夹和目标文件夹路径');
      return;
    }

    let actualSource = this.sourcePath;
    let actualTarget = this.targetPath;

    const sourceAccessible = await this.checkPathAccessible(actualSource);
    if (!sourceAccessible) {
      this.showError(`无法访问源文件夹：${actualSource}。请重新授权文件夹。`);
      return;
    }

    const targetAccessible = await this.checkPathAccessible(actualTarget);
    if (!targetAccessible) {
      this.showError(`无法访问目标文件夹：${actualTarget}。请重新授权文件夹。`);
      return;
    }

    this.isSyncing = true;
    this.hasResult = false;
    this.progressPhase = 'scanning';
    this.progressCurrent = 0;
    this.progressTotal = 0;
    this.progressFile = '';
    this.progressPercentage = 0;

    const self = this;
    this.syncService.setProgressCallback((p: SyncProgress) => {
      self.progressPhase = p.phase;
      self.progressCurrent = p.current;
      self.progressTotal = p.total;
      self.progressFile = p.currentFile;
      self.progressPercentage = p.percentage;
    });

    const startTime = Date.now();

    try {
      let syncSource = actualSource;
      let syncTarget = actualTarget;

      if (this.syncDirection === 'targetToSource') {
        syncSource = actualTarget;
        syncTarget = actualSource;
      }

      const result = await this.syncService.sync(
        syncSource,
        syncTarget,
        this.syncMode,
        this.deleteExtra
      );

      if (this.syncDirection === 'bidirectional') {
        const reverseResult = await this.syncService.sync(
          actualTarget,
          actualSource,
          this.syncMode,
          false
        );
        result.syncedFiles += reverseResult.syncedFiles;
        result.totalFiles += reverseResult.totalFiles;
        result.syncedSize += reverseResult.syncedSize;
        result.failedFiles += reverseResult.failedFiles;
        for (let i = 0; i < reverseResult.errors.length; i++) {
          result.errors.push(reverseResult.errors[i]);
        }
      }

      this.hasResult = true;
      this.resultTotalFiles = result.totalFiles;
      this.resultSyncedFiles = result.syncedFiles;
      this.resultSkippedFiles = result.skippedFiles;
      this.resultFailedFiles = result.failedFiles;
      this.resultSyncedSize = result.syncedSize;
      this.resultErrors = result.errors;
      this.isSyncing = false;

      const endTime = Date.now();
      const task = this.taskManager.getTask(this.selectedTaskId);
      let taskName = '手动同步';
      if (task) {
        taskName = task.name;
      }

      let status = 'success';
      if (result.failedFiles > 0) {
        if (result.syncedFiles > 0) {
          status = 'partial';
        } else {
          status = 'failed';
        }
      }

      const logInput: NewLogInput = {
        taskId: this.selectedTaskId !== '' ? this.selectedTaskId : 'manual',
        taskName: taskName,
        startTime: startTime,
        endTime: endTime,
        mode: this.syncMode,
        totalFiles: result.totalFiles,
        syncedFiles: result.syncedFiles,
        skippedFiles: result.skippedFiles,
        failedFiles: result.failedFiles,
        totalSize: result.totalSize,
        syncedSize: result.syncedSize,
        errors: result.errors,
        status: status
      };
      this.taskManager.addLog(logInput);

      this.lastSyncTime = endTime;
      await this.saveSettings();

      if (this.selectedTaskId !== '') {
        const updateTask = this.taskManager.getTask(this.selectedTaskId);
        if (updateTask) {
          updateTask.lastSyncTime = endTime;
          updateTask.lastSyncResult = `${result.syncedFiles} 文件已同步`;
          this.taskManager.updateTask(updateTask);
        }
      }
    } catch (e) {
      this.isSyncing = false;
      const errorMsg = e instanceof Error ? e.message : String(e);
      this.showError(`同步失败：${errorMsg}`);
    }
  }

  private async scanDifferences(): Promise<void> {
    if (this.sourcePath === '' || this.targetPath === '') {
      this.showError('请输入源文件夹和目标文件夹路径');
      return;
    }

    const sourceAccessible = await this.checkPathAccessible(this.sourcePath);
    if (!sourceAccessible) {
      this.showError(`无法访问源文件夹：${this.sourcePath}。请重新授权文件夹。`);
      return;
    }

    const targetAccessible = await this.checkPathAccessible(this.targetPath);
    if (!targetAccessible) {
      this.showError(`无法访问目标文件夹：${this.targetPath}。请重新授权文件夹。`);
      return;
    }

    this.progressPhase = 'scanning';
    this.progressCurrent = 0;
    this.progressTotal = 0;
    this.progressFile = '正在扫描...';
    this.progressPercentage = 0;

    try {
      const sourceFiles = await this.syncService.scanDirectory(this.sourcePath);
      const sourceOnly: FileInfo[] = [];
      for (let i = 0; i < sourceFiles.length; i++) {
        if (!sourceFiles[i].isDirectory) {
          sourceOnly.push(sourceFiles[i]);
        }
      }

      const targetFiles = await this.syncService.scanDirectory(this.targetPath);
      const targetOnly: FileInfo[] = [];
      for (let i = 0; i < targetFiles.length; i++) {
        if (!targetFiles[i].isDirectory) {
          targetOnly.push(targetFiles[i]);
        }
      }

      const compareResult: CompareResult = await this.syncService.compareFiles(
        sourceOnly,
        targetOnly,
        this.syncMode
      );

      this.progressPhase = 'complete';
      this.progressCurrent = 0;
      this.progressTotal = compareResult.toCopy.length + compareResult.toUpdate.length;
      this.progressFile = `待同步: ${compareResult.toCopy.length + compareResult.toUpdate.length} 文件, 待删除: ${compareResult.toDelete.length} 文件`;
      this.progressPercentage = 0;
    } catch (e) {
      const errorMsg = e instanceof Error ? e.message : String(e);
      this.showError(`扫描失败：${errorMsg}`);
    }
  }

  private async detectStorageDevices(): Promise<void> {
    try {
      const devices = await this.syncService.getStorageDevices();
      if (devices.length === 0) {
        this.progressPhase = 'complete';
        this.progressCurrent = 0;
        this.progressTotal = 0;
        this.progressFile = '未检测到移动存储设备';
        this.progressPercentage = 0;
      } else {
        this.progressPhase = 'complete';
        this.progressCurrent = 0;
        this.progressTotal = 0;
        this.progressFile = `检测到 ${devices.length} 个设备: ${devices.join(', ')}`;
        this.progressPercentage = 0;
      }
    } catch (e) {
      console.error(`Detection failed: ${JSON.stringify(e)}`);
    }
  }

  private async runSelfTest(): Promise<void> {
    this.isSyncing = true;
    this.hasResult = false;
    this.progressPhase = 'scanning';
    this.progressFile = '正在执行基础同步测试...';
    this.progressPercentage = 0;

    const self = this;
    this.syncService.setProgressCallback((p: SyncProgress) => {
      self.progressPhase = p.phase;
      self.progressCurrent = p.current;
      self.progressTotal = p.total;
      self.progressFile = p.currentFile;
      self.progressPercentage = p.percentage;
    });

    try {
      const filesDir = this.context.filesDir;
      const result = await this.syncService.runSelfTest(filesDir);

      this.hasResult = true;
      this.resultTotalFiles = result.totalFiles;
      this.resultSyncedFiles = result.syncedFiles;
      this.resultSkippedFiles = result.skippedFiles;
      this.resultFailedFiles = result.failedFiles;
      this.resultSyncedSize = result.syncedSize;
      this.resultErrors = result.errors;
      this.isSyncing = false;

      if (result.failedFiles === 0 && result.syncedFiles > 0) {
        this.progressFile = `基础测试通过！成功同步 ${result.syncedFiles} 个测试文件。`;
      } else if (result.syncedFiles === 0 && result.errors.length === 0) {
        this.progressFile = '基础测试完成：没有需要同步的文件（可能已同步过）';
      } else {
        this.progressFile = '基础测试完成，请查看下方结果';
      }

      if (this.sourcePath !== '') {
        try {
          const diagResults = await this.syncService.diagnosePathAccess(this.sourcePath);
          let diagOutput = '';
          for (let i = 0; i < diagResults.length; i++) {
            diagOutput += diagResults[i] + '\n';
          }
          console.log(`Diagnostic results:\n${diagOutput}`);

          let canAccess = false;
          let canList = false;
          let fileCount = 0;
          for (let i = 0; i < diagResults.length; i++) {
            const line = diagResults[i];
            if (line.includes('statSync: OK') || line.includes('statSync(URI): OK') ||
                line.includes('accessSync: OK') || line.includes('accessSync(URI): OK') ||
                line.includes('openSync(URI, READ_ONLY): OK')) {
              canAccess = true;
            }
            if (line.includes('listFileSync: OK') ||
                line.includes('listFileSync(URI): OK') ||
                line.includes('readdirSync: OK') ||
                line.includes('opendirSync: OK') ||
                line.includes('read ')) {
              const openParen = line.indexOf('(');
              const closeParen = line.indexOf(' entries)');
              if (openParen >= 0 && closeParen > openParen) {
                const numStr = line.substring(openParen + 1, closeParen);
                const parsed = parseInt(numStr);
                if (parsed > fileCount) {
                  fileCount = parsed;
                }
              }
              const readIdx = line.indexOf('read ');
              const readEnd = line.indexOf(' entries');
              if (readIdx >= 0 && readEnd > readIdx) {
                const numStr = line.substring(readIdx + 5, readEnd);
                const parsed = parseInt(numStr);
                if (parsed > fileCount) {
                  fileCount = parsed;
                }
              }
              if (line.includes('OK')) {
                canList = true;
              }
            }
          }

          if (canList && fileCount > 0) {
            this.progressFile += ` 源文件夹可访问，包含 ${fileCount} 个条目，可以直接同步。`;
          } else if (canAccess) {
            this.progressFile += ' 源文件夹可访问（通过statSync/accessSync），但无法直接列出内容。';
            this.progressFile += ' 同步功能可能受限，建议尝试使用应用沙箱内的路径。';
          } else {
            this.progressFile += ' 源文件夹无法访问。';
            this.progressFile += ' 请点击"选择文件夹"按钮通过系统文件选择器授权访问，或使用应用沙箱内的路径。';
          }
        } catch (e) {
          // diagnostic failed, ignore
        }
      }
    } catch (e) {
      this.isSyncing = false;
      const errorMsg = e instanceof Error ? e.message : String(e);
      this.showError(`自检失败：${errorMsg}。应用沙箱目录: ${this.context.filesDir}`);
    }
  }

  private saveCurrentTask(): void {
    const taskName = `同步任务 ${this.tasks.length + 1}`;
    const task = this.taskManager.addTask({
      name: taskName,
      sourcePath: this.sourcePath,
      targetPath: this.targetPath,
      mode: this.syncMode,
      direction: this.syncDirection,
      deleteExtra: this.deleteExtra
    });
    this.tasks = this.taskManager.getTasks();
    this.selectedTaskId = task.id;
    this.saveTaskFeedback = `已保存: ${taskName}`;
    this.showTaskPanel = true;
    this.showLogPanel = false;
    setTimeout(() => {
      this.saveTaskFeedback = '';
    }, 2000);
  }

  private executeTask(task: SyncTask): void {
    this.sourcePath = task.sourcePath;
    this.targetPath = task.targetPath;
    this.syncMode = task.mode;
    this.syncDirection = task.direction;
    this.deleteExtra = task.deleteExtra;
    this.selectedTaskId = task.id;
    this.showTaskPanel = false;
    this.startSync();
  }

  private loadTask(task: SyncTask): void {
    this.sourcePath = task.sourcePath;
    this.targetPath = task.targetPath;
    this.syncMode = task.mode;
    this.syncDirection = task.direction;
    this.deleteExtra = task.deleteExtra;
    this.selectedTaskId = task.id;
    if (task.sourcePath !== '') {
      this.sourcePermissionLost = !this.checkDirectoryListable(task.sourcePath);
    } else {
      this.sourcePermissionLost = false;
    }
    if (task.targetPath !== '') {
      this.targetPermissionLost = !this.checkDirectoryListable(task.targetPath);
    } else {
      this.targetPermissionLost = false;
    }
  }

  private finishRenameTask(taskId: string): void {
    const name = this.editingTaskName.trim();
    if (name !== '') {
      const task = this.taskManager.getTask(taskId);
      if (task) {
        task.name = name;
        this.taskManager.updateTask(task);
        this.tasks = this.taskManager.getTasks();
      }
    }
    this.editingTaskId = '';
    this.editingTaskName = '';
  }

  private getDirectionText(direction: SyncDirection): string {
    if (direction === 'sourceToTarget') return '源 → 目标';
    if (direction === 'targetToSource') return '目标 → 源';
    return '双向同步';
  }
}
