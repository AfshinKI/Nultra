package com.afshinki.nultra;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.*;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import java.util.*;

@android.annotation.SuppressLint("SetTextI18n") // Private English-only app.
public final class MainActivity extends Activity implements BleStore.Listener {
  static final int BG = Color.rgb(7, 15, 24),
      CARD = Color.rgb(15, 25, 35),
      INK = Color.rgb(244, 248, 251),
      MUTED = Color.rgb(147, 168, 181),
      MINT = Color.rgb(164, 241, 212),
      YELLOW = Color.rgb(255, 220, 64),
      BLUE = Color.rgb(63, 149, 255),
      GRAY = Color.rgb(69, 86, 98);
  BleStore store;
  LinearLayout content, grid, scenesPanel;
  String scenesKey = "";
  TextView status;
  Button allOff, allOn, allow;
  final Map<String, Card> cards = new LinkedHashMap<>();
  String layoutKey = "";

  @Override
  public void onCreate(Bundle state) {
    super.onCreate(state);
    store = BleStore.get(this);
    BackgroundRefresh.schedule(this);
    store.listener = this;
    LinearLayout root = column();
    root.setBackgroundColor(BG);
    root.setOnApplyWindowInsetsListener(
        (v, insets) -> {
          v.setPadding(
              insets.getSystemWindowInsetLeft(),
              insets.getSystemWindowInsetTop(),
              insets.getSystemWindowInsetRight(),
              insets.getSystemWindowInsetBottom());
          return insets.consumeSystemWindowInsets();
        });
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    root.addView(scroll, new LinearLayout.LayoutParams(-1, -1));
    content = column();
    content.setPadding(dp(16), dp(14), dp(16), dp(24));
    scroll.addView(content);
    LinearLayout header = row();
    ImageView icon = new ImageView(this);
    icon.setImageResource(com.afshinki.nultra.R.drawable.app_icon);
    header.addView(icon, new LinearLayout.LayoutParams(dp(42), dp(42)));
    TextView title = text("nultra", 32, INK);
    title.setTypeface(null, Typeface.BOLD);
    LinearLayout.LayoutParams titleP = new LinearLayout.LayoutParams(0, -2, 1);
    titleP.setMargins(dp(12), 0, 0, 0);
    header.addView(title, titleP);
    Button menu = button("☰", MINT, () -> menu());
    menu.setContentDescription("Open menu");
    header.addView(menu, new LinearLayout.LayoutParams(dp(52), dp(52)));
    content.addView(header);
    space(content, 14);
    LinearLayout bulk = row();
    allOff = button("All Off", MUTED, () -> store.all(false));
    allOn = button("All On", YELLOW, () -> store.all(true));
    bulk.addView(allOff, weighted());
    bulk.addView(allOn, weighted());
    content.addView(bulk);
    space(content, 10);
    status = text("Listening for switches…", 14, MUTED);
    status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
    content.addView(status);
    space(content, 8);
    allow = button("Allow Bluetooth access", MINT, this::requestBluetooth);
    content.addView(allow);
    scenesPanel = column();
    content.addView(scenesPanel);
    grid = column();
    content.addView(grid);
    setContentView(root);
    if (BuildConfig.DEBUG && getIntent().getBooleanExtra("demo", false)) store.demo(true);
    changed();
  }

  @Override
  protected void onResume() {
    super.onResume();
    store.resume();
    changed();
  }

  @Override
  protected void onPause() {
    store.pause();
    super.onPause();
  }

  @Override
  protected void onDestroy() {
    if (store.listener == this) store.listener = null;
    super.onDestroy();
  }

  void requestBluetooth() {
    if (!store.permissions())
      requestPermissions(
          Build.VERSION.SDK_INT >= 31
              ? new String[] {
                Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT
              }
              : new String[] {Manifest.permission.ACCESS_FINE_LOCATION},
          7);
    else startActivity(new Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS));
  }

  @Override
  public void onRequestPermissionsResult(int code, String[] p, int[] grants) {
    super.onRequestPermissionsResult(code, p, grants);
    if (code == 7) {
      if (store.permissions()) store.startScan();
      else
        store.message =
            "Permission denied. Allow Bluetooth access in Android Settings → Apps → Nultra →"
                + " Permissions.";
      changed();
    }
  }

  @Override
  public void changed() {
    if (isFinishing()) return;
    List<BleStore.Device> list = store.visible();
    updateScenes();
    status.setText(
        store.demo
            ? "DEMO · No physical switches controlled"
            : !store.message.isEmpty()
                ? store.message
                : list.isEmpty()
                    ? "Listening · Waiting for verified switch names"
                    : list.size() + " saved switches · Listening while open");
    allow.setVisibility(!store.demo && !store.permissions() ? View.VISIBLE : View.GONE);
    boolean enabled = !list.isEmpty() && !store.anyBusy();
    allOff.setEnabled(enabled);
    allOn.setEnabled(enabled);
    StringBuilder key = new StringBuilder(store.demo ? "demo" : "real");
    int columns = getResources().getConfiguration().fontScale >= 1.5f ? 1 : 2;
    key.append(columns);
    for (BleStore.Device d : list) key.append(d.address);
    if (!key.toString().equals(layoutKey)) {
      layoutKey = key.toString();
      grid.removeAllViews();
      cards.clear();
      if (list.isEmpty()) {
        TextView empty =
            text(
                "Your switches stay here, even when offline. New switches appear after Nultra reads"
                    + " their real name.",
                17,
                MUTED);
        empty.setPadding(dp(16), dp(28), dp(16), dp(28));
        grid.addView(empty);
        grid.addView(button("Explore the demo", MINT, () -> store.demo(true)));
      } else {
        LinearLayout line = null;
        int i = 0;
        for (BleStore.Device d : list) {
          if (i % columns == 0) {
            line = row();
            grid.addView(line);
          }
          Card card = new Card(d);
          cards.put(d.address, card);
          line.addView(card.root, weighted());
          i++;
        }
        if (columns == 2 && i % 2 == 1) line.addView(new View(this), weighted());
      }
    }
    for (Card card : cards.values()) card.update();
  }

  final class Card {
    final BleStore.Device device;
    final LinearLayout root;
    final TextView name;
    final StatusGlyph glyph;
    final FrameLayout control;
    final Bulb bulb;
    final ProgressBar progress;

    Card(BleStore.Device d) {
      device = d;
      root = column();
      root.setPadding(dp(10), dp(8), dp(10), dp(6));
      glyph = new StatusGlyph();
      root.addView(glyph, new LinearLayout.LayoutParams(-1, dp(20)));
      LinearLayout lower = row();
      name = text(d.name, 16, INK);
      name.setTypeface(null, Typeface.BOLD);
      name.setMaxLines(2);
      name.setMinHeight(dp(54));
      name.setGravity(Gravity.CENTER_VERTICAL);
      name.setOnClickListener(v -> details(d));
      name.setFocusable(true);
      name.setBackground(selectable());
      lower.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
      control = new FrameLayout(MainActivity.this);
      bulb = new Bulb();
      bulb.setOnClickListener(v -> store.power(d, !Boolean.TRUE.equals(d.power)));
      bulb.setFocusable(true);
      control.addView(bulb, new FrameLayout.LayoutParams(dp(48), dp(48), Gravity.CENTER));
      progress = new ProgressBar(MainActivity.this);
      FrameLayout.LayoutParams pp = new FrameLayout.LayoutParams(dp(25), dp(25), Gravity.CENTER);
      control.addView(progress, pp);
      lower.addView(control, new LinearLayout.LayoutParams(dp(50), dp(54)));
      root.addView(lower);
    }

    void update() {
      boolean on = Boolean.TRUE.equals(device.power), busy = store.busy(device);
      root.setBackground(shape(CARD, on ? 0xff514929 : 0xff1b2833, 18));
      name.setText(device.name);
      name.setContentDescription(device.name + ", switch settings");
      glyph.d = device;
      glyph.invalidate();
      glyph.setContentDescription(
          (store.online(device) ? "Online" : "Offline")
              + ", "
              + (device.battery >= 0
                  ? (device.battery < 10 ? "Low battery" : "Battery available")
                  : "Battery unknown"));
      bulb.on = on;
      bulb.invalidate();
      bulb.setContentDescription(
          device.name
              + ", "
              + (device.power == null ? "power unknown" : on ? "on" : "off")
              + ", turn "
              + (on ? "off" : "on"));
      bulb.setEnabled(!busy);
      bulb.setVisibility(busy ? View.INVISIBLE : View.VISIBLE);
      progress.setVisibility(busy ? View.VISIBLE : View.GONE);
      progress.setContentDescription("Changing " + device.name);
    }
  }

  void details(BleStore.Device d) {
    LinearLayout view = column();
    view.setPadding(dp(20), dp(8), dp(20), dp(12));
    TextView values = text("", 17, MUTED);
    view.addView(values);
    space(view, 18);
    Switch power = new Switch(this);
    power.setText("Light power");
    power.setTextColor(INK);
    power.setMinHeight(dp(48));
    power.setChecked(Boolean.TRUE.equals(d.power));
    power.setOnClickListener(w -> {
      if (!store.busy(d)) store.power(d, power.isChecked());
      power.setChecked(Boolean.TRUE.equals(d.power));
      power.setEnabled(!store.busy(d));
    });
    view.addView(power);
    ProgressBar wait = new ProgressBar(this);
    view.addView(wait, new LinearLayout.LayoutParams(dp(28), dp(28)));
    view.addView(button("Scenes · View and edit membership", MINT, () -> deviceScenes(d)));
    Button rename = button("Rename", MINT, () -> rename(d));
    view.addView(rename);
    space(view, 12);
    view.addView(
        text("Connects only to apply your change, then immediately disconnects.", 14, MUTED));
    AlertDialog dialog =
        new AlertDialog.Builder(this)
            .setTitle(d.name)
            .setView(view)
            .setPositiveButton("Done", null)
            .create();
    Handler h = new Handler(Looper.getMainLooper());
    Runnable update =
        new Runnable() {
          public void run() {
            if (!dialog.isShowing()) return;
            boolean busy = store.busy(d);
            values.setText(
                (d.power == null
                        ? "Power unknown"
                        : Boolean.TRUE.equals(d.power) ? "Power is on" : "Power is off")
                    + (d.serverReported ? "\nReported by backup server" : "")
                    + "\n\nBattery  "
                    + (d.battery < 0 ? "—" : d.battery + "%")
                    + "\nFirmware  "
                    + (d.firmware.isEmpty() ? "—" : d.firmware));
            wait.setVisibility(busy ? View.VISIBLE : View.GONE);
            power.setEnabled(!busy);
            power.setChecked(Boolean.TRUE.equals(d.power));
            power.setContentDescription("Light power, " + (d.power == null ? "unknown" : d.power ? "on" : "off"));
            rename.setEnabled(!busy);
            dialog.setTitle(d.name);
            h.postDelayed(this, 500);
          }
        };
    dialog.setOnDismissListener(v -> h.removeCallbacks(update));
    dialog.show();
    h.post(update);
  }

  void updateScenes() {
    String key = store.demo + Scenes.encode(store.scenes()) + store.anyBusy() + store.visible().size();
    if (key.equals(scenesKey)) return;
    scenesKey = key;
    scenesPanel.removeAllViews();
    LinearLayout title = row();
    title.addView(text("Scenes", 16, INK), new LinearLayout.LayoutParams(0, -2, 1));
    Button add = button("+", MINT, () -> sceneEditor(new Scenes.Scene(UUID.randomUUID().toString(), "", Collections.emptyList())));
    add.setContentDescription("Add scene"); add.setEnabled(!store.visible().isEmpty());
    title.addView(add, new LinearLayout.LayoutParams(dp(48), dp(48)));
    scenesPanel.addView(title);
    for (Scenes.Scene scene : store.scenes()) {
      LinearLayout line = row();
      Button name = button(scene.name + " · Edit", INK, () -> sceneEditor(scene));
      name.setContentDescription("Edit scene " + scene.name);
      line.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
      for (boolean on : new boolean[] {false, true}) {
        Button power = button(on ? "On" : "Off", on ? YELLOW : MUTED, () -> store.group(scene.target(), on));
        power.setEnabled(!store.anyBusy()); line.addView(power, new LinearLayout.LayoutParams(dp(56), -2));
      }
      scenesPanel.addView(line);
    }
  }

  void sceneEditor(Scenes.Scene scene) {
    ScrollView scroll = new ScrollView(this);
    LinearLayout view = column(); view.setPadding(dp(16), dp(8), dp(16), dp(8)); scroll.addView(view);
    EditText name = edit(scene.name, false); name.setHint("Scene name"); name.setContentDescription("Scene name");
    view.addView(name);
    view.addView(text("Lights may belong to multiple scenes.", 14, MUTED));
    Set<String> members = new LinkedHashSet<>(scene.members);
    members.retainAll(store.visible().stream().map(d -> d.address).collect(java.util.stream.Collectors.toList()));
    for (BleStore.Device d : store.visible()) {
      CheckBox check = new CheckBox(this); check.setText(d.name); check.setTextColor(INK); check.setChecked(members.contains(d.address));
      check.setOnCheckedChangeListener((b, on) -> { if (on) members.add(d.address); else members.remove(d.address); });
      view.addView(check);
    }
    final AlertDialog[] editor = new AlertDialog[1];
    if (store.scenes().stream().anyMatch(s -> s.id.equals(scene.id))) view.addView(button("Delete scene", MUTED, () -> {
      new AlertDialog.Builder(this).setTitle("Delete " + scene.name + "?")
        .setMessage("Lights and their other scenes are kept.").setNegativeButton("Cancel", null)
        .setPositiveButton("Delete", (d, w) -> { store.deleteScene(scene.id); editor[0].dismiss(); }).show();
    }));
    AlertDialog dialog = new AlertDialog.Builder(this).setTitle("Scene").setView(scroll).setNegativeButton("Cancel", null).setPositiveButton("Save", null).create();
    editor[0] = dialog;
    dialog.setOnShowListener(x -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(w -> {
      String value = name.getText().toString().trim();
      if (value.isEmpty() || value.length() > 40) { name.setError("Enter a name of 1–40 characters"); return; }
      if (members.isEmpty()) { toast("Choose at least one light"); return; }
      store.saveScene(new Scenes.Scene(scene.id, value, members)); dialog.dismiss();
    }));
    dialog.show();
  }

  void deviceScenes(BleStore.Device device) {
    List<Scenes.Scene> scenes = store.scenes();
    if (scenes.isEmpty()) { toast("Create a scene from the home screen first"); return; }
    LinearLayout view = column(); view.setPadding(dp(16), dp(8), dp(16), dp(8));
    final AlertDialog[] membershipDialog = new AlertDialog[1];
    for (Scenes.Scene scene : scenes) {
      LinearLayout line = row();
      CheckBox member = new CheckBox(this); member.setText(scene.name); member.setTextColor(INK); member.setChecked(scene.members.contains(device.address));
      member.setOnCheckedChangeListener((b, on) -> {
        Set<String> ids = new LinkedHashSet<>(scene.members);
        if (on) ids.add(device.address); else ids.remove(device.address);
        if (ids.isEmpty()) { member.setChecked(true); toast("Edit to replace the last light or delete the scene"); return; }
        scene.members.clear(); scene.members.addAll(ids); store.saveScene(scene);
      });
      line.addView(member, new LinearLayout.LayoutParams(0, -2, 1));
      line.addView(button("Edit", MINT, () -> { membershipDialog[0].dismiss(); sceneEditor(scene); })); view.addView(line);
    }
    ScrollView scroll = new ScrollView(this); scroll.addView(view);
    membershipDialog[0] = new AlertDialog.Builder(this).setTitle(device.name + " · Scenes").setView(scroll).setPositiveButton("Done", null).show();
  }

  void rename(BleStore.Device d) {
    EditText input = edit(d.name, false);
    AlertDialog dialog =
        new AlertDialog.Builder(this)
            .setTitle("Rename " + d.name)
            .setMessage("Exactly eight printable ASCII characters. Editing does not connect.")
            .setView(input)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Save", null)
            .create();
    dialog.setOnShowListener(
        v ->
            dialog
                .getButton(AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener(
                    w -> {
                      try {
                        store.rename(d, input.getText().toString());
                        dialog.dismiss();
                      } catch (IllegalArgumentException e) {
                        input.setError(e.getMessage());
                      }
                    }));
    dialog.show();
  }

  void switchCredential(BleStore.Device device) {
    EditText password = edit("", true);
    password.setHint("8 ASCII characters");
    new AlertDialog.Builder(this).setTitle(device.address).setView(password)
        .setNegativeButton("Cancel", null)
        .setNeutralButton("Forget", (dialog, which) -> {
          try { store.credentials.reset(device.address); toast("Password removed"); }
          catch (Exception e) { toast("Could not remove password"); }
        })
        .setPositiveButton("Save", (dialog, which) -> {
          try {
            String value = password.getText().toString();
            Protocol.ascii(value);
            store.credentials.save(device.address, value);
            store.retry();
            toast("Switch password saved");
          } catch (Exception e) { toast("Enter eight printable ASCII characters"); }
        }).show();
  }

  void menu() {
    ScrollView scroll = new ScrollView(this);
    LinearLayout v = column();
    v.setPadding(dp(22), dp(8), dp(22), dp(16));
    scroll.addView(v);
    v.addView(text("Switch password", 20, INK));
    v.addView(button("Choose switch", MINT, () -> {
      List<BleStore.Device> devices = new ArrayList<>(store.devices.values());
      if (devices.isEmpty()) { toast("Scan for a nearby switch first"); return; }
      String[] labels = devices.stream().map(d -> (d.name.isEmpty() ? "Nearby switch" : d.name) + " · " + d.address).toArray(String[]::new);
      new AlertDialog.Builder(this).setTitle("Choose switch").setItems(labels,
          (dialog, index) -> switchCredential(devices.get(index))).show();
    }));
    space(v, 20);
    v.addView(button("Battery alerts", MINT, this::batterySettings));
    v.addView(button("Background refresh", MINT, this::refreshSettings));
    v.addView(button("Backup server", MINT, this::serverSettings));
    v.addView(
        text(
            "Background controls: add the Nultra widget from your home screen. Choose all switches"
                + " or a scene or one saved light; Off/On runs without opening the app.",
            15,
            MUTED));
    space(v, 20);
    v.addView(text("Discovery", 20, INK));
    TextView connections = text(store.connectionSummary(), 14, MUTED);
    v.addView(connections);
    v.addView(text("Limit bounds short transactions; it is not a reported hardware maximum.", 14, MUTED));
    v.addView(
        text(
            "Blue means recently seen by Bluetooth or the enabled server; gray means offline. Real"
                + " names stay saved. No idle connections.",
            15,
            MUTED));
    v.addView(
        button(
            "Retry discovery",
            MINT,
            () -> {
              store.retry();
              toast("Discovery restarted");
            }));
    v.addView(
        button(
            "Bluetooth / permission settings",
            MUTED,
            () ->
                startActivity(
                    new Intent(
                        android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:" + getPackageName())))));
    space(v, 20);
    Switch demo = new Switch(this);
    demo.setText("Explore demo mode");
    demo.setTextColor(MINT);
    demo.setChecked(store.demo);
    v.addView(demo);
    space(v, 20);
    LinearLayout developer = column();
    developer.setPadding(dp(14), dp(14), dp(14), dp(14));
    developer.setBackground(shape(CARD, 0xff1b2833, 14));
    developer.addView(text("Afshin Kashani", 20, INK));
    developer.addView(
        button(
            "innovetron.com",
            MINT,
            () ->
                startActivity(
                    new Intent(Intent.ACTION_VIEW, Uri.parse("https://innovetron.com")))));
    developer.addView(text("Nultra " + BuildConfig.VERSION_NAME + " · Android", 14, MUTED));

    v.addView(developer, new LinearLayout.LayoutParams(-1, -2));

    AlertDialog dialog =
        new AlertDialog.Builder(this)
            .setTitle("Menu")
            .setView(scroll)
            .setPositiveButton("Done", null)
            .create();
    Handler connectionTimer = new Handler(Looper.getMainLooper());
    Runnable updateConnections = new Runnable() { public void run() {
      connections.setText(store.connectionSummary());
      if (dialog.isShowing()) connectionTimer.postDelayed(this, 500);
    }};
    dialog.setOnDismissListener(x -> connectionTimer.removeCallbacks(updateConnections));
    dialog.setOnShowListener(x -> connectionTimer.post(updateConnections));
    demo.setOnCheckedChangeListener(
        (b, checked) -> {
          store.demo(checked);
          dialog.dismiss();
        });
    dialog.show();
  }

  void refreshSettings() {
    LinearLayout view = column(); view.setPadding(dp(20), dp(8), dp(20), dp(16));
    Switch enabled = new Switch(this); enabled.setText("Enable background refresh"); enabled.setTextColor(INK);
    enabled.setChecked(BackgroundRefresh.enabled(this)); view.addView(enabled);
    view.addView(text("Requested interval", 16, INK));
    RadioGroup frequency = new RadioGroup(this);
    for (int m : new int[] {15, 30, 60}) {
      RadioButton b = new RadioButton(this); b.setId(m); b.setText(m + " minutes"); b.setTextColor(INK); frequency.addView(b);
    }
    frequency.check(BackgroundRefresh.minutes(this)); view.addView(frequency);
    view.addView(text("Refreshes battery and widget state through your enabled backup server. Android chooses when to run; intervals are best effort. Battery restrictions, force-stop, or an unreachable server can prevent refresh. Bluetooth discovery resumes when you open Nultra.", 14, MUTED));
    if (!store.server.enabled()) view.addView(text("Configure and enable Backup server first.", 14, MINT));
    long last = BackgroundRefresh.prefs(this).getLong("lastSuccess", 0);
    if (last > 0) view.addView(text("Last background refresh: " + java.text.DateFormat.getDateTimeInstance().format(new Date(last)), 14, MUTED));
    ScrollView scroll = new ScrollView(this); scroll.addView(view);
    new AlertDialog.Builder(this).setTitle("Background refresh").setView(scroll).setNegativeButton("Cancel", null)
      .setPositiveButton("Save", (d, w) -> {
        BackgroundRefresh.prefs(this).edit().putBoolean("enabled", enabled.isChecked()).putInt("minutes", frequency.getCheckedRadioButtonId()).apply();
        BackgroundRefresh.schedule(this);
      }).show();
  }

  void batterySettings() {
    LinearLayout view = column();
    view.setPadding(dp(20), dp(8), dp(20), dp(16));
    Switch enabled = new Switch(this);
    enabled.setText("Low battery notifications");
    enabled.setTextColor(INK);
    enabled.setChecked(store.batteryAlerts.enabled());
    view.addView(enabled);
    EditText threshold = edit(Integer.toString(store.batteryAlerts.threshold()), false);
    threshold.setInputType(InputType.TYPE_CLASS_NUMBER);
    threshold.setContentDescription("Battery alert threshold percent");
    view.addView(text("Notify at or below (%)", 16, INK));
    view.addView(threshold);
    view.addView(text("Default 5%. One alert per switch until its battery recovers by 10 percentage points above the alert threshold. Alerts use new readings received while Nultra is active; background readings require enabled Background refresh and a reachable backup server.", 14, MUTED));
    if (!store.batteryAlerts.permitted()) view.addView(text("Notifications are currently blocked. Allow them in Android Settings → Apps → Nultra → Notifications.", 14, MUTED));
    AlertDialog dialog = new AlertDialog.Builder(this).setTitle("Battery alerts").setView(view).setNegativeButton("Cancel", null).setPositiveButton("Save", null).create();
    dialog.setOnShowListener(x -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(w -> {
      int value;
      try { value = Integer.parseInt(threshold.getText().toString()); }
      catch (NumberFormatException e) { value = 0; }
      if (value < 1 || value > 50) { threshold.setError("Enter 1–50%"); return; }
      store.batteryAlerts.save(enabled.isChecked(), value);
      if (enabled.isChecked() && Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED)
        requestPermissions(new String[] {Manifest.permission.POST_NOTIFICATIONS}, 8);
      toast("Battery alert settings saved");
      dialog.dismiss();
    }));
    dialog.show();
  }

  void serverSettings() {
    ScrollView scroll = new ScrollView(this);
    LinearLayout v = column();
    v.setPadding(dp(20), dp(8), dp(20), dp(16));
    scroll.addView(v);
    Switch enabled = new Switch(this);
    enabled.setText("Enable backup server");
    enabled.setTextColor(INK);
    enabled.setChecked(store.server.enabled());
    v.addView(enabled);
    EditText url = edit(store.server.url(), false);
    url.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
    url.setHint("http://your-server:port");
    url.setContentDescription("Backup server URL");
    v.addView(url);
    v.addView(
        text(
            "Bluetooth is preferred. If a saved switch is not nearby, Nultra can ask your"
                + " Nultra_web fancy server to change it. Use a trusted network; HTTP is not"
                + " encrypted. Renaming and discovery still use Bluetooth.",
            15,
            MUTED));
    TextView state = text("", 15, MINT);
    v.addView(state);
    v.addView(
        button(
            "Save and check",
            MINT,
            () -> {
              if (store.anyBusy()) {
                toast("Wait for the current action to finish");
                return;
              }
              try {
                store.server.save(enabled.isChecked(), url.getText().toString());
                store.serverChanged();
                toast("Server settings saved");
              } catch (IllegalArgumentException e) {
                url.setError(e.getMessage());
              }
            }));
    v.addView(text("Switch mapping", 20, INK));
    v.addView(
        text(
            "Matches the Bluetooth address first, then a unique exact name. Select a mapping if"
                + " your server uses a different address. Saved mappings never silently change.",
            14,
            MUTED));
    for (BleStore.Device d : store.visible())
      v.addView(
          button(
              d.name + " · Choose server switch",
              MUTED,
              () -> {
                if (store.anyBusy()) {
                  toast("Wait for the current action to finish");
                  return;
                }
                List<ServerClient.Row> rows = new ArrayList<>(store.serverRows);
                if (rows.isEmpty()) {
                  toast("Enable, save and check the server first");
                  return;
                }
                String[] labels = new String[rows.size() + 1];
                labels[0] = "Automatic matching";
                for (int i = 0; i < rows.size(); i++)
                  labels[i + 1] = rows.get(i).name + " · " + rows.get(i).address;
                new AlertDialog.Builder(this)
                    .setTitle(d.name)
                    .setItems(
                        labels,
                        (dialog, index) -> {
                          if (store.anyBusy()) {
                            toast("Wait for the current action to finish");
                            return;
                          }
                          store.server.map(
                              d.address, index == 0 ? null : rows.get(index - 1).address);
                          toast("Mapping saved");
                          store.notifyUI();
                        })
                    .show();
              }));
    AlertDialog dialog =
        new AlertDialog.Builder(this)
            .setTitle("Backup server")
            .setView(scroll)
            .setPositiveButton("Done", null)
            .create();
    Handler handler = new Handler(Looper.getMainLooper());
    Runnable refresh =
        new Runnable() {
          public void run() {
            if (!dialog.isShowing()) return;
            state.setText(
                store.demo
                    ? "Demo mode: server requests disabled"
                    : !store.server.enabled() ? "Disabled" : store.serverStatus);
            handler.postDelayed(this, 500);
          }
        };
    dialog.setOnDismissListener(x -> handler.removeCallbacks(refresh));
    dialog.show();
    handler.post(refresh);
  }

  EditText edit(String value, boolean secret) {
    EditText e = new EditText(this);
    e.setTextColor(INK);
    e.setSingleLine(true);
    e.setInputType(
        InputType.TYPE_CLASS_TEXT
            | (secret
                ? InputType.TYPE_TEXT_VARIATION_PASSWORD
                : InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS));
    e.setText(value);
    e.setPadding(dp(16), dp(12), dp(16), dp(12));
    return e;
  }

  void toast(String s) {
    Toast.makeText(this, s, Toast.LENGTH_SHORT).show();
  }

  LinearLayout column() {
    LinearLayout l = new LinearLayout(this);
    l.setOrientation(LinearLayout.VERTICAL);
    return l;
  }

  LinearLayout row() {
    LinearLayout l = new LinearLayout(this);
    l.setGravity(Gravity.CENTER_VERTICAL);
    return l;
  }

  LinearLayout.LayoutParams weighted() {
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, -2, 1);
    p.setMargins(dp(3), dp(4), dp(3), dp(4));
    return p;
  }

  TextView text(String s, int size, int color) {
    TextView v = new TextView(this);
    v.setText(s);
    v.setTextSize(size);
    v.setTextColor(color);
    return v;
  }

  Button button(String s, int color, Runnable action) {
    Button b = new Button(this);
    b.setText(s);
    b.setTextColor(color);
    b.setTextSize(16);
    b.setAllCaps(false);
    b.setMinHeight(dp(48));
    b.setBackground(shape(CARD, 0xff1b2833, 14));
    b.setPadding(dp(8), dp(8), dp(8), dp(8));
    b.setOnClickListener(v -> action.run());
    return b;
  }

  android.graphics.drawable.Drawable selectable() {
    android.util.TypedValue t = new android.util.TypedValue();
    getTheme().resolveAttribute(android.R.attr.selectableItemBackground, t, true);
    return getDrawable(t.resourceId);
  }

  GradientDrawable shape(int color, int stroke, int radius) {
    GradientDrawable g = new GradientDrawable();
    g.setColor(color);
    g.setCornerRadius(dp(radius));
    g.setStroke(dp(1), stroke);
    return g;
  }

  int dp(float value) {
    return Math.round(value * getResources().getDisplayMetrics().density);
  }

  void space(LinearLayout l, int height) {
    l.addView(new View(this), new LinearLayout.LayoutParams(1, dp(height)));
  }

  final class Bulb extends View {
    boolean on;
    final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    final Path path = new Path();
    final Shader glow =
        new RadialGradient(
            0, 0, 23, new int[] {0x88ffdc40, 0x00ffdc40}, null, Shader.TileMode.CLAMP);

    Bulb() {
      super(MainActivity.this);
      setMinimumWidth(dp(48));
      setMinimumHeight(dp(48));
      path.moveTo(-5, 8);
      path.cubicTo(-5, 2, -10, -1, -10, -7);
      path.cubicTo(-10, -20, 10, -20, 10, -7);
      path.cubicTo(10, -1, 5, 2, 5, 8);
      path.close();
    }

    @Override
    protected void onDraw(Canvas c) {
      super.onDraw(c);
      c.save();
      c.translate(getWidth() / 2f, getHeight() / 2f);
      c.scale(dp(1), dp(1));
      if (on) {
        p.setShader(glow);
        p.setStyle(Paint.Style.FILL);
        c.drawCircle(0, 0, 23, p);
        p.setShader(null);
      }
      p.setColor(on ? YELLOW : MUTED);
      p.setStrokeWidth(2);
      p.setStyle(on ? Paint.Style.FILL : Paint.Style.STROKE);
      c.drawPath(path, p);
      p.setStyle(Paint.Style.STROKE);
      p.setStrokeCap(Paint.Cap.ROUND);
      c.drawLine(-5, 12, 5, 12, p);
      c.drawLine(-3, 16, 3, 16, p);
      c.restore();
    }
  }

  final class StatusGlyph extends View {
    BleStore.Device d;
    final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);

    StatusGlyph() {
      super(MainActivity.this);
      setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);
    }

    @Override
    protected void onDraw(Canvas c) {
      if (d == null) return;
      float scale = getResources().getDisplayMetrics().density;
      c.save();
      c.scale(scale, scale);
      float w = getWidth() / scale;
      boolean online = store.online(d);
      p.setStyle(Paint.Style.FILL);
      p.setColor(online ? BLUE : GRAY);
      c.drawCircle(4, 8, 3, p);
      int bars = d.online(SystemClock.elapsedRealtime()) ? Protocol.bars(d.rssi) : 0;
      for (int i = 0; i < 3; i++) {
        p.setColor(i < bars ? MUTED : 0xff26343f);
        c.drawRoundRect(w - 58 + i * 6, 15 - (i + 1) * 4, w - 54 + i * 6, 15, 1, 1, p);
      }
      p.setStyle(Paint.Style.STROKE);
      p.setStrokeWidth(1.2f);
      p.setColor(MUTED);
      c.drawRoundRect(w - 31, 3, w - 3, 16, 2, 2, p);
      c.drawLine(w - 1, 7, w - 1, 12, p);
      p.setStyle(Paint.Style.FILL);
      if (d.battery >= 0) {
        p.setColor(d.battery < 10 ? 0xffff5252 : 0xff32d367);
        c.drawRoundRect(w - 28, 6, w - 28 + Math.max(2, 22 * d.battery / 100f), 13, 1, 1, p);
      }
      c.restore();
    }
  }
}
