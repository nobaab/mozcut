import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The editor needs room for its panels; below this it would overflow.
    self.minSize = NSSize(width: 1200, height: 720)
    // Open at a comfortable editor size, centred.
    self.setContentSize(NSSize(width: 1360, height: 840))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
