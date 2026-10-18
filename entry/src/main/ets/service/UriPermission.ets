import { fileShare } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'UriPermission';
const DOMAIN = 0xFF00;

// A picker grant is temporary: it is dropped when the app exits or the device reboots.
// persistPermission keeps it across restarts; activatePermission reloads it into memory on every
// start — a persisted grant is still unusable without that call. WRITE_MODE does not imply read
// access, so persisting write alone leaves the folder unreadable after a restart.
export class UriPermission {
  static isUri(path: string): boolean {
    return path.startsWith('file://');
  }

  // Returns '' when the grant was persisted, otherwise the reason, for inline display.
  static async persist(uri: string): Promise<string> {
    if (!UriPermission.isUri(uri)) {
      return '';
    }
    const policy: fileShare.PolicyInfo = {
      uri: uri,
      operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
    };
    try {
      await fileShare.persistPermission([policy]);
      hilog.info(DOMAIN, TAG, 'persistPermission READ|WRITE ok: %{public}s', uri);
      return '';
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'persistPermission failed: %{public}s', JSON.stringify(e) ?? '');
      return err.message ?? '授权持久化失败';
    }
  }

  // Every folder the app touches this run goes in one call; the system resolves them individually.
  static async activate(uris: string[]): Promise<boolean> {
    const policies: fileShare.PolicyInfo[] = [];
    for (const u of uris) {
      if (UriPermission.isUri(u)) {
        const policy: fileShare.PolicyInfo = {
          uri: u,
          operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
        };
        policies.push(policy);
      }
    }
    if (policies.length === 0) {
      return true;
    }
    try {
      await fileShare.activatePermission(policies);
      hilog.info(DOMAIN, TAG, 'activatePermission ok for %{public}d uri(s)', policies.length);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'activatePermission failed: %{public}s', JSON.stringify(e) ?? '');
      return false;
    }
  }
}
