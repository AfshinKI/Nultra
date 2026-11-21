package com.afshinki.nultra;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.Build;

final class BatteryNotifications {
  static final String CHANNEL = "switch-battery";
  final Context context;
  final SharedPreferences prefs;
  final NotificationManager manager;

  BatteryNotifications(Context context) {
    this.context = context;
    prefs = context.getSharedPreferences("battery-alerts", 0);
    manager = context.getSystemService(NotificationManager.class);
    manager.createNotificationChannel(new NotificationChannel(CHANNEL, "Switch battery", NotificationManager.IMPORTANCE_DEFAULT));
  }

  boolean enabled() { return prefs.getBoolean("enabled", false); }
  int threshold() { return Math.max(1, Math.min(50, prefs.getInt("threshold", 5))); }
  void save(boolean enabled, int threshold) {
    prefs.edit().putBoolean("enabled", enabled).putInt("threshold", Math.max(1, Math.min(50, threshold))).apply();
  }
  boolean permitted() {
    return (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
        && manager.areNotificationsEnabled()
        && manager.getNotificationChannel(CHANNEL).getImportance() != NotificationManager.IMPORTANCE_NONE;
  }

  void observe(BleStore.Device device) {
    if (device.name.isEmpty() || device.battery < 0 || device.battery > 100) return;
    String key = device.address;
    BatteryAlertPolicy policy = new BatteryAlertPolicy(prefs.getBoolean(key + ":alerted", false), prefs.getInt(key + ":recovery", 15));
    boolean wasAlerted = policy.alerted;
    boolean alert = policy.observe(device.battery, threshold());
    if (alert) {
      if (!enabled() || !permitted()) return;
      PendingIntent open = PendingIntent.getActivity(context, 0, new Intent(context, MainActivity.class), PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
      try {
        manager.notify(key, 1, new Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.notification_bulb)
            .setContentTitle(device.name + " battery is low")
            .setContentText("Battery is at " + device.battery + "%. Replace or recharge the switch battery.")
            .setContentIntent(open).setAutoCancel(true).build());
      } catch (SecurityException e) { return; }
    }
    if (wasAlerted != policy.alerted) {
      prefs.edit().putBoolean(key + ":alerted", policy.alerted).putInt(key + ":recovery", policy.recoveryLevel).apply();
    }
  }
}
