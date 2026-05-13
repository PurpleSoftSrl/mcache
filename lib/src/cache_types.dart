
enum CacheItemPriority {
  low,
  normal,
  high,
  neverRemove,
}

abstract class ICacheEntry {
  Object get key;
  dynamic get value;
  set value(dynamic v);
  DateTime? get absoluteExpiration;
  set absoluteExpiration(DateTime? v);
  Duration? get absoluteExpirationRelativeToNow;
  set absoluteExpirationRelativeToNow(Duration? v);
  Duration? get slidingExpiration;
  set slidingExpiration(Duration? v);
  List<IChangeToken> get expirationTokens;
  List<PostEvictionCallbackRegistration> get postEvictionCallbacks;
  CacheItemPriority get priority;
  set priority(CacheItemPriority v);
  int? get size;
  set size(int? v);

  void dispose();
}

abstract class IChangeToken {
  bool get hasChanged;
  bool get activeChangeCallbacks;
  IDisposable registerChangeCallback(void Function(Object? state) callback, Object? state);
}

abstract class IDisposable {
  void dispose();
}

class PostEvictionCallbackRegistration {
  final void Function(Object key, Object? value, EvictionReason reason, Object? state) callback;
  final Object? state;

  const PostEvictionCallbackRegistration(this.callback, [this.state]);
}

enum EvictionReason {
  none,
  removed,
  replaced,
  expired,
  tokenExpired,
  capacity,
}

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
