import Foundation

enum URLValidationError: LocalizedError, Equatable {
    case empty
    case unsupportedScheme
    case missingHost

    var errorDescription: String? {
        switch self {
        case .empty:
            "Enter an HTTPS media URL first."
        case .unsupportedScheme:
            "Only HTTP and HTTPS media URLs are supported on tvOS."
        case .missingHost:
            "The media URL is missing a valid host."
        }
    }
}

enum URLValidator {
    static func mediaSource(from rawValue: String, title: String) throws -> MediaSource {
        let url = try validatedURL(from: rawValue)
        return MediaSource(title: title, subtitle: url.host() ?? "User source", url: url, playbackEngine: .native)
    }

    static func validatedURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw URLValidationError.empty }
        guard let url = URL(string: trimmed) else { throw URLValidationError.missingHost }

        let scheme = url.scheme?.lowercased()
        guard scheme == "https" || scheme == "http" else {
            throw URLValidationError.unsupportedScheme
        }

        guard url.host()?.isEmpty == false else {
            throw URLValidationError.missingHost
        }

        return url
    }
}
