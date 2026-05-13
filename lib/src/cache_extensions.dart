import 'memory_cache.dart';
import 'cache_types.dart';

extension CacheExtensions on MemoryCache {
  T getOrCreate<T>(Object key, T Function() factory, [MemoryCacheEntryOptions? opts]) {
    dynamic result;
    if (tryGet(key, (v) => result = v)) return result as T;
    final value = factory();
    set(key, value, opts);
    return value;
  }

  Future<T> getOrCreateAsync<T>(Object key, Future<T> Function() factory, [MemoryCacheEntryOptions? opts]) async {
    dynamic result;
    if (tryGet(key, (v) => result = v)) return result as T;
    final value = await factory();
    set(key, value, opts);
    return value;
  }
}
