import { fileIo } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';

export interface FileInfo {
  path: string;
  name: string;
  isDirectory: boolean;
  size: number;
  mtime: number;
  relativePath: string;
}

export interface SyncResult {
  totalFiles: number;
  syncedFiles: number;
  skippedFiles: number;
  failedFiles: number;
  totalSize: number;
  syncedSize: number;
  errors: string[];
}

export interface SyncProgress {
  current: number;
  total: number;
  currentFile: string;
  percentage: number;
  phase: string;
}

export interface CompareResult {
  toCopy: FileInfo[];
  toDelete: FileInfo[];
  toUpdate: FileInfo[];
}

export type SyncMode = 'full' | 'incremental';
export type SyncDirection = 'sourceToTarget' | 'targetToSource' | 'bidirectional';

export type ProgressCallback = (progress: SyncProgress) => void;

@Concurrent
function copyFileTask(srcPath: string, destPath: string): boolean {
  const destDir = destPath.substring(0, destPath.lastIndexOf('/'));

  const isUri = destDir.startsWith('file://');
  let plainDir: string = '';
  if (isUri) {
    if (destDir.startsWith('file://docs')) {
      plainDir = destDir.replace('file://docs', '');
    } else {
      plainDir = destDir.replace('file://', '');
    }
  }

  try {
    fileIo.mkdirSync(destDir, true);
  } catch (e) {
    if (isUri) {
      try {
        fileIo.mkdirSync(plainDir, true);
      } catch (e2) {
      }
    }
  }

  let srcFile: fileIo.File;
  try {
    srcFile = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
  } catch (e) {
    if (srcPath.startsWith('file://')) {
      let plainSrc: string;
      if (srcPath.startsWith('file://docs')) {
        plainSrc = srcPath.replace('file://docs', '');
      } else {
        plainSrc = srcPath.replace('file://', '');
      }
      srcFile = fileIo.openSync(plainSrc, fileIo.OpenMode.READ_ONLY);
    } else {
      return false;
    }
  }

  let destFile: fileIo.File;
  try {
    destFile = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  } catch (e) {
    if (isUri) {
      destFile = fileIo.openSync(plainDir + destPath.substring(destDir.length), fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    } else {
      return false;
    }
  }

  const bufferSize = 64 * 1024;
  const buffer = new ArrayBuffer(bufferSize);
  let readLen = 0;

  try {
    do {
      readLen = fileIo.readSync(srcFile.fd, buffer);
      if (readLen > 0) {
        const writeBuffer = buffer.slice(0, readLen);
        fileIo.writeSync(destFile.fd, writeBuffer);
      }
    } while (readLen > 0);
  } finally {
    fileIo.closeSync(srcFile);
    fileIo.closeSync(destFile);
  }

  return true;
}

export class FileSyncService {
  private progressCallback: ProgressCallback | null = null;
  private isCancelled: boolean = false;

  setProgressCallback(callback: ProgressCallback | null): void {
    this.progressCallback = callback;
  }

  cancel(): void {
    this.isCancelled = true;
  }

  private isUri(path: string): boolean {
    return path.startsWith('file://');
  }

  private uriToPlainPath(uri: string): string {
    if (uri.startsWith('file://docs')) {
      return uri.replace('file://docs', '');
    }
    if (uri.startsWith('file://')) {
      return uri.replace('file://', '');
    }
    return uri;
  }

  private async yieldToUI(): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, 0);
    });
  }

  async scanDirectory(dirPath: string, basePath?: string): Promise<FileInfo[]> {
    const files: FileInfo[] = [];

    let entries: string[] = [];

    try {
      entries = fileIo.listFileSync(dirPath);
      console.log(`scanDirectory: listFileSync("${dirPath}") returned ${entries.length} entries`);
    } catch (e) {
      console.log(`scanDirectory: listFileSync("${dirPath}") failed: ${JSON.stringify(e)}`);
      if (this.isUri(dirPath)) {
        const plainPath = this.uriToPlainPath(dirPath);
        try {
          entries = fileIo.listFileSync(plainPath);
          console.log(`scanDirectory: fallback listFileSync("${plainPath}") returned ${entries.length} entries`);
          dirPath = plainPath;
        } catch (e2) {
          console.error(`scanDirectory: fallback listFileSync("${plainPath}") also failed: ${JSON.stringify(e2)}`);
          return files;
        }
      } else {
        return files;
      }
    }

    for (let i = 0; i < entries.length; i++) {
      if (this.isCancelled) break;

      if (i % 50 === 0 && i > 0) {
        await this.yieldToUI();
      }

      const entry = entries[i];
      if (entry === '.' || entry === '..') continue;

      const fullPath = `${dirPath}/${entry}`;
      let stat: fileIo.Stat | null = null;
      try {
        stat = fileIo.statSync(fullPath);
      } catch (e) {
        if (this.isUri(fullPath)) {
          const plainChild = this.uriToPlainPath(fullPath);
          try {
            stat = fileIo.statSync(plainChild);
          } catch (e2) {
          }
        }
        if (stat === null) {
          continue;
        }
      }

      const storedBase = basePath ?? dirPath;
      const storedRelative = fullPath.substring(storedBase.length + 1);

      const fileInfo: FileInfo = {
        path: fullPath,
        name: entry,
        isDirectory: stat.isDirectory(),
        size: stat.size,
        mtime: stat.mtime,
        relativePath: storedRelative
      };

      files.push(fileInfo);

      if (stat.isDirectory()) {
        const subFiles = await this.scanDirectory(fullPath, basePath ?? dirPath);
        for (let j = 0; j < subFiles.length; j++) {
          files.push(subFiles[j]);
        }
      }
    }

    return files;
  }

  async compareFiles(
    sourceFiles: FileInfo[],
    targetFiles: FileInfo[],
    mode: SyncMode
  ): Promise<CompareResult> {
    const result: CompareResult = {
      toCopy: [],
      toDelete: [],
      toUpdate: []
    };

    const targetMap = new Map<string, FileInfo>();
    for (let i = 0; i < targetFiles.length; i++) {
      targetMap.set(targetFiles[i].relativePath, targetFiles[i]);
    }

    const sourceMap = new Map<string, FileInfo>();
    for (let i = 0; i < sourceFiles.length; i++) {
      sourceMap.set(sourceFiles[i].relativePath, sourceFiles[i]);
    }

    for (let i = 0; i < sourceFiles.length; i++) {
      if (this.isCancelled) break;
      if (i % 200 === 0 && i > 0) {
        await this.yieldToUI();
      }
      const sf = sourceFiles[i];
      const tf = targetMap.get(sf.relativePath);
      if (!tf) {
        result.toCopy.push(sf);
      } else if (mode === 'full') {
        result.toUpdate.push(sf);
      } else if (mode === 'incremental') {
        if (sf.mtime > tf.mtime || sf.size !== tf.size) {
          result.toUpdate.push(sf);
        }
      }
    }

    for (let i = 0; i < targetFiles.length; i++) {
      if (this.isCancelled) break;
      if (i % 200 === 0 && i > 0) {
        await this.yieldToUI();
      }
      const tf = targetFiles[i];
      if (!sourceMap.has(tf.relativePath)) {
        result.toDelete.push(tf);
      }
    }

    return result;
  }

  private async copyFile(srcPath: string, destPath: string): Promise<void> {
    try {
      const task = new taskpool.Task(copyFileTask, srcPath, destPath);
      await taskpool.execute(task);
    } catch (e) {
      console.error(`copyFile taskpool failed: ${JSON.stringify(e)}, falling back to main thread`);
      await this.copyFileSync(srcPath, destPath);
    }
  }

  private async copyFileSync(srcPath: string, destPath: string): Promise<void> {
    const destDir = destPath.substring(0, destPath.lastIndexOf('/'));
    if (this.isUri(destDir)) {
      const plainDir = this.uriToPlainPath(destDir);
      try {
        fileIo.mkdirSync(destDir, true);
      } catch (e) {
        try {
          fileIo.mkdirSync(plainDir, true);
        } catch (e2) {
        }
      }
    } else {
      this.ensureDirExists(destDir);
    }

    let srcFile: fileIo.File;
    if (this.isUri(srcPath)) {
      try {
        srcFile = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
      } catch (e) {
        const plainSrc = this.uriToPlainPath(srcPath);
        srcFile = fileIo.openSync(plainSrc, fileIo.OpenMode.READ_ONLY);
      }
    } else {
      srcFile = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
    }
    let destFile: fileIo.File;
    if (this.isUri(destPath)) {
      try {
        destFile = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      } catch (e) {
        const plainDest = this.uriToPlainPath(destPath);
        destFile = fileIo.openSync(plainDest, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      }
    } else {
      destFile = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    }

    const bufferSize = 64 * 1024;
    const buffer = new ArrayBuffer(bufferSize);
    let readLen = 0;
    let chunkCount = 0;

    do {
      if (this.isCancelled) {
        fileIo.closeSync(srcFile);
        fileIo.closeSync(destFile);
        return;
      }
      readLen = fileIo.readSync(srcFile.fd, buffer);
      if (readLen > 0) {
        const writeBuffer = buffer.slice(0, readLen);
        fileIo.writeSync(destFile.fd, writeBuffer);
        chunkCount++;
        if (chunkCount % 100 === 0) {
          await this.yieldToUI();
        }
      }
    } while (readLen > 0);

    fileIo.closeSync(srcFile);
    fileIo.closeSync(destFile);
  }

  private ensureDirExists(dirPath: string): void {
    try {
      fileIo.mkdirSync(dirPath, true);
    } catch (e) {
      // might already exist or permission issue
    }
  }

  private reportProgress(phase: string, current: number, total: number, currentFile: string): void {
    if (this.progressCallback) {
      const progress: SyncProgress = {
        phase: phase,
        current: current,
        total: total,
        currentFile: currentFile,
        percentage: total > 0 ? Math.round((current / total) * 100) : 0
      };
      this.progressCallback(progress);
    }
  }

  async sync(
    sourcePath: string,
    targetPath: string,
    mode: SyncMode,
    deleteExtra: boolean = false
  ): Promise<SyncResult> {
    this.isCancelled = false;

    const result: SyncResult = {
      totalFiles: 0,
      syncedFiles: 0,
      skippedFiles: 0,
      failedFiles: 0,
      totalSize: 0,
      syncedSize: 0,
      errors: []
    };

    try {
      this.reportProgress('scanning', 0, 0, '正在扫描源文件夹...');
      const sourceFiles = await this.scanDirectory(sourcePath);
      const sourceOnlyFiles: FileInfo[] = [];
      for (let i = 0; i < sourceFiles.length; i++) {
        if (!sourceFiles[i].isDirectory) {
          sourceOnlyFiles.push(sourceFiles[i]);
        }
      }

      this.reportProgress('scanning', 0, 0, '正在扫描目标文件夹...');
      let targetFiles: FileInfo[] = [];
      let targetExists = false;

      try {
        fileIo.accessSync(targetPath);
        targetExists = true;
      } catch (e) {
      }

      if (!targetExists) {
        try {
          fileIo.statSync(targetPath);
          targetExists = true;
        } catch (e2) {
        }
      }

      if (!targetExists) {
        try {
          fileIo.listFileSync(targetPath);
          targetExists = true;
        } catch (e3) {
        }
      }

      if (!targetExists && this.isUri(targetPath)) {
        const plainTarget = this.uriToPlainPath(targetPath);
        try {
          fileIo.accessSync(plainTarget);
          targetExists = true;
          console.log(`sync: target accessible via plain path: ${plainTarget}`);
        } catch (e4) {
        }
        if (!targetExists) {
          try {
            fileIo.listFileSync(plainTarget);
            targetExists = true;
            console.log(`sync: target listable via plain path: ${plainTarget}`);
          } catch (e5) {
          }
        }
      }

      if (targetExists) {
        targetFiles = await this.scanDirectory(targetPath);
      } else {
        let created = false;
        if (this.isUri(targetPath)) {
          const plainTarget = this.uriToPlainPath(targetPath);
          try {
            fileIo.mkdirSync(plainTarget, true);
            created = true;
            console.log(`sync: created target via plain path: ${plainTarget}`);
          } catch (e) {
            console.log(`sync: mkdirSync("${plainTarget}") failed: ${JSON.stringify(e)}`);
          }
        } else {
          try {
            fileIo.mkdirSync(targetPath, true);
            created = true;
          } catch (e) {
            console.log(`sync: mkdirSync("${targetPath}") failed: ${JSON.stringify(e)}`);
          }
        }
        if (!created) {
          result.errors.push(`无法创建目标目录: ${targetPath}`);
          return result;
        }
      }

      this.reportProgress('comparing', 0, 0, '正在比较文件差异...');
      const compareResult = await this.compareFiles(sourceOnlyFiles, targetFiles, mode);
      const toCopy = compareResult.toCopy;
      const toDelete = compareResult.toDelete;
      const toUpdate = compareResult.toUpdate;

      result.totalFiles = toCopy.length + toUpdate.length;
      let totalSize = 0;
      for (let i = 0; i < toCopy.length; i++) {
        totalSize += toCopy[i].size;
      }
      for (let i = 0; i < toUpdate.length; i++) {
        totalSize += toUpdate[i].size;
      }
      result.totalSize = totalSize;

      const allToSync: FileInfo[] = [];
      for (let i = 0; i < toCopy.length; i++) {
        allToSync.push(toCopy[i]);
      }
      for (let i = 0; i < toUpdate.length; i++) {
        allToSync.push(toUpdate[i]);
      }
      let processedCount = 0;

      for (let i = 0; i < allToSync.length; i++) {
        if (this.isCancelled) break;
        const file = allToSync[i];
        const destPath = `${targetPath}/${file.relativePath}`;
        this.reportProgress('syncing', processedCount, allToSync.length, file.name);

        try {
          await this.copyFile(file.path, destPath);
          result.syncedFiles++;
          result.syncedSize += file.size;
        } catch (e) {
          result.failedFiles++;
          result.errors.push(`Failed to copy ${file.relativePath}: ${JSON.stringify(e)}`);
        }
        processedCount++;

        if (i % 10 === 0 && i > 0) {
          await this.yieldToUI();
        }
      }

      if (deleteExtra) {
        // unlinkSync cannot remove a directory (fails with 13900019 "Is a directory"), so split the
        // extras: remove files first, then directories deepest-first so each is empty by the time
        // rmdirSync reaches it.
        const deleteFiles: FileInfo[] = [];
        const deleteDirs: FileInfo[] = [];
        for (let i = 0; i < toDelete.length; i++) {
          if (toDelete[i].isDirectory) {
            deleteDirs.push(toDelete[i]);
          } else {
            deleteFiles.push(toDelete[i]);
          }
        }
        for (let i = 0; i < deleteFiles.length; i++) {
          if (this.isCancelled) break;
          this.removeEntry(deleteFiles[i].path, false, result);
        }
        deleteDirs.sort((a: FileInfo, b: FileInfo): number => b.path.length - a.path.length);
        for (let i = 0; i < deleteDirs.length; i++) {
          if (this.isCancelled) break;
          this.removeEntry(deleteDirs[i].path, true, result);
        }
      } else {
        result.skippedFiles = toDelete.length;
      }

      this.reportProgress('complete', allToSync.length, allToSync.length, '同步完成');
    } catch (e) {
      result.errors.push(`Sync error: ${JSON.stringify(e)}`);
    }

    return result;
  }

  // unlinkSync only removes files; rmdirSync only removes empty directories. Callers must delete the
  // files inside a directory before the directory itself, deepest-first.
  private removeEntry(path: string, isDirectory: boolean, result: SyncResult): void {
    try {
      if (isDirectory) {
        fileIo.rmdirSync(path);
      } else {
        fileIo.unlinkSync(path);
      }
    } catch (e) {
      if (this.isUri(path)) {
        const plainPath = this.uriToPlainPath(path);
        try {
          if (isDirectory) {
            fileIo.rmdirSync(plainPath);
          } else {
            fileIo.unlinkSync(plainPath);
          }
        } catch (e2) {
          result.errors.push(`Failed to delete ${path}: ${JSON.stringify(e2)}`);
        }
      } else {
        result.errors.push(`Failed to delete ${path}: ${JSON.stringify(e)}`);
      }
    }
  }

  async getDirectorySize(dirPath: string): Promise<number> {
    const files = await this.scanDirectory(dirPath);
    let totalSize = 0;
    for (let i = 0; i < files.length; i++) {
      if (!files[i].isDirectory) {
        totalSize += files[i].size;
      }
    }
    return totalSize;
  }

  async getStorageDevices(): Promise<string[]> {
    const devices: string[] = [];
    const mountPaths: string[] = [
      '/storage',
      '/mnt/media_rw',
      '/dev/block'
    ];

    for (let i = 0; i < mountPaths.length; i++) {
      const mountPath = mountPaths[i];
      try {
        fileIo.accessSync(mountPath);
        const entries = fileIo.listFileSync(mountPath);
        for (let j = 0; j < entries.length; j++) {
          const entry = entries[j];
          const fullPath = `${mountPath}/${entry}`;
          try {
            const stat = fileIo.statSync(fullPath);
            if (stat.isDirectory()) {
              devices.push(fullPath);
            }
          } catch (e) {
            // skip inaccessible
          }
        }
      } catch (e) {
        // skip
      }
    }

    return devices;
  }

  async runSelfTest(basePath: string): Promise<SyncResult> {
    const testSource = `${basePath}/test_sync_source`;
    const testTarget = `${basePath}/test_sync_target`;

    try {
      fileIo.mkdirSync(testSource, true);
      fileIo.mkdirSync(`${testSource}/subdir`, true);
    } catch (e) {
      // may already exist
    }

    const testFiles: string[] = [
      `${testSource}/file1.txt`,
      `${testSource}/file2.txt`,
      `${testSource}/subdir/file3.txt`
    ];
    const testContents: string[] = [
      'Hello, this is test file 1',
      'Hello, this is test file 2 with more content',
      'Hello, this is test file 3 in a subdirectory'
    ];

    for (let i = 0; i < testFiles.length; i++) {
      let fd: fileIo.File;
      try {
        fd = fileIo.openSync(testFiles[i], fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      } catch (e) {
        continue;
      }
      const content = testContents[i];
      const buffer = new ArrayBuffer(content.length);
      const uint8 = new Uint8Array(buffer);
      for (let j = 0; j < content.length; j++) {
        uint8[j] = content.charCodeAt(j);
      }
      try {
        fileIo.writeSync(fd.fd, buffer);
      } catch (e) {
        // write error
      }
      try {
        fileIo.closeSync(fd);
      } catch (e) {
        // close error
      }
    }

    try {
      fileIo.mkdirSync(testTarget, true);
    } catch (e) {
      // may already exist
    }

    return this.sync(testSource, testTarget, 'incremental', false);
  }

  async scanDirectoryCount(dirPath: string): Promise<number> {
    const files = await this.scanDirectory(dirPath);
    let count = 0;
    for (let i = 0; i < files.length; i++) {
      if (!files[i].isDirectory) {
        count++;
      }
    }
    return count;
  }

  async diagnosePathAccess(path: string): Promise<string[]> {
    const results: string[] = [];
    results.push(`Testing access to: ${path}`);
    results.push(`Is URI: ${path.startsWith('file://')}`);

    if (path.startsWith('file://')) {
      results.push('');
      results.push('=== Testing URI access methods ===');

      try {
        const stat = fileIo.statSync(path);
        results.push(`1. statSync(URI): OK (isDir=${stat.isDirectory()}, size=${stat.size})`);
      } catch (e) {
        results.push(`1. statSync(URI): FAILED - ${JSON.stringify(e)}`);
      }

      try {
        fileIo.accessSync(path);
        results.push('2. accessSync(URI): OK');
      } catch (e) {
        results.push(`2. accessSync(URI): FAILED - ${JSON.stringify(e)}`);
      }

      try {
        const f = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
        fileIo.closeSync(f);
        results.push('3. openSync(URI, READ_ONLY): OK');
      } catch (e) {
        results.push(`3. openSync(URI, READ_ONLY): FAILED - ${JSON.stringify(e)}`);
      }

      try {
        const entries = fileIo.listFileSync(path);
        results.push(`4. listFileSync(URI): OK (${entries.length} entries)`);
        if (entries.length > 0) {
          results.push(`   First 3: ${entries.slice(0, 3).join(', ')}`);
        }
      } catch (e) {
        results.push(`4. listFileSync(URI): FAILED - ${JSON.stringify(e)}`);
      }

      let stripped: string;
      if (path.startsWith('file://docs')) {
        stripped = path.replace('file://docs', '');
      } else {
        stripped = path.replace('file://', '');
      }
      results.push('');
      results.push(`=== Testing stripped path: ${stripped} ===`);
      try {
        fileIo.accessSync(stripped);
        results.push('5. accessSync(stripped): OK');
      } catch (e) {
        results.push(`5. accessSync(stripped): FAILED - ${JSON.stringify(e)}`);
      }
      try {
        const entries = fileIo.listFileSync(stripped);
        results.push(`6. listFileSync(stripped): OK (${entries.length} entries)`);
      } catch (e) {
        results.push(`6. listFileSync(stripped): FAILED - ${JSON.stringify(e)}`);
      }
    } else {
      results.push('');
      results.push('=== Testing plain path access ===');

      try {
        fileIo.accessSync(path);
        results.push('1. accessSync: OK');
      } catch (e) {
        results.push(`1. accessSync: FAILED - ${JSON.stringify(e)}`);
      }

      try {
        const stat = fileIo.statSync(path);
        results.push(`2. statSync: OK (isDir=${stat.isDirectory()}, size=${stat.size})`);
      } catch (e) {
        results.push(`2. statSync: FAILED - ${JSON.stringify(e)}`);
      }

      try {
        const entries = fileIo.listFileSync(path);
        results.push(`3. listFileSync: OK (${entries.length} entries)`);
        if (entries.length > 0) {
          results.push(`   First 3: ${entries.slice(0, 3).join(', ')}`);
        }
      } catch (e) {
        results.push(`3. listFileSync: FAILED - ${JSON.stringify(e)}`);
      }
    }

    return results;
  }
}
