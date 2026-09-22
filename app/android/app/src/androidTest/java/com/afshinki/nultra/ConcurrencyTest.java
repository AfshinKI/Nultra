package com.afshinki.nultra;

import static org.junit.Assert.*;
import android.content.Context;
import android.os.Build;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import org.junit.Test;

/** Seven fictional devices and a blocked loopback server exercise the shared slot bound. */
public class ConcurrencyTest {
  @Test public void sixRemoteRequestsRunAndSeventhWaitsForAFreeSlot() throws Exception {
    assertTrue(Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk"));
    var instrumentation = InstrumentationRegistry.getInstrumentation();
    Context context = instrumentation.getTargetContext();
    CountDownLatch firstSix = new CountDownLatch(6), release = new CountDownLatch(1);
    CountDownLatch posted = new CountDownLatch(7);
    ExecutorService clients = Executors.newCachedThreadPool();
    List<String> posts = Collections.synchronizedList(new ArrayList<>());
    StringBuilder rows = new StringBuilder("[");
    for (int i = 0; i < 7; i++) {
      if (i > 0) rows.append(',');
      rows.append(String.format(Locale.US,
          "{\"address\":\"AA:BB:CC:DD:EE:%02d\",\"display_name\":\"TEST%04d\",\"seen_recently\":1,\"switch_state\":1}", i, i));
    }
    rows.append(']');
    try (ServerSocket server = new ServerSocket(0, 20, InetAddress.getByName("127.0.0.1"))) {
      server.setSoTimeout(20000);
      Thread accept = new Thread(() -> {
        try {
          for (int i = 0; i < 14; i++) {
            Socket socket = server.accept();
            clients.submit(() -> {
              try (Socket client = socket) {
                client.setSoTimeout(10000);
                BufferedReader reader = new BufferedReader(new InputStreamReader(client.getInputStream()));
                String request = reader.readLine();
                String header;
                while ((header = reader.readLine()) != null && !header.isEmpty()) {}
                boolean get = request.startsWith("GET ");
                if (get) { firstSix.countDown(); if (!release.await(5, TimeUnit.SECONDS)) return; }
                byte[] body = (get ? rows.toString() : "{\"status\":\"OK\"}").getBytes(StandardCharsets.UTF_8);
                client.getOutputStream().write(("HTTP/1.1 200 OK\r\nContent-Length: " + body.length
                    + "\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.UTF_8));
                client.getOutputStream().write(body);
                client.getOutputStream().flush();
                if (!get) { posts.add(request); posted.countDown(); }
              } catch (Exception ignored) { }
            });
          }
        } catch (IOException ignored) { }
      });
      accept.setDaemon(true); accept.start();
      try {
        instrumentation.runOnMainSync(() -> {
          BleStore store = BleStore.get(context);
          store.pause(); store.cancelBackground(); store.cancelAll("Fixture setup"); store.demo = false;
          store.devices.clear(); store.foreground = true;
          store.server.save(true, "http://127.0.0.1:" + server.getLocalPort());
          for (int i = 0; i < 7; i++) {
            BleStore.Device d = new BleStore.Device(String.format(Locale.US, "AA:BB:CC:DD:EE:%02d", i));
            d.name = String.format(Locale.US, "TEST%04d", i);
            store.devices.put(d.address, d);
            store.power(d, false);
          }
        });
        assertTrue("Six network requests should start together", firstSix.await(5, TimeUnit.SECONDS));
        instrumentation.runOnMainSync(() -> {
          BleStore store = BleStore.get(context);
          assertEquals(6, store.remote.size());
          assertEquals(1, store.queue.size());
          assertEquals("6 active · 1 queued · limit 6", store.connectionSummary());
        });
        release.countDown();
        assertTrue("All seven commands should finish as slots free", posted.await(15, TimeUnit.SECONDS));
        assertEquals(7, new HashSet<>(posts).size());
        for (String request : posts) assertTrue(request.endsWith("/0 HTTP/1.1"));
      } finally {
        release.countDown();
        instrumentation.runOnMainSync(() -> {
          BleStore store = BleStore.get(context);
          store.foreground = false; store.cancelAll("Fixture cleanup"); store.devices.clear();
          store.server.save(false, "");
        });
      }
    } finally { clients.shutdownNow(); }
  }
}
