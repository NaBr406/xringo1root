package o1.st.shell;

import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Floating window for the wireless-debugging pairing code.
 *
 * The system pairing code is only valid while the wireless-debugging screen is
 * in front, so the user cannot switch to our activity to type it. This overlay
 * sits on top of that screen: the code is typed without ever leaving it.
 */
public class PairOverlay {

    public interface Callback {
        void onPair(String code);
    }

    private final Context ctx;
    private WindowManager wm;
    private View root;

    public PairOverlay(Context ctx) {
        this.ctx = ctx;
    }

    public static boolean hasPermission(Context ctx) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true;
        }
        return Settings.canDrawOverlays(ctx);
    }

    public static void requestPermission(Context ctx) {
        Intent i = new Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:" + ctx.getPackageName()));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        ctx.startActivity(i);
    }

    public void show(final Callback cb) {
        if (root != null) {
            return;
        }
        final int pad = (int) (10 * ctx.getResources().getDisplayMetrics().density);

        LinearLayout box = new LinearLayout(ctx);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setBackgroundColor(0xF0181818);
        box.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(ctx);
        title.setText("o1p：输入配对码（不用离开此页）");
        title.setTextColor(Color.WHITE);
        title.setTextSize(14);
        box.addView(title);

        final EditText input = new EditText(ctx);
        input.setHint("6 位配对码");
        input.setInputType(InputType.TYPE_CLASS_NUMBER);
        input.setTextColor(Color.WHITE);
        input.setHintTextColor(0xFF888888);
        box.addView(input, new LinearLayout.LayoutParams(-1, -2));

        LinearLayout row = new LinearLayout(ctx);
        row.setOrientation(LinearLayout.HORIZONTAL);

        Button go = new Button(ctx);
        go.setText("配对");
        go.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                String code = input.getText().toString().trim();
                hide();
                cb.onPair(code);
            }
        });
        row.addView(go, new LinearLayout.LayoutParams(0, -2, 1f));

        Button cancel = new Button(ctx);
        cancel.setText("取消");
        cancel.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                hide();
            }
        });
        row.addView(cancel, new LinearLayout.LayoutParams(0, -2, 1f));

        box.addView(row);

        wm = (WindowManager) ctx.getSystemService(Context.WINDOW_SERVICE);
        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                        ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                        : WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        lp.gravity = Gravity.TOP;
        lp.y = (int) (60 * ctx.getResources().getDisplayMetrics().density);

        root = box;
        try {
            wm.addView(root, lp);
        } catch (Throwable t) {
            root = null;
        }
    }

    public void hide() {
        if (root == null || wm == null) {
            return;
        }
        try {
            wm.removeView(root);
        } catch (Throwable ignored) {
        }
        root = null;
    }
}
