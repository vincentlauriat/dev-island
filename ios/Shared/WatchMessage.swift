import Foundation

/// iPhone -> Watch
enum WatchMessage: Codable, Sendable {
    case permissionRequest(PermissionPayload)
    case question(QuestionPayload)
    case sessionCompleted(CompletionPayload)
    case resolved(requestID: String)  // Handled on the Mac side — tells the Watch to clear its UI

    struct PermissionPayload: Codable, Sendable {
        let requestID: String
        let sessionID: String
        let agentTool: String
        let title: String
        let summary: String
        let workingDirectory: String?
    }

    struct QuestionPayload: Codable, Sendable {
        let requestID: String
        let sessionID: String
        let agentTool: String
        let title: String
        let options: [String]
    }

    struct CompletionPayload: Codable, Sendable {
        let sessionID: String
        let agentTool: String
        let summary: String
    }
}

/// Watch -> iPhone
enum WatchResponse: Codable, Sendable {
    case resolution(requestID: String, action: String)
}
