import Foundation

enum NuvioSourceError: LocalizedError {
    case invalidURL
    case invalidManifest
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid Nuvio add-on manifest URL."
        case .invalidManifest:
            "That URL did not return a valid Nuvio add-on manifest."
        case let .httpStatus(status):
            "Source request failed with HTTP \(status)."
        }
    }
}

actor NuvioSourceService {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchAddon(from input: String) async throws -> NuvioAddon {
        let endpoint = try AddonEndpoint(input)
        let url = try endpoint.url(path: "/manifest.json")
        let dto: ManifestDTO = try await get(url)
        guard !dto.id.isEmpty, !dto.name.isEmpty else {
            throw NuvioSourceError.invalidManifest
        }
        return dto.addon(baseURL: endpoint.baseURL)
    }

    func fetchCatalog(addon: NuvioAddon, catalog: NuvioCatalogDescriptor, search: String? = nil, skip: Int = 0) async throws -> [NuvioCatalogItem] {
        let url = try catalogURL(addon: addon, catalog: catalog, search: search, skip: skip)
        let response: CatalogResponseDTO = try await get(url)
        return response.metas.map { $0.item(type: catalog.type, addon: addon) }
    }

    func fetchMeta(addon: NuvioAddon, item: NuvioCatalogItem) async throws -> NuvioCatalogItemMeta {
        let endpoint = try AddonEndpoint(addon.baseURL)
        guard let encodedType = item.type.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedID = item.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw NuvioSourceError.invalidURL
        }
        let response: MetaResponseDTO = try await get(try endpoint.url(path: "/meta/\(encodedType)/\(encodedID).json"))
        return response.meta.itemMeta(type: item.type, addon: addon)
    }

    func fetchStreams(addon: NuvioAddon, type: String, id: String) async throws -> [NuvioStream] {
        let endpoint = try AddonEndpoint(addon.baseURL)
        guard let encodedType = type.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw NuvioSourceError.invalidURL
        }
        let url = try endpoint.url(path: "/stream/\(encodedType)/\(encodedID).json")
        let response: StreamResponseDTO = try await get(url)
        return response.streams.map { $0.stream(addon: addon) }
    }

    private func catalogURL(addon: NuvioAddon, catalog: NuvioCatalogDescriptor, search: String?, skip: Int) throws -> URL {
        let endpoint = try AddonEndpoint(addon.baseURL)
        guard let encodedType = catalog.type.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedCatalog = catalog.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw NuvioSourceError.invalidURL
        }

        var extras: [String: String] = [:]
        if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extras["search"] = search
        }
        if skip > 0 {
            extras["skip"] = "\(skip)"
        }

        let suffix: String
        if extras.isEmpty {
            suffix = ".json"
        } else {
            let encodedExtras = extras
                .sorted { $0.key < $1.key }
                .compactMap { key, value -> String? in
                    guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                          let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                        return nil
                    }
                    return "\(encodedKey)=\(encodedValue)"
                }
                .joined(separator: "&")
            suffix = "/\(encodedExtras).json"
        }

        return try endpoint.url(path: "/catalog/\(encodedType)/\(encodedCatalog)\(suffix)")
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("NuvioTV-tvOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NuvioSourceError.invalidManifest
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NuvioSourceError.httpStatus(http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
}

private struct AddonEndpoint {
    let baseURL: String
    private let path: String
    private let query: String

    init(_ input: String) throws {
        let normalized = input.normalizedAddonBaseURL()
        guard !normalized.isEmpty else {
            throw NuvioSourceError.invalidURL
        }
        guard let queryStart = normalized.firstIndex(of: "?") else {
            self.baseURL = normalized
            self.path = normalized
            self.query = ""
            return
        }
        self.path = String(normalized[..<queryStart])
        self.query = String(normalized[queryStart...])
        self.baseURL = normalized
    }

    func url(path endpointPath: String) throws -> URL {
        guard let url = URL(string: path + endpointPath + query) else {
            throw NuvioSourceError.invalidURL
        }
        return url
    }
}

private struct ManifestDTO: Decodable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let logo: String?
    let background: String?
    let catalogs: [CatalogDescriptorDTO]?
    let resources: [ResourceDTO]
    let types: [String]?
    let idPrefixes: [String]?

    func addon(baseURL: String) -> NuvioAddon {
        NuvioAddon(
            id: id,
            name: name,
            version: version ?? "",
            description: description,
            logo: logo,
            background: background,
            catalogs: (catalogs ?? []).map(\.catalog),
            resources: resources.map(\.resource),
            types: types ?? [],
            idPrefixes: idPrefixes ?? [],
            baseURL: baseURL
        )
    }
}

private struct CatalogDescriptorDTO: Decodable {
    let type: String
    let id: String
    let name: String?
    let extra: [NuvioCatalogExtra]
    let pageSize: Int?
    let extraSupported: [String]?
    let extraRequired: [String]?

    enum CodingKeys: String, CodingKey {
        case type, id, name, extra, pageSize, extraSupported, extraRequired
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.pageSize = try container.decodeIfPresent(Int.self, forKey: .pageSize)
        self.extraSupported = try container.decodeIfPresent([String].self, forKey: .extraSupported)
        self.extraRequired = try container.decodeIfPresent([String].self, forKey: .extraRequired)
        self.extra = (try? container.decode([NuvioCatalogExtra].self, forKey: .extra)) ?? []
    }

    var catalog: NuvioCatalogDescriptor {
        NuvioCatalogDescriptor(
            type: type,
            id: id,
            name: name ?? id,
            extra: extra,
            pageSize: pageSize,
            extraSupported: extraSupported ?? [],
            extraRequired: extraRequired ?? []
        )
    }
}

private struct ResourceDTO: Decodable {
    let name: String
    let types: [String]
    let idPrefixes: [String]?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            self.name = single
            self.types = []
            self.idPrefixes = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.types = (try? container.decode([String].self, forKey: .types)) ?? []
        self.idPrefixes = try? container.decode([String].self, forKey: .idPrefixes)
    }

    enum CodingKeys: String, CodingKey {
        case name, types, idPrefixes
    }

    var resource: NuvioAddonResource {
        NuvioAddonResource(name: name, types: types, idPrefixes: idPrefixes)
    }
}

private struct CatalogResponseDTO: Decodable {
    let metas: [MetaDTO]
}

private struct MetaDTO: Decodable {
    let id: String
    let type: String?
    let name: String
    let poster: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let genres: [String]?
    let runtime: String?
    let videos: [VideoDTO]?

    func item(type fallbackType: String, addon: NuvioAddon) -> NuvioCatalogItem {
        NuvioCatalogItem(
            id: id,
            type: type ?? fallbackType,
            name: name,
            poster: poster,
            background: background,
            logo: logo,
            description: description,
            releaseInfo: releaseInfo,
            imdbRating: imdbRating,
            genres: genres,
            runtime: runtime,
            addonBaseURL: addon.baseURL,
            addonName: addon.displayName
        )
    }

    func itemMeta(type fallbackType: String, addon: NuvioAddon) -> NuvioCatalogItemMeta {
        NuvioCatalogItemMeta(
            item: item(type: fallbackType, addon: addon),
            videos: (videos ?? []).compactMap(\.video)
        )
    }
}

private struct MetaResponseDTO: Decodable {
    let meta: MetaDTO
}

struct NuvioCatalogItemMeta: Hashable {
    let item: NuvioCatalogItem
    let videos: [NuvioVideo]
}

private struct VideoDTO: Decodable {
    let id: String
    let title: String?
    let name: String?
    let released: String?
    let season: Int?
    let episode: Int?
    let thumbnail: String?
    let overview: String?
    let description: String?

    var video: NuvioVideo? {
        let displayTitle = (title ?? name ?? id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return NuvioVideo(
            id: id,
            title: displayTitle.isEmpty ? id : displayTitle,
            released: released,
            season: season,
            episode: episode,
            thumbnail: thumbnail,
            description: description ?? overview
        )
    }
}

private struct StreamResponseDTO: Decodable {
    let streams: [StreamDTO]
}

private struct StreamDTO: Decodable {
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let externalUrl: String?
    let infoHash: String?
    let behaviorHints: BehaviorHintsDTO?

    func stream(addon: NuvioAddon) -> NuvioStream {
        NuvioStream(
            name: name,
            title: title,
            description: description,
            url: url,
            externalURL: externalUrl,
            infoHash: infoHash,
            addonName: addon.displayName,
            addonLogo: addon.logo,
            notWebReady: behaviorHints?.notWebReady ?? false,
            filename: behaviorHints?.filename,
            videoSize: behaviorHints?.videoSize
        )
    }
}

private struct BehaviorHintsDTO: Decodable {
    let notWebReady: Bool?
    let filename: String?
    let videoSize: Int64?
}
