import 'dart:async';
import 'cache_types.dart';

class CancellationChangeToken implements IChangeToken {
  final Completer<void> _completer = Completer<void>();
  bool _changed = false;

  @override
  bool get hasChanged => _changed;

  @override
  bool get activeChangeCallbacks => !_completer.isCompleted;

  void cancel() {
    if (_changed) return;
    _changed = true;
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  @override
  IDisposable registerChangeCallback(void Function(Object? state) callback, Object? state) {
    _completer.future.then((_) => callback(state));
    return _ChangeTokenDisposable();
  }
}

class CallbackChangeToken implements IChangeToken {
  final bool Function() _checker;
  Timer? _timer;
  bool _changed = false;
  bool _disposed = false;

  CallbackChangeToken(this._checker, {Duration pollInterval = const Duration(seconds: 30)}) {
    _timer = Timer.periodic(pollInterval, (_) {
      if (!_changed && _checker()) {
        _changed = true;
        _notifyCallbacks();
        _timer?.cancel();
      }
    });
  }

  @override
  bool get hasChanged => _changed;

  @override
  bool get activeChangeCallbacks => !_disposed;

  final List<void Function(Object?)> _callbacks = [];

  void _notifyCallbacks() {
    for (final cb in List.from(_callbacks)) {
      cb(null);
    }
    _callbacks.clear();
  }

  @override
  IDisposable registerChangeCallback(void Function(Object? state) callback, Object? state) {
    if (_changed) {
      callback(state);
    } else {
      _callbacks.add(callback);
    }
    return _ChangeTokenDisposable();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _callbacks.clear();
  }
}

class CompositeChangeToken implements IChangeToken {
  final List<IChangeToken> _tokens;
  bool _changed = false;
  bool _registered = false;

  CompositeChangeToken(this._tokens);

  @override
  bool get hasChanged => _tokens.any((t) => t.hasChanged);

  @override
  bool get activeChangeCallbacks => !_changed;

  @override
  IDisposable registerChangeCallback(void Function(Object? state) callback, Object? state) {
    if (_registered) return _NoopDisposable();
    _registered = true;
    for (final token in _tokens) {
      token.registerChangeCallback((_) {
        if (!_changed) {
          _changed = true;
          callback(state);
        }
      }, null);
    }
    return _NoopDisposable();
  }
}

class _ChangeTokenDisposable implements IDisposable {
  _ChangeTokenDisposable();
  @override
  void dispose() {}
}

class _NoopDisposable implements IDisposable {
  @override
  void dispose() {}
}
