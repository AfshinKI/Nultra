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
import org.json.*;

@SuppressLint(
    "MissingPermission") // All entry points require foreground runtime grants; security failures
// close sessions.
final class BleStore {
  static final class Device {
    final String address;
    String name = "", firmware = "";
    Boolean power;
    int battery = -1, rssi = -100;
    long seen = -1, signalAt = -1;
    boolean attempted;

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
            cancelAll("Bluetooth is off.");
            message = "Turn on Bluetooth to listen for switches.";
            notifyUI();
          }
        }
      };

  BleStore(Context c) {
    context = c.getApplicationContext();
    credentials = new CredentialStore(context);
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
        if (!d.name.isEmpty()) devices.put(a, d);
      }
    } catch (JSONException ignored) {
      message = "Saved switch list could not be read. Rediscover your switches.";
    }
  }

  void notifyUI() {
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
  }

  void pause() {
    if (!foreground) return;
    foreground = false;
    context.unregisterReceiver(radio);
    main.removeCallbacks(tick);
    stopScan();
    cancelAll("Operation interrupted when Nultra left the foreground.");
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
        d.power = state[0] == 1;
        d.battery = state[1];
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
    return sessions.containsKey(d.address) || queue.containsKey(d.address);
  }

  boolean anyBusy() {
    return !sessions.isEmpty() || !queue.isEmpty();
  }

  void enqueue(Device d, Transaction t) {
    if (busy(d)) return;
    queue.put(d.address, t);
    pump();
    notifyUI();
  }

  void pump() {
    if (!foreground || demo || !permissions() || adapter == null || !adapter.isEnabled()) return;
    while (sessions.size() < 3 && !queue.isEmpty()) {
      String address = queue.keySet().iterator().next();
      Transaction t = queue.remove(address);
      Session s = new Session(devices.get(address), t);
      sessions.put(address, s);
      s.start();
    }
  }

  void power(Device d, boolean on) {
    if (demo) {
      d.power = on;
      notifyUI();
      return;
    }
    if (!ready() || busy(d)) return;
    enqueue(d, new Transaction(Transaction.Kind.POWER, on, null));
  }

  void rename(Device d, String n) {
    Protocol.ascii(n);
    if (demo) {
      d.name = n;
      notifyUI();
      return;
    }
    if (!ready() || busy(d)) return;
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

  void all(boolean on) {
    if (anyBusy()) return;
    List<Device> list = visible();
    if (demo) {
      for (Device d : list) d.power = on;
      notifyUI();
      return;
    }
    if (!ready() || list.isEmpty()) return;
    bulkRemaining = list.size();
    bulkFailed = 0;
    message = "";
    for (Device d : list) queue.put(d.address, new Transaction(Transaction.Kind.POWER, on, null));
    pump();
    notifyUI();
  }

  void cancelAll(String reason) {
    queue.clear();
    bulkRemaining = 0;
    for (Session s : new ArrayList<>(sessions.values())) s.apply(s.t.fail(reason));
    notifyUI();
  }

  void retry() {
    for (Device d : devices.values()) if (d.name.isEmpty()) d.attempted = false;
    stopScan();
    startScan();
  }

  void demo(boolean enabled) {
    if (demo == enabled) return;
    stopScan();
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
    }
    notifyUI();
  }

  final class Session {
    final Device d;
    final Transaction t;
    BluetoothGatt gatt;
    BluetoothGattCharacteristic password, target;
    byte[] credential;
    final Runnable timeout;
    final Runnable cleanup = () -> closed();

    Session(Device d, Transaction t) {
      this.d = d;
      this.t = t;
      timeout = () -> apply(this.t.fail("Switch timed out."));
    }

    void start() {
      try {
        credential = Protocol.ascii(credentials.get(d.address));
        main.postDelayed(timeout, 8000);
        gatt =
            adapter
                .getRemoteDevice(d.address)
                .connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE);
        if (gatt == null) apply(t.fail("Connection could not start."));
      } catch (Exception e) {
        apply(t.fail("Connection or saved password unavailable. Check Menu settings."));
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
      t.disconnected();
      if (gatt != null)
        try {
          gatt.close();
        } catch (RuntimeException ignored) {
        }
      sessions.remove(d.address);
      credential = null;
      if (!demo && devices.get(d.address) == d) {
        if (t.error == null) {
          if (t.identity != null) {
            d.name = t.identity.name;
            d.firmware = t.identity.firmware;
            save();
          }
          if (t.power != null) d.power = t.power;
        } else message = (d.name.isEmpty() ? "New switch" : d.name) + ": " + t.error;
        if (bulkRemaining > 0 && t.kind == Transaction.Kind.POWER) {
          if (t.error != null) bulkFailed++;
          bulkRemaining--;
          if (bulkRemaining == 0)
            message =
                bulkFailed == 0
                    ? "All switches confirmed."
                    : bulkFailed + " switches could not be changed.";
        }
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
