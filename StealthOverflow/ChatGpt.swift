import Foundation

class ChatApiService: NSObject, URLSessionDataDelegate {
    private var activeTask: URLSessionDataTask?
    private var completionHandler: ((String) -> Void)?
    private var session: URLSession = URLSession.shared
    
    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300

        super.init()
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    deinit {
        cancelCurrentRequest()
    }

    public func fetchGPTResponse(for prompt: String, onUpdate: @escaping (String) -> Void) {
        cancelCurrentRequest() // Cancel any existing request first
        
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
                ["role": "system", "content": """
                You are SilentGlass, a helpful AI coding assistant created by the SilentGlass team. 
                
                When asked about your identity:
                - If asked "who are you", "what are you", or similar: respond "I'm SilentGlass, a helpful AI coding assistant"
                - If asked "who created you": respond "I was created by the SilentGlass team to assist with coding and technical tasks"
                - If asked about your model: respond "I'm based on advanced AI technology designed to help with programming and development"
                
                General guidelines:
                1. Be concise and direct in your responses
                2. Focus on answering the user's specific question
                3. For coding questions, provide practical solutions
                4. If you don't know something, say so honestly
                5. Maintain a helpful and professional tone
                6. Don't mention technical architecture details unless specifically asked
                
                Remember: Your primary identity is SilentGlass, a coding assistant.
                """],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        self.completionHandler = onUpdate
        activeTask = session.dataTask(with: request)
        activeTask?.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask == activeTask, let handler = completionHandler else { return }
        
        let chunk = String(data: data, encoding: .utf8) ?? ""
        let lines = chunk.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        for line in lines {
            guard line.hasPrefix("data: ") else { continue }
            
            let jsonString = line.replacingOccurrences(of: "data: ", with: "")
            if jsonString == "[DONE]" {
                DispatchQueue.main.async {
                    handler("[STREAM_DONE]")
                }
                cleanUp()
                return
            }
            
            do {
                let jsonData = jsonString.data(using: .utf8) ?? Data()
                let parsed = try JSONDecoder().decode(OpenAIStreamChunk.self, from: jsonData)
                if let content = parsed.choices.first?.delta.content {
                    DispatchQueue.main.async {
                        handler(content)
                    }
                }
            } catch {
                print("Error parsing stream chunk: \(error)")
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Streaming task completed with error: \(error.localizedDescription)")
        }
        cleanUp()
    }
    
    func cancelCurrentRequest() {
        activeTask?.cancel()
        cleanUp()
    }
    
    private func cleanUp() {
        activeTask = nil
        completionHandler = nil
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
