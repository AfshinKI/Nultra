package com.afshinki.nultra;

import android.app.*;
import android.appwidget.*;
import android.content.*;
import android.os.Bundle;
import java.util.*;

public final class WidgetConfigurationActivity extends Activity {
  @Override
  public void onCreate(Bundle state) {
    super.onCreate(state);
    setResult(RESULT_CANCELED);
    int id =
        getIntent()
            .getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID);
    AppWidgetProviderInfo info = AppWidgetManager.getInstance(this).getAppWidgetInfo(id);
    if (info == null || !info.provider.equals(new ComponentName(this, SwitchWidget.class))) {
      finish();
      return;
    }
    BleStore store = BleStore.get(this);
    if (store.demo || store.visible().isEmpty()) {
      new AlertDialog.Builder(this)
          .setMessage("Open Nultra and discover your real switches before adding a widget.")
          .setPositiveButton("Done", (d, w) -> finish())
          .setOnCancelListener(d -> finish())
          .show();
      return;
    }
    List<BleStore.Device> devices = store.visible();
    List<Scenes.Scene> scenes = store.scenes();
    String[] names = new String[devices.size() + scenes.size() + 1];
    names[0] = "All switches";
    for (int i = 0; i < devices.size(); i++) names[i + 1] = devices.get(i).name;
    for (int i = 0; i < scenes.size(); i++) names[devices.size() + i + 1] = "Scene · " + scenes.get(i).name;
    new AlertDialog.Builder(this)
        .setTitle("Nultra background controls")
        .setItems(
            names,
            (d, index) -> {
              getSharedPreferences("widgets", 0)
                  .edit()
                  .putString("target:" + id, index == 0 ? "*" : index <= devices.size() ? devices.get(index - 1).address : scenes.get(index - devices.size() - 1).target())
                  .putString("name:" + id, names[index])
                  .apply();
              SwitchWidget.update(this, id, "Tap Off or On");
              setResult(RESULT_OK, new Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id));
              finish();
            })
        .setOnCancelListener(d -> finish())
        .show();
  }
}
