class AppConfig {
  static const bool useEmulator = false; // true = máy ảo, false = máy thật

  static String get signalingUrl {
    if (useEmulator) {
      return "ws://10.0.2.2:8080"; // emulator
    }
    return "ws://192.168.1.48:8080"; // máy thật
    // return "ws://192.168.1.6:8080";
    //192.168.1.19
  }
}
