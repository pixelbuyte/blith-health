import Foundation

/// Persists `HealthHistory` on device as JSON, one file per data origin. Health values never
/// leave the device through this type. On iOS the file is written with complete file
/// protection so it is encrypted while the device is locked.
public actor LocalHealthStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("HealthHistory", isDirectory: true)
    }

    private func url(for origin: DataOrigin) -> URL { directory.appendingPathComponent(origin.fileName) }

    public func load(_ origin: DataOrigin) -> HealthHistory? {
        guard let data = try? Data(contentsOf: url(for: origin)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(HealthHistory.self, from: data)
    }

    public func save(_ history: HealthHistory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(history)
        #if os(iOS)
        try data.write(to: url(for: history.origin), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url(for: history.origin), options: [.atomic])
        #endif
    }

    public func delete(_ origin: DataOrigin) {
        try? FileManager.default.removeItem(at: url(for: origin))
    }

    public func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
