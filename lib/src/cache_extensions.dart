import 'dart:async';
import 'memory_cache.dart';
import 'cache_types.dart';

/// Convenience extension on [MemoryCache] for get-or-create patterns.

extension CacheExtensions on MemoryCache {
  /// Gets a value by [key], or creates it via [factory] and stores it.

  /// Returns the existing value on hit, otherwise calls [factory], stores
  /// the result, and returns it. This is atomic at the instance level and
  /// prevents stampede for synchronous factories.
  T getOrCreate<T>(Object key, Object? Function() factory,
      [MemoryCacheEntryOptions? opts]) {
    Object? result;
    if (tryGet(key, (v) => result = v)) return result as T;
    final value = factory();
    set(key, value, opts);
    return value as T;
  }

  /// Gets a value by [key], or creates it asynchronously via [factory] and stores it.

  /// Returns the existing value on hit, otherwise calls the async [factory],
  /// stores the result, and returns it.
  Future<T> getOrCreateAsync<T>(Object key, FutureOr<Object?> Function() factory,
      [MemoryCacheEntryOptions? opts]) async {
    Object? result;
    if (tryGet(key, (v) => result = v)) return result as T;
    final value = await factory();
    set(key, value, opts);
    return value as T;
  }
}
