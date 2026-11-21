package com.afshinki.nultra;

import static org.junit.Assert.*;
import android.app.*;
import android.app.job.*;
import android.content.*;
import android.os.*;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.Test;

public class ScenesAndRefreshTest {
  @Test public void scheduledRefreshUpdatesWidgetsWithoutActivityAndCancelsWhenDisabled() throws Exception {
    assertTrue(Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk"));
    Instrumentation test = InstrumentationRegistry.getInstrumentation();
    Context context = test.getTargetContext();
    JobScheduler scheduler = context.getSystemService(JobScheduler.class);
    Instrumentation.ActivityMonitor monitor = test.addMonitor(MainActivity.class.getName(), null, false);
    try (ServerSocket socket = new ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))) {
      socket.setSoTimeout(15000);
      CountDownLatch received = new CountDownLatch(1);
      Thread fixture = new Thread(() -> {
        try (Socket client = socket.accept()) {
          BufferedReader reader = new BufferedReader(new InputStreamReader(client.getInputStream()));
          assertEquals("GET /devices HTTP/1.1", reader.readLine());
          while (!reader.readLine().isEmpty()) { }
          String body = "[{\"address\":\"AA:BB:CC:DD:EE:77\",\"display_name\":\"TESTLAMP\",\"seen_recently\":1,\"switch_state\":1,\"battery\":4}]";
          client.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Length: " + body.length() + "\r\nConnection: close\r\n\r\n" + body).getBytes(java.nio.charset.StandardCharsets.UTF_8));
          received.countDown();
        } catch (Exception e) { throw new RuntimeException(e); }
      });
      fixture.setDaemon(true); fixture.start();
      test.runOnMainSync(() -> {
        BleStore store = BleStore.get(context); store.pause(); store.cancelAll("Fixture"); store.demo = false; store.devices.clear();
        BleStore.Device d = new BleStore.Device("AA:BB:CC:DD:EE:77"); d.name = "TESTLAMP"; store.devices.put(d.address, d); store.save();
        Scenes.Scene scene = new Scenes.Scene(UUID.randomUUID().toString(), "Evening", Arrays.asList(d.address));
        store.saveScene(scene);
        assertEquals(1, store.targets(scene.target()).size());
        assertTrue(store.targets("scene:missing").isEmpty());
        store.server.save(true, "http://127.0.0.1:" + socket.getLocalPort());
        BackgroundRefresh.prefs(context).edit().clear().commit();
        assertTrue(BackgroundRefresh.enabled(context));
        BackgroundRefresh.schedule(context);
        assertEquals(30 * 60000L, scheduler.getPendingJob(BackgroundRefresh.JOB_ID).getIntervalMillis());
      });
      try (ParcelFileDescriptor descriptor = test.getUiAutomation().executeShellCommand("cmd jobscheduler run -f " + context.getPackageName() + " 1001");
           InputStream input = new FileInputStream(descriptor.getFileDescriptor())) { while (input.read() != -1) { } }
      assertTrue("Background job did not fetch server", received.await(15, TimeUnit.SECONDS));
      long deadline = SystemClock.elapsedRealtime() + 10000;
      while (BackgroundRefresh.prefs(context).getLong("lastSuccess", 0) == 0 && SystemClock.elapsedRealtime() < deadline) Thread.sleep(100);
      assertTrue(BackgroundRefresh.prefs(context).getLong("lastSuccess", 0) > 0);
      assertTrue(WidgetReadings.state(context, "*").startsWith("On ·"));
      assertEquals(0, monitor.getHits());
      test.runOnMainSync(() -> {
        BleStore store = BleStore.get(context);
        assertEquals(4, store.visible().get(0).battery);
        assertTrue(store.sessions.isEmpty()); assertFalse(store.scanning);
        BackgroundRefresh.prefs(context).edit().putBoolean("enabled", false).commit();
        BackgroundRefresh.schedule(context); assertNull(scheduler.getPendingJob(BackgroundRefresh.JOB_ID));
      });
    } finally {
      test.removeMonitor(monitor);
      test.runOnMainSync(() -> {
        BleStore store = BleStore.get(context); store.server.save(false, ""); store.devices.clear(); store.save();
        Scenes.save(context, Collections.emptyList());
        scheduler.cancel(BackgroundRefresh.JOB_ID);
        BackgroundRefresh.prefs(context).edit().clear().commit();
        context.getSharedPreferences("widget-readings", 0).edit().clear().commit();
      });
    }
  }
}
