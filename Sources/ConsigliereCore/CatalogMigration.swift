import Foundation

/// Keeps an existing config.json in step with new built-in commands. Ported from `reference-js/migrate.js`.
///
/// The bug this exists to fix: config.json is only ever written with `DefaultCatalog.entries` the very
/// first time Consigliere runs. Every catalog entry added in a later update (like "flip" or "settings")
/// would otherwise never appear for someone who already has a config.json, no matter how many times they
/// update — loading a config that already has a "catalog" array just uses that array as-is.
public enum CatalogMigration {

    public struct Result: Equatable {
        public let catalog: [CatalogEntry]
        /// Sorted, for stable comparisons and fixtures.
        public let offered: [String]
    }

    /// Adds any built-in entry that is missing from `existing` and has never been offered before, so a
    /// Mac updated to a newer version of Consigliere automatically gains new built-in commands without
    /// disturbing anything the person added or changed themselves. An entry that was offered before and
    /// is missing now was deleted on purpose, and stays deleted.
    public static func merge(existing: [CatalogEntry], defaults: [CatalogEntry], alreadyOffered: Set<String>) -> Result {
        var existingNames = Set(existing.map { $0.name })
        var offered = alreadyOffered
        var merged = existing

        for entry in defaults {
            if existingNames.contains(entry.name) {
                offered.insert(entry.name)
                continue
            }
            if alreadyOffered.contains(entry.name) {
                continue
            }
            merged.append(entry)
            existingNames.insert(entry.name)
            offered.insert(entry.name)
        }
        return Result(catalog: merged, offered: offered.sorted())
    }
}

/// What has been offered before. Its own tiny file (`catalog-migrations.json`), not part of config.json,
/// so config.json stays exactly what section 16 of the guide documents — nothing extra shows up in it.
public struct CatalogMigrationState: Codable, Equatable {
    public var offered: [String]

    public init(offered: [String] = []) {
        self.offered = offered
    }
}

public enum CatalogMigrationStore {
    public static func load(from url: URL = ConsiglierePaths.catalogMigrationFile) -> CatalogMigrationState {
        return (try? JSONFile.read(CatalogMigrationState.self, from: url)) ?? CatalogMigrationState()
    }

    public static func save(_ state: CatalogMigrationState, to url: URL = ConsiglierePaths.catalogMigrationFile) {
        try? JSONFile.write(state, to: url)
    }
}
