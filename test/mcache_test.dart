import 'package:mcache/mcache.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryCache', () {
    late MemoryCache cache;

    setUp(() {
      cache = MemoryCache();
    });

    tearDown(() {
      cache.dispose();
    });

    test('set and get', () {
      cache.set('key', 'value');
      expect(cache.get('key'), equals('value'));
    });

    test('get returns null for missing key', () {
      expect(cache.get('missing'), isNull);
    });

    test('tryGet calls callback on hit', () {
      cache.set('key', 42);
      int? result;
      expect(cache.tryGet('key', (v) => result = v as int), isTrue);
      expect(result, equals(42));
    });

    test('tryGet returns false on miss', () {
      expect(cache.tryGet('key', (_) {}), isFalse);
    });

    test('absolute expiration', () async {
      cache.set('key', 'value', MemoryCacheEntryOptions()
        ..absoluteExpirationRelativeToNow = const Duration(milliseconds: 100));
      expect(cache.get('key'), equals('value'));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(cache.get('key'), isNull);
    });

    test('sliding expiration', () async {
      cache.set('key', 'value', MemoryCacheEntryOptions()
        ..slidingExpiration = const Duration(milliseconds: 200));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(cache.get('key'), equals('value')); // resets timer
      await Future.delayed(const Duration(milliseconds: 50));
      expect(cache.get('key'), equals('value')); // still alive (~50ms since reset, <200)
      await Future.delayed(const Duration(milliseconds: 250));
      expect(cache.get('key'), isNull); // expired (~300ms since reset, >200)
    });

    test('getOrCreate computes once', () {
      var calls = 0;
      final v1 = cache.getOrCreate('key', () { calls++; return 'computed'; });
      final v2 = cache.getOrCreate('key', () { calls++; return 'computed2'; });
      expect(v1, equals('computed'));
      expect(v2, equals('computed'));
      expect(calls, equals(1)); // factory called exactly once
    });

    test('getOrCreateAsync', () async {
      final v = await cache.getOrCreateAsync('key', () async => 'async');
      expect(v, equals('async'));
    });

    test('remove fires callback', () {
      var fired = false;
      cache.set('key', 'value', MemoryCacheEntryOptions()
        ..postEvictionCallbacks = [
          PostEvictionCallbackRegistration((k, v, r, s) {
            fired = true;
            expect(r, equals(EvictionReason.removed));
          }),
        ]);
      cache.remove('key');
      expect(fired, isTrue);
    });

    test('change token expires entry', () {
      final token = CancellationChangeToken();
      cache.set('key', 'value', MemoryCacheEntryOptions()
        ..expirationTokens = [token]);
      expect(cache.get('key'), equals('value'));
      token.cancel();
      expect(cache.get('key'), isNull);
    });

    test('priority eviction', () {
      final c = MemoryCache(MemoryCacheOptions(sizeLimit: 300));
      c.set('a', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
      c.set('b', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
      c.set('c', 'x' * 100, MemoryCacheEntryOptions()
        ..size = 100
        ..priority = CacheItemPriority.neverRemove);
      c.set('d', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
      expect(c.get('c'), isNotNull); // never removed
      expect(c.get('a'), isNull);   // evicted (lowest priority + oldest)
      c.dispose();
    });

    test('stats track hits and misses', () {
      cache.set('key', 'value');
      cache.tryGet('key', (_) {});
      cache.tryGet('missing', (_) {});
      expect(cache.stats.totalHits, equals(1));
      expect(cache.stats.totalMisses, equals(1));
    });

    test('clear removes all entries', () {
      cache.set('a', 1);
      cache.set('b', 2);
      cache.clear();
      expect(cache.count, equals(0));
      expect(cache.get('a'), isNull);
    });
  });
}
