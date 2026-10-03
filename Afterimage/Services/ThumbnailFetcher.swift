import UIKit
import Kingfisher

struct ThumbnailFetcher {

    static func fetchThumbnails(for candidates: [MatchCandidate]) async -> [MatchCandidate] {
        var results = candidates

        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    guard let url = URL(string: candidate.photo.thumbnailURL) else {
                        return (index, nil)
                    }
                    return (index, await fetchImage(from: url))
                }
            }

            for await (index, image) in group {
                results[index].recordThumbnail(image)
            }
        }

        // Preserve candidates whose archive image is unavailable. Dropping them
        // would turn a network/cache limitation into the false claim "no match."
        return results
    }

    // MARK: - Private

    private static func fetchImage(from url: URL) async -> UIImage? {
        do {
            let result = try await KingfisherManager.shared.retrieveImage(with: url)
            return result.image
        } catch {
            return nil
        }
    }
}
