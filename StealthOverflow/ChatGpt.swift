import Foundation

class ChatApiService {
    public func fetchGPTResponse(for prompt: String, completion: @escaping (String) -> Void) {
        let OpenRouterKey = "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"
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(OpenRouterKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": "mistralai/mistral-7b-instruct",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant."],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion("Network error: \(error.localizedDescription)")
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion("No data received.")
                }
                return
            }

            // 💡 Print raw response for inspection
            if let raw = String(data: data, encoding: .utf8) {
                print("Raw GPT response:\n\(raw)")
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    DispatchQueue.main.async {
                        completion(content.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion("Error parsing response (missing expected fields).")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion("JSON parse error: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    public func mockResponse(for text: String) -> String {
        return "This is a mock response to: \"\(text)\""
    }
}