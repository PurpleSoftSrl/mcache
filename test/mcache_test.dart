import 'dart:async';
import 'dart:math';
import 'package:mcache_dart/mcache.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryCache', () {
    group('Basic CRUD', _basicCrud);
    group('Expiration', _expiration);
    group('Change tokens', _changeTokens);
    group('Priority eviction', _priorityEviction);
    group('Size limits & compaction', _sizeLimits);
    group('Post-eviction callbacks', _callbacks);
    group('GetOrCreate / anti-stampede', _getOrCreate);
    group('Statistics', _statistics);
    group('Clear & dispose', _clearDispose);
    group('Edge cases', _edgeCases);
    group('Stress / scale', _stress);
  });
}

void _basicCrud() {
  late MemoryCache cache;
  setUp(() => cache = MemoryCache());
  tearDown(() => cache.dispose());

  test('set and get', () {
    cache.set('k', 'v');
    expect(cache.get('k'), 'v');
  });

  test('get missing returns null', () {
    expect(cache.get('x'), isNull);
  });

  test('overwrite replaces value', () {
    cache.set('k', 1);
    cache.set('k', 2);
    expect(cache.get('k'), 2);
  });

  test('null value allowed', () {
    cache.set('k', null);
    expect(cache.get('k'), isNull);
  });

  test('remove existing key', () {
    cache.set('k', 1);
    cache.remove('k');
    expect(cache.get('k'), isNull);
  });

  test('remove missing key is no-op', () {
    cache.remove('x');
    expect(cache.count, 0);
  });

  test('count reflects entries', () {
    expect(cache.count, 0);
    cache.set('a', 1);
    cache.set('b', 2);
    expect(cache.count, 2);
    cache.remove('a');
    expect(cache.count, 1);
  });

  test('tryGet on hit', () {
    cache.set('k', 42);
    int? result;
    expect(cache.tryGet('k', (v) => result = v as int), isTrue);
    expect(result, 42);
  });

  test('tryGet on miss', () {
    expect(cache.tryGet('k', (_) {}), isFalse);
  });

  test('identical value set skips work', () {
    final obj = Object();
    cache.set('k', obj);
    cache.set('k', obj); // same reference — should be no-op after promote
    expect(cache.get('k'), same(obj));
  });

  test('different value updates entry', () {
    final a = Object();
    final b = Object();
    cache.set('k', a);
    cache.set('k', b);
    expect(cache.get('k'), same(b));
  });

  test('set many keys', () {
    for (var i = 0; i < 1000; i++) {
      cache.set('k_$i', i);
    }
    expect(cache.count, 1000);
    expect(cache.get('k_500'), 500);
  });
}

void _expiration() {
  late MemoryCache cache;
  setUp(() => cache = MemoryCache());
  tearDown(() => cache.dispose());

  test('absolute expiration via DateTime', () async {
    final expiresAt = DateTime.now().add(const Duration(milliseconds: 100));
    cache.set('k', 'v', MemoryCacheEntryOptions()..absoluteExpiration = expiresAt);
    expect(cache.get('k'), 'v');
    await Future.delayed(const Duration(milliseconds: 200));
    expect(cache.get('k'), isNull);
  });

  test('absolute expiration via Duration', () async {
    cache.set('k', 'v', MemoryCacheEntryOptions()
      ..absoluteExpirationRelativeToNow = const Duration(milliseconds: 100));
    expect(cache.get('k'), 'v');
    await Future.delayed(const Duration(milliseconds: 200));
    expect(cache.get('k'), isNull);
  });

  test('sliding expiration resets on access', () async {
    cache.set('k', 'v', MemoryCacheEntryOptions()
      ..slidingExpiration = const Duration(milliseconds: 200));
    await Future.delayed(const Duration(milliseconds: 100));
    expect(cache.get('k'), 'v'); // access resets
    await Future.delayed(const Duration(milliseconds: 150)); // ~150ms since reset, <200
    expect(cache.get('k'), 'v'); // still alive
    await Future.delayed(const Duration(milliseconds: 250)); // >200 since last access
    expect(cache.get('k'), isNull);
  });

  test('sliding expiration expires without access', () async {
    cache.set('k', 'v', MemoryCacheEntryOptions()
      ..slidingExpiration = const Duration(milliseconds: 50));
    await Future.delayed(const Duration(milliseconds: 100));
    expect(cache.get('k'), isNull);
  });

  test('absolute + sliding combined', () async {
    // sliding is stricter than absolute
    cache.set('k', 'v', MemoryCacheEntryOptions()
      ..absoluteExpirationRelativeToNow = const Duration(milliseconds: 500)
      ..slidingExpiration = const Duration(milliseconds: 100));
    await Future.delayed(const Duration(milliseconds: 200)); // no access, sliding expired
    expect(cache.get('k'), isNull); // sliding killed it before absolute could
  });

  test('expired entry removed from count', () async {
    cache.set('k', 'v', MemoryCacheEntryOptions()
      ..absoluteExpirationRelativeToNow = const Duration(milliseconds: 50));
    expect(cache.count, 1);
    await Future.delayed(const Duration(milliseconds: 100));
    cache.get('k'); // triggers lazy expiration and removal
    expect(cache.count, 0);
  });
}

void _changeTokens() {
  late MemoryCache cache;
  setUp(() => cache = MemoryCache());
  tearDown(() => cache.dispose());

  test('CancellationChangeToken cancels immediately', () {
    final t = CancellationChangeToken();
    cache.set('k', 'v', MemoryCacheEntryOptions()..expirationTokens = [t]);
    expect(cache.get('k'), 'v');
    t.cancel();
    expect(cache.get('k'), isNull);
    expect(t.hasChanged, isTrue);
  });

  test('CancellationChangeToken double cancel is idempotent', () {
    final t = CancellationChangeToken();
    t.cancel();
    t.cancel();
    expect(t.hasChanged, isTrue);
  });

  test('CallbackChangeToken fires on condition', () async {
    var expired = false;
    final t = CallbackChangeToken(() => expired, pollInterval: const Duration(milliseconds: 50));
    cache.set('k', 'v', MemoryCacheEntryOptions()..expirationTokens = [t]);
    expect(cache.get('k'), 'v');

    expired = true;
    await Future.delayed(const Duration(milliseconds: 100));
    expect(cache.get('k'), isNull);
  });

  test('CompositeChangeToken fires if any child fires', () {
    final a = CancellationChangeToken();
    final b = CancellationChangeToken();
    final composite = CompositeChangeToken([a, b]);
    cache.set('k', 'v', MemoryCacheEntryOptions()..expirationTokens = [composite]);
    expect(cache.get('k'), 'v');

    b.cancel(); // only b fires
    expect(cache.get('k'), isNull);
  });

  test('CompositeChangeToken with no child does not expire', () {
    final c = CompositeChangeToken([]);
    cache.set('k', 'v', MemoryCacheEntryOptions()..expirationTokens = [c]);
    expect(cache.get('k'), 'v');
    // should still be alive since no token fired
    expect(cache.get('k'), 'v');
  });

  test('token combined with absolute expiration', () async {
    final t = CancellationChangeToken();
    cache.set('k', 'v', MemoryCacheEntryOptions()
      ..absoluteExpirationRelativeToNow = const Duration(milliseconds: 500)
      ..expirationTokens = [t]);
    expect(cache.get('k'), 'v');
    t.cancel();
    expect(cache.get('k'), isNull);
  });
}

void _priorityEviction() {
  test('low evicted before normal', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 250));
    c.set('a', 'x' * 100, MemoryCacheEntryOptions()..size = 100 ..priority = CacheItemPriority.low);
    c.set('b', 'x' * 100, MemoryCacheEntryOptions()..size = 100 ..priority = CacheItemPriority.normal);
    c.set('d', 'x' * 100, MemoryCacheEntryOptions()..size = 100 ..priority = CacheItemPriority.normal);
    expect(c.get('a'), isNull); // low evicted first
    expect(c.get('b'), isNotNull);
    c.dispose();
  });

  test('normal evicted before high', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 250));
    c.set('a', 'x' * 100, MemoryCacheEntryOptions()..size = 100 ..priority = CacheItemPriority.normal);
    c.set('b', 'x' * 100, MemoryCacheEntryOptions()..size = 100 ..priority = CacheItemPriority.high);
    c.set('d', 'x' * 100, MemoryCacheEntryOptions()..size = 100 ..priority = CacheItemPriority.normal);
    expect(c.get('a'), isNull);
    expect(c.get('b'), isNotNull);
    c.dispose();
  });

  test('neverRemove survives eviction', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 10));
    c.set('vip', 'precious', MemoryCacheEntryOptions()..size = 100 ..priority = CacheItemPriority.neverRemove);
    c.set('x', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    // even though size massively exceeds limit, neverRemove is kept
    expect(c.get('vip'), isNotNull);
    c.dispose();
  });

  test('LRU within same priority', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 350));
    c.set('old', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    c.set('young', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    c.get('old'); // promote to MRU, young becomes LRU
    c.set('newest', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    c.set('fourth', 'x' * 100, MemoryCacheEntryOptions()..size = 100); // triggers eviction
    expect(c.get('old'), isNotNull);
    expect(c.get('young'), isNull); // young was LRU
    c.dispose();
  });

  test('neverRemove survives eviction', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 50));
    c.set('vip', 'x', MemoryCacheEntryOptions()..size = 100 ..priority = CacheItemPriority.neverRemove);
    c.set('x', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    expect(c.get('vip'), isNotNull);
    c.dispose();
  });

  test('LRU within same priority', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 350));
    c.set('old', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    c.set('young', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    c.get('old'); // promote to MRU, young becomes LRU
    c.set('newest', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    c.set('fourth', 'x' * 100, MemoryCacheEntryOptions()..size = 100); // triggers eviction
    expect(c.get('old'), isNotNull);
    expect(c.get('young'), isNull);
    c.dispose();
  });

  test('neverRemove survives eviction', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 10));
    c.set('vip', 'precious', MemoryCacheEntryOptions()..size = 100 ..priority = CacheItemPriority.neverRemove);
    c.set('x', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    // even though size massively exceeds limit, neverRemove is kept
    expect(c.get('vip'), isNotNull);
    c.dispose();
  });

  test('LRU within same priority', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 350));
    c.set('old', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    c.set('young', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    c.get('old'); // promote to MRU, young becomes LRU
    c.set('newest', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    c.set('fourth', 'x' * 100, MemoryCacheEntryOptions()..size = 100); // triggers eviction
    expect(c.get('old'), isNotNull);
    expect(c.get('young'), isNull); // young was LRU
    c.dispose();
  });
}

void _sizeLimits() {
  test('entry size tracked correctly', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 500));
    c.set('a', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    c.set('b', 'x' * 200, MemoryCacheEntryOptions()..size = 200);
    expect(c.stats.currentEstimatedSize, greaterThan(250));
    c.dispose();
  });

  test('compaction reduces size', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 500));
    for (var i = 0; i < 20; i++) {
      c.set('k_$i', 'x' * 50, MemoryCacheEntryOptions()..size = 50);
    }
    final before = c.count;
    c.compact(0.5);
    expect(c.count, lessThan(before));
    c.dispose();
  });

  test('no size limit means no eviction', () {
    final c = MemoryCache(); // no sizeLimit
    for (var i = 0; i < 5000; i++) {
      c.set('k_$i', 'v');
    }
    expect(c.count, 5000);
    c.dispose();
  });

  test('replacing updates size', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 500));
    c.set('k', 'x' * 10, MemoryCacheEntryOptions()..size = 50);
    final s1 = c.stats.currentEstimatedSize;
    c.set('k', 'x' * 50, MemoryCacheEntryOptions()..size = 200);
    final s2 = c.stats.currentEstimatedSize;
    expect(s2, greaterThan(s1)); // size increased
    c.dispose();
  });
}

void _callbacks() {
  late MemoryCache cache;
  setUp(() => cache = MemoryCache());
  tearDown(() => cache.dispose());

  test('removed reason', () {
    EvictionReason? reason;
    cache.set('k', 'v', MemoryCacheEntryOptions()
      ..postEvictionCallbacks = [
        PostEvictionCallbackRegistration((k, v, r, s) => reason = r),
      ]);
    cache.remove('k');
    expect(reason, EvictionReason.removed);
  });

  test('replaced reason', () {
    EvictionReason? reason;
    cache.set('k', 'v1', MemoryCacheEntryOptions()
      ..postEvictionCallbacks = [
        PostEvictionCallbackRegistration((k, v, r, s) => reason = r),
      ]);
    cache.set('k', 'v2'); // replaces
    expect(reason, EvictionReason.replaced);
  });

  test('expired reason', () async {
    EvictionReason? reason;
    cache.set('k', 'v', MemoryCacheEntryOptions()
      ..absoluteExpirationRelativeToNow = const Duration(milliseconds: 10)
      ..postEvictionCallbacks = [
        PostEvictionCallbackRegistration((k, v, r, s) => reason = r),
      ]);
    await Future.delayed(const Duration(milliseconds: 50));
    cache.get('k'); // triggers lazy expiration
    expect(reason, EvictionReason.expired);
  });

  test('capacity reason', () {
    EvictionReason? reason;
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 50));
    c.set('k', 'v', MemoryCacheEntryOptions()
      ..size = 40
      ..postEvictionCallbacks = [
        PostEvictionCallbackRegistration((k, v, r, s) => reason = r),
      ]);
    c.set('x', 'y', MemoryCacheEntryOptions()..size = 40); // triggers eviction
    expect(reason, EvictionReason.capacity);
    c.dispose();
  });

  test('clear fires removed for all', () {
    var count = 0;
    for (var i = 0; i < 10; i++) {
      cache.set('k_$i', i, MemoryCacheEntryOptions()
        ..postEvictionCallbacks = [
          PostEvictionCallbackRegistration((k, v, r, s) => count++),
        ]);
    }
    cache.clear();
    expect(count, 10);
  });
}

void _getOrCreate() {
  late MemoryCache cache;
  setUp(() => cache = MemoryCache());
  tearDown(() => cache.dispose());

  test('factory called only once', () {
    var calls = 0;
    cache.getOrCreate('k', () { calls++; return 1; });
    cache.getOrCreate('k', () { calls++; return 2; });
    expect(calls, 1);
  });

  test('factory not called on hit', () {
    cache.set('k', 42);
    final v = cache.getOrCreate('k', () => throw 'should not call');
    expect(v, 42);
  });

  test('factory result is stored', () {
    final v1 = cache.getOrCreate('k', () => 'computed');
    final v2 = cache.get('k');
    expect(v1, v2);
    expect(v1, 'computed');
  });

  test('getOrCreateAsync', () async {
    final v = await cache.getOrCreateAsync('k', () async => 'async val');
    expect(v, 'async val');
  });

  test('getOrCreateAsync not called on hit', () async {
    cache.set('k', 'existing');
    final v = await cache.getOrCreateAsync('k', () async => throw 'nope');
    expect(v, 'existing');
  });

  test('getOrCreateAsync stores result', () async {
    final v1 = await cache.getOrCreateAsync('k', () async => 'computed');
    final v2 = cache.get('k');
    expect(v1, v2);
  });

  test('getOrCreate with options', () {
    cache.getOrCreate('k', () => 'v', MemoryCacheEntryOptions()
      ..priority = CacheItemPriority.neverRemove);
    // Fill with low-priority entries to verify neverRemove is kept
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 50));
    c.getOrCreate('vip', () => 'data', MemoryCacheEntryOptions()
      ..size = 40 ..priority = CacheItemPriority.neverRemove);
    c.set('x', 'y', MemoryCacheEntryOptions()..size = 40);
    expect(c.get('vip'), isNotNull);
    c.dispose();
  });
}

void _statistics() {
  late MemoryCache cache;
  setUp(() => cache = MemoryCache());
  tearDown(() => cache.dispose());

  test('hits and misses', () {
    cache.set('k', 1);
    cache.tryGet('k', (_) {});
    cache.tryGet('missing', (_) {});
    cache.tryGet('missing', (_) {});
    expect(cache.stats.totalHits, 1);
    expect(cache.stats.totalMisses, 2);
  });

  test('entry count', () {
    expect(cache.stats.currentEntryCount, 0);
    cache.set('a', 1);
    expect(cache.stats.currentEntryCount, 1);
    cache.set('b', 2);
    expect(cache.stats.currentEntryCount, 2);
    cache.remove('a');
    expect(cache.stats.currentEntryCount, 1);
  });

  test('estimated size reflects additions', () {
    cache.set('a', 'x' * 100, MemoryCacheEntryOptions()..size = 100);
    expect(cache.stats.currentEstimatedSize, greaterThan(0));
  });

  test('stats reset after clear', () {
    for (var i = 0; i < 10; i++) {
      cache.set('k_$i', i);
      cache.get('k_$i');
    }
    cache.clear();
    expect(cache.stats.currentEntryCount, 0);
    expect(cache.stats.currentEstimatedSize, 0);
    // hits/misses are NOT reset — they are cumulative
    expect(cache.stats.totalHits, greaterThan(0));
  });
}

void _clearDispose() {
  late MemoryCache cache;
  setUp(() => cache = MemoryCache());
  tearDown(() => cache.dispose());

  test('clear empties all entries', () {
    cache.set('a', 1);
    cache.set('b', 2);
    cache.clear();
    expect(cache.count, 0);
    expect(cache.get('a'), isNull);
    expect(cache.get('b'), isNull);
  });

  test('clear fires callbacks', () {
    var fired = 0;
    for (var i = 0; i < 5; i++) {
      cache.set('k_$i', i, MemoryCacheEntryOptions()
        ..postEvictionCallbacks = [
          PostEvictionCallbackRegistration((k, v, r, s) => fired++),
        ]);
    }
    cache.clear();
    expect(fired, 5);
  });

  test('dispose stops the clock', () {
    cache.dispose();
    // no-op after dispose
    cache.set('k', 'v');
    expect(cache.count, 0);
  });

  test('double dispose is safe', () {
    cache.dispose();
    cache.dispose();
  });

  test('operations after dispose are no-op', () {
    cache.dispose();
    cache.set('k', 1);
    expect(cache.get('k'), isNull);
    cache.remove('k'); // should not throw
    cache.clear(); // should not throw
  });
}

void _edgeCases() {
  late MemoryCache cache;
  setUp(() => cache = MemoryCache());
  tearDown(() => cache.dispose());

  test('empty string key', () {
    cache.set('', 'v');
    expect(cache.get(''), 'v');
  });

  test('int key', () {
    cache.set(42, 'v');
    expect(cache.get(42), 'v');
  });

  test('object key', () {
    final k = Object();
    cache.set(k, 'v');
    expect(cache.get(k), 'v');
  });

  test('size limit zero', () {
    final c = MemoryCache(MemoryCacheOptions(sizeLimit: 0));
    c.set('k', 'v', MemoryCacheEntryOptions()..size = 1);
    expect(c.get('k'), isNull); // evicted immediately
    c.dispose();
  });

  test('large compaction percentage', () {
    final c = MemoryCache(MemoryCacheOptions(
      sizeLimit: 200,
      compactionPercentage: 0.9,
    ));
    for (var i = 0; i < 20; i++) {
      c.set('k_$i', 'x' * 50, MemoryCacheEntryOptions()..size = 50);
    }
    // with 90% compaction, should keep very few entries
    expect(c.count, lessThan(10));
    c.dispose();
  });

  test('custom clock', () {
    var ticks = 0;
    final c = MemoryCache(MemoryCacheOptions(clock: () => ticks));
    c.set('k', 'v', MemoryCacheEntryOptions()
      ..absoluteExpirationRelativeToNow = const Duration(milliseconds: 100));
    expect(c.get('k'), 'v');
    ticks = 200000; // advance clock beyond expiration
    expect(c.get('k'), isNull);
    c.dispose();
  });

  test('expired token on access after cancel', () {
    final t = CancellationChangeToken();
    cache.set('k', 'v', MemoryCacheEntryOptions()..expirationTokens = [t]);
    t.cancel();
    expect(cache.get('k'), isNull); // lazy check on access
    expect(cache.count, 0);
  });

  test('same key with different types', () {
    cache.set('k', 'string');
    cache.set('k', 42);
    expect(cache.get('k'), 42);
  });

  test('remove key that was already removed', () {
    cache.set('k', 1);
    cache.remove('k');
    cache.remove('k'); // no-op, no throw
    expect(cache.count, 0);
  });
}

void _stress() {
  test('10k inserts and reads', () {
    final cache = MemoryCache();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 10000; i++) {
      cache.set('k_$i', i);
    }
    for (var i = 0; i < 10000; i++) {
      expect(cache.get('k_$i'), i);
    }
    sw.stop();
    expect(cache.count, 10000);
    expect(sw.elapsedMilliseconds, lessThan(5000));
    cache.dispose();
  });

  test('mixed operations with expiration', () async {
    final cache = MemoryCache(MemoryCacheOptions(sizeLimit: 50 * 1024));
    final rng = Random(42);
    for (var i = 0; i < 5000; i++) {
      cache.set('k_$i', 'v_$i', MemoryCacheEntryOptions()
        ..slidingExpiration = const Duration(seconds: 30)
        ..size = rng.nextInt(10) + 1);
      if (i % 3 == 0) cache.get('k_${i ~/ 2}');
      if (i % 7 == 0) cache.remove('k_${i - 1}');
    }
    expect(cache.count, greaterThan(0));
    cache.dispose();
  });

  test('100k rapid sets with no size limit', () {
    final cache = MemoryCache();
    for (var i = 0; i < 100000; i++) {
      cache.set(i, i);
    }
    expect(cache.count, 100000);
    cache.dispose();
  });
}
