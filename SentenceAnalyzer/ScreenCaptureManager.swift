import AppKit

class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()
    private var completion: ((NSImage?) -> Void)?

    func captureRegion(completion: @escaping (NSImage?) -> Void) {
        self.completion = completion

        let tmpPath = "/tmp/sa_capture_\(Int(Date().timeIntervalSince1970)).png"
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-i", "-s", tmpPath]

        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if FileManager.default.fileExists(atPath: tmpPath),
                   let image = NSImage(contentsOfFile: tmpPath) {
                    try? FileManager.default.removeItem(atPath: tmpPath)
                    self?.completion?(image)
                } else {
                    self?.completion?(nil)
                }
            }
        }

        try? task.run()
    }
}
