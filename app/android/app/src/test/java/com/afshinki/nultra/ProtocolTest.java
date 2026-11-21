package com.afshinki.nultra;

import static org.junit.Assert.*;

import java.nio.charset.StandardCharsets;
import org.junit.Test;

public class ProtocolTest {
  @Test
  public void validatesAllBroadcastValues() {
    for (int state = 0; state < 2; state++)
      for (int battery = 0; battery <= 100; battery++)
        assertArrayEquals(
            new int[] {state, battery},
            Protocol.advertisement(
                String.format(java.util.Locale.US, "Nultra%d%03d", state, battery)));
  }

  @Test
  public void rejectsMalformedAdvertisements() {
    for (String s :
        new String[] {
          "Nultra2100", "Nultra1101", "Nultra1abc", "Nultra100", "Other1100", "Nultra1١٠٠"
        }) assertNull(Protocol.advertisement(s));
    assertNull(Protocol.advertisement(null));
  }

  @Test
  public void checksAsciiBytes() {
    assertEquals(8, Protocol.ascii("TESTONLY").length);
    for (String s : new String[] {"short", "123456789", "1234567é", "1234567\n"})
      assertThrows(IllegalArgumentException.class, () -> Protocol.ascii(s));
  }

  @Test
  public void readsNameAndUnsignedFirmware() {
    byte[] b = {'T', 'E', 'S', 'T', 'O', 'N', 'L', 'Y', 1, 2, (byte) 255};
    Protocol.Identity i = Protocol.identity(b);
    assertEquals("TESTONLY", i.name);
    assertEquals("v1.2.255", i.firmware);
  }

  @Test
  public void rejectsInvalidNames() {
    assertThrows(IllegalArgumentException.class, () -> Protocol.identity(new byte[] {0, 0}));
    assertThrows(IllegalArgumentException.class, () -> Protocol.identity(new byte[] {(byte) 255}));
  }

  @Test
  public void acceptsTrimmedNames() {
    assertEquals("LIGHT", Protocol.identity("LIGHT\0\0\0".getBytes(StandardCharsets.UTF_8)).name);
  }

  @Test
  public void validatesPowerBytes() {
    for (int b = 0; b < 256; b++) {
      final byte[] bytes = {(byte) b};
      if (b < 2) assertEquals(b == 1, Protocol.power(bytes));
      else assertThrows(IllegalArgumentException.class, () -> Protocol.power(bytes));
    }
    assertThrows(IllegalArgumentException.class, () -> Protocol.power(new byte[0]));
  }

  @Test
  public void matchesFancySignalThresholds() {
    assertEquals(3, Protocol.bars(-60));
    assertEquals(2, Protocol.bars(-61));
    assertEquals(2, Protocol.bars(-80));
    assertEquals(1, Protocol.bars(-81));
  }
}
