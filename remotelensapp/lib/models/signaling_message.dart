class SignalingMessage {
  final String type;
  final String? roomId;
  final String? senderId;
  final String? role;
  final Map<String, dynamic>? payload;

  const SignalingMessage({
    required this.type,
    this.roomId,
    this.senderId,
    this.role,
    this.payload,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'roomId': roomId,
    'senderId': senderId,
    'payload': payload,
    'role': role,
  };

  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    return SignalingMessage(
      type: json['type']?.toString() ?? '',
      roomId: json['roomId']?.toString(),
      senderId: json['senderId']?.toString(),
      role: json['role']?.toString(),
      payload: json['payload'] is Map
          ? (json['payload'] as Map).cast<String, dynamic>()
          : null,
    );
  }
}
