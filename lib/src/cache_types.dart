/// Eviction priority for cache entries. Lower-priority entries are evicted
/// first under memory pressure. [neverRemove] entries are only evicted by
/// explicit removal.
enum CacheItemPriority {
  low,
  normal,
  high,
  neverRemove,
}

/// Represents a cache entry that can be inspected and configured.

/// Provides access to key, value, expiration settings, expiration
/// tokens, post-eviction callbacks, and priority.
abstract class ICacheEntry {
  /// The entry's cache key.
  Object get key;

  /// The cached value.
  dynamic get value;
  set value(dynamic v);

  /// Absolute expiration time.
  DateTime? get absoluteExpiration;
  set absoluteExpiration(DateTime? v);

  /// Expiration duration relative to now.
  Duration? get absoluteExpirationRelativeToNow;
  set absoluteExpirationRelativeToNow(Duration? v);

  /// Sliding expiration duration.
  Duration? get slidingExpiration;
  set slidingExpiration(Duration? v);

  /// Change tokens that can trigger expiration.
  List<IChangeToken> get expirationTokens;

  /// Post-eviction callback registrations.
  List<PostEvictionCallbackRegistration> get postEvictionCallbacks;

  /// Eviction priority.
  CacheItemPriority get priority;
  set priority(CacheItemPriority v);

  /// Estimated byte size of this entry.
  int? get size;
  set size(int? v);

  void dispose();
}

/// Propagates notifications that a change has occurred.

abstract class IChangeToken {
  /// Whether the token has been signalled.
  bool get hasChanged;

  /// Whether there are active registered callbacks.
  bool get activeChangeCallbacks;

  /// Registers a callback to invoke when the token fires.
  IDisposable registerChangeCallback(void Function(Object? state) callback, Object? state);
}

/// An object whose resources can be released.
abstract class IDisposable {
  void dispose();
}

/// Registration for a post-eviction callback.

/// The [callback] receives the entry's key, value, eviction reason, and an
/// optional user-defined [state].
class PostEvictionCallbackRegistration {
  final void Function(Object key, Object? value, EvictionReason reason, Object? state) callback;
  final Object? state;

  const PostEvictionCallbackRegistration(this.callback, [this.state]);
}

/// Reason why a cache entry was evicted.

enum EvictionReason {
  none,
  removed,
  replaced,
  expired,
  tokenExpired,
  capacity,
}

/// Options for setting a cache entry via [MemoryCache.set].

/// Configures absolute and sliding expiration, priority, estimated size,
/// expiration tokens, and post-eviction callbacks.
class MemoryCacheEntryOptions {
  DateTime? absoluteExpiration;
  Duration? absoluteExpirationRelativeToNow;
  Duration? slidingExpiration;
  CacheItemPriority priority = CacheItemPriority.normal;
  int? size;
  List<IChangeToken>? expirationTokens;
  List<PostEvictionCallbackRegistration>? postEvictionCallbacks;

  MemoryCacheEntryOptions();

  MemoryCacheEntryOptions copyWith({
    DateTime? absoluteExpiration,
    Duration? absoluteExpirationRelativeToNow,
    Duration? slidingExpiration,
    CacheItemPriority? priority,
    int? size,
    List<IChangeToken>? expirationTokens,
    List<PostEvictionCallbackRegistration>? postEvictionCallbacks,
  }) {
    final opts = MemoryCacheEntryOptions();
    opts.absoluteExpiration = absoluteExpiration ?? this.absoluteExpiration;
    opts.absoluteExpirationRelativeToNow = absoluteExpirationRelativeToNow ?? this.absoluteExpirationRelativeToNow;
    opts.slidingExpiration = slidingExpiration ?? this.slidingExpiration;
    opts.priority = priority ?? this.priority;
    opts.size = size ?? this.size;
    opts.expirationTokens = expirationTokens ?? this.expirationTokens;
    opts.postEvictionCallbacks = postEvictionCallbacks ?? this.postEvictionCallbacks;
    return opts;
  }
}
