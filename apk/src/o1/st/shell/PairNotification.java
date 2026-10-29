package o1.st.shell;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.RemoteInput;
import android.content.Context;
import android.content.Intent;
import android.graphics.drawable.Icon;
import android.os.Build;

/**
 * Pairing-code entry through a notification with RemoteInput.
 *
 * A settings screen hides overlays (HIDE_OVERLAY_WINDOWS), so the code has to
 * be typed from the notification shade: pulling it down does not close the
 * system pairing dialog, so the code stays valid.
 */
public final class PairNotification {

    public static final String CHANNEL = "o1p_pair";
    public static final int ID = 0x1F0001;

    private PairNotification() {
    }

    private static Notification.Builder builder(Context ctx) {
        NotificationManager nm =
                (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm != null) {
            NotificationChannel ch = new NotificationChannel(
                    CHANNEL, "配对", NotificationManager.IMPORTANCE_HIGH);
            ch.setShowBadge(true);
            nm.createNotificationChannel(ch);
            return new Notification.Builder(ctx, CHANNEL);
        }
        return new Notification.Builder(ctx);
    }

    /** Ask for the code: notification with an inline reply action. */
    public static void show(Context ctx) {
        NotificationManager nm =
                (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) {
            return;
        }

        RemoteInput ri = new RemoteInput.Builder(PairReceiver.KEY)
                .setLabel("6 位配对码")
                .build();

        Intent i = new Intent(ctx, PairReceiver.class);
        i.setAction(PairReceiver.ACTION);
        i.setPackage(ctx.getPackageName());
        PendingIntent pi = PendingIntent.getBroadcast(
                ctx, 0, i,
                PendingIntent.FLAG_UPDATE_CURRENT
                        | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                        ? PendingIntent.FLAG_MUTABLE : 0));

        Notification.Action action = new Notification.Action.Builder(
                Icon.createWithResource(ctx, android.R.drawable.ic_menu_send),
                "输入配对码", pi)
                .addRemoteInput(ri)
                .setAllowGeneratedReplies(true)
                .build();

        Notification.Builder b = builder(ctx)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("o1p：输入无线调试配对码")
                .setContentText("展开通知，在「输入配对码」里填 6 位数字")
                .addAction(action)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(true);

        try {
            b.setStyle(new Notification.BigTextStyle().bigText(
                    "① 打开「开发者选项 → 无线调试 → 使用配对码配对设备」\n"
                            + "② 下拉通知栏，展开这条通知，点「输入配对码」\n"
                            + "③ 填入 6 位数字并发送（30 秒内）"));
        } catch (Throwable ignored) {
        }

        try {
            nm.notify(ID, b.build());
        } catch (Throwable ignored) {
        }
    }

    /** Visible feedback for every step of the bootstrap. */
    public static void update(Context ctx, String status) {
        try {
            NotificationManager nm =
                    (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) {
                return;
            }
            Notification.Builder b = builder(ctx)
                    .setSmallIcon(android.R.drawable.stat_sys_download_done)
                    .setContentTitle("o1p：" + status)
                    .setContentText(status)
                    .setOngoing(false)
                    .setAutoCancel(true);
            nm.notify(ID + 1, b.build());
        } catch (Throwable ignored) {
        }
    }

    public static void hide(Context ctx) {
        try {
            NotificationManager nm =
                    (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) {
                nm.cancel(ID);
            }
        } catch (Throwable ignored) {
        }
    }
}
