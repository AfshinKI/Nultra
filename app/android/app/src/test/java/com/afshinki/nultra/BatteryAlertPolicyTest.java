package com.afshinki.nultra;

import org.junit.Test;
import static org.junit.Assert.*;

public class BatteryAlertPolicyTest {
  @Test public void thresholdAndJitterDoNotRepeat() {
    BatteryAlertPolicy p = new BatteryAlertPolicy(false, 15);
    assertFalse(p.observe(6, 5));
    assertTrue(p.observe(5, 5));
    for (int b : new int[] {4, 7, 3, 8, 5, 0, 14}) assertFalse(p.observe(b, 5));
    assertFalse(p.observe(15, 5));
    assertTrue(p.observe(4, 5));
  }
  @Test public void restoreAndThresholdChanges() {
    BatteryAlertPolicy p = new BatteryAlertPolicy(false, 15);
    assertTrue(p.observe(5, 5));
    p = new BatteryAlertPolicy(p.alerted, p.recoveryLevel);
    assertFalse(p.observe(5, 1));
    assertFalse(p.observe(7, 50));
    assertFalse(p.observe(15, 50));
    assertTrue(p.observe(14, 50));
  }
  @Test public void invalidReadingsDoNotRearm() {
    BatteryAlertPolicy p = new BatteryAlertPolicy(false, 15);
    assertFalse(p.observe(-1, 5));
    assertFalse(p.observe(101, 5));
    assertTrue(p.observe(0, 5));
    assertFalse(p.observe(101, 5));
    assertTrue(p.alerted);
  }
}
