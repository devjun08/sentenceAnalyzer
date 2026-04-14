import Foundation

// MARK: - 데이터 모델

struct SentenceAnalysis: Identifiable {
    let id = UUID()
    let original: String
    var translation: String?
    var structure: [SentenceComponent]?  // nil = 로딩, [] = 실패
    var structureError: String? = nil
    var questions: [String]?             // nil = 로딩, [] = 실패
    var questionsError: String? = nil
}

struct SentenceComponent: Identifiable {
    let id = UUID()
    let text: String
    let role: String
    let color: String
    let hint: String
}

// MARK: - 분석 매니저

class AnalysisManager {
    static let shared = AnalysisManager()

    // GitHub Models 설정
    private let apiEndpoint = "https://models.inference.ai.azure.com/chat/completions"
    private let model = "gpt-4o-mini"

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "gemini_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "gemini_api_key") }
    }

    func splitIntoSentences(_ text: String) -> [String] {
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 3 }
        return sentences.isEmpty ? [text] : sentences
    }

    func analyze(
        _ sentence: String,
        onBasic: @escaping (SentenceAnalysis) -> Void,
        onQuestions: @escaping (UUID, [String], String?) -> Void
    ) {
        guard !apiKey.isEmpty else {
            var dummy = SentenceAnalysis(original: sentence)
            dummy.structure = []
            dummy.structureError = "API 키를 설정해주세요 (⌘,)"
            dummy.questions = []
            dummy.questionsError = "API 키를 설정해주세요 (⌘,)"
            DispatchQueue.main.async { onBasic(dummy) }
            return
        }
        callBasic(sentence: sentence) { analysis in
            onBasic(analysis)
            self.callQuestions(id: analysis.id, sentence: sentence, completion: onQuestions)
        }
    }

    // MARK: - Phase 1: 구조 칩 + 직독직해

    private func callBasic(sentence: String, completion: @escaping (SentenceAnalysis) -> Void) {
        let prompt = """
        영어 문장을 의미 단위로 나눠서 각 덩어리의 문장 성분과 짧은 한국어 직독직해를 JSON만 출력해. 마크다운 절대 금지.

        {"components":[{"text":"Before the negotiations","role":"Adverb","color":"#9B59B6","hint":"협상 전에"}]}

        role: Subject, Verb, Object, Complement, Adverb, Modifier, Conjunction, Preposition
        color: Subject=#4A90E2 Verb=#E25C5C Object=#50C878 Complement=#F5A623 Adverb=#9B59B6 Modifier=#1ABC9C Conjunction=#95A5A6 Preposition=#E67E22
        hint: 2~4단어 자연스러운 한국어 직독직해

        문장: "\(sentence)"
        """

        callAPI(prompt: prompt) { result, errorText in
            var analysis = SentenceAnalysis(original: sentence)
            if let parsed = result,
               let rawComponents = parsed["components"] as? [[String: Any]] {
                analysis.structure = rawComponents.map { comp in
                    SentenceComponent(
                        text: comp["text"] as? String ?? "",
                        role: comp["role"] as? String ?? "",
                        color: comp["color"] as? String ?? "#888888",
                        hint: comp["hint"] as? String ?? ""
                    )
                }
            } else {
                analysis.structure = []
                analysis.structureError = errorText ?? "알 수 없는 오류"
                print("⚠️ Phase1 실패: \(analysis.structureError ?? "")")
            }
            DispatchQueue.main.async { completion(analysis) }
        }
    }

    // MARK: - Phase 2: 문법 질문 3개

    private func callQuestions(id: UUID, sentence: String, completion: @escaping (UUID, [String], String?) -> Void) {
        let prompt = """
        아래 영어 문장에서 한국인 영어 학습자가 궁금해할 만한 문법 포인트를 질문 3개로 만들어. JSON만 출력해. 마크다운 금지.

        {"questions":["왜 과거완료를 썼을까?","'that'과 'which'의 차이는?","이 경우 왜 수동태를 쓸까?"]}

        조건: "왜 ~을 썼을까?", "~와 ~의 차이는?" 형태, 한국어, 짧고 핵심적으로

        문장: "\(sentence)"
        """

        callAPI(prompt: prompt) { result, errorText in
            if let questions = result?["questions"] as? [String], !questions.isEmpty {
                DispatchQueue.main.async { completion(id, questions, nil) }
            } else {
                let err = errorText ?? "'questions' 키 없음 또는 빈 배열"
                print("⚠️ Phase2 실패: \(err)")
                DispatchQueue.main.async { completion(id, [], err) }
            }
        }
    }

    // MARK: - 질문 답변 (채팅)

    func askQuestion(_ question: String, context: String, completion: @escaping (String) -> Void) {
        let prompt = """
        영어를 공부하는 한국인이 아래 영어 원문에 대해 질문했어. 한국어로 명확하고 친절하게 답해줘. 마크다운 금지, 순수 텍스트로만.

        원문: "\(context)"
        질문: "\(question)"
        """
        callAPIRawText(prompt: prompt, completion: completion)
    }

    // MARK: - 공통 API 호출 (JSON 반환)

    private func callAPI(prompt: String, completion: @escaping ([String: Any]?, String?) -> Void) {
        guard let url = URL(string: apiEndpoint) else {
            completion(nil, "URL 생성 실패")
            return
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.3,
            "max_tokens": 8192
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(nil, "네트워크 오류: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(nil, "HTTP \(http.statusCode): \(body.prefix(200))")
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let rawText = message["content"] as? String else {
                completion(nil, "응답 구조 파싱 실패")
                return
            }
            if let parsed = self.extractJSON(from: rawText) {
                completion(parsed, nil)
            } else {
                completion(nil, rawText)
            }
        }.resume()
    }

    // MARK: - Raw 텍스트 반환 (채팅용)

    private func callAPIRawText(prompt: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: apiEndpoint) else {
            DispatchQueue.main.async { completion("요청 실패") }
            return
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.5,
            "max_tokens": 2048
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion("네트워크 오류: \(error.localizedDescription)") }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String else {
                DispatchQueue.main.async { completion("답변을 가져오지 못했습니다.") }
                return
            }
            DispatchQueue.main.async { completion(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }.resume()
    }

    // MARK: - JSON 추출

    private func extractJSON(from text: String) -> [String: Any]? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else { return nil }

        let jsonString = String(cleaned[start...end])
        return (try? JSONSerialization.jsonObject(with: Data(jsonString.utf8))) as? [String: Any]
    }
}
