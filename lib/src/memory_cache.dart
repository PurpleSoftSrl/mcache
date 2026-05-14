import 'dart:collection';
import 'cache_types.dart';

/// A concrete cache entry stored in [MemoryCache].

class MemoryCacheEntry {
  final Object key;
  dynamic value;
  int ticksAtCreation;
  int ticksAtLastAccess;
  int? ticksAtAbsoluteExpiration;
  int? ticksForSlidingExpiration;
  int estimatedSize;
  CacheItemPriority priority;
  List<IChangeToken>? _expirationTokens;
  List<PostEvictionCallbackRegistration>? _postEvictionCallbacks;

  MemoryCacheEntry? previous;
  MemoryCacheEntry? next;

  MemoryCacheEntry({
    required this.key,
    this.value,
    required this.ticksAtCreation,
    this.ticksAtAbsoluteExpiration,
    this.ticksForSlidingExpiration,
    this.estimatedSize = 0,
    this.priority = CacheItemPriority.normal,
    List<IChangeToken>? expirationTokens,
    List<PostEvictionCallbackRegistration>? postEvictionCallbacks,
  })  : ticksAtLastAccess = ticksAtCreation,
        _expirationTokens = expirationTokens,
        _postEvictionCallbacks = postEvictionCallbacks;

  List<IChangeToken> get expirationTokens => _expirationTokens ??= [];
  List<PostEvictionCallbackRegistration> get postEvictionCallbacks => _postEvictionCallbacks ??= [];
}

/// Cache usage statistics.

class MemoryCacheStatistics {
  int totalHits = 0;
  int totalMisses = 0;
  int currentEntryCount = 0;
  int currentEstimatedSize = 0;
}

/// A clock function returning monotonic ticks (usually microseconds).

typedef CacheClock = int Function();

/// Options for [MemoryCache].

/// Configures byte-size limits and compaction behaviour.
class MemoryCacheOptions {
  final int? sizeLimit;
  final double compactionPercentage;
  final CacheClock? clock;

  const MemoryCacheOptions({
    this.sizeLimit,
    this.compactionPercentage = 0.05,
    this.clock,
  });
}

/// A high-performance, concurrency-safe in-memory cache.

/// Uses a [HashMap] and custom doubly-linked LRU list for O(1) lookup,
/// insert, promote, and evict operations. Supports absolute, sliding,
/// and change-token expiration, priority-based eviction, byte-size
/// limits with compaction, post-eviction callbacks, and lazy expiration
/// (no background timer).
///
/// ```dart
/// final cache = MemoryCache();
/// cache.set('key', 'value', MemoryCacheEntryOptions()
///   ..absoluteExpirationRelativeToNow = Duration(minutes: 5));
/// final value = cache.get('key');
/// ```
class MemoryCache {
  final MemoryCacheOptions _options;
  final MemoryCacheStatistics stats = MemoryCacheStatistics();
  final HashMap<Object, MemoryCacheEntry> _map = HashMap<Object, MemoryCacheEntry>();
  final Stopwatch _stopwatch = Stopwatch();
  final int _timeBase = DateTime.now().microsecondsSinceEpoch;
  MemoryCacheEntry? _mru;
  MemoryCacheEntry? _lru;
  int _estimatedSize = 0;
  bool _disposed = false;

  MemoryCache([MemoryCacheOptions? options])
      : _options = options ?? const MemoryCacheOptions() {
    _stopwatch.start();
  }

  int get _now =>
      _options.clock?.call() ?? (_stopwatch.elapsedMicroseconds + _timeBase);

  /// The number of entries currently in the cache.
  int get count => _map.length;

  /// Tries to get a value from the cache.

  /// Returns `true` if the entry exists and is not expired. The value is
  /// passed to [onValue] on hit. On miss or expiration, returns `false`.
  bool tryGet(Object key, void Function(dynamic value)? onValue) {
    if (_disposed) return false;
    final entry = _map[key];
    if (entry == null) {
      stats.totalMisses++;
      return false;
    }
    if (_isExpired(entry)) {
      _removeEntry(entry, EvictionReason.expired);
      stats.totalMisses++;
      return false;
    }
    entry.ticksAtLastAccess = _now;
    _promoteEntry(entry);
    stats.totalHits++;
    onValue?.call(entry.value);
    return true;
  }

  /// Stores a value in the cache.

  /// If [key] already exists, the entry is updated in place.
  /// [opts] can specify expiration, priority, size, and callbacks.
  void set(Object key, dynamic value, [MemoryCacheEntryOptions? opts]) {
    if (_disposed) return;
    final existing = _map[key];
    if (existing != null) {
      // Fast path: same object — just promote
      if (identical(existing.value, value)) {
        _promoteEntry(existing);
        return;
      }
      // Replace existing — update in place
      _fireCallbacks(existing, EvictionReason.replaced);
      _estimatedSize -= existing.estimatedSize;
      existing.value = value;
      existing.estimatedSize = opts?.size ?? _estimateBytes(value);
      existing.priority = opts?.priority ?? CacheItemPriority.normal;
      _estimatedSize += existing.estimatedSize;
      _promoteEntry(existing);
      if (opts?.slidingExpiration != null) {
        existing.ticksForSlidingExpiration = _durationToTicks(opts!.slidingExpiration!);
      }
      stats.currentEntryCount = _map.length;
      stats.currentEstimatedSize = _estimatedSize;
      return;
    }

    // New entry — fast path for no options (most common case)
    if (opts == null) {
      final entry = MemoryCacheEntry(key: key, value: value, ticksAtCreation: 0);
      entry.estimatedSize = _fastSize(value);
      _map[key] = entry;
      _estimatedSize += entry.estimatedSize;
      _promoteEntry(entry);
      stats.currentEntryCount = _map.length;
      stats.currentEstimatedSize = _estimatedSize;
      return;
    }

    // New entry with options
    _ensureCapacity(opts.size ?? _estimateBytes(value));
    final now = _now;
    final entry = MemoryCacheEntry(key: key, value: value, ticksAtCreation: now);
    entry.estimatedSize = opts.size ?? _estimateBytes(value);
    entry.priority = opts.priority;

    if (opts.absoluteExpiration != null) {
      entry.ticksAtAbsoluteExpiration = _dateTimeToTicks(opts.absoluteExpiration!);
    }
    if (opts.absoluteExpirationRelativeToNow != null) {
      entry.ticksAtAbsoluteExpiration = now + _durationToTicks(opts.absoluteExpirationRelativeToNow!);
    }
    if (opts.slidingExpiration != null) {
      entry.ticksForSlidingExpiration = _durationToTicks(opts.slidingExpiration!);
    }
    if (opts.expirationTokens != null) {
      entry.expirationTokens.addAll(opts.expirationTokens!);
    }
    if (opts.postEvictionCallbacks != null) {
      entry.postEvictionCallbacks.addAll(opts.postEvictionCallbacks!);
    }

    _insertMru(entry);
    stats.currentEntryCount = _map.length;
    stats.currentEstimatedSize = _estimatedSize;
  }

  /// Gets a value from the cache. Returns `null` on miss or expiration.

  dynamic get(Object key) {
    dynamic result;
    tryGet(key, (v) => result = v);
    return result;
  }

  /// Removes the entry with the given [key], firing post-eviction callbacks.

  void remove(Object key) {
    if (_disposed) return;
    final entry = _map[key];
    if (entry != null) _removeEntry(entry, EvictionReason.removed);
  }

  /// Compacts the cache to [percentage] below the size limit.

  void compact(double percentage) {
    final sizeLimit = _options.sizeLimit;
    if (sizeLimit == null) return;
    _compactToSize((sizeLimit * (1.0 - percentage)).toInt());
  }

  /// Removes all entries from the cache and fires post-eviction callbacks.

  void clear() {
    if (_disposed) return;
    var entry = _mru;
    while (entry != null) {
      final next = entry.next;
      _fireCallbacks(entry, EvictionReason.removed);
      entry = next;
    }
    _map.clear();
    _mru = _lru = null;
    _estimatedSize = 0;
    stats.currentEntryCount = 0;
    stats.currentEstimatedSize = 0;
  }

  /// Disposes the cache, clearing all entries and stopping the internal clock.

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clear();
    _stopwatch.stop();
  }

  bool _isExpired(MemoryCacheEntry entry) {
    final now = _now;
    if (entry.ticksAtAbsoluteExpiration != null && now > entry.ticksAtAbsoluteExpiration!) return true;
    if (entry.ticksForSlidingExpiration != null) {
      if (now - entry.ticksAtLastAccess > entry.ticksForSlidingExpiration!) return true;
    }
    final tokens = entry._expirationTokens;
    if (tokens != null) {
      for (final token in tokens) {
        if (token.hasChanged) return true;
      }
    }
    return false;
  }

  void _fireCallbacks(MemoryCacheEntry entry, EvictionReason reason) {
    final cbs = entry._postEvictionCallbacks;
    if (cbs != null) {
      for (final reg in cbs) {
        try { reg.callback(entry.key, entry.value, reason, reg.state); } catch (_) {}
      }
    }
  }

  void _removeEntry(MemoryCacheEntry entry, EvictionReason reason) {
    _fireCallbacks(entry, reason);
    _map.remove(entry.key);
    _unlink(entry);
    _estimatedSize -= entry.estimatedSize;
    stats.currentEntryCount = _map.length;
    stats.currentEstimatedSize = _estimatedSize;
  }

  void _ensureCapacity(int newEntrySize) {
    final limit = _options.sizeLimit;
    if (limit == null) return;
    if (_estimatedSize + newEntrySize > limit) {
      _compactToSize((limit * (1.0 - _options.compactionPercentage)).toInt() - newEntrySize);
    }
  }

  void _compactToSize(int target) {
    final order = [CacheItemPriority.low, CacheItemPriority.normal, CacheItemPriority.high];
    for (final priority in order) {
      if (_estimatedSize <= target) break;
      var current = _lru;
      while (current != null) {
        final prev = current.previous;
        if (_estimatedSize <= target) break;
        if (current.priority == priority) {
          _removeEntry(current, EvictionReason.capacity);
        }
        current = prev;
      }
    }
    while (_estimatedSize > target) {
      final lru = _lru;
      if (lru == null || lru.priority == CacheItemPriority.neverRemove) break;
      _removeEntry(lru, EvictionReason.capacity);
    }
  }

  void _promoteEntry(MemoryCacheEntry entry) {
    if (entry == _mru) return;

    // Unlink from current position
    if (entry.previous != null) {
      entry.previous!.next = entry.next;
      if (_lru == entry) _lru = entry.previous;
    }
    if (entry.next != null) {
      entry.next!.previous = entry.previous;
    }

    // Insert at MRU
    entry.previous = null;
    entry.next = _mru;
    final mru = _mru;
    if (mru != null) mru.previous = entry;
    _mru = entry;
    if (_lru == null) _lru = entry;
  }

  // quiver-inspired: single hash lookup for insert-via-putIfAbsent
  void _insertMru(MemoryCacheEntry entry) {
    _map[entry.key] = entry;
    _estimatedSize += entry.estimatedSize;
    _promoteEntry(entry);
    if (_options.sizeLimit != null && _estimatedSize > _options.sizeLimit!) {
      _compactToSize((_options.sizeLimit! * (1.0 - _options.compactionPercentage)).toInt());
    }
  }

  void _unlink(MemoryCacheEntry entry) {
    if (entry.previous != null) {
      entry.previous!.next = entry.next;
    } else {
      _mru = entry.next;
    }
    if (entry.next != null) {
      entry.next!.previous = entry.previous;
    } else {
      _lru = entry.previous;
    }
    entry.previous = null;
    entry.next = null;
  }

  static int _fastSize(dynamic v) {
    if (v == null) return 0;
    if (v is int) return 8;
    if (v is double) return 8;
    if (v is bool) return 4;
    if (v is String) return 40 + v.length * 2;
    return 64;
  }

  static int _durationToTicks(Duration d) => d.inMicroseconds;

  static int _dateTimeToTicks(DateTime dt) => dt.microsecondsSinceEpoch;

  static int _estimateBytes(dynamic v) {
    if (v == null) return 0;
    if (v is String) return 50 + v.length * 2;
    if (v is List) return 40 + v.length * 8;
    if (v is Map) return 40 + v.length * 32;
    return 64;
  }
}
