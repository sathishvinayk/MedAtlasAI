import Foundation

class ChatApiService: NSObject, URLSessionDataDelegate {
    private var taskToHandler: [URLSessionDataTask: (String) -> Void] = [:]

    public func fetchGPTResponse(for prompt: String, onUpdate: @escaping (String) -> Void) {
        let OpenRouterKey = "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"
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(OpenRouterKey)", forHTTPHeaderField: "Authorization")
        request.addValue("https://localhost", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": "mistralai/mistral-7b-instruct",
            "stream": true,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant."],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        taskToHandler[task] = onUpdate
        task.resume()
        // URLSession.shared.dataTask(with: request) { data, response, error in
        //     if let error = error {
        //         DispatchQueue.main.async {
        //             completion("Network error: \(error.localizedDescription)")
        //         }
        //         return
        //     }

        //     guard let data = data else {
        //         DispatchQueue.main.async {
        //             completion("No data received.")
        //         }
        //         return
        //     }

        //     // 💡 Print raw response for inspection
        //     if let raw = String(data: data, encoding: .utf8) {
        //         print("Raw GPT response:\n\(raw)")
        //     }

        //     do {
        //         if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        //            let choices = json["choices"] as? [[String: Any]],
        //            let message = choices.first?["message"] as? [String: Any],
        //            let content = message["content"] as? String {
        //             DispatchQueue.main.async {
        //                 completion(content.trimmingCharacters(in: .whitespacesAndNewlines))
        //             }
        //         } else {
        //             DispatchQueue.main.async {
        //                 completion("Error parsing response (missing expected fields).")
        //             }
        //         }
        //     } catch {
        //         DispatchQueue.main.async {
        //             completion("JSON parse error: \(error.localizedDescription)")
        //         }
        //     }
        // }.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }

        let lines = chunk.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = line.replacingOccurrences(of: "data: ", with: "")
                if jsonString == "[DONE]" {
                    if let handler = taskToHandler[dataTask] {
                        DispatchQueue.main.async {
                            handler("[STREAM_DONE]")
                        }
                    }
                    // 🧼 Remove handler after done
                    taskToHandler.removeValue(forKey: dataTask)
                    return
                }

                if let jsonData = jsonString.data(using: .utf8),
                    let parsed = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: jsonData),
                    let content = parsed.choices.first?.delta.content,
                    let handler = taskToHandler[dataTask] {
                        DispatchQueue.main.async {
                            handler(content)
                        }
                    
                }
            }
        }
    }

    public func mockResponse(for text: String) -> String {
        return "This is a mock response to: \"\(text)\""
    }
}

struct OpenAIStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}
