package com.afshinki.nultra;

import android.app.*;
import android.appwidget.*;
import android.content.*;
import android.net.Uri;
import android.widget.RemoteViews;

public final class SwitchWidget extends AppWidgetProvider {
  @Override
  public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
    for (int id : ids) update(context, id, "Tap Off or On");
  }

  @Override
  public void onDeleted(Context context, int[] ids) {
    SharedPreferences.Editor edit = context.getSharedPreferences("widgets", 0).edit();
    for (int id : ids) edit.remove("target:" + id).remove("name:" + id);
    edit.apply();
  }

  static void status(Context context, String message) {
    AppWidgetManager manager = AppWidgetManager.getInstance(context);
    for (int id : manager.getAppWidgetIds(new ComponentName(context, SwitchWidget.class)))
      update(context, id, message);
  }

  static void update(Context context, int id, String message) {
    SharedPreferences prefs = context.getSharedPreferences("widgets", 0);
    String target = prefs.getString("target:" + id, "*");
    RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.switch_widget);
    views.setTextViewText(R.id.widget_title, prefs.getString("name:" + id, "All switches"));
    views.setTextViewText(R.id.widget_status, message);
    for (boolean on : new boolean[] {false, true}) {
      Intent intent =
          new Intent(context, CommandService.class)
              .setData(Uri.parse("nultra-widget://action/" + id + "/" + (on ? "on" : "off")))
              .putExtra("target", target)
              .putExtra("on", on);
      views.setOnClickPendingIntent(
          on ? R.id.widget_on : R.id.widget_off,
          PendingIntent.getForegroundService(
              context,
              id,
              intent,
              PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
    }
    AppWidgetManager.getInstance(context).updateAppWidget(id, views);
  }
}
