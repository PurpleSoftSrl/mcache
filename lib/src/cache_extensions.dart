import 'dart:async';
import 'memory_cache.dart';
import 'cache_types.dart';

extension CacheExtensions on MemoryCache {
  T getOrCreate<T>(Object key, Object? Function() factory,
      [MemoryCacheEntryOptions? opts]) {
    Object? result;
    if (tryGet(key, (v) => result = v)) return result as T;
    final value = factory();
    set(key, value, opts);
    return value as T;
  }

  Future<T> getOrCreateAsync<T>(Object key, FutureOr<Object?> Function() factory,
      [MemoryCacheEntryOptions? opts]) async {
    Object? result;
    if (tryGet(key, (v) => result = v)) return result as T;
    final value = await factory();
    set(key, value, opts);
    return value as T;
  }
}
