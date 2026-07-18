import Foundation

public struct SharedGroupSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let emoji: String

    public init(id: UUID, name: String, emoji: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
    }
}

public struct SharedImportStore {
    public static let defaultAppGroupIdentifier = "group.com.example.crewpick"
    private static let importsKey = "pendingImports.v1"
    private static let groupsKey = "groupSummaries.v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init?(appGroupIdentifier: String = defaultAppGroupIdentifier) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return nil }
        self.defaults = defaults
    }

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func pendingImports() -> [PendingImport] {
        guard let data = defaults.data(forKey: Self.importsKey) else { return [] }
        return (try? decoder.decode([PendingImport].self, from: data)) ?? []
    }

    public func append(_ item: PendingImport) throws {
        var items = pendingImports()
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
        defaults.set(try encoder.encode(items), forKey: Self.importsKey)
    }

    public func remove(id: UUID) throws {
        let items = pendingImports().filter { $0.id != id }
        defaults.set(try encoder.encode(items), forKey: Self.importsKey)
    }

    public func saveGroups(_ groups: [SharedGroupSummary]) throws {
        defaults.set(try encoder.encode(groups), forKey: Self.groupsKey)
    }

    public func groups() -> [SharedGroupSummary] {
        guard let data = defaults.data(forKey: Self.groupsKey) else { return [] }
        return (try? decoder.decode([SharedGroupSummary].self, from: data)) ?? []
    }
}

