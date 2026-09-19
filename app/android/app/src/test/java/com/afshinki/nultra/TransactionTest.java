package com.afshinki.nultra;

import static org.junit.Assert.*;

import java.nio.charset.StandardCharsets;
import org.junit.Test;

public class TransactionTest {
  Transaction authenticated(Transaction.Kind k) {
    Transaction t = new Transaction(k, true, "NEWNAME1");
    assertEquals(Transaction.Effect.DISCOVER, t.connected());
    assertEquals(Transaction.Effect.AUTHENTICATE, t.discovered());
    return t;
  }

  @Test
  public void identifyReadsOnlyNameThenDisconnects() {
    Transaction t = authenticated(Transaction.Kind.IDENTIFY);
    assertEquals(Transaction.Effect.READ, t.written());
    assertEquals(
        Transaction.Effect.DISCONNECT, t.read("BEDROOM1".getBytes(StandardCharsets.US_ASCII)));
    assertEquals("BEDROOM1", t.identity.name);
    assertEquals(Transaction.Stage.DISCONNECT, t.stage);
    t.disconnected();
    assertNull(t.error);
  }

  @Test
  public void powerWritesAndVerifies() {
    Transaction t = authenticated(Transaction.Kind.POWER);
    assertEquals(Transaction.Effect.WRITE, t.written());
    assertEquals(Transaction.Effect.READ, t.written());
    assertEquals(Transaction.Effect.DISCONNECT, t.read(new byte[] {1}));
    assertNull(t.error);
  }

  @Test
  public void mismatchedPowerFails() {
    Transaction t = authenticated(Transaction.Kind.POWER);
    t.written();
    t.written();
    t.read(new byte[] {0});
    assertNotNull(t.error);
    assertEquals(Transaction.Stage.DISCONNECT, t.stage);
  }

  @Test
  public void renameVerifiesExactName() {
    Transaction t = authenticated(Transaction.Kind.RENAME);
    t.written();
    t.written();
    t.read("NEWNAME1".getBytes(StandardCharsets.US_ASCII));
    assertNull(t.error);
  }

  @Test
  public void wrongRenameFails() {
    Transaction t = authenticated(Transaction.Kind.RENAME);
    t.written();
    t.written();
    t.read("OLDNAME1".getBytes(StandardCharsets.US_ASCII));
    assertNotNull(t.error);
  }

  @Test
  public void timeoutPreventsLateWritesAtEveryStage() {
    for (int stage = 0; stage < 5; stage++) {
      Transaction t = new Transaction(Transaction.Kind.POWER, true, null);
      if (stage > 0) t.connected();
      if (stage > 1) t.discovered();
      if (stage > 2) t.written();
      if (stage > 3) t.written();
      assertEquals(Transaction.Effect.DISCONNECT, t.fail("timeout"));
      assertEquals(Transaction.Effect.NONE, t.connected());
      assertEquals(Transaction.Effect.NONE, t.discovered());
      assertEquals(Transaction.Effect.NONE, t.written());
      assertEquals(Transaction.Effect.NONE, t.read(new byte[] {1}));
      assertEquals("timeout", t.error);
    }
  }

  @Test
  public void earlyDisconnectIsFailure() {
    Transaction t = authenticated(Transaction.Kind.POWER);
    t.disconnected();
    assertNotNull(t.error);
    assertEquals(Transaction.Effect.NONE, t.written());
  }

  @Test
  public void unsolicitedReadsDoNotConfirm() {
    Transaction t = authenticated(Transaction.Kind.POWER);
    assertEquals(Transaction.Effect.NONE, t.read(new byte[] {1}));
    assertNull(t.power);
  }

  @Test
  public void terminalFailureIsStable() {
    Transaction t = authenticated(Transaction.Kind.POWER);
    t.fail("first");
    t.fail("second");
    t.disconnected();
    t.fail("third");
    assertEquals("first", t.error);
  }
}
