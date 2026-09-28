import 'dart:async';

import 'package:equatable/equatable.dart';

import '../../../core/bloc/safe_cubit.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/socket_service.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';

class ChatState extends Equatable {
  const ChatState({
    this.messages = const [],
    this.isLoading = true,
    this.errorMessage,
    this.sendError,
    this.otherIsTyping = false,
    this.tick = 0,
  });

  /// Oldest first.
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? errorMessage;
  final String? sendError;
  final bool otherIsTyping;
  final int tick;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? errorMessage,
    String? sendError,
    bool? otherIsTyping,
    int? tick,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: errorMessage,
        sendError: sendError,
        otherIsTyping: otherIsTyping ?? this.otherIsTyping,
        tick: tick ?? this.tick,
      );

  @override
  List<Object?> get props => [messages, isLoading, errorMessage, sendError, otherIsTyping, tick];
}

/// One conversation: history over REST, live updates over Socket.IO,
/// sends through the socket with a REST fallback.
class ChatCubit extends SafeCubit<ChatState> {
  ChatCubit({
    required this.conversationId,
    required this.myUserId,
    required ChatRepository repository,
    required SocketService socket,
  })  : _repository = repository,
        _socket = socket,
        super(const ChatState()) {
    _subscription = _socket.events.listen(_onEvent);
    _socket.connect();
    load();
  }

  final String conversationId;
  final String myUserId;
  final ChatRepository _repository;
  final SocketService _socket;
  late final StreamSubscription<SocketEvent> _subscription;
  Timer? _typingTimer;
  Timer? _typingDebounce;
  int _pendingCounter = 0;

  Future<void> load() async {
    safeEmit(state.copyWith(isLoading: state.messages.isEmpty));
    try {
      final messages = await _repository.messages(conversationId);
      safeEmit(state.copyWith(messages: messages, isLoading: false));
    } on ApiException catch (error) {
      safeEmit(state.copyWith(isLoading: false, errorMessage: error.displayMessage));
    }
  }

  void _onEvent(SocketEvent event) {
    if (event.data['conversationId']?.toString() != conversationId) return;
    switch (event.name) {
      case 'new_message':
        final raw = event.data['message'];
        if (raw is! Map) return;
        final message = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
        _addConfirmed(message);
        if (message.senderId != myUserId) {
          safeEmit(state.copyWith(otherIsTyping: false));
          // Opening the thread marks it read on the server.
          _repository.messages(conversationId).ignore();
        }
      case 'typing':
        if (event.data['userId']?.toString() == myUserId) return;
        safeEmit(state.copyWith(otherIsTyping: true));
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 4), () => safeEmit(state.copyWith(otherIsTyping: false)));
      case 'typing_stop':
        safeEmit(state.copyWith(otherIsTyping: false));
      case 'messages_read':
        safeEmit(state.copyWith(
          messages: [for (final m in state.messages) m.senderId == myUserId ? m.copyWith(isRead: true) : m],
        ));
    }
  }

  void _addConfirmed(ChatMessage message) {
    if (state.messages.any((m) => m.id == message.id)) return;
    // Replace the matching optimistic message from this device, if any.
    final pendingIndex = state.messages.indexWhere(
      (m) => m.isPending && m.senderId == message.senderId && m.text == message.text,
    );
    final updated = [...state.messages];
    if (pendingIndex >= 0) {
      updated[pendingIndex] = message;
    } else {
      updated.add(message);
    }
    safeEmit(state.copyWith(messages: updated));
  }

  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) return;
    _socket.typing(conversationId, active: false);

    final pending = ChatMessage(
      id: 'local-${_pendingCounter++}',
      senderId: myUserId,
      text: text,
      createdAt: DateTime.now(),
      isPending: true,
    );
    safeEmit(state.copyWith(messages: [...state.messages, pending]));

    final ack = await _socket.sendMessage(conversationId, text);
    if (ack != null && ack['success'] == true && ack['message'] is Map) {
      _addConfirmed(ChatMessage.fromJson(Map<String, dynamic>.from(ack['message'] as Map)));
      return;
    }

    try {
      final saved = await _repository.send(conversationId, text);
      _addConfirmed(saved);
    } on ApiException catch (error) {
      safeEmit(state.copyWith(
        messages: state.messages.where((m) => m.id != pending.id).toList(),
        sendError: error.displayMessage,
        tick: state.tick + 1,
      ));
    }
  }

  void onTextChanged(String text) {
    if (text.isEmpty) {
      _socket.typing(conversationId, active: false);
      return;
    }
    if (_typingDebounce?.isActive ?? false) return;
    _socket.typing(conversationId, active: true);
    _typingDebounce = Timer(const Duration(seconds: 2), () {});
  }

  @override
  Future<void> close() async {
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    _socket.typing(conversationId, active: false);
    await _subscription.cancel();
    return super.close();
  }
}
