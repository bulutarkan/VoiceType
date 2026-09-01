import Foundation

struct GroqChatError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class GroqLLMService {
    static let shared = GroqLLMService()

    private init() {}

    func processTranscript(
        _ transcript: String,
        mode: SmartProcessingMode,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let instructions: String
        switch mode {
        case .raw:
            instructions = "Correct spelling, capitalization, punctuation, and obvious proper-name casing only. Preserve every meaningful word, repetition, filler, sentence order, tone, and language. Do not rewrite or summarize."
        case .clean:
            instructions = "Correct spelling, capitalization, punctuation, and proper names. Remove verbal fillers, accidental repetitions, and obvious false starts. Preserve the speaker's meaning, tone, language, detail, and phrasing as much as possible."
        case .polished:
            instructions = "Turn the dictation into fluent, send-ready writing. Correct spelling, capitalization, punctuation, and proper names; remove fillers and repetitions; improve sentence flow and paragraphs. Preserve the original meaning, facts, tone, language, and level of detail. Do not add new information."
        }

        let system = "You are VoiceType's transcription editor. Return only the final edited text with no commentary, quotes, labels, or markdown fences. Never translate unless the source itself switches languages."
        let user = "Editing mode: \(mode.rawValue)\n\nRules: \(instructions)\n\nTranscript:\n\(transcript)"
        chat(system: system, user: user, completion: completion)
    }

    func applyCommand(
        to selectedText: String,
        instruction: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let system = "You are VoiceType Command Mode. Apply the user's spoken editing command to the selected text. Return only the resulting replacement text. No explanations, labels, quotes, or markdown fences. Preserve facts unless the user explicitly asks to change them."
        let user = "Spoken command:\n\(instruction)\n\nSelected text:\n\(selectedText)"
        chat(system: system, user: user, completion: completion)
    }

    private func chat(system: String, user: String, completion: @escaping (Result<String, Error>) -> Void) {
        let apiKey = AppSettings.shared.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            completion(.failure(GroqChatError(message: "Groq API key is missing.")))
            return
        }

        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            completion(.failure(GroqChatError(message: "Invalid Groq endpoint.")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": AppSettings.shared.groqTextModel.rawValue,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.1,
            "max_completion_tokens": 2048,
            "stream": false
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data else {
                completion(.failure(GroqChatError(message: "Groq returned an empty response.")))
                return
            }

            guard (200..<300).contains(status) else {
                let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0["error"] as? [String: Any] }
                    .flatMap { $0["message"] as? String }
                completion(.failure(GroqChatError(message: detail ?? "Groq text model returned HTTP \(status).")))
                return
            }

            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = object["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(.failure(GroqChatError(message: "Could not parse Groq text response.")))
                return
            }

            let output = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else {
                completion(.failure(GroqChatError(message: "Groq text model returned empty text.")))
                return
            }
            completion(.success(output))
        }.resume()
    }
}
