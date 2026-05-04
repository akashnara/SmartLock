import Foundation

enum DownloadError: LocalizedError {
    case noInternetConnection
    case httpError(Int)
    case networkError(Error)
    case fileSystemError(Error)

    var errorDescription: String? {
        switch self {
        case .noInternetConnection:
            return "No internet connection. Please check your network and try again."
        case .httpError(let code):
            return "Server returned error \(code). Please try again later."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .fileSystemError(let error):
            return "Failed to save file: \(error.localizedDescription)"
        }
    }
}

struct DownloadService {
    // Replace with your actual firmware/binary endpoint
    static let downloadURL = URL(string: "https://www.rd.usda.gov/sites/default/files/pdf-sample_0.pdf")!

    /// Downloads the file at `downloadURL`, streams bytes to report progress, and writes
    /// the result to a UUID-named temp file. The caller owns the file and must delete it.
    static func downloadFile(
        progressHandler: @MainActor @escaping (Double) -> Void
    ) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartlock_\(UUID().uuidString).bin")

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: downloadURL)

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.networkError(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            throw DownloadError.httpError(http.statusCode)
        }

        let contentLength = http.expectedContentLength   // -1 if unknown
        var buffer = Data()
        buffer.reserveCapacity(contentLength > 0 ? Int(contentLength) : 65_536)

        do {
            for try await byte in asyncBytes {
                buffer.append(byte)
                if contentLength > 0 {
                    let progress = Double(buffer.count) / Double(contentLength)
                    progressHandler(min(progress, 1.0))
                }
            }
        } catch let error as NSError {
            let noInternet: Set<Int> = [
                NSURLErrorNotConnectedToInternet,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorDataNotAllowed
            ]
            if noInternet.contains(error.code) {
                throw DownloadError.noInternetConnection
            }
            throw DownloadError.networkError(error)
        }

        progressHandler(1.0)

        do {
            try buffer.write(to: destination, options: .atomic)
        } catch {
            throw DownloadError.fileSystemError(error)
        }

        return destination
    }
}
