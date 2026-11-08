import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 비밀번호를 평문 대신 소금과 PBKDF2-HMAC-SHA256 해시로 바꿉니다.
class PasswordHasher {
  const PasswordHasher._();

  static const int defaultIterations = 10000;
  static const int _saltLength = 16;
  static const int _keyLength = 32;

  static String generateSalt() {
    final Random random = Random.secure();
    final Uint8List bytes = Uint8List(_saltLength);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = random.nextInt(256);
    }
    return base64UrlEncode(bytes);
  }

  static String hash({
    required String password,
    required String salt,
    int iterations = defaultIterations,
  }) {
    final Uint8List key = deriveKey(
      password: utf8.encode(password),
      salt: base64Url.decode(salt),
      iterations: iterations,
    );
    return base64UrlEncode(key);
  }

  static bool matches({
    required String password,
    required String salt,
    required String expectedHash,
    int iterations = defaultIterations,
  }) {
    final String actual = hash(
      password: password,
      salt: salt,
      iterations: iterations,
    );
    if (actual.length != expectedHash.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < actual.length; index++) {
      difference |= actual.codeUnitAt(index) ^ expectedHash.codeUnitAt(index);
    }
    return difference == 0;
  }

  /// RFC 8018 PBKDF2입니다. 테스트 벡터로 구현을 확인할 수 있게 열어 둡니다.
  static Uint8List deriveKey({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    int keyLength = _keyLength,
  }) {
    if (iterations < 1) {
      throw ArgumentError.value(iterations, 'iterations', '1 이상이어야 합니다.');
    }
    if (keyLength < 1) {
      throw ArgumentError.value(keyLength, 'keyLength', '1 이상이어야 합니다.');
    }

    final Hmac prf = Hmac(sha256, password);
    const int hashLength = 32;
    final int blockCount = (keyLength + hashLength - 1) ~/ hashLength;
    final BytesBuilder builder = BytesBuilder(copy: false);

    for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      builder.add(
        _block(
          prf: prf,
          salt: salt,
          iterations: iterations,
          blockIndex: blockIndex,
        ),
      );
    }

    final Uint8List derived = builder.toBytes();
    return Uint8List.sublistView(derived, 0, keyLength);
  }

  static List<int> _block({
    required Hmac prf,
    required List<int> salt,
    required int iterations,
    required int blockIndex,
  }) {
    final List<int> seed = <int>[
      ...salt,
      (blockIndex >> 24) & 0xff,
      (blockIndex >> 16) & 0xff,
      (blockIndex >> 8) & 0xff,
      blockIndex & 0xff,
    ];
    List<int> block = prf.convert(seed).bytes;
    final List<int> mixed = List<int>.from(block);

    for (var round = 1; round < iterations; round++) {
      block = prf.convert(block).bytes;
      for (var index = 0; index < mixed.length; index++) {
        mixed[index] ^= block[index];
      }
    }
    return mixed;
  }
}
