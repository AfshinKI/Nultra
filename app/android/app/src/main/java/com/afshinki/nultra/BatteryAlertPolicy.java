package com.afshinki.nultra;

final class BatteryAlertPolicy {
  boolean alerted;
  int recoveryLevel;

  BatteryAlertPolicy(boolean alerted, int recoveryLevel) {
    this.alerted = alerted;
    this.recoveryLevel = recoveryLevel;
  }

  boolean observe(int battery, int threshold) {
    if (battery < 0 || battery > 100) return false;
    threshold = Math.max(1, Math.min(50, threshold));
    if (alerted) {
      if (battery >= recoveryLevel) alerted = false;
      return false;
    }
    if (battery > threshold) return false;
    alerted = true;
    recoveryLevel = threshold + 10;
    return true;
  }
}
