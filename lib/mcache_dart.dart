/// A high-performance in-memory cache for Dart.

/// Time-based expiration (absolute, sliding, change-token), priority
/// eviction with byte-size limits, anti-stampede `getOrCreate`, and
/// post-eviction callbacks.
library mcache_dart;

export 'src/cache_types.dart';
export 'src/cache_extensions.dart';
export 'src/change_tokens.dart';
export 'src/memory_cache.dart'
    show
        MemoryCache,
        MemoryCacheEntry,
        MemoryCacheOptions,
        MemoryCacheStatistics,
        CacheClock;
