import Foundation
import Domain

/// Recipes the assistant wrote, kept on the phone so opening one again costs nothing: no request,
/// no use of the allowance, and it opens at once. In the app's own container, not the App Group:
/// the widget never shows a recipe.
///
/// One small JSON file per recipe, named by `RecipeRequest.cacheKey`. The newest `keptRecipes` stay;
/// a recipe is derived from a meal and can always be asked for again, so losing one loses nothing.
@MainActor
public final class RecipeCache {
    public static let keptRecipes = 200

    private let directory: URL?
    /// Everything, when nothing is to be stored (previews and seeded test states).
    private var memory: [String: Recipe] = [:]

    public init(inMemory: Bool = false) {
        if inMemory {
            directory = nil
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            directory = base?.appending(path: "Recipes", directoryHint: .isDirectory)
        }
    }

    public func recipe(for key: String) -> Recipe? {
        guard let file = file(for: key) else { return memory[key] }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Recipe.self, from: data)
    }

    public func save(_ recipe: Recipe, for key: String) {
        guard let directory, let file = file(for: key) else {
            memory[key] = recipe
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(recipe).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return
        }
        prune(directory)
    }

    /// Forgets every recipe, with the rest of the person's data.
    public func removeAll() {
        memory = [:]
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(for key: String) -> URL? {
        // Keys are hex digits; anything else never names a file.
        guard let directory, !key.isEmpty, key.allSatisfy(\.isHexDigit) else { return nil }
        return directory.appending(path: "\(key).json", directoryHint: .notDirectory)
    }

    /// Keeps the newest `keptRecipes`, by when they were written.
    private func prune(_ directory: URL) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
              files.count > Self.keptRecipes
        else { return }
        let dated = files.map { file in
            (file, (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for (file, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(Self.keptRecipes) {
            try? manager.removeItem(at: file)
        }
    }
}
