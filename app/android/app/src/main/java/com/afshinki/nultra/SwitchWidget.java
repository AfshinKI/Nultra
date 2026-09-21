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
  public void onAppWidgetOptionsChanged(Context context, AppWidgetManager manager, int id, android.os.Bundle options) {
    update(context, id, context.getSharedPreferences("widgets", 0).getString("status:" + id, "Tap Off or On"));
  }

  @Override
  public void onDeleted(Context context, int[] ids) {
    SharedPreferences.Editor edit = context.getSharedPreferences("widgets", 0).edit();
    for (int id : ids) edit.remove("target:" + id).remove("name:" + id).remove("status:" + id);
    edit.apply();
  }

  static void refresh(Context context) {
    AppWidgetManager manager = AppWidgetManager.getInstance(context);
    for (int id : manager.getAppWidgetIds(new ComponentName(context, SwitchWidget.class)))
      update(context, id, context.getSharedPreferences("widgets", 0).getString("status:" + id, "Tap Off or On"));
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
    String name = prefs.getString("name:" + id, "All switches");
    if (target.startsWith("scene:")) name = Scenes.load(context).stream().filter(s -> s.target().equals(target)).map(s -> s.name).findFirst().orElse("Scene removed");
    String state = WidgetReadings.state(context, target);
    views.setTextViewText(R.id.widget_title, name + " · " + state);
    views.setTextViewText(R.id.widget_status, message);
    prefs.edit().putString("status:" + id, message).apply();
    int height = AppWidgetManager.getInstance(context).getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 56);
    views.setViewVisibility(R.id.widget_status, height >= 100 ? android.view.View.VISIBLE : android.view.View.GONE);
    views.setContentDescription(R.id.widget_title, name + ". Last reported " + state + ". " + message);
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
