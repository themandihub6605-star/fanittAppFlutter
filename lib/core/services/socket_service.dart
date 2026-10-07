import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';
import '../storage/token_storage.dart';

class SocketEvent {
  const SocketEvent(this.name, this.data);

  final String name;
  final Map<String, dynamic> data;
}

/// One authenticated Socket.IO connection for the whole app (chat).
class SocketService {
  SocketService(this._tokens);

  final TokenStorage _tokens;
  io.Socket? _socket;
  final StreamController<SocketEvent> _events = StreamController<SocketEvent>.broadcast();

  Stream<SocketEvent> get events => _events.stream;
  bool get isConnected => _socket?.connected ?? false;

  static const _forwarded = [
    'new_message',
    'typing',
    'typing_stop',
    'messages_read',
    'community_message',
    'community_message_removed',
    'community_typing',
    // Fanitt Store calls
    'store_call_request',
    'store_call_accepted',
    'store_call_ended',
  ];

  /// Community chat rooms this device has open — re-joined after reconnects.
  final Set<String> _communityRooms = {};

  Future<void> connect() async {
    final token = await _tokens.accessToken;
    if (token == null) return;

    if (_socket != null) {
      _socket!
        ..auth = {'token': token}
        ..connect();
      return;
    }

    final socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .disableAutoConnect()
          .build(),
    );

    for (final name in _forwarded) {
      socket.on(name, (data) {
        if (data is Map) _events.add(SocketEvent(name, Map<String, dynamic>.from(data)));
      });
    }
    socket.onConnect((_) {
      for (final id in _communityRooms) {
        socket.emit('community_join', {'communityId': id});
      }
    });
    socket.onConnectError((error) async {
      debugPrint('Socket connect error: $error');
      // The token may have been refreshed since we connected.
      final fresh = await _tokens.accessToken;
      if (fresh != null) socket.auth = {'token': fresh};
    });

    _socket = socket..connect();
  }

  /// Sends a message and resolves with the server's ack.
  Future<Map<String, dynamic>?> sendMessage(String conversationId, String text) {
    final socket = _socket;
    if (socket == null || !socket.connected) return Future.value(null);
    final completer = Completer<Map<String, dynamic>?>();
    socket.emitWithAck('send_message', {'conversationId': conversationId, 'text': text}, ack: (data) {
      if (!completer.isCompleted) completer.complete(data is Map ? Map<String, dynamic>.from(data) : null);
    });
    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
  }

  void typing(String conversationId, {required bool active}) {
    _socket?.emit(active ? 'typing_start' : 'typing_stop', {'conversationId': conversationId});
  }

  /// Emits an event and resolves with the server's ack (null on timeout /
  /// when not connected).
  Future<Map<String, dynamic>?> emitWithAck(String event, Map<String, dynamic> data) {
    final socket = _socket;
    if (socket == null || !socket.connected) return Future.value(null);
    final completer = Completer<Map<String, dynamic>?>();
    socket.emitWithAck(event, data, ack: (response) {
      if (!completer.isCompleted) completer.complete(response is Map ? Map<String, dynamic>.from(response) : null);
    });
    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
  }

  // --- Community group chat ---------------------------------------------------

  Future<void> joinCommunity(String communityId) async {
    _communityRooms.add(communityId);
    await connect();
    await emitWithAck('community_join', {'communityId': communityId});
  }

  void leaveCommunity(String communityId) {
    _communityRooms.remove(communityId);
    _socket?.emit('community_leave', {'communityId': communityId});
  }

  void communityTyping(String communityId) {
    _socket?.emit('community_typing', {'communityId': communityId});
  }

  void disconnect() {
    _communityRooms.clear();
    _socket?.dispose();
    _socket = null;
  }
}