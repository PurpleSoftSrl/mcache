## 0.1.9

- Add dartdoc documentation to all public API (20%+ coverage)
- Shorten pubspec description for pub.dev scoring
- Add example/ directory with usage sample

## 0.1.8

- Fix CHANGELOG entry for OIDC automated publish compliance

## 0.1.7

- OIDC automated publish fix

## 0.1.6

- Dynamic CI/Publish/Stars badges on README

## 0.1.5

- OIDC-only automated publishing to pub.dev

## 0.1.4

- GitHub Actions CI passing: 69/69 tests on push

## 0.1.3

- Automated publishing via GitHub Actions OIDC to pub.dev

## 0.1.2

- Add GitHub Actions CI workflow (analyze + test on push/PR)
- Add publish workflow (auto-publish to pub.dev on version tag)
- Add dynamic CI badge and platform badges to README

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
