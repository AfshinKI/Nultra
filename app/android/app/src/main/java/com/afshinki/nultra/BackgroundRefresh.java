package com.afshinki.nultra;

import android.app.job.*;
import android.content.*;
import android.os.*;
import java.util.*;
import java.util.concurrent.*;

/** OS-scheduled, read-only server polling. Never scans or opens a BLE connection. */
public final class BackgroundRefresh extends JobService {
  static final int JOB_ID = 1001;
  static SharedPreferences prefs(Context c) { return c.getSharedPreferences("background-refresh", 0); }
  static boolean enabled(Context c) { return prefs(c).getBoolean("enabled", true); }
  static int minutes(Context c) { int m = prefs(c).getInt("minutes", 30); return m == 15 || m == 60 ? m : 30; }
  static void schedule(Context c) {
    JobScheduler scheduler = c.getSystemService(JobScheduler.class);
    if (!enabled(c) || !new ServerSettings(c).enabled()) { scheduler.cancel(JOB_ID); return; }
    long interval = minutes(c) * 60000L;
    JobInfo existing = scheduler.getPendingJob(JOB_ID);
    if (existing != null && existing.getIntervalMillis() == interval) return;
    scheduler.schedule(new JobInfo.Builder(JOB_ID, new ComponentName(c, BackgroundRefresh.class))
        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true).setPeriodic(interval).build());
  }
  final Handler main = new Handler(Looper.getMainLooper());
  final ExecutorService executor = Executors.newSingleThreadExecutor();
  Future<?> future;
  ServerClient client;
  int generation;
  @Override public boolean onStartJob(JobParameters params) {
    BleStore store = BleStore.get(this);
    if (!enabled(this) || !store.server.enabled() || store.demo || store.anyBusy()) return false;
    final Map<String, ?> configuration = new HashMap<>(store.server.prefs.getAll());
    final int token = ++generation;
    final ServerClient request = new ServerClient(store.server.url(), store.credentials);
    client = request;
    future = executor.submit(() -> {
      List<ServerClient.Row> rows = null;
      try { rows = request.devices(); } catch (Exception ignored) { }
      final List<ServerClient.Row> result = rows;
      main.post(() -> {
        if (token != generation) return;
        client = null; future = null;
        boolean valid = enabled(this) && !store.demo && !store.anyBusy() && configuration.equals(store.server.prefs.getAll());
        if (valid && result != null) {
          store.applyBackgroundRows(result);
          prefs(this).edit().putLong("lastSuccess", System.currentTimeMillis()).apply();
        }
        jobFinished(params, false);
      });
    });
    return true;
  }
  @Override public boolean onStopJob(JobParameters params) { cancel(); return false; }
  void cancel() {
    generation++;
    if (client != null) client.cancel();
    if (future != null) future.cancel(true);
    client = null; future = null;
  }
  @Override public void onDestroy() { cancel(); executor.shutdownNow(); super.onDestroy(); }
}
