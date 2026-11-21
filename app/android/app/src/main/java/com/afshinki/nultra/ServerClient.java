package com.afshinki.nultra;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

/** Fancy acknowledges queue admission, not a physical switch readback. */
final class ServerClient {
  static String base(String value) {
    try {
      URI uri = new URI(value.trim());
      if (!("http".equalsIgnoreCase(uri.getScheme()) || "https".equalsIgnoreCase(uri.getScheme()))
          || uri.getHost() == null
          || ("http".equalsIgnoreCase(uri.getScheme())
              && !Arrays.asList("localhost", "127.0.0.1", "[::1]").contains(uri.getHost().toLowerCase(Locale.ROOT)))
          || uri.getUserInfo() != null
          || uri.getQuery() != null
          || uri.getFragment() != null
          || uri.getPort() == 0
          || uri.getPort() > 65535
          || uri.getPort() < -1) throw new IllegalArgumentException();
      return uri.toASCIIString().replaceAll("/+$", "");
    } catch (Exception e) {
      throw new IllegalArgumentException(
          "Enter an HTTPS URL or a loopback HTTP URL. No password, query or fragment.");
    }
  }

  static final class Row {
    final String address, name;
    final boolean available;
    final Boolean power;
    final int battery;

    Row(JSONObject j) throws JSONException {
      address = j.getString("address").toUpperCase(Locale.ROOT);
      name = j.getString("display_name").trim();
      available = j.getInt("seen_recently") == 1;
      int state = j.optInt("switch_state", -1);
      power = state == 0 ? Boolean.FALSE : state == 1 ? Boolean.TRUE : null;
      int b = j.optInt("battery", -1);
      battery = b >= 0 && b <= 100 ? b : -1;
    }
  }

  static boolean validAddress(String address) {
    return address != null && address.matches("[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}");
  }

  static Row resolve(String address, String name, String pinned, boolean uniqueName, List<Row> rows)
      throws IOException {
    List<Row> matches = new ArrayList<>();
    String preferred = pinned != null ? pinned : address;
    for (Row row : rows) if (row.address.equalsIgnoreCase(preferred)) matches.add(row);
    if (matches.isEmpty() && pinned == null && uniqueName)
      for (Row row : rows) if (row.name.equals(name)) matches.add(row);
    if (matches.size() != 1
        || !validAddress(matches.get(0).address)
        || matches.get(0).name.isEmpty())
      throw new IOException(
          "No unique server match for " + name + ". Check switch mapping in Menu.");
    Row row = matches.get(0);
    if (!row.available) throw new IOException("Server has not seen " + name + " recently.");
    return row;
  }

  final String url;
  volatile boolean cancelled;
  volatile HttpURLConnection connection;

  private final CredentialStore credentials;

  ServerClient(String url) { this(url, null); }

  ServerClient(String url, CredentialStore credentials) {
    this.credentials = credentials;
    this.url = base(url);
  }

  void cancel() {
    cancelled = true;
    HttpURLConnection c = connection;
    if (c != null) c.disconnect();
  }

  String request(String path, String method) throws Exception {
    if (cancelled) throw new IOException("Request cancelled.");
    HttpURLConnection c = (HttpURLConnection) new URL(url + path).openConnection();
    connection = c;
    try {
      if (cancelled) throw new IOException("Request cancelled.");
      c.setConnectTimeout(4000);
      c.setReadTimeout(4000);
      c.setInstanceFollowRedirects(false);
      c.setUseCaches(false);
      c.setRequestMethod(method);
      c.setRequestProperty("Accept", "application/json");
      c.setRequestProperty("X-Nultra-Request", "1");
      if (credentials != null) {
        String token = credentials.get("server:" + url);
        if (!token.isEmpty()) {
          String basic = Base64.getEncoder().encodeToString(("nultra:" + token).getBytes(StandardCharsets.UTF_8));
          c.setRequestProperty("Authorization", "Basic " + basic);
        }
      }
      if (c.getResponseCode() < 200 || c.getResponseCode() >= 300)
        throw new IOException("Server request failed (HTTP " + c.getResponseCode() + ").");
      try (InputStream in = c.getInputStream();
          ByteArrayOutputStream out = new ByteArrayOutputStream()) {
        byte[] b = new byte[4096];
        int n;
        while ((n = in.read(b)) != -1) {
          if (cancelled || out.size() + n > 1024 * 1024)
            throw new IOException("Server response cancelled or too large.");
          out.write(b, 0, n);
        }
        return out.toString(StandardCharsets.UTF_8.name());
      }
    } finally {
      c.disconnect();
      connection = null;
    }
  }

  List<Row> devices() throws Exception {
    JSONArray array = new JSONArray(request("/devices", "GET"));
    List<Row> rows = new ArrayList<>();
    for (int i = 0; i < array.length(); i++) rows.add(new Row(array.getJSONObject(i)));
    return rows;
  }

  void power(String address, boolean on) throws Exception {
    if (!validAddress(address)) throw new IOException("Invalid server switch address.");
    JSONObject reply =
        new JSONObject(request("/toggle/" + address + "/" + (on ? "1" : "0"), "POST"));
    if (!"OK".equals(reply.optString("status")))
      throw new IOException("Server rejected the command.");
  }
}
