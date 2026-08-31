import Foundation

struct TranscriptionError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

class GroqTranscriptionService {
    static let shared = GroqTranscriptionService()
    var apiKey = ""

    func transcribe(audioURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try? FileManager.default.removeItem(at: audioURL)
            completion(.failure(TranscriptionError(message: "Groq API key is missing. Open VoiceType → Settings and add your API key.")))
            return
        }

        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let audioData = try? Data(contentsOf: audioURL), !audioData.isEmpty else {
            completion(.failure(TranscriptionError(message: "Could not read audio file or file was empty.")))
            return
        }
        var body = Data()
        func field(_ name: String, _ value: String) {
            body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!
        }
        field("model", "whisper-large-v3-turbo")
        field("response_format", "text")
        body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!
        body += audioData
        body += "\r\n--\(boundary)--\r\n".data(using: .utf8)!
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { data, response, error in
            try? FileManager.default.removeItem(at: audioURL)
            if let e = error { completion(.failure(e)); return }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseText = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard (200..<300).contains(statusCode) else {
                if statusCode == 401 {
                    completion(.failure(TranscriptionError(message: "Groq API key is invalid or expired. Please update it in Settings.")))
                    return
                }
                let detail = responseText.isEmpty ? "HTTP \(statusCode)" : responseText
                completion(.failure(TranscriptionError(message: "Transcription service returned an error: \(detail)")))
                return
            }

            if !responseText.isEmpty {
                completion(.success(responseText))
                return
            }

            completion(.failure(TranscriptionError(message: "Transcription came back empty. Try again.")))
        }.resume()
    }
}

extension Data {
    static func += (lhs: inout Data, rhs: Data) { lhs.append(rhs) }
}
