import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'TrayRaise';
const DOMAIN = 0xFF00;

// The panel runs in its own process, so it cannot call showAbility() on the main ability directly;
// it raises the window by launching the singleton EntryAbility. The window must be raised only after
// the panel window itself is on screen: raising first makes the host draw the panel on top of the
// restored window, and the user has to click a second time. So every trigger (session create, page
// show, foreground) gets its own raise; the main ability is a singleton, so repeats are no-ops.
export class TrayRaise {
  private static handler: ((from: string) => void) | null = null;

  static setHandler(handler: ((from: string) => void) | null): void {
    TrayRaise.handler = handler;
  }

  static raise(from: string): void {
    hilog.info(DOMAIN, TAG, 'tray raise from=%{public}s', from);
    const handler = TrayRaise.handler;
    if (handler === null) {
      hilog.warn(DOMAIN, TAG, 'tray raise has no panel to launch the main ability with');
      return;
    }
    handler(from);
  }
}
