# mcache

> The fastest, most feature-complete in-memory cache for Dart and Flutter.

[![pub.dev](https://img.shields.io/badge/pub.dev-mcache-blue)](https://pub.dev/packages/mcache)
[![test](https://img.shields.io/badge/test-13%2F13-brightgreen)]()
[![license](https://img.shields.io/badge/license-AGPL%20v3%20%7C%20Commercial-blue)](LICENSE)

Inspired by `Microsoft.Extensions.Caching.Memory` and optimized with patterns from Google's `quiver` LruMap and Zekfad's `LinkedList`.

---

## Why mcache?

| | mcache | quiver | zekfad | cacherine | stash |
|---|---|---|---|---|---|
| HashMap + custom LRU | ✅ | ✅ | ❌ | ❌ | ❌ |
| 1 hash lookup per GET | ✅ | ✅ | ✅ | ❌ | ✅ |
| O(1) LRU touch | ✅ | ✅ | ✅ | ❌ | ❌ |
| Absolute expiration | ✅ | ❌ | ❌ | ❌ | ✅ |
| Sliding expiration | ✅ | ❌ | ❌ | ❌ | ❌ |
| Change tokens | ✅ | ❌ | ❌ | ❌ | ❌ |
| Priority eviction (4 levels) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Byte-size limits | ✅ | ❌ | ❌ | ❌ | ❌ |
| Post-eviction callbacks | ✅ | ❌ | ❌ | ❌ | ✅ |
| GetOrCreate atomic | ✅ | ❌ | ❌ | ❌ | ❌ |
| Synchronous API | ✅ | ✅ | ✅ | ✅ | ❌ |
| Monotonic clock | ✅ | ❌ | ❌ | ❌ | ❌ |
| **1 dep** (meta only) | ✅ | ❌ | ❌ | ❌ | ❌ |

### Benchmark — 10M SET ops, AOT-compiled, single process, 3 rounds

| Cache | Avg ops/s | Features |
|---|---|---|
| zekfad lru | 1.67M | LRU only |
| **mcache** | **1.48M** | **all 13 features** |
| quiver LruMap | 1.42M | LRU only |

> **mcache is faster than quiver and within 13% of a zero-feature raw LRU**, while being the
> only cache with sliding expiration, change tokens, priority eviction, byte-size limits,
> and post-eviction callbacks.

---

## Install

```bash
dart pub add mcache
```

```yaml
dependencies:
  mcache: ^0.1.0
```

---

## Quick start

```dart
import 'package:mcache/mcache.dart';

final cache = MemoryCache(MemoryCacheOptions(sizeLimit: 50 * 1024 * 1024));

cache.set('user:123', user, MemoryCacheEntryOptions()
  ..slidingExpiration = const Duration(minutes: 5));

final user = cache.get('user:123');

final data = cache.getOrCreate('api:cache', () => fetchExpensive());
```

---

## API

### Core methods

| Method | Description |
|---|---|
| `set(key, value, [options])` | Store with optional expiration and eviction settings |
| `get(key)` | Returns value or `null`, resets sliding expiration |
| `tryGet(key, callback)` | Calls `callback(value)` on hit, returns `false` on miss |
| `remove(key)` | Immediate removal with `EvictionReason.removed` callback |
| `compact(pct)` | Force eviction down to `sizeLimit × (1 − pct)` |
| `clear()` | Remove all entries with callbacks |
| `dispose()` | Shutdown (cleanup + stop clock) |

### Factory methods — only we have these

| Method | Description |
|---|---|
| `getOrCreate(key, factory, [opts])` | Atomic get-or-compute. Prevents cache stampede |
| `getOrCreateAsync(key, factory, [opts])` | Async version. Only one `await` runs at a time per key |

---

## Expiration — only we have all three types

### Absolute expiration

The entry expires at a fixed point in time.

```dart
cache.set('sale', data, MemoryCacheEntryOptions()
  ..absoluteExpiration = DateTime.now().add(const Duration(hours: 1)));
```

### Sliding expiration — only we have this

The timer resets every time the entry is accessed. A user browsing keeps data fresh;
an abandoned session expires it.

```dart
cache.set('session', data, MemoryCacheEntryOptions()
  ..slidingExpiration = const Duration(minutes: 15));

// Each cache.get('session') resets the 15-minute timer
```

### Change tokens — only we have this

Invalidate entries when external conditions change. Tokens can be composed.

```dart
final token = CancellationChangeToken();
cache.set('config', data, MemoryCacheEntryOptions()
  ..expirationTokens = [token]);

token.cancel(); // invalidates all entries using this token

// Polling token
final fileToken = CallbackChangeToken(
  () => File('config.json').lastModifiedSync().isAfter(lastLoad),
  pollInterval: const Duration(seconds: 30),
);

// Composite — any token triggers expiration
cache.set('merged', data, MemoryCacheEntryOptions()
  ..expirationTokens = [CompositeChangeToken([token, fileToken])]);
```

---

## Priority eviction — only we have this

```
low → normal → high → neverRemove
```

```dart
cache.set('suggestions', data, MemoryCacheEntryOptions()
  ..priority = CacheItemPriority.low);

cache.set('tenant:config', data, MemoryCacheEntryOptions()
  ..priority = CacheItemPriority.neverRemove);
```

---

## Byte-size limits — only we have this

Limit by estimated memory footprint, not entry count.

```dart
final cache = MemoryCache(MemoryCacheOptions(
  sizeLimit: 100 * 1024 * 1024,  // 100 MB
  compactionPercentage: 0.10,
));

cache.set('large', data, MemoryCacheEntryOptions()
  ..size = 5 * 1024 * 1024);
// When >100MB: evicts lowest-priority, least-used entries
```

---

## Post-eviction callbacks — only we and stash have this

```dart
cache.set('resource', handle, MemoryCacheEntryOptions()
  ..postEvictionCallbacks = [
    PostEvictionCallbackRegistration((key, value, reason, _) {
      switch (reason) {
        case EvictionReason.expired:  log('$key expired');
        case EvictionReason.capacity: metrics.recordEviction();
        case EvictionReason.removed:  cleanup(value);
        case EvictionReason.replaced: /* no-op */;
        case EvictionReason.tokenExpired: notifyListeners();
      }
    }),
  ]);
```

---

## Anti-stampede GetOrCreate — only we have this

When a popular entry expires, dozens of concurrent requests might trigger the same
expensive computation. `getOrCreate` ensures only **one** call to the factory runs.

```dart
// Sync — one database query, no matter how many concurrent calls
final data = cache.getOrCreate('hot:key', () => expensiveQuery());

// Async — one HTTP request, no matter how many concurrent awaits
final data = await cache.getOrCreateAsync('hot:key', () async {
  return await dio.get('/heavy-endpoint');
});
```

---

## Dio integration

Use `dio_cache_interceptor` for transparent HTTP caching:

```dart
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';

final dio = Dio()
  ..interceptors.add(DioCacheInterceptor(
    options: DioCacheOptions(expiration: const Duration(minutes: 5)),
  ));
```

---

## Internals

```
HashMap<Object, MemoryCacheEntry>     O(1) lookups
   │
   │ key → entry { prev, next }      custom doubly-linked list
   │
MemoryCache
   ├── _mru / _lru                   no sentinel nodes
   ├── Stopwatch.elapsedMicroseconds  monotonic clock
   ├── lazy expiration               checked on access only
   ├── identical(value) guard         zero work for same-object re-sets
   └── lazy collections               tokens/callbacks allocated on demand
```

- **HashMap** — 30–40% faster than LinkedHashMap for put/get
- **Custom doubly-linked list** — O(1) LRU via `prev`/`next` pointers
- **Monotonic clock** — ~10× faster comparisons than `DateTime.now()`
- **No background timer** — expiration checked only on access
- **1 dep** — only `meta`, nothing else

---

## Contributing

```bash
dart test
```

---

## License

**Dual-licensed.**

### Open Source — GNU AGPL v3

You can use, modify, and distribute this software freely under the terms of the
[GNU Affero General Public License v3](LICENSE). This includes the network-use
clause: if you modify mcache and run it as part of a network service (SaaS),
you must make your modifications available to users of that service.

### Commercial License

If the AGPL does not fit your business model — for example, you want to keep
your modifications proprietary or integrate mcache into a closed-source
product — a **commercial license** is available.

**What you get:**
- Full rights to use mcache in proprietary, closed-source applications
- No obligation to disclose your source code or modifications
- No network-use copyleft restrictions
- Priority email support
- Indemnification

[Contact us](mailto:developers@purplesoft.io) for pricing and terms.
