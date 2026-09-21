package com.afshinki.nultra;

import android.content.Context;
import java.util.*;
import org.json.*;

final class Scenes {
  static final class Scene {
    final String id;
    String name;
    final List<String> members;
    Scene(String id, String name, Collection<String> members) {
      this.id = id; this.name = name.trim(); this.members = new ArrayList<>(new LinkedHashSet<>(members));
    }
    String target() { return "scene:" + id; }
    List<String> targets(Collection<String> known) {
      List<String> result = new ArrayList<>(members); result.retainAll(known); return result;
    }
  }
  static List<Scene> decode(String json) {
    List<Scene> result = new ArrayList<>();
    Set<String> ids = new HashSet<>();
    try {
      JSONArray a = new JSONArray(json);
      for (int i = 0; i < a.length(); i++) {
        JSONObject j = a.getJSONObject(i);
        String id = j.getString("id"); UUID.fromString(id);
        List<String> members = new ArrayList<>();
        JSONArray m = j.getJSONArray("members");
        for (int n = 0; n < m.length(); n++) members.add(m.getString(n));
        if (ids.add(id)) result.add(new Scene(id, j.getString("name"), members));
      }
    } catch (JSONException | IllegalArgumentException ignored) { }
    return result;
  }
  static String encode(List<Scene> scenes) {
    JSONArray a = new JSONArray();
    for (Scene s : scenes) try {
      a.put(new JSONObject().put("id", s.id).put("name", s.name).put("members", new JSONArray(s.members)));
    } catch (JSONException ignored) { }
    return a.toString();
  }
  static List<Scene> load(Context context) { return decode(context.getSharedPreferences("scenes", 0).getString("catalog", "[]")); }
  static void save(Context context, List<Scene> scenes) { context.getSharedPreferences("scenes", 0).edit().putString("catalog", encode(scenes)).apply(); }
}
