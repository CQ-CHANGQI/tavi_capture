import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // 原型是 1180×738 的采集平板；桌面上先给一个接近的窗口。
    self.title = "Tavi Capture"
    self.isRestorable = false
    self.minSize = NSSize(width: 720, height: 620)
    // nib 的 frame 在 awakeFromNib 之后还会被套用一次，等这一轮结束再改。
    DispatchQueue.main.async {
      self.setContentSize(NSSize(width: 1180, height: 760))
      guard let visible = NSScreen.screens.first?.visibleFrame else { return }
      let frame = self.frame
      let origin = NSPoint(
        x: visible.midX - frame.width / 2,
        y: visible.midY - frame.height / 2
      )
      self.setFrameOrigin(origin)
      self.makeKeyAndOrderFront(nil)
    }
  }
}
