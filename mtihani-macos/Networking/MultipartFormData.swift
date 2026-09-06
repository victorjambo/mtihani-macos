import Foundation

nonisolated struct MultipartFormData {
    let boundary: String

    private var body = Data()
    private var isFinalized = false

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func appendPNG(_ data: Data) {
        precondition(!isFinalized, "Cannot append to finalized multipart data")

        appendBoundary()
        append("Content-Disposition: form-data; name=\"screenshot\"; filename=\"capture.png\"\r\n")
        append("Content-Type: image/png\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    mutating func appendLanguage(_ language: String) {
        precondition(!isFinalized, "Cannot append to finalized multipart data")

        appendBoundary()
        append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        append(language)
        append("\r\n")
    }

    mutating func finalize() -> Data {
        if !isFinalized {
            append("--\(boundary)--\r\n")
            isFinalized = true
        }

        return body
    }

    private mutating func appendBoundary() {
        append("--\(boundary)\r\n")
    }

    private mutating func append(_ value: String) {
        body.append(contentsOf: value.utf8)
    }
}
