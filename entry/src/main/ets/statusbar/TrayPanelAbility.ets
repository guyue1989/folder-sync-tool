import { StatusBarViewExtensionAbility } from '@kit.DeskTopExtensionKit';
import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TrayRaise } from './TrayRaise';

const TAG = 'TrayPanelAbility';
const DOMAIN = 0xFF00;
const BUNDLE_NAME = 'com.niangao.foldersync';

// Left click on the status-bar icon opens this panel: it is the only left-click channel this device
// delivers — the documented statusBarIconClick event never fires. It runs in its own process, so the
// window comes back by launching the singleton main ability rather than by calling showAbility().
//
// The session is never closed by us. terminateSelf() makes the host reopen the panel ~100ms later and
// that empty panel is drawn on top of the window we just restored, which reads as "the icon needs two
// clicks". Leaving the session alone costs nothing.
export default class TrayPanelAbility extends StatusBarViewExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    hilog.info(DOMAIN, TAG, 'tray panel session created');
    TrayRaise.setHandler((from: string): void => {
      this.startMainWindow(from);
    });
    try {
      session.loadContent('pages/TrayPanelPage');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'tray panel content failed: %{public}s', JSON.stringify(e) ?? '');
    }
    TrayRaise.raise('create');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'tray panel foreground');
    TrayRaise.raise('foreground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'tray panel background');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'tray panel destroyed');
    TrayRaise.setHandler(null);
  }

  private startMainWindow(from: string): void {
    const target: Want = {
      bundleName: BUNDLE_NAME,
      abilityName: 'EntryAbility'
    };
    this.context.startAbility(target).then(() => {
      hilog.info(DOMAIN, TAG, 'main ability raised from=%{public}s', from);
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'tray raise from=%{public}s failed: %{public}s', from, e.message ?? '');
    });
  }
}
