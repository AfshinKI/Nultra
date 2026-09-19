package com.afshinki.nultra;

import static org.junit.Assert.*;

import java.io.*;
import java.net.*;
import java.util.*;
import org.json.*;
import org.junit.Test;

public class ServerClientTest {
  ServerClient.Row row(String address, String name, int seen) throws Exception {
    return new ServerClient.Row(
        new JSONObject()
            .put("address", address)
            .put("display_name", name)
            .put("seen_recently", seen)
            .put("switch_state", 1)
            .put("battery", 7));
  }

  static final String A = "AA:BB:CC:DD:EE:01", B = "AA:BB:CC:DD:EE:02";

  @Test
  public void validatesConfiguredEndpoint() {
    assertEquals(
        "http://raspberrypi.local:5050/api",
        ServerClient.base(" http://raspberrypi.local:5050/api/ "));
    for (String bad :
        new String[] {
          "localhost:5050",
          "ftp://host",
          "http://user:pass@host",
          "http://host?x=1",
          "http://host#frag",
          "http://host:0",
          "http://host:65536"
        }) assertThrows(IllegalArgumentException.class, () -> ServerClient.base(bad));
  }

  @Test
  public void stableAddressWinsOverName() throws Exception {
    ServerClient.Row selected = row(A, "RENAMED1", 1);
    assertSame(
        selected,
        ServerClient.resolve(
            A, "BEDROOM1", null, true, Arrays.asList(selected, row(B, "BEDROOM1", 1))));
  }

  @Test
  public void pinnedMappingNeverSilentlyRematches() throws Exception {
    assertThrows(
        IOException.class,
        () -> ServerClient.resolve(A, "BEDROOM1", B, true, Arrays.asList(row(A, "BEDROOM1", 1))));
  }

  @Test
  public void namesMustBeUniqueAndRecentlySeen() throws Exception {
    assertThrows(
        IOException.class,
        () ->
            ServerClient.resolve(A, "BEDROOM1", null, true, Arrays.asList(row(B, "BEDROOM1", 0))));
    assertThrows(
        IOException.class,
        () ->
            ServerClient.resolve(A, "BEDROOM1", null, false, Arrays.asList(row(B, "BEDROOM1", 1))));
    assertThrows(
        IOException.class,
        () ->
            ServerClient.resolve(
                A,
                "BEDROOM1",
                null,
                true,
                Arrays.asList(row(B, "BEDROOM1", 1), row("AA:BB:CC:DD:EE:03", "BEDROOM1", 1))));
    assertThrows(
        IOException.class,
        () ->
            ServerClient.resolve(
                A, "BEDROOM1", null, true, Arrays.asList(row("../bad", "BEDROOM1", 1))));
  }

  @Test
  public void malformedBatteryAndStateAreUnknown() throws Exception {
    ServerClient.Row row =
        new ServerClient.Row(
            new JSONObject(
                "{\"address\":\""
                    + A
                    + "\",\"display_name\":\"BEDROOM1\",\"seen_recently\":1,\"battery\":200,\"switch_state\":2}"));
    assertNull(row.power);
    assertEquals(-1, row.battery);
  }

  @Test
  public void requestsUseExactRoutesAndRejectQueueErrors() throws Exception {
    try (ServerSocket socket = new ServerSocket(0, 8, InetAddress.getLoopbackAddress())) {
      List<String> requests = Collections.synchronizedList(new ArrayList<>());
      Thread server =
          new Thread(
              () -> {
                try {
                  String[] bodies = {"[]", "{\"status\":\"OK\"}", "{\"status\":\"ERROR\"}"};
                  for (String body : bodies)
                    try (Socket client = socket.accept()) {
                      BufferedReader reader =
                          new BufferedReader(new InputStreamReader(client.getInputStream()));
                      requests.add(reader.readLine());
                      while (!reader.readLine().isEmpty()) {}
                      byte[] bytes = body.getBytes(java.nio.charset.StandardCharsets.UTF_8);
                      client
                          .getOutputStream()
                          .write(
                              ("HTTP/1.1 200 OK\r\nContent-Length: "
                                      + bytes.length
                                      + "\r\nConnection: close\r\n\r\n"
                                      + body)
                                  .getBytes(java.nio.charset.StandardCharsets.UTF_8));
                    }
                } catch (Exception e) {
                  throw new RuntimeException(e);
                }
              });
      server.setDaemon(true);
      server.start();
      ServerClient client = new ServerClient("http://127.0.0.1:" + socket.getLocalPort() + "/api", true);
      assertTrue(client.devices().isEmpty());
      client.power(A, false);
      assertThrows(IOException.class, () -> client.power(A, true));
      server.join(2000);
      assertEquals(
          Arrays.asList(
              "GET /api/devices HTTP/1.1",
              "POST /api/toggle/" + A + "/0 HTTP/1.1",
              "POST /api/toggle/" + A + "/1 HTTP/1.1"),
          requests);
    }
  }

  @Test
  public void cancelledClientNeverMakesRequest() {
    ServerClient client = new ServerClient("http://127.0.0.1:1");
    client.cancel();
    assertThrows(IOException.class, client::devices);
  }
}
