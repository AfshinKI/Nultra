package com.afshinki.nultra;

import android.Manifest;
import android.annotation.SuppressLint;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.os.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

@SuppressLint(
    "MissingPermission") // All entry points require foreground runtime grants; security failures
// close sessions.
final class BleStore {
  private static BleStore instance;

  static synchronized BleStore get(Context context) {
    if (instance == null) instance = new BleStore(context);
    return instance;
  }

  static final int CONNECTION_LIMIT = 6;
  final List<Scenes.Scene> demoScenes = new ArrayList<>();
  List<Scenes.Scene> scenes() { return demo ? new ArrayList<>(demoScenes) : Scenes.load(context); }
  void saveScene(Scenes.Scene value) {
    List<Scenes.Scene> all = scenes();
    int index = -1;
    for (int i = 0; i < all.size(); i++) if (all.get(i).id.equals(value.id)) index = i;
    if (index >= 0) all.set(index, value); else all.add(value);
    persistScenes(all);
  }
  void deleteScene(String id) {
    List<Scenes.Scene> all = scenes(); all.removeIf(s -> s.id.equals(id)); persistScenes(all);
  }
  void persistScenes(List<Scenes.Scene> all) {
    if (demo) { demoScenes.clear(); demoScenes.addAll(all); }
    else { Scenes.save(context, all); SwitchWidget.refresh(context); }
    notifyUI();
  }
  List<Device> targets(String target) {
    List<Device> list = visible();
    if (target.startsWith("scene:")) {
      Scenes.Scene scene = scenes().stream().filter(s -> s.target().equals(target)).findFirst().orElse(null);
      list.removeIf(d -> scene == null || !scene.members.contains(d.address));
    } else if (!target.equals("*")) list.removeIf(d -> !d.address.equals(target));
    return list;
  }
  String connectionSummary() { return (sessions.size() + remote.size()) + " active · " + queue.size() + " queued · limit " + CONNECTION_LIMIT; }
  final ServerSettings server;
  final BatteryNotifications batteryAlerts;
  final ExecutorService network = Executors.newFixedThreadPool(CONNECTION_LIMIT);
  final Map<String, Remote> remote = new LinkedHashMap<>();
  List<ServerClient.Row> serverRows = new ArrayList<>();
  long serverSeen = -1;
  String serverStatus = "Not checked";
  ServerClient pollClient;
  Future<?> pollFuture;
  int generation;
  boolean backgroundCommand;
  java.util.function.Consumer<String> completion;
  int bulkQueued;
  final Runnable poll = () -> checkServer();
  final Runnable pollTimeout = () -> finishPollTimeout();

  boolean bluetoothReady() {
    try {
      return adapter != null
          && (Build.VERSION.SDK_INT < 31
              || context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
                  == PackageManager.PERMISSION_GRANTED)
          && adapter.isEnabled();
    } catch (SecurityException e) {
      return false;
    }
  }

  boolean online(Device d) {
    if (d.online(SystemClock.elapsedRealtime())) return true;
    if (!server.enabled()
        || demo
        || serverSeen < 0
        || SystemClock.elapsedRealtime() - serverSeen >= 30000) return false;
    try {
      match(d, serverRows);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  ServerClient.Row match(Device d, List<ServerClient.Row> rows) throws java.io.IOException {
    long same = visible().stream().filter(x -> x.name.equals(d.name)).count();
    return ServerClient.resolve(d.address, d.name, server.mapping(d.address), same == 1, rows);
  }

  void applyBackgroundRows(List<ServerClient.Row> rows) {
    serverRows = rows; serverSeen = SystemClock.elapsedRealtime();
    for (Device d : visible()) try {
      if (d.online(SystemClock.elapsedRealtime()) || busy(d)) continue;
      ServerClient.Row row = match(d, rows);
      d.power = row.power; d.battery = row.battery; d.serverReported = true;
      d.reportedAt = System.currentTimeMillis(); batteryAlerts.observe(d);
    } catch (Exception ignored) { }
    notifyUI();
  }

  void serverChanged() {
    BackgroundRefresh.schedule(context);
    generation++;
    cancelPoll();
    for (Remote r : new ArrayList<>(remote.values())) r.finish("Server settings changed.", false);
    serverRows.clear();
    serverSeen = -1;
    serverStatus = "Not checked";
    if (foreground && !demo) checkServer();
    notifyUI();
  }

  void cancelPoll() {
    main.removeCallbacks(poll);
    main.removeCallbacks(pollTimeout);
    if (pollFuture != null) pollFuture.cancel(true);
    if (pollClient != null) pollClient.cancel();
    pollClient = null;
    pollFuture = null;
  }

  void finishPollTimeout() {
    cancelPoll();
    serverSeen = -1;
    serverStatus = "Server check timed out.";
    notifyUI();
    schedulePoll();
  }

  void schedulePoll() {
    main.removeCallbacks(poll);
    if (foreground && !demo && server.enabled()) main.postDelayed(poll, 15000);
  }

  void checkServer() {
    if (!foreground || demo || !server.enabled() || pollClient != null) return;
    if (anyBusy()) {
      schedulePoll();
      return;
    }
    final ServerClient client = new ServerClient(server.url(), credentials);
    pollClient = client;
    serverStatus = "Checking server…";
    main.postDelayed(pollTimeout, 8000);
    pollFuture =
        network.submit(
            () -> {
              List<ServerClient.Row> rows = null;
              String error = null;
              try {
                rows = client.devices();
              } catch (Exception e) {
                error = "Server unavailable. Check address and network.";
              }
              final List<ServerClient.Row> result = rows;
              final String failure = error;
              main.post(
                  () -> {
                    if (pollClient != client) return;
                    main.removeCallbacks(pollTimeout);
                    pollClient = null;
                    pollFuture = null;
                    if (failure != null) {
                      serverSeen = -1;
                      serverStatus = failure;
                    } else {
                      serverRows = result;
                      serverSeen = SystemClock.elapsedRealtime();
                      serverStatus = result.size() + " server switches loaded";
                      for (Device d : visible())
                        try {
                          ServerClient.Row row = match(d, result);
                          if (server.mapping(d.address) == null) server.map(d.address, row.address);
                          if (!d.online(SystemClock.elapsedRealtime()) && !busy(d)) {
                            d.reportedAt = System.currentTimeMillis();
                            d.power = row.power;
                            d.battery = row.battery;
                            batteryAlerts.observe(d);
                            d.serverReported = true;
                          }
                        } catch (Exception ignored) {
                        }
                    }
                    notifyUI();
                    schedulePoll();
                  });
            });
  }

  void remotePower(Device d, Transaction t) {
    Remote r = new Remote(d, t);
    remote.put(d.address, r);
    r.start();
  }

  final class Remote {
    final Device d;
    final Transaction t;
    final ServerClient client;
    final String pinned;
    final boolean unique;
    final int epoch;
    Future<?> future;
    final Runnable timeout =
        () -> finish("Server timed out; command may already be queued.", false);

    Remote(Device d, Transaction t) {
      this.d = d;
      this.t = t;
      client = new ServerClient(server.url(), credentials);
      pinned = server.mapping(d.address);
      unique = visible().stream().filter(x -> x.name.equals(d.name)).count() == 1;
      epoch = generation;
    }

    void start() {
      main.postDelayed(timeout, 8000);
      future =
          network.submit(
              () -> {
                String error = null;
                ServerClient.Row row = null;
                try {
                  row = ServerClient.resolve(d.address, d.name, pinned, unique, client.devices());
                  client.power(row.address, t.target);
                } catch (Exception e) {
                  error =
                      e instanceof java.io.IOException
                          ? (e.getMessage() == null ? "Server request failed." : e.getMessage())
                          : "Invalid server response.";
                }
                final String failure = error;
                final ServerClient.Row selected = row;
                main.post(
                    () -> {
                      if (remote.get(d.address) != this || epoch != generation) return;
                      if (selected != null && pinned == null)
                        server.map(d.address, selected.address);
                      finish(failure, failure == null);
                    });
              });
    }

    void finish(String error, boolean queued) {
      if (remote.remove(d.address) != this) return;
      main.removeCallbacks(timeout);
      client.cancel();
      if (future != null) future.cancel(true);
      message = d.name + (queued ? ": queued by server; awaiting reported state." : ": " + error);
      finishPower(error, queued);
      pump();
      notifyUI();
    }
  }

  void finishPower(String error, boolean queued) {
    if (bulkRemaining > 0) {
      if (error != null) bulkFailed++;
      if (queued) bulkQueued++;
      if (--bulkRemaining == 0)
        message =
            bulkFailed > 0
                ? bulkFailed + " switches failed; " + bulkQueued + " queued by server."
                : bulkQueued > 0
                    ? bulkQueued + " queued by server; other switches confirmed over Bluetooth."
                    : "All switches confirmed.";
    }
    if (backgroundCommand && bulkRemaining == 0 && !anyBusy()) {
      java.util.function.Consumer<String> done = completion;
      completion = null;
      backgroundCommand = false;
      schedulePoll();
      if (done != null) done.accept(message);
    }
  }

  boolean backgroundPower(String address, boolean on, java.util.function.Consumer<String> done) {
    if (demo || anyBusy() || backgroundCommand) return false;
    List<Device> list = targets(address);
    if (list.isEmpty()) return false;
    cancelPoll();
    backgroundCommand = true;
    completion = done;
    bulkRemaining = list.size();
    bulkFailed = 0;
    bulkQueued = 0;
    for (Device d : list) queue.put(d.address, new Transaction(Transaction.Kind.POWER, on, null));
    pump();
    return true;
  }

  void cancelBackground() {
    if (!backgroundCommand) return;
    backgroundCommand = false;
    completion = null;
    cancelAll("Background action timed out or stopped.");
  }

  static final class Device {
    final String address;
    String name = "", firmware = "";
    Boolean power;
    int battery = -1, rssi = -100;
    long seen = -1, signalAt = -1, reportedAt;
    boolean attempted, serverReported;

    Device(String a) {
      address = a;
    }

    boolean online(long now) {
      return seen >= 0 && now - seen < 15_000;
    }
  }

  interface Listener {
    void changed();
  }

  final Context context;
  final CredentialStore credentials;
  final LinkedHashMap<String, Device> devices = new LinkedHashMap<>();
  final LinkedHashMap<String, Session> sessions = new LinkedHashMap<>();
  final LinkedHashMap<String, Transaction> queue = new LinkedHashMap<>();
  final Handler main = new Handler(Looper.getMainLooper());
  Listener listener;
  BluetoothAdapter adapter;
  BluetoothLeScanner scanner;
  boolean foreground, scanning, demo;
  long scanStartedNanos;
  String message = "";
  int bulkRemaining, bulkFailed;
  final Runnable tick =
      new Runnable() {
        public void run() {
          if (foreground) {
            if (demo)
              for (Device d : devices.values())
                if (d.seen >= 0) d.seen = SystemClock.elapsedRealtime();
            notifyUI();
            main.postDelayed(this, 2000);
          }
        }
      };
  final BroadcastReceiver radio =
      new BroadcastReceiver() {
        public void onReceive(Context c, Intent i) {
          if (permissions() && adapter != null && adapter.isEnabled()) startScan();
          else {
            stopScan();
            for (Session session : new ArrayList<>(sessions.values()))
              session.apply(session.t.fail("Bluetooth is off."));
            pump();
            message = "Turn on Bluetooth to listen for switches.";
            notifyUI();
          }
        }
      };

  BleStore(Context c) {
    context = c.getApplicationContext();
    credentials = new CredentialStore(context);
    server = new ServerSettings(context);
    batteryAlerts = new BatteryNotifications(context);
    BluetoothManager manager = context.getSystemService(BluetoothManager.class);
    adapter = manager == null ? null : manager.getAdapter();
    try {
      JSONArray saved =
          new JSONArray(context.getSharedPreferences("switches", 0).getString("catalog", "[]"));
      for (int i = 0; i < saved.length(); i++) {
        JSONObject j = saved.getJSONObject(i);
        String a = j.getString("address");
        if (!BluetoothAdapter.checkBluetoothAddress(a)) continue;
        Device d = new Device(a);
        d.name = j.getString("name");
        d.firmware = j.optString("firmware");
        WidgetReadings.restore(context, d);
        if (!d.name.isEmpty()) devices.put(a, d);
      }
    } catch (JSONException ignored) {
      message = "Saved switch list could not be read. Rediscover your switches.";
    }
  }

  void notifyUI() {
    if (!demo) WidgetReadings.save(context, visible());
    if (listener != null) listener.changed();
  }

  void save() {
    JSONArray a = new JSONArray();
    for (Device d : devices.values())
      if (!d.name.isEmpty())
        try {
          a.put(
              new JSONObject()
                  .put("address", d.address)
                  .put("name", d.name)
                  .put("firmware", d.firmware));
        } catch (JSONException ignored) {
        }
    context.getSharedPreferences("switches", 0).edit().putString("catalog", a.toString()).apply();
  }

  boolean permissions() {
    if (Build.VERSION.SDK_INT >= 31)
      return context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)
              == PackageManager.PERMISSION_GRANTED
          && context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
              == PackageManager.PERMISSION_GRANTED;
    return context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        == PackageManager.PERMISSION_GRANTED;
  }

  void resume() {
    if (foreground) return;
    foreground = true;
    context.registerReceiver(radio, new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED));
    startScan();
    main.post(tick);
    checkServer();
  }

  void pause() {
    if (!foreground) return;
    foreground = false;
    context.unregisterReceiver(radio);
    main.removeCallbacks(tick);
    stopScan();
    cancelPoll();
    if (!backgroundCommand) cancelAll("Operation interrupted when Nultra left the foreground.");
    for (Device d : devices.values()) d.seen = -1;
  }

  void startScan() {
    if (!foreground || demo || scanning) return;
    if (!permissions()) {
      message = "Allow Nearby devices to discover switches.";
      notifyUI();
      return;
    }
    if (adapter == null || !adapter.isEnabled()) {
      message = "Turn on Bluetooth to listen for switches.";
      notifyUI();
      return;
    }
    if (Build.VERSION.SDK_INT < 31) {
      LocationManager lm = context.getSystemService(LocationManager.class);
      if (lm != null
          && !lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
          && !lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
        message = "Enable system Location for Bluetooth scanning on this Android version.";
        notifyUI();
        return;
      }
    }
    try {
      scanner = adapter.getBluetoothLeScanner();
      if (scanner == null) throw new IllegalStateException();
      scanStartedNanos = SystemClock.elapsedRealtimeNanos();
      scanner.startScan(
          null,
          new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),
          scan);
      scanning = true;
      message = "";
    } catch (RuntimeException e) {
      message = "Bluetooth scanning could not start. Check permissions and Bluetooth, then retry.";
      scanning = false;
    }
    notifyUI();
  }

  void stopScan() {
    if (scanner != null && scanning)
      try {
        scanner.stopScan(scan);
      } catch (RuntimeException ignored) {
      }
    scanning = false;
  }

  final ScanCallback scan =
      new ScanCallback() {
        @Override
        public void onScanResult(int type, ScanResult result) {
          main.post(() -> observe(result));
        }

        @Override
        public void onBatchScanResults(List<ScanResult> results) {
          main.post(
              () -> {
                for (ScanResult r : results) observe(r);
              });
        }

        @Override
        public void onScanFailed(int code) {
          main.post(
              () -> {
                scanning = false;
                for (Device d : devices.values()) d.seen = -1;
                message = "Scan stopped (" + code + "). Use Retry discovery in Menu.";
                notifyUI();
              });
        }
      };

  void observe(ScanResult result) {
    if (!foreground || demo || !scanning || result.getTimestampNanos() < scanStartedNanos) return;
    ScanRecord record = result.getScanRecord();
    String advertised = record == null ? null : record.getDeviceName();
    String address = result.getDevice().getAddress();
    Device d = devices.get(address);
    boolean match = advertised != null && advertised.contains("Nultra");
    if (record != null && record.getServiceUuids() != null)
      match |= record.getServiceUuids().contains(new ParcelUuid(Protocol.SERVICE));
    if (d == null && !match) return;
    if (d == null) {
      d = new Device(address);
      devices.put(address, d);
    }
    long now = SystemClock.elapsedRealtime();
    d.seen = now;
    if (d.signalAt < 0 || now - d.signalAt >= 5000) {
      d.rssi = result.getRssi();
      d.signalAt = now;
    }
    if (!sessions.containsKey(address)) {
      int[] state = Protocol.advertisement(advertised);
      if (state != null) {
        d.serverReported = false;
        d.reportedAt = System.currentTimeMillis();
        d.power = state[0] == 1;
        d.battery = state[1];
        if (!demo) batteryAlerts.observe(d);
      }
    }
    if (d.name.isEmpty() && !d.attempted && bulkRemaining == 0) {
      d.attempted = true;
      enqueue(d, new Transaction(Transaction.Kind.IDENTIFY, false, null));
    }
  }

  List<Device> visible() {
    List<Device> list = new ArrayList<>();
    for (Device d : devices.values()) if (!d.name.isEmpty()) list.add(d);
    list.sort(Comparator.comparing(d -> d.name));
    return list;
  }

  boolean busy(Device d) {
    return sessions.containsKey(d.address)
        || queue.containsKey(d.address)
        || remote.containsKey(d.address);
  }

  boolean anyBusy() {
    return !sessions.isEmpty() || !queue.isEmpty() || !remote.isEmpty();
  }

  void enqueue(Device d, Transaction t) {
    if (busy(d)) return;
    queue.put(d.address, t);
    pump();
    notifyUI();
  }

  void pump() {
    if ((!foreground && !backgroundCommand) || demo) return;
    while (sessions.size() + remote.size() < CONNECTION_LIMIT && !queue.isEmpty()) {
      String address = queue.keySet().iterator().next();
      Transaction t = queue.remove(address);
      Device d = devices.get(address);
      if (t.kind == Transaction.Kind.POWER
          && server.enabled()
          && (!bluetoothReady()
              || (!backgroundCommand && !d.online(SystemClock.elapsedRealtime())))) {
        remotePower(d, t);
      } else if (bluetoothReady()) {
        Session session = new Session(d, t);
        sessions.put(address, session);
        session.start();
      } else {
        message = "Bluetooth unavailable. Enable Bluetooth or configure a backup server.";
        if (t.kind == Transaction.Kind.POWER) finishPower(message, false);
      }
    }
  }

  void power(Device d, boolean on) {
    if (demo) {
      d.power = on;
      notifyUI();
      return;
    }
    if (!foreground || backgroundCommand || busy(d)) return;
    enqueue(d, new Transaction(Transaction.Kind.POWER, on, null));
  }

  void rename(Device d, String n) {
    Protocol.ascii(n);
    if (demo) {
      d.name = n;
      notifyUI();
      return;
    }
    if (backgroundCommand || !ready() || busy(d)) return;
    enqueue(d, new Transaction(Transaction.Kind.RENAME, false, n));
  }

  boolean ready() {
    if (!foreground || !permissions() || adapter == null || !adapter.isEnabled()) {
      message = "Open Nultra with Bluetooth enabled and permissions allowed.";
      notifyUI();
      return false;
    }
    return true;
  }

  void all(boolean on) { group("*", on); }

  void group(String target, boolean on) {
    if (anyBusy()) return;
    List<Device> list = targets(target);
    if (demo) {
      for (Device d : list) d.power = on;
      notifyUI();
      return;
    }
    if ((!foreground && !backgroundCommand) || list.isEmpty()) return;
    bulkRemaining = list.size();
    bulkFailed = 0;
    bulkQueued = 0;
    message = "";
    for (Device d : list) queue.put(d.address, new Transaction(Transaction.Kind.POWER, on, null));
    pump();
    notifyUI();
  }

  void cancelAll(String reason) {
    queue.clear();
    bulkRemaining = 0;
    for (Session s : new ArrayList<>(sessions.values())) {
      s.cancelled = true;
      s.apply(s.t.fail(reason));
      s.closed();
    }
    for (Remote r : new ArrayList<>(remote.values())) r.finish(reason, false);
    notifyUI();
  }

  void retry() {
    for (Device d : devices.values()) if (d.name.isEmpty()) d.attempted = false;
    stopScan();
    startScan();
  }

  void demo(boolean enabled) {
    if (demo == enabled) return;
    demoScenes.clear();
    stopScan();
    cancelPoll();
    cancelBackground();
    cancelAll("Mode changed.");
    demo = enabled;
    // Real devices stay intact in storage; demo never writes the catalog.
    devices.clear();
    if (enabled) {
      String[] names = {"BEDROOM1", "CORNER01", "DESKLAMP", "HALLWAY1", "KITCHEN1", "SHELFLED"};
      for (int i = 0; i < names.length; i++) {
        Device d = new Device("demo" + i);
        d.name = names[i];
        d.power = i > 1;
        d.battery = i == 3 ? 7 : 92 - i * 5;
        d.rssi = -50 - i * 7;
        d.seen = i == 3 ? -1 : SystemClock.elapsedRealtime();
        devices.put(d.address, d);
      }
      message = "DEMO · No physical switches controlled";
    } else {
      BleStore restored = new BleStore(context);
      devices.putAll(restored.devices);
      message = "";
      startScan();
      checkServer();
    }
    notifyUI();
  }

  final class Session {
    final Device d;
    final Transaction t;
    BluetoothGatt gatt;
    BluetoothGattCharacteristic password, target;
    byte[] credential;
    boolean cancelled;
    final Runnable connectTimeout;
    final Runnable timeout;
    final Runnable cleanup = () -> closed();

    Session(Device d, Transaction t) {
      this.d = d;
      this.t = t;
      connectTimeout =
          () -> {
            if (this.t.stage == Transaction.Stage.CONNECT) apply(this.t.fail("Switch not nearby."));
          };
      timeout = () -> apply(this.t.fail("Switch timed out."));
    }

    void start() {
      try {
        credential = Protocol.ascii(credentials.get(d.address));
        main.postDelayed(timeout, d.name.isEmpty() && !backgroundCommand ? 60000 : 8000);
        if (backgroundCommand && server.enabled()) main.postDelayed(connectTimeout, 2000);
        gatt =
            adapter
                .getRemoteDevice(d.address)
                .connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE);
        if (gatt == null) apply(t.fail("Connection could not start."));
      } catch (Exception e) {
        apply(t.fail("Connection or switch password unavailable. Choose this switch in Menu."));
      }
    }

    void apply(Transaction.Effect effect) {
      if (sessions.get(d.address) != this) return;
      try {
        switch (effect) {
          case NONE:
            break;
          case DISCOVER:
            if (!gatt.discoverServices()) apply(t.fail("Service discovery could not start."));
            break;
          case AUTHENTICATE:
            write(password, credential, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);
            break;
          case WRITE:
            write(
                target,
                t.kind == Transaction.Kind.POWER
                    ? new byte[] {(byte) (t.target ? 1 : 0)}
                    : Protocol.ascii(t.rename),
                t.kind == Transaction.Kind.POWER
                    ? BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                    : BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);
            break;
          case READ:
            if (!gatt.readCharacteristic(target)) apply(t.fail("Readback could not start."));
            break;
          case DISCONNECT:
            main.removeCallbacks(timeout);
            main.removeCallbacks(connectTimeout);
            credential = null;
            if (gatt != null) {
              main.postDelayed(cleanup, 1500);
              try {
                gatt.disconnect();
              } catch (RuntimeException e) {
                closed();
              }
            } else closed();
            break;
        }
      } catch (RuntimeException e) {
        apply(t.fail("Bluetooth operation failed."));
      }
    }

    @SuppressWarnings("deprecation")
    void write(BluetoothGattCharacteristic c, byte[] bytes, int type) {
      boolean started;
      if (Build.VERSION.SDK_INT >= 33)
        started = gatt.writeCharacteristic(c, bytes, type) == BluetoothStatusCodes.SUCCESS;
      else {
        c.setWriteType(type);
        c.setValue(bytes);
        started = gatt.writeCharacteristic(c);
      }
      if (!started) apply(t.fail("Write could not start."));
    }

    void closed() {
      if (sessions.get(d.address) != this) return;
      main.removeCallbacks(timeout);
      main.removeCallbacks(cleanup);
      main.removeCallbacks(connectTimeout);
      t.disconnected();
      if (gatt != null)
        try {
          gatt.close();
        } catch (RuntimeException ignored) {
        }
      sessions.remove(d.address);
      credential = null;
      if (!cancelled && !demo && devices.get(d.address) == d) {
        if (t.error != null
            && t.kind == Transaction.Kind.POWER
            && server.enabled()
            && (foreground || backgroundCommand)) {
          remotePower(d, t);
          pump();
          notifyUI();
          return;
        }
        if (t.error == null) {
          if (t.identity != null) {
            d.name = t.identity.name;
            d.firmware = t.identity.firmware;
            save();
            batteryAlerts.observe(d);
          }
          if (t.power != null) {
            d.reportedAt = System.currentTimeMillis();
            d.power = t.power;
            d.serverReported = false;
            message = d.name + ": confirmed.";
          }
        } else message = (d.name.isEmpty() ? "New switch" : d.name) + ": " + t.error;
        if (t.kind == Transaction.Kind.POWER) finishPower(t.error, false);
      }
      pump();
      notifyUI();
    }

    void event(BluetoothGatt source, Runnable action) {
      main.post(
          () -> {
            if (gatt == source && sessions.get(d.address) == this) action.run();
          });
    }

    final BluetoothGattCallback callback =
        new BluetoothGattCallback() {
          @Override
          public void onConnectionStateChange(BluetoothGatt g, int status, int state) {
            event(
                g,
                () -> {
                  if (state == BluetoothProfile.STATE_DISCONNECTED) {
                    closed();
                    return;
                  }
                  if (status != BluetoothGatt.GATT_SUCCESS) {
                    apply(t.fail("Connection failed (" + status + ")."));
                    return;
                  }
                  if (state == BluetoothProfile.STATE_CONNECTED) apply(t.connected());
                });
          }

          @Override
          public void onServicesDiscovered(BluetoothGatt g, int status) {
            event(
                g,
                () -> {
                  if (t.stage != Transaction.Stage.DISCOVER) return;
                  BluetoothGattService service = g.getService(Protocol.SERVICE);
                  if (status != BluetoothGatt.GATT_SUCCESS || service == null) {
                    apply(t.fail("Nultra service not found."));
                    return;
                  }
                  password = service.getCharacteristic(Protocol.PASSWORD);
                  target =
                      service.getCharacteristic(
                          t.kind == Transaction.Kind.POWER ? Protocol.STATE : Protocol.NAME);
                  int required = BluetoothGattCharacteristic.PROPERTY_READ;
                  if (t.kind == Transaction.Kind.POWER)
                    required |= BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE;
                  if (t.kind == Transaction.Kind.RENAME)
                    required |= BluetoothGattCharacteristic.PROPERTY_WRITE;
                  if (password == null
                      || target == null
                      || (password.getProperties() & BluetoothGattCharacteristic.PROPERTY_WRITE)
                          == 0
                      || (target.getProperties() & required) != required) {
                    apply(t.fail("Required switch characteristics unavailable."));
                    return;
                  }
                  apply(t.discovered());
                });
          }

          @Override
          public void onCharacteristicWrite(
              BluetoothGatt g, BluetoothGattCharacteristic c, int status) {
            event(
                g,
                () -> {
                  if ((t.stage == Transaction.Stage.AUTHENTICATE
                          && !c.getUuid().equals(Protocol.PASSWORD))
                      || (t.stage == Transaction.Stage.WRITE
                          && !c.getUuid().equals(target.getUuid()))) return;
                  if (status != BluetoothGatt.GATT_SUCCESS)
                    apply(t.fail("Switch rejected the write."));
                  else apply(t.written());
                });
          }

          @Override
          public void onCharacteristicRead(
              BluetoothGatt g, BluetoothGattCharacteristic c, byte[] value, int status) {
            readEvent(g, c, value.clone(), status);
          }

          @SuppressWarnings("deprecation")
          @Override
          public void onCharacteristicRead(
              BluetoothGatt g, BluetoothGattCharacteristic c, int status) {
            if (Build.VERSION.SDK_INT < 33)
              readEvent(g, c, c.getValue() == null ? new byte[0] : c.getValue().clone(), status);
          }

          void readEvent(BluetoothGatt g, BluetoothGattCharacteristic c, byte[] value, int status) {
            event(
                g,
                () -> {
                  if (target == null || !c.getUuid().equals(target.getUuid())) return;
                  if (status != BluetoothGatt.GATT_SUCCESS) apply(t.fail("Readback failed."));
                  else apply(t.read(value));
                });
          }
        };
  }
}
