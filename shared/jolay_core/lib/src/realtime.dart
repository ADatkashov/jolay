import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

class RealtimeEvent {
  final String type;
  final Map<String, dynamic> data;
  RealtimeEvent(this.type, this.data);
}

/// WebSocket client with exponential-backoff reconnect. Events are only HINTS: on every (re)connect the app emits a
/// synthetic `CONNECTED` event so screens re-fetch authoritative state over REST (rides, payments, balances).
class RealtimeClient {
  final TokenStore tokens;
  final _ctrl = StreamController<RealtimeEvent>.broadcast();
  WebSocketChannel? _ch;
  Timer? _retry;
  Timer? _ping;
  int _attempt = 0;
  bool _running = false;

  RealtimeClient(this.tokens);
  Stream<RealtimeEvent> get events => _ctrl.stream;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _connect();
  }

  Future<void> _connect() async {
    if (!_running) return;
    final t = await tokens.read();
    if (t == null) {
      _schedule();
      return;
    }
    try {
      final ch = WebSocketChannel.connect(
        Uri.parse('${ApiConfig.wsUrl}?token=${t.access}'),
      );
      _ch = ch;
      await ch.ready;
      _attempt = 0;
      _ctrl.add(RealtimeEvent('CONNECTED', const {}));
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          ch.sink.add('ping');
        } catch (_) {}
      });
      ch.stream.listen(
        (m) {
          if (m is! String || m == 'pong') return;
          try {
            final j = jsonDecode(m) as Map<String, dynamic>;
            _ctrl.add(
              RealtimeEvent(
                j['type'] as String,
                (j['data'] as Map?)?.cast<String, dynamic>() ?? {},
              ),
            );
          } catch (_) {}
        },
        onDone: _schedule,
        onError: (_) => _schedule(),
        cancelOnError: true,
      );
    } catch (_) {
      _schedule();
    }
  }

  void _schedule() {
    _ping?.cancel();
    if (!_running) return;
    _retry?.cancel();
    final delay = Duration(seconds: [1, 2, 4, 8, 15, 30][_attempt.clamp(0, 5)]);
    _attempt++;
    _retry = Timer(delay, _connect);
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _ping?.cancel();
    await _ch?.sink.close();
  }
}
