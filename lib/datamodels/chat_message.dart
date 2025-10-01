class ChatMessage {
  final String sender;
  final String recipient;
  final String message;
  final bool isMe;

  ChatMessage({
    required this.sender,
    required this.recipient,
    required this.message,
    required this.isMe,
  });
}