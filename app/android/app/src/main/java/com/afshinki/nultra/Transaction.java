package com.afshinki.nultra;

/** Pure state machine: no callback can issue work after disconnect begins. */
final class Transaction {
  enum Kind {
    IDENTIFY,
    POWER,
    RENAME
  }

  enum Stage {
    CONNECT,
    DISCOVER,
    AUTHENTICATE,
    WRITE,
    READ,
    DISCONNECT,
    CLOSED
  }

  enum Effect {
    NONE,
    DISCOVER,
    AUTHENTICATE,
    WRITE,
    READ,
    DISCONNECT
  }

  final Kind kind;
  final boolean target;
  final String rename;
  Stage stage = Stage.CONNECT;
  String error;
  Protocol.Identity identity;
  Boolean power;

  Transaction(Kind k, boolean t, String n) {
    kind = k;
    target = t;
    rename = n;
    if (k == Kind.RENAME) Protocol.ascii(n);
  }

  Effect connected() {
    if (stage != Stage.CONNECT) return Effect.NONE;
    stage = Stage.DISCOVER;
    return Effect.DISCOVER;
  }

  Effect discovered() {
    if (stage != Stage.DISCOVER) return Effect.NONE;
    stage = Stage.AUTHENTICATE;
    return Effect.AUTHENTICATE;
  }

  Effect written() {
    if (stage == Stage.AUTHENTICATE) {
      stage = kind == Kind.IDENTIFY ? Stage.READ : Stage.WRITE;
      return kind == Kind.IDENTIFY ? Effect.READ : Effect.WRITE;
    }
    if (stage == Stage.WRITE) {
      stage = Stage.READ;
      return Effect.READ;
    }
    return Effect.NONE;
  }

  Effect read(byte[] bytes) {
    if (stage != Stage.READ) return Effect.NONE;
    try {
      if (kind == Kind.POWER) {
        power = Protocol.power(bytes);
        if (power != target) throw new IllegalArgumentException("Power change was not confirmed.");
      } else {
        identity = Protocol.identity(bytes);
        if (kind == Kind.RENAME && !identity.name.equals(rename.trim()))
          throw new IllegalArgumentException("Rename was not confirmed.");
      }
      stage = Stage.DISCONNECT;
      return Effect.DISCONNECT;
    } catch (IllegalArgumentException e) {
      return fail(e.getMessage());
    }
  }

  Effect fail(String reason) {
    if (stage == Stage.CLOSED || stage == Stage.DISCONNECT) return Effect.NONE;
    error = reason;
    stage = Stage.DISCONNECT;
    return Effect.DISCONNECT;
  }

  void disconnected() {
    if (stage != Stage.DISCONNECT && stage != Stage.CLOSED)
      error = "Switch disconnected before confirmation.";
    stage = Stage.CLOSED;
  }
}
