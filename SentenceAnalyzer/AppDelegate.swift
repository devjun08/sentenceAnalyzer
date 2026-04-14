import AppKit
import Carbon
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var hotKeyRef: EventHotKeyRef?
    var overlayWindow: AnalysisWindow?
    var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        registerHotKey()
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - 메뉴바

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "text.magnifyingglass",
                accessibilityDescription: "Sentence Analyzer"
            )
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "캡처 & 분석  ⌘⇧S",
            action: #selector(startCapture),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "API 키 설정",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "종료",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem?.menu = menu
    }

    // MARK: - 전역 단축키 ⌘⇧S

    func registerHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x53414E41), id: 1)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 1 // S

        RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )

        let eventSpec = [EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )]

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                if let ptr = userData {
                    Unmanaged<AppDelegate>
                        .fromOpaque(ptr)
                        .takeUnretainedValue()
                        .startCapture()
                }
                return noErr
            },
            1, eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }

    // MARK: - 캡처 시작

    @objc func startCapture() {
        ScreenCaptureManager.shared.captureRegion { [weak self] image in
            // 캡처 완료 → 패널 열고 OCR 시작 알림
            DispatchQueue.main.async {
                if self?.overlayWindow == nil {
                    self?.overlayWindow = AnalysisWindow()
                }
                self?.overlayWindow?.setStatus("🔍 텍스트 인식 중...")
                self?.overlayWindow?.show()
            }

            guard let image = image else { return }

            OCRManager.shared.extractText(from: image) { [weak self] text in
                guard let text = text, !text.isEmpty else {
                    self?.showError("텍스트를 인식하지 못했습니다.")
                    return
                }
                // OCR 완료 → 즉시 원문 카드 표시 + API 시작
                DispatchQueue.main.async {
                    self?.showAnalysisWindow(with: text)
                }
            }
        }
    }

    func showAnalysisWindow(with text: String) {
        if overlayWindow == nil {
            overlayWindow = AnalysisWindow()
        }
        overlayWindow?.setContent(text: text)
        overlayWindow?.show()
    }

    func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "오류"
            alert.informativeText = message
            alert.runModal()
        }
    }

    @objc func openSettings() {
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "API 키 설정"
        settingsWindow.center()
        settingsWindow.contentView = NSHostingView(rootView: SettingsView())
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = settingsWindow
    }
}
