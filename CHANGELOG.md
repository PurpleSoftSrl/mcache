## 0.1.1

- Rename barrel file to `mcache_dart.dart` to match package name convention
- Fix README references and import paths

## 0.1.0

- Initial release
- HashMap + custom doubly-linked list for O(1) LRU with 1 hash lookup per GET
- Absolute, sliding, and change-token expiration (CancellationChangeToken, CallbackChangeToken, CompositeChangeToken)
- Priority eviction with 4 levels (low, normal, high, neverRemove)
- Byte-size limits with configurable compaction percentage
- Anti-stampede GetOrCreate (sync and async)
- Post-eviction callbacks with EvictionReason
- Monotonic Stopwatch clock (no DateTime.now() overhead)
- Zero background timer (pure lazy expiration)
- No sentinel nodes, lazy collections, identical() guard for zero-allocation re-sets
- Benchmarked at 1.48M SET ops/s (faster than quiver, within 13% of raw LRU)
- Single dependency: meta
