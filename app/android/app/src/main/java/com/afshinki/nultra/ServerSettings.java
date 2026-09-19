package com.afshinki.nultra;

import android.content.*;

final class ServerSettings {
  final SharedPreferences prefs;

  ServerSettings(Context context) {
    prefs = context.getSharedPreferences("backup-server", 0);
  }

  boolean enabled() {
    return prefs.getBoolean("enabled", false) && !url().isEmpty();
  }

  String url() {
    return prefs.getString("url", "");
  }

  void save(boolean enabled, String url) {
    String normalized = url.trim().isEmpty() && !enabled ? "" : ServerClient.base(url);
    SharedPreferences.Editor edit = prefs.edit();
    if (!normalized.equals(url())) edit.clear();
    edit.putBoolean("enabled", enabled).putString("url", normalized).apply();
  }

  String mapping(String address) {
    return prefs.getString("map:" + address, null);
  }

  void map(String address, String remote) {
    prefs.edit().putString("map:" + address, remote).apply();
  }
}
