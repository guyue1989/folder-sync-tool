import { SyncMode, SyncDirection } from './FileSyncService';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export interface SyncTask {
  id: string;
  name: string;
  sourcePath: string;
  targetPath: string;
  mode: SyncMode;
  direction: SyncDirection;
  deleteExtra: boolean;
  lastSyncTime: number;
  lastSyncResult: string;
  createdAt: number;
}

export interface SyncLog {
  id: string;
  taskId: string;
  taskName: string;
  startTime: number;
  endTime: number;
  mode: SyncMode;
  totalFiles: number;
  syncedFiles: number;
  skippedFiles: number;
  failedFiles: number;
  totalSize: number;
  syncedSize: number;
  errors: string[];
  status: string;
}

export interface NewTaskInput {
  name: string;
  sourcePath: string;
  targetPath: string;
  mode: SyncMode;
  direction: SyncDirection;
  deleteExtra: boolean;
}

export interface NewLogInput {
  taskId: string;
  taskName: string;
  startTime: number;
  endTime: number;
  mode: SyncMode;
  totalFiles: number;
  syncedFiles: number;
  skippedFiles: number;
  failedFiles: number;
  totalSize: number;
  syncedSize: number;
  errors: string[];
  status: string;
}

const PREF_NAME = 'sync_preferences';
const KEY_TASKS = 'sync_tasks';
const KEY_LOGS = 'sync_logs';

export class SyncTaskManager {
  private tasks: SyncTask[] = [];
  private logs: SyncLog[] = [];
  private context: common.UIAbilityContext | null = null;
  private store: preferences.Preferences | null = null;

  async init(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    try {
      this.store = await preferences.getPreferences(context, PREF_NAME);
    } catch (e) {
      this.store = null;
    }
    this.loadTasks();
    this.loadLogs();
  }

  private loadTasks(): void {
    if (!this.store) return;
    try {
      const data = this.store.getSync(KEY_TASKS, '[]') as string;
      this.tasks = JSON.parse(data);
    } catch (e) {
      this.tasks = [];
    }
  }

  private saveTasks(): void {
    if (!this.store) return;
    try {
      this.store.putSync(KEY_TASKS, JSON.stringify(this.tasks));
      this.store.flush();
    } catch (e) {
      console.error('Failed to save tasks');
    }
  }

  private loadLogs(): void {
    if (!this.store) return;
    try {
      const data = this.store.getSync(KEY_LOGS, '[]') as string;
      this.logs = JSON.parse(data);
    } catch (e) {
      this.logs = [];
    }
  }

  private saveLogs(): void {
    if (!this.store) return;
    try {
      this.store.putSync(KEY_LOGS, JSON.stringify(this.logs));
      this.store.flush();
    } catch (e) {
      console.error('Failed to save logs');
    }
  }

  addTask(input: NewTaskInput): SyncTask {
    const newTask: SyncTask = {
      id: this.generateId(),
      name: input.name,
      sourcePath: input.sourcePath,
      targetPath: input.targetPath,
      mode: input.mode,
      direction: input.direction,
      deleteExtra: input.deleteExtra,
      createdAt: Date.now(),
      lastSyncTime: 0,
      lastSyncResult: ''
    };
    this.tasks.push(newTask);
    this.saveTasks();
    return newTask;
  }

  updateTask(task: SyncTask): void {
    const index = this.tasks.findIndex(t => t.id === task.id);
    if (index >= 0) {
      this.tasks[index] = task;
      this.saveTasks();
    }
  }

  deleteTask(taskId: string): void {
    const newTasks: SyncTask[] = [];
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id !== taskId) {
        newTasks.push(this.tasks[i]);
      }
    }
    this.tasks = newTasks;
    this.saveTasks();
  }

  getTasks(): SyncTask[] {
    const result: SyncTask[] = [];
    for (let i = 0; i < this.tasks.length; i++) {
      result.push(this.tasks[i]);
    }
    return result;
  }

  getTask(taskId: string): SyncTask | undefined {
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id === taskId) {
        return this.tasks[i];
      }
    }
    return undefined;
  }

  addLog(input: NewLogInput): SyncLog {
    const newLog: SyncLog = {
      id: this.generateId(),
      taskId: input.taskId,
      taskName: input.taskName,
      startTime: input.startTime,
      endTime: input.endTime,
      mode: input.mode,
      totalFiles: input.totalFiles,
      syncedFiles: input.syncedFiles,
      skippedFiles: input.skippedFiles,
      failedFiles: input.failedFiles,
      totalSize: input.totalSize,
      syncedSize: input.syncedSize,
      errors: input.errors,
      status: input.status
    };
    this.logs.unshift(newLog);
    if (this.logs.length > 100) {
      this.logs = this.logs.slice(0, 100);
    }
    this.saveLogs();
    return newLog;
  }

  getLogs(): SyncLog[] {
    const result: SyncLog[] = [];
    for (let i = 0; i < this.logs.length; i++) {
      result.push(this.logs[i]);
    }
    return result;
  }

  getLogsByTask(taskId: string): SyncLog[] {
    const result: SyncLog[] = [];
    for (let i = 0; i < this.logs.length; i++) {
      if (this.logs[i].taskId === taskId) {
        result.push(this.logs[i]);
      }
    }
    return result;
  }

  clearLogs(): void {
    this.logs = [];
    this.saveLogs();
  }

  private generateId(): string {
    return Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
  }

  formatSize(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  formatTime(timestamp: number): string {
    if (timestamp === 0) return '从未同步';
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}`;
  }

  formatDuration(startTime: number, endTime: number): string {
    const duration = endTime - startTime;
    if (duration < 1000) return `${duration}ms`;
    const seconds = Math.floor(duration / 1000);
    if (seconds < 60) return `${seconds}秒`;
    const minutes = Math.floor(seconds / 60);
    const remainSeconds = seconds % 60;
    if (minutes < 60) return `${minutes}分${remainSeconds}秒`;
    const hours = Math.floor(minutes / 60);
    const remainMinutes = minutes % 60;
    return `${hours}小时${remainMinutes}分`;
  }
}
