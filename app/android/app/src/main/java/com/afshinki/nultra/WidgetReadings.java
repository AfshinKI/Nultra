package com.afshinki.nultra;

import android.content.*;
import java.util.*;
import org.json.*;

final class WidgetReadings {
  static void save(Context context, List<BleStore.Device> devices) {
    SharedPreferences prefs = context.getSharedPreferences("widget-readings", 0);
    SharedPreferences.Editor edit = prefs.edit();
    boolean changed = false;
    for (BleStore.Device d : devices) {
      if (d.reportedAt <= 0) continue;
      try {
        String value = new JSONObject().put("power", d.power == null ? JSONObject.NULL : d.power)
            .put("date", d.reportedAt).toString();
        JSONObject old = new JSONObject(prefs.getString(d.address, "{}"));
        boolean samePower = (d.power == null && old.isNull("power")) || (d.power != null && !old.isNull("power") && old.getBoolean("power") == d.power);
        if (!samePower || d.reportedAt - old.optLong("date") >= 60000 || old.optLong("date") <= 0) {
          edit.putString(d.address, value); changed = true;
        }
      } catch (JSONException ignored) { }
    }
    if (changed) { edit.apply(); SwitchWidget.refresh(context); }
  }
  static void restore(Context context, BleStore.Device d) {
    try {
      JSONObject j = new JSONObject(context.getSharedPreferences("widget-readings", 0).getString(d.address, "{}"));
      d.power = j.isNull("power") ? null : j.getBoolean("power");
      d.reportedAt = j.optLong("date");
    } catch (JSONException ignored) { }
  }
  static String state(Context context, String target) {
    List<String> ids = new ArrayList<>();
    try {
      JSONArray catalog = new JSONArray(context.getSharedPreferences("switches", 0).getString("catalog", "[]"));
      for (int i = 0; i < catalog.length(); i++) ids.add(catalog.getJSONObject(i).getString("address"));
      if (target.startsWith("scene:")) {
        Scenes.Scene scene = Scenes.load(context).stream().filter(s -> s.target().equals(target)).findFirst().orElse(null);
        if (scene == null) return "Scene removed";
        ids.retainAll(scene.members);
      } else if (!target.equals("*")) ids.retainAll(Collections.singleton(target));
      if (ids.isEmpty()) return "No saved lights";
      SharedPreferences prefs = context.getSharedPreferences("widget-readings", 0);
      Boolean power = null; boolean mixed = false; long oldest = Long.MAX_VALUE;
      for (String id : ids) {
        JSONObject value = new JSONObject(prefs.getString(id, "{}"));
        if (value.isNull("power") || value.optLong("date") <= 0) return "State unknown";
        boolean on = value.getBoolean("power");
        if (power != null && power != on) mixed = true;
        power = on; oldest = Math.min(oldest, value.getLong("date"));
      }
      long age = Math.max(0, (System.currentTimeMillis() - oldest) / 60000L);
      return (mixed ? "Mixed" : Boolean.TRUE.equals(power) ? "On" : "Off") + " · " + (age < 1 ? "<1m" : age < 60 ? age + "m" : age / 60 + "h") + " ago";
    } catch (JSONException e) { return "State unknown"; }
  }
}
