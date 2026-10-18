import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export interface FolderItem {
  name: string;
  path: string;
  isDirectory: boolean;
}

interface PathEntry {
  path: string;
  name: string;
}

export class FolderBrowser {
  private context: common.UIAbilityContext | null = null;

  init(context: common.UIAbilityContext): void {
    this.context = context;
  }

  async listFolders(dirPath: string): Promise<FolderItem[]> {
    const items: FolderItem[] = [];

    try {
      const entries = fileIo.listFileSync(dirPath);

      for (let i = 0; i < entries.length; i++) {
        const entry = entries[i];
        const fullPath = `${dirPath}/${entry}`;

        try {
          const stat = fileIo.statSync(fullPath);
          items.push({
            name: entry,
            path: fullPath,
            isDirectory: stat.isDirectory()
          });
        } catch (e) {
          // Skip items we can't access
        }
      }

      // Sort: directories first, then files, both alphabetically
      items.sort((a, b) => {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        if (a.name < b.name) return -1;
        if (a.name > b.name) return 1;
        return 0;
      });
    } catch (e) {
      console.error(`Failed to list folder: ${JSON.stringify(e)}`);
    }

    return items;
  }

  async getRootFolders(): Promise<FolderItem[]> {
    const roots: FolderItem[] = [];

    try {
      // Add app's own directories first
      if (this.context) {
        const filesDir = this.context.filesDir;
        const cacheDir = this.context.cacheDir;
        const tempDir = this.context.tempDir;

        // Try to create some test folders in filesDir for demonstration
        try {
          const testDir1 = `${filesDir}/示例文件夹1`;
          const testDir2 = `${filesDir}/示例文件夹2`;
          
          try {
            fileIo.accessSync(testDir1);
          } catch (e) {
            fileIo.mkdirSync(testDir1);
          }
          
          try {
            fileIo.accessSync(testDir2);
          } catch (e) {
            fileIo.mkdirSync(testDir2);
          }
        } catch (e) {
          // Ignore errors creating test folders
        }

        roots.push({
          name: '应用文件',
          path: filesDir,
          isDirectory: true
        });

        roots.push({
          name: '缓存目录',
          path: cacheDir,
          isDirectory: true
        });

        roots.push({
          name: '临时目录',
          path: tempDir,
          isDirectory: true
        });
      }

      // Try common accessible paths
      const commonPaths: PathEntry[] = [
        { path: '/storage/Users/currentUser/Documents', name: '文档' },
        { path: '/storage/Users/currentUser/Download', name: '下载' },
        { path: '/storage/Users/currentUser/Pictures', name: '图片' },
        { path: '/storage/Users/currentUser/Music', name: '音乐' },
        { path: '/storage/Users/currentUser/Videos', name: '视频' }
      ];

      for (let i = 0; i < commonPaths.length; i++) {
        const item = commonPaths[i];
        try {
          fileIo.accessSync(item.path);
          roots.push({
            name: item.name,
            path: item.path,
            isDirectory: true
          });
        } catch (e) {
          // Path not accessible, skip it
        }
      }
    } catch (e) {
      console.error(`Failed to get root folders: ${JSON.stringify(e)}`);
    }

    return roots;
  }

  getParentPath(currentPath: string): string | null {
    const parts = currentPath.split('/');
    if (parts.length <= 2) {
      return null;
    }
    parts.pop();
    return parts.join('/');
  }
}
