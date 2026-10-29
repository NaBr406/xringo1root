package o1.st.shell;

import android.app.RemoteInput;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.Charset;

/**
 * Receives the pairing code typed into the notification, and runs the whole
 * bootstrap here so it does not depend on the activity still being alive.
 *
 * Every step gives visible feedback: a Toast immediately, then notification
 * updates and a log file.
 */
public class PairReceiver extends BroadcastReceiver {

    public static final String ACTION = "o1.st.shell.PAIR_CODE";
    public static final String KEY = "pair_code";
    private static final String TAG = "o1p-pair";

    @Override
    public void onReceive(final Context ctx, Intent intent) {
        Bundle results = RemoteInput.getResultsFromIntent(intent);
        String code = "";
        if (results != null) {
            CharSequence cs = results.getCharSequence(KEY);
            if (cs != null) {
                code = cs.toString().trim();
            }
        }

        if (code.isEmpty()) {
            toast(ctx, "没读到配对码");
            PairNotification.update(ctx, "没读到配对码，请重新输入");
            return;
        }

        // bring the app forward so the user can watch the progress
        try {
            Intent fg = new Intent(ctx, MainActivity.class);
            fg.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            ctx.startActivity(fg);
        } catch (Throwable ignored) {
        }
        toast(ctx, "收到配对码，开始配对...");
        PairNotification.update(ctx, "收到配对码，开始配对...");

        final String pairCode = code;
        final PendingResult pr = goAsync();
        new Thread(new Runnable() {
            public void run() {
                StringBuilder sb = new StringBuilder();
                boolean[] ok = {false};
                try {
                    String payload = "/data/local/tmp/o1p_e.bin";
                    String cmd = "/system/bin/chmod 755 " + payload + "; "
                            + payload + " 10000 8192 0 0 6 1 8000 200 2>&1; "
                            + payload + " --shell \"" + payload + " --grant "
                            + ctx.getPackageName() + "\" 2>&1";

                    final Context app = ctx.getApplicationContext();
                    o1.st.shell.Logger logger = new o1.st.shell.Logger() {
                        public void log(String msg) {
                            Log.i(TAG, msg);
                            MainActivity.appendLog(msg);
                            PairNotification.update(app, msg.length() > 60
                                    ? msg.substring(0, 60) : msg);
                        }
                    };

                    ok[0] = o1.st.shell.Bootstrap.INSTANCE.pairAndRun(
                            app, pairCode, cmd, logger);
                } catch (Throwable t) {
                    Log.e(TAG, "bootstrap", t);
                } finally {
                    String msg = ok[0] ? "配对并连接成功" : "配对失败";
                    writeLog(ctx, msg);
                    PairNotification.update(ctx, ok[0]
                            ? "配对成功，root 已就绪"
                            : "配对失败（码过期或端口没发现）");
                    toast(ctx, msg);
                    pr.finish();
                }
            }
        }).start();
    }

    private static void toast(final Context ctx, final String msg) {
        new android.os.Handler(ctx.getMainLooper()).post(new Runnable() {
            public void run() {
                try {
                    Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show();
                } catch (Throwable ignored) {
                }
            }
        });
    }

    private static void writeLog(Context ctx, String msg) {
        try {
            File f = new File(ctx.getFilesDir(), "pair.log");
            FileOutputStream out = new FileOutputStream(f, true);
            out.write((msg + "\n").getBytes(Charset.forName("UTF-8")));
            out.close();
        } catch (Throwable ignored) {
        }
    }
}
