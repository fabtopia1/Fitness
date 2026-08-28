import 'dart:math';
import 'dart:typed_data';

/// Generates client-side identifiers.
///
/// UUID v7 is used deliberately: it is time-ordered, so records sort naturally
/// by creation without a separate index, and it lets the client own the
/// document id. That ownership is what makes an offline write idempotent —
/// replaying it is a `set(merge: true)` to the same path, not a second insert
/// (docs/02 §7.1).
class IdGenerator {
  const IdGenerator();

  static final Random _random = Random.secure();

  String v7([DateTime? at]) {
    final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final bytes = Uint8List(16);

    // 48-bit big-endian millisecond timestamp.
    bytes[0] = (ms >> 40) & 0xFF;
    bytes[1] = (ms >> 32) & 0xFF;
    bytes[2] = (ms >> 24) & 0xFF;
    bytes[3] = (ms >> 16) & 0xFF;
    bytes[4] = (ms >> 8) & 0xFF;
    bytes[5] = ms & 0xFF;

    for (var i = 6; i < 16; i++) {
      bytes[i] = _random.nextInt(256);
    }

    // Version 7, RFC 4122 variant.
    bytes[6] = (bytes[6] & 0x0F) | 0x70;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    final hex =
        [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
