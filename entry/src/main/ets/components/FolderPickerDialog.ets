import { FolderBrowser, FolderItem } from '../service/FolderBrowser';
import { common } from '@kit.AbilityKit';

@Component
export struct FolderPickerDialog {
  @Prop @Watch('onVisibleChange') isVisible: boolean = false;
  @Prop title: string = '选择文件夹';
  @Prop initialPath: string = '';
  onFolderSelected: (path: string) => void = (path: string) => {};
  onClose: () => void = () => {};

  @State currentPath: string = '';
  @State folders: FolderItem[] = [];
  @State isLoading: boolean = false;
  @State pathHistory: string[] = [];
  @State showPathInput: boolean = false;
  @State manualPath: string = '';

  private browser: FolderBrowser = new FolderBrowser();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.browser.init(this.context);
    if (this.initialPath !== '') {
      this.currentPath = this.initialPath;
      this.loadFolders(this.initialPath);
    } else {
      this.loadRoots();
    }
  }

  onVisibleChange(): void {
    if (this.isVisible) {
      if (this.initialPath !== '') {
        this.currentPath = this.initialPath;
        this.loadFolders(this.initialPath);
      } else {
        this.loadRoots();
      }
    }
  }

  async loadRoots(): Promise<void> {
    this.isLoading = true;
    this.currentPath = '';
    this.pathHistory = [];
    this.folders = await this.browser.getRootFolders();
    this.isLoading = false;
  }

  async loadFolders(path: string): Promise<void> {
    this.isLoading = true;
    this.folders = await this.browser.listFolders(path);
    this.isLoading = false;
  }

  navigateTo(folder: FolderItem): void {
    if (this.currentPath !== '') {
      this.pathHistory.push(this.currentPath);
    }
    this.currentPath = folder.path;
    this.loadFolders(folder.path);
  }

  navigateUp(): void {
    if (this.pathHistory.length > 0) {
      const parent = this.pathHistory.pop();
      if (parent !== undefined) {
        this.currentPath = parent;
        this.loadFolders(parent);
      }
    } else {
      const parent = this.browser.getParentPath(this.currentPath);
      if (parent !== null) {
        this.currentPath = parent;
        this.loadFolders(parent);
      } else {
        this.loadRoots();
      }
    }
  }

  selectCurrentFolder(): void {
    if (this.currentPath !== '') {
      this.onFolderSelected(this.currentPath);
    }
  }

  togglePathInput(): void {
    this.showPathInput = !this.showPathInput;
    if (this.showPathInput) {
      this.manualPath = this.currentPath;
    }
  }

  useManualPath(): void {
    if (this.manualPath !== '') {
      this.currentPath = this.manualPath;
      this.loadFolders(this.manualPath);
      this.showPathInput = false;
    }
  }

  getDisplayPath(): string {
    if (this.currentPath === '') return '根目录';
    if (this.currentPath.length > 40) {
      const parts = this.currentPath.split('/');
      if (parts.length > 3) {
        return '.../' + parts.slice(-2).join('/');
      }
    }
    return this.currentPath;
  }

  build() {
    if (this.isVisible) {
      Column() {
        // Overlay background
        Column()
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('rgba(0,0,0,0.5)')
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })

      Column() {
        // Header
        Row() {
          if (this.currentPath !== '' || this.pathHistory.length > 0) {
            Button('←')
              .fontSize(18)
              .width(40)
              .height(40)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.primary_color'))
              .onClick(() => this.navigateUp())
          }

          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .margin({ left: this.currentPath !== '' || this.pathHistory.length > 0 ? 0 : 0 })

          Button('路径')
            .fontSize(14)
            .height(36)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.primary_color'))
            .margin({ right: 8 })
            .onClick(() => this.togglePathInput())

          Button('关闭')
            .fontSize(14)
            .height(36)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 8 })

        // Manual path input
        if (this.showPathInput) {
          Row() {
            TextInput({ text: this.manualPath, placeholder: '输入完整路径' })
              .fontSize(14)
              .layoutWeight(1)
              .height(40)
              .onChange((value: string) => {
                this.manualPath = value;
              })

            Button('前往')
              .fontSize(13)
              .height(36)
              .margin({ left: 8 })
              .onClick(() => this.useManualPath())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor('#F5F5F5')
        }

        // Current path display
        Row() {
          Text(this.getDisplayPath())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('#F5F5F5')

        Divider()

        // Folder list
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color($r('app.color.primary_color'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.folders.length === 0) {
          Column() {
            Text('此目录下没有子文件夹')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 32 })
            
            Text('可以点击"路径"按钮手动输入路径')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.folders, (item: FolderItem) => {
              ListItem() {
                Row() {
                  if (item.isDirectory) {
                    Text('📁')
                      .fontSize(20)
                      .margin({ right: 12 })
                  } else {
                    Text('📄')
                      .fontSize(20)
                      .margin({ right: 12 })
                  }

                  Column() {
                    Text(item.name)
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    if (!item.isDirectory) {
                      Text('文件')
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ top: 2 })
                    }
                  }
                  .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .onClick(() => {
                  if (item.isDirectory) {
                    this.navigateTo(item);
                  }
                })
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
        }

        Divider()

        // Bottom action bar
        Row() {
          Button('选择此文件夹')
            .width('100%')
            .height(44)
            .fontSize(16)
            .enabled(this.currentPath !== '')
            .onClick(() => this.selectCurrentFolder())
        }
        .width('100%')
        .padding(16)
      }
      .width('90%')
      .height('70%')
      .backgroundColor(Color.White)
      .borderRadius(12)
      .position({ x: '5%', y: '15%' })
      .shadow({ radius: 8, color: 'rgba(0,0,0,0.2)', offsetY: 4 })
    }
  }
}
