import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("설정")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("GitHub Token")
                    .font(.headline)
                Text("github.com → Settings → Developer settings → Personal access tokens")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SecureField("ghp_...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Button("저장") {
                    AnalysisManager.shared.apiKey = apiKey
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        saved = false
                    }
                }
                .buttonStyle(.borderedProminent)

                if saved {
                    Label("저장됐어요", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("단축키: ⌘⇧S", systemImage: "keyboard")
                Label("화면 영역 드래그 캡처", systemImage: "selection.pin.in.out")
                Label("OCR 텍스트 인식", systemImage: "doc.text.viewfinder")
                Label("Gemini AI 문장 분석", systemImage: "brain")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(width: 400, height: 300)
    }
}
