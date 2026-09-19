package com.afshinki.nultra;

import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

final class Protocol {
  static final UUID SERVICE = UUID.fromString("0000fe40-cc7a-482a-984a-7f2ed5b3e58f");
  static final UUID STATE = UUID.fromString("0000fe41-8e22-4541-9d4c-21edae82ed19");
  static final UUID NAME = UUID.fromString("0000fe44-8e22-4541-9d4c-21edae82ed19");
  static final UUID PASSWORD = UUID.fromString("0000fe45-8e22-4541-9d4c-21edae82ed19");

  static byte[] ascii(String text) {
    if (text.length() != 8)
      throw new IllegalArgumentException("Use exactly eight printable ASCII characters.");
    for (char c : text.toCharArray())
      if (c < 32 || c > 126)
        throw new IllegalArgumentException("Use exactly eight printable ASCII characters.");
    return text.getBytes(StandardCharsets.US_ASCII);
  }

  static final class Identity {
    final String name, firmware;

    Identity(String n, String f) {
      name = n;
      firmware = f;
    }
  }

  static Identity identity(byte[] bytes) {
    if (bytes == null) throw new IllegalArgumentException("Unreadable switch name.");
    try {
      String n =
          StandardCharsets.UTF_8
              .newDecoder()
              .decode(ByteBuffer.wrap(bytes, 0, bytes.length == 11 ? 8 : bytes.length))
              .toString()
              .trim();
      if (n.isEmpty()) throw new IllegalArgumentException("Empty switch name.");
      return new Identity(
          n,
          bytes.length == 11
              ? "v" + (bytes[8] & 255) + "." + (bytes[9] & 255) + "." + (bytes[10] & 255)
              : "");
    } catch (CharacterCodingException ex) {
      throw new IllegalArgumentException("Unreadable switch name.");
    }
  }

  static boolean power(byte[] bytes) {
    if (bytes == null || bytes.length == 0 || (bytes[0] & 255) > 1)
      throw new IllegalArgumentException("Invalid power readback.");
    return bytes[0] == 1;
  }

  static int[] advertisement(String name) {
    if (name == null || name.length() < 10 || !name.startsWith("Nultra")) return null;
    if (name.charAt(6) != '0' && name.charAt(6) != '1') return null;
    int battery = 0;
    for (int i = 7; i < 10; i++) {
      char c = name.charAt(i);
      if (c < '0' || c > '9') return null;
      battery = battery * 10 + c - '0';
    }
    return battery <= 100 ? new int[] {name.charAt(6) - '0', battery} : null;
  }

  static int bars(int rssi) {
    return rssi >= -60 ? 3 : rssi >= -80 ? 2 : 1;
  }
}
