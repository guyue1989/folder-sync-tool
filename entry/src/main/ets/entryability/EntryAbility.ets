import { AbilityConstant, UIAbility, Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { statusBarManager } from '@kit.DeskTopExtensionKit';
import { emitter } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';

const TAG = 'EntryAbility';
const DOMAIN = 0xFF00;

export default class EntryAbility extends UIAbility {
  private isBackgroundRunning: boolean = false;
  private mainWindow: window.Window | null = null;
  private statusBarActive: boolean = false;
  private isHidden: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
    this.removeStatusBarIcon();
    this.stopBackgroundTask();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate');

    windowStage.getMainWindow().then((win: window.Window) => {
      this.mainWindow = win;
      hilog.info(DOMAIN, TAG, 'Main window obtained');
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to get main window: %{public}s', err.message ?? '');
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');

      try {
        windowStage.on('windowStageClose', (): boolean => {
          hilog.info(DOMAIN, TAG, 'windowStageClose: intercepting');
          this.hideToTray();
          return true;
        });
        hilog.info(DOMAIN, TAG, 'windowStageClose listener registered');
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'windowStageClose not available: %{public}s', JSON.stringify(e) ?? '');
      }

      this.addStatusBarIcon();
      // Hold the long-running task from launch, while the window is still up. Requesting it only in
      // onBackground is a two-hop async call and loses the race when the app is backgrounded and
      // reclaimed quickly, so the process dies before startBackgroundRunning lands.
      this.startBackgroundTask();
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
    this.mainWindow = null;
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onNewWant');
    this.showMainWindow();
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
    this.isHidden = false;
    // Do not release the keepalive here. This is a tray-resident app that keeps syncing in the
    // background, so the long-running task stays held for the whole process life and is released
    // only in onDestroy. Stopping it on every foreground re-opened the background-kill race.
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
    this.startBackgroundTask();
  }

  private hideToTray(): void {
    if (this.isHidden) {
      return;
    }
    if (!this.statusBarActive) {
      if (this.mainWindow) {
        try {
          this.mainWindow.minimize();
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'minimize failed: %{public}s', JSON.stringify(e) ?? '');
        }
      }
      return;
    }
    this.isHidden = true;
    this.context.hideAbility().then(() => {
      hilog.info(DOMAIN, TAG, 'Ability hidden');
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'hideAbility failed: %{public}s', JSON.stringify(e) ?? '');
      this.isHidden = false;
      if (this.mainWindow) {
        try {
          this.mainWindow.minimize();
        } catch (e2) {
          hilog.error(DOMAIN, TAG, 'minimize also failed: %{public}s', JSON.stringify(e2) ?? '');
        }
      }
    });
  }

  private showMainWindow(): void {
    this.isHidden = false;
    this.context.showAbility().then(() => {
      hilog.info(DOMAIN, TAG, 'Ability shown');
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'showAbility failed: %{public}s', JSON.stringify(e) ?? '');
    });
  }

  private addStatusBarIcon(): void {
    if (this.statusBarActive) {
      return;
    }
    this.setupStatusBarListeners();

    const pixelMap = this.loadIconPixelMap();
    const icon: statusBarManager.StatusBarIcon = {
      white: pixelMap,
      black: pixelMap
    };

    const operation: statusBarManager.QuickOperation = {
      abilityName: 'TrayPanelAbility',
      moduleName: 'entry',
      title: '文件夹同步工具',
      height: 24
    };

    const openAction: statusBarManager.StatusBarMenuAction = {
      abilityName: 'EntryAbility',
      moduleName: 'entry'
    };
    const openMenuItem: statusBarManager.StatusBarMenuItem = {
      title: '回到主界面',
      menuAction: openAction
    };
    const menuGroup: statusBarManager.StatusBarGroupMenu = [openMenuItem];

    const item: statusBarManager.StatusBarItem = {
      icons: icon,
      quickOperation: operation,
      statusBarGroupMenu: [menuGroup]
    };

    statusBarManager.addToStatusBar(this.context, item);
    this.statusBarActive = true;
    hilog.info(DOMAIN, TAG, 'Status bar icon added');
  }

  private loadIconPixelMap(): image.PixelMap {
    const mediaData: Uint8Array = this.context.resourceManager.getMediaContentSync($r('app.media.foreground').id);
    const imgSource = image.createImageSource(mediaData.buffer as ArrayBuffer);
    // Decode to 24x24; the host's "pixelmap exceeds the limit" log fires regardless of the delivered
    // size (confirmed 2026-10-18), so this is just tidy, not a fix for that warning.
    const options: image.DecodingOptions = {
      editable: true,
      desiredSize: { width: 24, height: 24 },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    };
    const pixelMap = imgSource.createPixelMapSync(options);
    const info = pixelMap.getImageInfoSync();
    hilog.info(DOMAIN, TAG, 'Tray icon decoded %{public}d x %{public}d', info.size.width, info.size.height);
    imgSource.release();
    return pixelMap;
  }

  private removeStatusBarIcon(): void {
    if (!this.statusBarActive) {
      return;
    }
    try {
      statusBarManager.removeFromStatusBar(this.context);
      this.statusBarActive = false;
      hilog.info(DOMAIN, TAG, 'Status bar icon removed');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'removeFromStatusBar failed: %{public}s', JSON.stringify(e) ?? '');
    }
  }

  private setupStatusBarListeners(): void {
    statusBarManager.on('statusBarIconClick', (_eventData: emitter.EventData): void => {
      hilog.info(DOMAIN, TAG, 'Status bar icon clicked, restoring');
      this.showMainWindow();
    });

    statusBarManager.on('rightMenuClick', (eventData: emitter.EventData): void => {
      const data = eventData.data;
      if (data !== undefined && data !== null) {
        const menuTitle = data['title'] as string;
        hilog.info(DOMAIN, TAG, 'Menu clicked: %{public}s', menuTitle);
        if (menuTitle === '回到主界面') {
          this.showMainWindow();
        }
      }
    });
  }

  private startBackgroundTask(): void {
    if (this.isBackgroundRunning) {
      return;
    }
    try {
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: this.context.abilityInfo.bundleName,
            abilityName: this.context.abilityInfo.name
          }
        ],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      };
      const self = this;
      wantAgent.getWantAgent(agentInfo).then((agentObj: WantAgent) => {
        self.acquireKeepalive(agentObj);
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'getWantAgent failed: %{public}s', err.message ?? '');
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to start background task: %{public}s', JSON.stringify(e) ?? '');
    }
  }

  // Without one of these held, the system suspends the process as soon as the window is closed to the
  // status bar, which stops the auto-sync timer. taskKeeping is the PC/2in1 background-computation
  // type (open to third-party apps from API 20) and carries no progress obligation, which suits a
  // client idle between polls; dataTransfer is the fallback but the system cancels a transfer once
  // ~10 minutes pass without a live-window progress update, so it is the weaker keepalive.
  private async acquireKeepalive(agentObj: WantAgent): Promise<void> {
    const modes: backgroundTaskManager.BackgroundMode[] = [
      backgroundTaskManager.BackgroundMode.TASK_KEEPING,
      backgroundTaskManager.BackgroundMode.DATA_TRANSFER
    ];
    for (const mode of modes) {
      try {
        await backgroundTaskManager.startBackgroundRunning(this.context, mode, agentObj);
        this.isBackgroundRunning = true;
        hilog.info(DOMAIN, TAG, 'Background task started, mode=%{public}d', mode);
        return;
      } catch (e) {
        const err = e as BusinessError;
        if (err.code === 9800005) {
          // Already applied: a continuous task is held, so asking again is a no-op.
          this.isBackgroundRunning = true;
          hilog.info(DOMAIN, TAG, 'Background task already held, mode=%{public}d', mode);
          return;
        }
        hilog.warn(DOMAIN, TAG, 'startBackgroundRunning mode=%{public}d rejected: %{public}s',
          mode, err.message ?? '');
      }
    }
    hilog.error(DOMAIN, TAG, 'No keepalive mode available; sync may sleep while hidden');
  }

  private stopBackgroundTask(): void {
    if (!this.isBackgroundRunning) {
      return;
    }
    try {
      this.isBackgroundRunning = false;
      backgroundTaskManager.stopBackgroundRunning(this.context);
      hilog.info(DOMAIN, TAG, 'Background task stopped');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to stop background task: %{public}s', JSON.stringify(e) ?? '');
    }
  }
}
