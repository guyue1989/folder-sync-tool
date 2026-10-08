import { AbilityConstant, UIAbility, Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

const TAG = 'EntryAbility';
const DOMAIN = 0xFF00;

export default class EntryAbility extends UIAbility {
  private isBackgroundRunning: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
    this.stopBackgroundTask();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
    this.stopBackgroundTask();
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
    this.startBackgroundTask();
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
        backgroundTaskManager.startBackgroundRunning(
          self.context,
          backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
          agentObj
        ).then(() => {
          self.isBackgroundRunning = true;
          hilog.info(DOMAIN, TAG, 'Background task started');
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'startBackgroundRunning failed: %{public}s', err.message ?? '');
        });
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'getWantAgent failed: %{public}s', err.message ?? '');
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to start background task: %{public}s', JSON.stringify(e) ?? '');
    }
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
