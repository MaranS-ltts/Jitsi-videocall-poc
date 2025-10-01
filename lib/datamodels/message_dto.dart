// lib/message_dto.dart

class MessageDto {
  // CORRECTED ORDER: receiver is now first.
  final String receiver;
  final String sender;
  final String message;
  final String roomName;

  MessageDto({
    required this.receiver,
    required this.sender,
    required this.message,
    required this.roomName,
  });

  // Creates a MessageDto object from a Map (JSON from the server)
  factory MessageDto.fromJson(Map<String, dynamic> json) {
    return MessageDto(
      receiver: json['receiver'] ?? 'Unknown',
      sender: json['sender'] ?? 'Unknown',
      message: json['message'] ?? '',
      roomName: json['roomName'] ?? '',
    );
  }

  // Converts this DTO to a Map to be sent as JSON
  // The keys MUST EXACTLY MATCH your C# record property names.
  Map<String, dynamic> toJson() {
    return {
      'receiver': receiver,
      'sender': sender,
      'message': message,
      'roomName': roomName,
    };
  }
}