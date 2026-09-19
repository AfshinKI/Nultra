package com.afshinki.nultra;

import static org.junit.Assert.*;

import android.app.*;
import android.content.*;
import android.os.*;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.Test;

/** Emulator-only acceptance: uses a loopback server and fictional saved switches. */
@SuppressWarnings("deprecation")
public class BackgroundControlTest {
  Instrumentation getInstrumentation() {
    return InstrumentationRegistry.getInstrumentation();
  }

  @Test
  public void testWidgetActionDoesNotLaunchActivityAndUsesSavedServer() throws Exception {
    assertTrue(
        "Do not run fixture test on a real phone",
        Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk"));
    Context context = getInstrumentation().getTargetContext();
    try (ServerSocket socket = new ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))) {
      socket.setSoTimeout(15000);
      List<String> requests = Collections.synchronizedList(new ArrayList<>());
      CountDownLatch posted = new CountDownLatch(1);
      Thread fixture =
          new Thread(
              () -> {
                try {
                  for (int i = 0; i < 2; i++)
                    try (Socket client = socket.accept()) {
                      BufferedReader reader =
                          new BufferedReader(new InputStreamReader(client.getInputStream()));
                      String first = reader.readLine();
                      requests.add(first);
                      while (!reader.readLine().isEmpty()) {}
                      String body =
                          i == 0
                              ? "[{\"address\":\"AA:BB:CC:DD:EE:01\",\"display_name\":\"BEDROOM1\",\"seen_recently\":1,\"switch_state\":1,\"battery\":80}]"
                              : "{\"status\":\"OK\"}";
                      byte[] bytes = body.getBytes(java.nio.charset.StandardCharsets.UTF_8);
                      client
                          .getOutputStream()
                          .write(
                              ("HTTP/1.1 200 OK\r\nContent-Length: "
                                      + bytes.length
                                      + "\r\nConnection: close\r\n\r\n"
                                      + body)
                                  .getBytes(java.nio.charset.StandardCharsets.UTF_8));
                      if (i == 1) posted.countDown();
                    }
                } catch (Exception ignored) {
                }
              });
      fixture.setDaemon(true);
      fixture.start();
      Instrumentation.ActivityMonitor monitor =
          getInstrumentation().addMonitor(MainActivity.class.getName(), null, false);
      getInstrumentation()
          .runOnMainSync(
              () -> {
                BleStore store = BleStore.get(context);
                store.pause();
                store.cancelAll("Test setup");
                store.demo = false;
                store.devices.clear();
                BleStore.Device device = new BleStore.Device("AA:BB:CC:DD:EE:01");
                device.name = "BEDROOM1";
                store.devices.put(device.address, device);
                store.save();
                store.server.save(true, "http://127.0.0.1:" + socket.getLocalPort());
                assertTrue(new ServerSettings(context).enabled());
                Intent intent =
                    new Intent(context, CommandService.class)
                        .putExtra("target", "*")
                        .putExtra("on", false);
                try {
                  PendingIntent.getForegroundService(
                          context,
                          999,
                          intent,
                          PendingIntent.FLAG_CANCEL_CURRENT | PendingIntent.FLAG_IMMUTABLE)
                      .send();
                } catch (PendingIntent.CanceledException e) {
                  throw new AssertionError(e);
                }
              });
      boolean received = posted.await(15, TimeUnit.SECONDS);
      String[] diagnostic = {""};
      getInstrumentation().runOnMainSync(() -> diagnostic[0] = BleStore.get(context).message);
      assertTrue(
          "Server never received power request: " + requests + " / " + diagnostic[0], received);
      long end = SystemClock.elapsedRealtime() + 5000;
      boolean[] finished = {false};
      do {
        getInstrumentation()
            .runOnMainSync(() -> finished[0] = !BleStore.get(context).backgroundCommand);
        if (!finished[0]) Thread.sleep(100);
      } while (!finished[0] && SystemClock.elapsedRealtime() < end);
      assertTrue("Action did not finish", finished[0]);
      assertEquals(0, monitor.getHits());
      assertEquals(
          Arrays.asList("GET /devices HTTP/1.1", "POST /toggle/AA:BB:CC:DD:EE:01/0 HTTP/1.1"),
          requests);
      getInstrumentation()
          .runOnMainSync(
              () -> {
                BleStore store = BleStore.get(context);
                assertTrue(store.message.contains("queued by server"));
                assertNull(
                    "Queue acknowledgement must not become confirmed power",
                    store.visible().get(0).power);
                assertFalse(store.anyBusy());
                assertTrue(store.sessions.isEmpty());
                store.server.save(false, "");
                store.serverChanged();
                store.devices.clear();
                store.save();
              });
      getInstrumentation().removeMonitor(monitor);
    }
  }

  @Test
  public void cancellationPreventsLateServerPost() throws Exception {
    assertTrue(Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk"));
    Context context = getInstrumentation().getTargetContext();
    try (ServerSocket socket = new ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))) {
      socket.setSoTimeout(2000);
      CountDownLatch get = new CountDownLatch(1), release = new CountDownLatch(1);
      List<String> requests = Collections.synchronizedList(new ArrayList<>());
      Thread fixture =
          new Thread(
              () -> {
                try (Socket client = socket.accept()) {
                  BufferedReader reader =
                      new BufferedReader(new InputStreamReader(client.getInputStream()));
                  requests.add(reader.readLine());
                  while (!reader.readLine().isEmpty()) {}
                  get.countDown();
                  release.await(5, TimeUnit.SECONDS);
                  String body =
                      "[{\"address\":\"AA:BB:CC:DD:EE:01\",\"display_name\":\"BEDROOM1\",\"seen_recently\":1}]";
                  client
                      .getOutputStream()
                      .write(
                          ("HTTP/1.1 200 OK\r\nContent-Length: "
                                  + body.length()
                                  + "\r\nConnection: close\r\n\r\n"
                                  + body)
                              .getBytes(java.nio.charset.StandardCharsets.UTF_8));
                } catch (Exception ignored) {
                }
                try (Socket late = socket.accept()) {
                  requests.add("UNEXPECTED POST");
                } catch (Exception expected) {
                }
              });
      fixture.setDaemon(true);
      fixture.start();
      getInstrumentation()
          .runOnMainSync(
              () -> {
                BleStore store = BleStore.get(context);
                store.pause();
                store.cancelBackground();
                store.cancelAll("Test setup");
                store.demo = false;
                store.devices.clear();
                BleStore.Device device = new BleStore.Device("AA:BB:CC:DD:EE:01");
                device.name = "BEDROOM1";
                store.devices.put(device.address, device);
                store.server.save(true, "http://127.0.0.1:" + socket.getLocalPort());
                assertTrue(
                    store.backgroundPower(
                        "*", false, result -> fail("Cancelled action must not complete")));
              });
      assertTrue(get.await(5, TimeUnit.SECONDS));
      getInstrumentation()
          .runOnMainSync(
              () -> {
                BleStore store = BleStore.get(context);
                store.cancelBackground();
                assertFalse(store.backgroundCommand);
                assertFalse(store.anyBusy());
              });
      release.countDown();
      fixture.join(3500);
      assertEquals(Collections.singletonList("GET /devices HTTP/1.1"), requests);
      getInstrumentation()
          .runOnMainSync(
              () -> {
                BleStore store = BleStore.get(context);
                store.server.save(false, "");
                store.serverChanged();
                store.devices.clear();
                store.save();
              });
    }
  }
}
