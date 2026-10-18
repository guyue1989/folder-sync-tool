import { TrayRaise } from '../statusbar/TrayRaise';

// The panel has nothing to show; it exists so the icon's left click has a business. This page is the
// moment the panel is really on screen, so raising the main window from here lands above the panel
// instead of underneath it.
@Entry
@Component
struct TrayPanelPage {
  onPageShow(): void {
    TrayRaise.raise('page show');
  }

  build() {
    Column() {
    }
    .width('100%')
    .height('100%')
  }
}
