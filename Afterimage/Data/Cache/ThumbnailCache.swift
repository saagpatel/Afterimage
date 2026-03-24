import Kingfisher

enum ThumbnailCacheConfig {
    static func configure() {
        let cache = ImageCache.default
        cache.diskStorage.config.sizeLimit = 200 * 1024 * 1024
        cache.diskStorage.config.expiration = .days(30)
        cache.memoryStorage.config.totalCostLimit = 50 * 1024 * 1024
        cache.memoryStorage.config.countLimit = 100
    }
}
