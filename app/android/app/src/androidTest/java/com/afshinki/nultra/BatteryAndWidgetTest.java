package com.afshinki.nultra;

import static org.junit.Assert.*;
import android.Manifest;
import android.app.*;
import android.appwidget.*;
import android.content.*;
import android.os.*;
import android.widget.*;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.FileInputStream;
import org.junit.Test;

public class BatteryAndWidgetTest {
  @Test public void notificationSuppressesJitterAcrossInstances() throws Exception {
    assertTrue(Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk"));
    Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
    Context context = instrumentation.getTargetContext();
    if (Build.VERSION.SDK_INT >= 33) {
      try (ParcelFileDescriptor command = instrumentation.getUiAutomation().executeShellCommand("pm grant " + context.getPackageName() + " " + Manifest.permission.POST_NOTIFICATIONS);
           FileInputStream stream = new FileInputStream(command.getFileDescriptor())) {
        while (stream.read() != -1) {}
      }
    }
    context.getSharedPreferences("battery-alerts", 0).edit().clear().commit();
    NotificationManager manager = context.getSystemService(NotificationManager.class);
    manager.cancelAll();
    BatteryNotifications notifications = new BatteryNotifications(context);
    assertEquals(5, notifications.threshold());
    notifications.save(true, 5);
    BleStore.Device light = new BleStore.Device("AA:BB:CC:DD:EE:99");
    light.name = "TESTLAMP";
    light.battery = 5;
    notifications.observe(light);
    Thread.sleep(500);
    assertEquals(1, manager.getActiveNotifications().length);
    manager.cancelAll();
    notifications = new BatteryNotifications(context);
    for (int battery : new int[] {4, 7, 3, 8, 5, 0, 14}) {
      light.battery = battery;
      notifications.observe(light);
    }
    Thread.sleep(250);
    assertEquals(0, manager.getActiveNotifications().length);
    light.battery = 15;
    notifications.observe(light);
    light.battery = 5;
    notifications.observe(light);
    Thread.sleep(500);
    assertEquals(1, manager.getActiveNotifications().length);
    manager.cancelAll();
    notifications.save(false, 5);
    context.getSharedPreferences("battery-alerts", 0).edit().clear().commit();
  }

  @Test public void compactWidgetFitsTwoByOne() {
    Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
    AppWidgetProviderInfo provider = AppWidgetManager.getInstance(context).getInstalledProviders().stream()
        .filter(p -> p.provider.getClassName().equals(SwitchWidget.class.getName())).findFirst().get();
    if (Build.VERSION.SDK_INT >= 31) {
      assertEquals(2, provider.targetCellWidth);
      assertEquals(1, provider.targetCellHeight);
    }
    InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
      android.view.View view = android.view.LayoutInflater.from(context).inflate(R.layout.switch_widget, null);
      float density = context.getResources().getDisplayMetrics().density;
      view.measure(android.view.View.MeasureSpec.makeMeasureSpec((int)(130 * density), android.view.View.MeasureSpec.EXACTLY), android.view.View.MeasureSpec.makeMeasureSpec((int)(70 * density), android.view.View.MeasureSpec.EXACTLY));
      view.layout(0, 0, view.getMeasuredWidth(), view.getMeasuredHeight());
      for (int id : new int[] {R.id.widget_on, R.id.widget_off}) {
        android.view.View button = view.findViewById(id);
        assertTrue(button.getMeasuredWidth() >= 48 * density);
        assertTrue(button.getMeasuredHeight() >= 40 * density);
      }
    });
  }
}
