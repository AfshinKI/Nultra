package com.afshinki.nultra;

import android.app.*;
import android.content.*;
import android.os.*;
import android.widget.Toast;

/** Only explicit, user-tapped widget PendingIntents can start this private service. */
public final class CommandService extends Service {
  final Handler handler = new Handler(Looper.getMainLooper());
  boolean running;
  final Runnable deadline =
      () -> {
        BleStore.get(this).cancelBackground();
        finish("Action timed out. Some server commands may already be queued.");
      };

  @Override
  public IBinder onBind(Intent intent) {
    return null;
  }

  @Override
  public int onStartCommand(Intent intent, int flags, int startId) {
    NotificationManager manager = getSystemService(NotificationManager.class);
    manager.createNotificationChannel(
        new NotificationChannel(
            "switch-actions", "Switch actions", NotificationManager.IMPORTANCE_LOW));
    startForeground(
        17,
        new Notification.Builder(this, "switch-actions")
            .setSmallIcon(R.drawable.notification_bulb)
            .setContentTitle("Nultra")
            .setContentText("Changing switches…")
            .setOngoing(true)
            .build());
    if (running) return START_NOT_STICKY;
    String address = intent == null ? null : intent.getStringExtra("target");
    if (address == null || !(address.equals("*") || ServerClient.validAddress(address))) {
      finish("Choose a saved switch in the Nultra widget.");
      return START_NOT_STICKY;
    }
    running = true;
    handler.postDelayed(deadline, 24000);
    if (!BleStore.get(this)
        .backgroundPower(address, intent.getBooleanExtra("on", false), this::finish))
      finish("Open Nultra to save switches, leave demo mode, or wait for the current action.");
    return START_NOT_STICKY;
  }

  void finish(String result) {
    handler.removeCallbacks(deadline);
    running = false;
    SwitchWidget.status(this, result);
    Toast.makeText(this, result, Toast.LENGTH_LONG).show();
    stopForeground(STOP_FOREGROUND_REMOVE);
    stopSelf();
  }

  @Override
  public void onDestroy() {
    handler.removeCallbacks(deadline);
    if (running) BleStore.get(this).cancelBackground();
    super.onDestroy();
  }
}
