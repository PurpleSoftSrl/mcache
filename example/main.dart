import 'package:mcache_dart/mcache_dart.dart';

void main() {
  // Create a cache with a 1 MB size limit
  final cache = MemoryCache(MemoryCacheOptions(sizeLimit: 1 * 1024 * 1024));

  // Store with absolute expiration
  cache.set('key1', 'value1', MemoryCacheEntryOptions()
    ..absoluteExpirationRelativeToNow = const Duration(minutes: 5));

  // Retrieve
  final value = cache.get('key1');
  print('key1 = $value'); // prints: key1 = value1

  // Get-or-create (anti-stampede)
  final created = cache.getOrCreate('key2', () => 'default_value');
  print('key2 = $created'); // prints: key2 = default_value

  // Check statistics
  print('Hits: ${cache.stats.totalHits}, '
      'Misses: ${cache.stats.totalMisses}, '
      'Count: ${cache.count}');

  // Invalidate
  cache.remove('key1');

  // Priority-based eviction
  cache.set('low', 'low_value', MemoryCacheEntryOptions()
    ..priority = CacheItemPriority.low);
  cache.set('high', 'high_value', MemoryCacheEntryOptions()
    ..priority = CacheItemPriority.high);

  // Cleanup
  cache.dispose();
}
