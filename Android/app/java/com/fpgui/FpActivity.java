package com.fpgui;

import android.app.Activity;
import android.app.ActivityOptions;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Rect;
import android.graphics.drawable.ColorDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.SparseArray;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.widget.FrameLayout;

import java.lang.reflect.Method;
import java.nio.ByteBuffer;

/**
 * Host activity for one fpGUI window.
 *
 * The main window (windowId=0) is a plain fullscreen activity with no system
 * caption; its surface fills the screen minus the system bars and every
 * window-size change is reported back to Pascal. Dialog/form secondary
 * windows are additional FpActivity instances launched as freeform system
 * windows (windowId>0). wtPopup windows (menus/dropdowns) are NOT activities:
 * they are in-app floating windows (see FpSubWindow), created in the activity
 * of the window they belong to. See FREEFORM-DESIGN.zh-CN.md.
 */
public class FpActivity extends Activity {

    private static final String TAG = "fpGUI-java";
    private static final String LIB_NAME_META = "com.fpgui.lib_name";
    private static final String PRESENTER_META = "com.fpgui.presenter";
    private static final String EXTRA_WINDOW_ID = "windowId";
    private static final String EXTRA_BORDERLESS = "borderless";
    private static final String EXTRA_CONTENT_W = "contentW";
    private static final String EXTRA_CONTENT_H = "contentH";
    private static final String EXTRA_DISMISS_OUTSIDE = "dismissOutside";
    private static final String EXTRA_OWNER_ID = "ownerId";
    private static final String EXTRA_MAIN_TITLE = "mainTitle";

    private static final int WINDOWING_MODE_FREEFORM = 5;
    /** Initial estimate of the freeform window decoration (caption) height in
     *  dp; replaced by the real measured value (sDecorHeight) after the first
     *  dialog has been laid out. */
    private static final int DECOR_DP = 48;

    /** Process-wide state. */
    private static boolean sAppStarted = false;
    private static boolean sMainTitleApplied = false;
    private static int sInstanceCounter = 0;
    /** Measured freeform caption height (device pixels); 0 = not measured. */
    private static int sDecorHeight = 0;
    /** fpGUI main-window title, applied to the system ActionBar. */
    private static String sMainTitleText = "";
    private static final SparseArray<FpActivity> sWindowActivities = new SparseArray<FpActivity>();
    private static Boolean sSupportsFreeform = null;
    /** Main window's surface view: the origin of the fpGUI virtual screen. */
    private static FpSurfaceView sMainView = null;
    /** Main window activity (owns the surface; input target for forwarding). */
    private static FpActivity sMainActivity = null;
    /** Current modal secondary-window id (0 = none). While a modal is active
     *  every other window gets FLAG_NOT_TOUCHABLE, so neither its content nor
     *  its system caption buttons can be used. */
    private static int sModalWindowId = 0;
    /** In-app floating windows (wtPopup menus/dropdowns), process-wide: a
     *  popup is created in the activity of its owning window but the JNI
     *  calls (present/move/show/destroy) all target the main activity. */
    private static final SparseArray<FpSubWindow> sSubWindows = new SparseArray<FpSubWindow>();

    private int windowId;
    private int instanceToken;
    private boolean borderless;
    private boolean skipNativeStop;      // replaced by a decoration re-launch
    private FpSurfaceView view;          // main window only
    private FpWindowView windowView;     // secondary (freeform) windows only

    protected int getPresenterMode() {
        try {
            ApplicationInfo info = getPackageManager()
                    .getApplicationInfo(getPackageName(), PackageManager.GET_META_DATA);
            if (info.metaData != null) {
                String name = info.metaData.getString(PRESENTER_META);
                if (name != null && name.equalsIgnoreCase("native")) {
                    return 1;
                }
            }
        } catch (PackageManager.NameNotFoundException e) {
            // fall through to the default
        }
        return 0;
    }

    protected String getLibraryName() {
        try {
            ApplicationInfo info = getPackageManager()
                    .getApplicationInfo(getPackageName(), PackageManager.GET_META_DATA);
            if (info.metaData != null) {
                String name = info.metaData.getString(LIB_NAME_META);
                if (name != null) {
                    return name;
                }
            }
        } catch (PackageManager.NameNotFoundException e) {
            // fall through to the default
        }
        return "helloworld";
    }

    static boolean supportsFreeform(Context ctx) {
        if (sSupportsFreeform == null) {
            sSupportsFreeform = ctx.getPackageManager()
                    .hasSystemFeature("android.software.freeform_window_management");
        }
        return sSupportsFreeform;
    }

    private boolean inFreeform() {
        return Build.VERSION.SDK_INT >= 24 && isInMultiWindowMode();
    }

    /** Screen location of the main window's content origin (the fpGUI virtual
     *  screen origin). Secondary-window bounds are reported relative to it so
     *  Pascal window positions stay in virtual-screen coordinates. */
    static void getMainViewLocation(int[] loc) {
        loc[0] = 0;
        loc[1] = 0;
        FpSurfaceView v = sMainView;
        if (v != null) {
            v.getLocationOnScreen(loc);
        }
    }

    /** Initial caption-height estimate in device pixels (replaced by the
     *  measured value after the first dialog has been laid out). */
    private int decorEstimate() {
        return Math.round(DECOR_DP * getResources().getDisplayMetrics().density);
    }

    /** ActivityOptions with FREEFORM windowing mode + window bounds.
     *  setLaunchWindowingMode is a hidden @SystemApi - reflect.
     *  The caller passes the full window size (content + caption). */
    private ActivityOptions freeformOptions(int x, int y, int w, int h) {
        ActivityOptions opts = ActivityOptions.makeBasic();
        opts.setLaunchBounds(new Rect(x, y, x + w, y + h));
        try {
            Method m = ActivityOptions.class.getMethod("setLaunchWindowingMode", int.class);
            m.invoke(opts, WINDOWING_MODE_FREEFORM);
        } catch (Throwable t) {
            Log.w(TAG, "setLaunchWindowingMode unavailable: " + t);
        }
        return opts;
    }

    /**
     * Borderless windows use a floating (dialog) theme: freeform floating
     * windows carry no system caption bar. Must run before setContentView.
     */
    private void applyBorderlessTheme() {
        setTheme(android.R.style.Theme_DeviceDefault_Dialog);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
    }

    /** Post-setContentView tweaks for a floating borderless window. */
    private void finishBorderlessWindow(int w, int h) {
        Window win = getWindow();
        win.setBackgroundDrawable(new ColorDrawable(0));
        win.setDimAmount(0f);
        win.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
        setFinishOnTouchOutside(false);
        WindowManager.LayoutParams lp = win.getAttributes();
        lp.width = Math.max(1, w);
        lp.height = Math.max(1, h);
        // A freeform task has a platform minimum size (220dp). When the
        // requested window is smaller, the window manager would otherwise
        // center the content window inside the task, displacing popup menus
        // by half the difference. Pin it to the task's top-left instead, so
        // the content lands exactly at the launch position.
        lp.gravity = Gravity.TOP | Gravity.LEFT;
        win.setAttributes(lp);
        win.getDecorView().setMinimumWidth(0);
        win.getDecorView().setMinimumHeight(0);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        Intent intent = getIntent();
        final boolean mainTitle = intent.getBooleanExtra(EXTRA_MAIN_TITLE, false);
        if (mainTitle) {
            // Re-launched to get the system title bar (the manifest theme has
            // no ActionBar so borderless/fullscreen windows never flash one).
            setTheme(android.R.style.Theme_DeviceDefault);
        }
        super.onCreate(savedInstanceState);
        windowId = intent.getIntExtra(EXTRA_WINDOW_ID, 0);
        borderless = intent.getBooleanExtra(EXTRA_BORDERLESS, false);
        instanceToken = ++sInstanceCounter;

        if (windowId == 0) {
            if (sAppStarted && !mainTitle) {
                // Duplicate launcher start while running: drop it. A title-bar
                // re-launch re-attaches the running application's surface.
                finish();
                return;
            }
            if (mainTitle) {
                sMainTitleApplied = true;
            }
            initMainWindow(mainTitle);
            sAppStarted = true;
        } else {
            initSecondaryWindow();
        }
    }

    /** Main window: a plain fullscreen activity. Its surface fills the screen
     *  minus the system bars; any window-size change is reported back to
     *  Pascal (nativeSurfaceChanged) so the fpGUI main form always follows
     *  the current window size. The system title bar depends on the fpGUI
     *  window attributes (see setMainDecoration): waBorderless/waFullScreen
     *  show none, anything else gets one. */
    private void initMainWindow(boolean mainTitle) {
        if (!mainTitle) {
            requestWindowFeature(Window.FEATURE_NO_TITLE);
        }

        System.loadLibrary(getLibraryName());

        final FrameLayout root = new FrameLayout(this);
        view = new FpSurfaceView(this);
        view.setInstanceToken(instanceToken);
        sMainView = view;
        sMainActivity = this;
        watchMainViewSize(view);
        root.addView(view, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));
        if (!inFreeform()) {
            // Fullscreen: pad for the system bars (edge-to-edge layout).
            root.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
                @Override
                public WindowInsets onApplyWindowInsets(View v, WindowInsets insets) {
                    v.setPadding(insets.getSystemWindowInsetLeft(),
                            insets.getSystemWindowInsetTop(),
                            insets.getSystemWindowInsetRight(),
                            insets.getSystemWindowInsetBottom());
                    return insets.consumeSystemWindowInsets();
                }
            });
        }
        setContentView(root);
        if (mainTitle && getActionBar() != null && sMainTitleText.length() > 0) {
            getActionBar().setTitle(sMainTitleText);
        }

        DisplayMetrics dm = getResources().getDisplayMetrics();
        String ext = "";
        java.io.File extDir = getExternalFilesDir(null);
        if (extDir != null) {
            ext = extDir.getAbsolutePath();
        }
        view.nativeInit(this, view,
                getFilesDir().getAbsolutePath(),
                getCacheDir().getAbsolutePath(),
                ext, dm.density, getPresenterMode(),
                supportsFreeform(this));
        // Report the display metrics before the first surface callback so
        // the Pascal main form is laid out for the right screen size even
        // if its window is created before surfaceChanged arrives.
        view.nativeSurfaceChanged(instanceToken, dm.widthPixels, dm.heightPixels, dm.density);
        view.requestFocus();
    }

    private void initSecondaryWindow() {
        if (borderless) {
            applyBorderlessTheme();
        } else {
            requestWindowFeature(Window.FEATURE_NO_TITLE);
        }
        final int cw = getIntent().getIntExtra(EXTRA_CONTENT_W, 0);
        final int ch = getIntent().getIntExtra(EXTRA_CONTENT_H, 0);
        windowView = new FpWindowView(this, windowId);
        setContentView(windowView);
        if (borderless) {
            // Borderless windows wrap their content exactly.
            int w = cw > 0 ? cw : getResources().getDisplayMetrics().widthPixels;
            int h = ch > 0 ? ch : getResources().getDisplayMetrics().heightPixels;
            finishBorderlessWindow(w, h);
        } else if (cw > 0 && ch > 0) {
            // Freeform dialog with a system caption: the window must be the
            // requested content plus the REAL caption height, otherwise the
            // extra (estimated/min-task) area shows as a blank strip and the
            // bounds sync would enlarge the fpGUI window. Pinned top-left.
            finishDialogWindow(cw, ch, sDecorHeight > 0 ? sDecorHeight : decorEstimate());
        }
        // No system window/task entrance animation for secondary windows:
        // the freeform task is otherwise visibly scaled/translated into
        // place (Animation.Material.Activity / task_open_enter).
        getWindow().setWindowAnimations(0);
        // Keep the window invisible while the freeform task entry and the
        // caption-size correction happen; reveal it once everything has
        // settled so the user sees it directly at its final position.
        WindowManager.LayoutParams lp = getWindow().getAttributes();
        lp.alpha = 0f;
        getWindow().setAttributes(lp);
        windowView.postDelayed(new Runnable() {
            @Override
            public void run() {
                revealWindow();
            }
        }, 400);
        if (!borderless && cw > 0 && ch > 0) {
            // Measure the real caption height after layout and correct the
            // window height once; the value is reused for later dialogs.
            windowView.postDelayed(new Runnable() {
                private int tries = 0;

                @Override
                public void run() {
                    int frameH = getWindow().getDecorView().getHeight();
                    int viewH = windowView.getHeight();
                    if ((frameH <= 0 || viewH <= 0) && tries++ < 10) {
                        windowView.postDelayed(this, 100);
                        return;
                    }
                    int decor = frameH - viewH;
                    if (decor <= 0) {
                        return;
                    }
                    sDecorHeight = decor;
                    WindowManager.LayoutParams p = getWindow().getAttributes();
                    int want = ch + decor;
                    if (p.height != want) {
                        p.height = want;
                        p.gravity = Gravity.TOP | Gravity.LEFT;
                        getWindow().setAttributes(p);
                    }
                }
            }, 200);
        }
        // A window created while a modal is active must be blocked too -
        // except wtPopup windows (dismissOnOutside=true), which belong to the
        // modal itself (combo dropdowns etc.) and must stay usable.
        boolean dismissOnOutside = getIntent().getBooleanExtra(EXTRA_DISMISS_OUTSIDE, false);
        if (sModalWindowId != 0 && windowId != sModalWindowId && !dismissOnOutside) {
            applyModalTouchability(true);
        }
        sWindowActivities.put(windowId, this);
        windowView.nativeWindowAttached(windowId, this, windowView);
    }

    /** Size a freeform dialog window to its requested content plus the real
     *  caption height, pinned to the task's top-left so no extra area shows. */
    private void finishDialogWindow(int cw, int ch, int decor) {
        Window win = getWindow();
        WindowManager.LayoutParams lp = win.getAttributes();
        lp.width = Math.max(1, cw);
        lp.height = Math.max(1, ch + decor);
        lp.gravity = Gravity.TOP | Gravity.LEFT;
        win.setAttributes(lp);
        win.getDecorView().setMinimumWidth(0);
        win.getDecorView().setMinimumHeight(0);
    }

    /** Report main-window client-size changes even when the surface callback
     *  does not fire (e.g. a forced/maximized freeform resize): Pascal
     *  deduplicates by physical size, so a redundant report is harmless. */
    private void watchMainViewSize(final FpSurfaceView v) {
        v.addOnLayoutChangeListener(new View.OnLayoutChangeListener() {
            @Override
            public void onLayoutChange(View view, int left, int top, int right, int bottom,
                                       int oldLeft, int oldTop, int oldRight, int oldBottom) {
                int w = right - left;
                int h = bottom - top;
                if (w > 0 && h > 0 && (w != oldRight - oldLeft || h != oldBottom - oldTop)) {
                    v.nativeSurfaceChanged(instanceToken, w, h,
                            getResources().getDisplayMetrics().density);
                }
            }
        });
    }

    /** Called from Pascal (loop thread) whenever the modal window changes:
     *  id = modal secondary-window id, 0 = no modal. Disables input on every
     *  other window (content AND system caption buttons) and keeps the modal
     *  task on top. */
    public void setModalWindow(final int id) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                sModalWindowId = id;
                for (int i = 0; i < sWindowActivities.size(); i++) {
                    FpActivity a = sWindowActivities.valueAt(i);
                    if (a != null) {
                        a.applyModalTouchability(a.windowId != id);
                    }
                }
                if (sMainActivity != null) {
                    sMainActivity.applyModalTouchability(id != 0);
                }
                if (id != 0) {
                    FpActivity modal = sWindowActivities.get(id);
                    if (modal != null) {
                        android.app.ActivityManager am = (android.app.ActivityManager)
                                getSystemService(Context.ACTIVITY_SERVICE);
                        if (am != null) {
                            try {
                                am.moveTaskToFront(modal.getTaskId(), 0);
                            } catch (Throwable t) {
                                Log.w(TAG, "moveTaskToFront failed: " + t);
                            }
                        }
                    }
                }
            }
        });
    }

    private void applyModalTouchability(boolean blocked) {
        Window win = getWindow();
        if (blocked) {
            win.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
        } else {
            win.clearFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
        }
    }

    /** Called from Pascal (loop thread) once the main window's attributes are
     *  known:
     *  - waBorderless: no title bar (the manifest theme already has none).
     *  - waFullScreen: no title bar and no system status bar.
     *  - otherwise: keep the system title bar - the manifest theme has no
     *    ActionBar (so borderless windows never flash one), therefore the
     *    window is re-opened once with the normal theme; the Pascal
     *    application keeps running and re-attaches its surface. */
    public void setMainDecoration(final boolean borderless, final boolean fullscreen,
                                  final String title) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (windowId != 0) {
                    return;
                }
                if (title != null && title.length() > 0) {
                    sMainTitleText = title;
                    if (getActionBar() != null) {
                        getActionBar().setTitle(title);
                    }
                }
                if (fullscreen) {
                    getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
                    getWindow().getDecorView().setSystemUiVisibility(
                            View.SYSTEM_UI_FLAG_FULLSCREEN
                                    | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
                    return;
                }
                /*if (borderless || sMainTitleApplied) {
                    return;
                }
                sMainTitleApplied = true;
                skipNativeStop = true;
                Intent i = new Intent(FpActivity.this, FpActivity.class);
                i.putExtra(EXTRA_WINDOW_ID, 0);
                i.putExtra(EXTRA_MAIN_TITLE, true);
                i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                        | Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
                startActivity(i);
                finish();*/
            }
        });
    }

    /** Make a secondary window visible (called with the first frame, and as a
     *  delayed safety net). No-op for the main window. */
    void revealWindow() {
        if (windowId == 0) {
            return;
        }
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                WindowManager.LayoutParams lp = getWindow().getAttributes();
                if (lp.alpha != 1f) {
                    lp.alpha = 1f;
                    getWindow().setAttributes(lp);
                }
            }
        });
    }

    @Override
    protected void onDestroy() {
        if (windowId == 0) {
            // A decoration re-launch replaces this instance; the Pascal
            // application must keep running and re-attach to the new surface.
            if (view != null && !skipNativeStop) {
                view.nativeStop(instanceToken);
            }
            if (!skipNativeStop) {
                // The application is exiting (Quit / activity destroyed). The
                // process may stay cached, so reset the process-wide state -
                // otherwise the next launch would be dropped as a "duplicate
                // launcher start".
                sAppStarted = false;
                sMainTitleApplied = false;
                sMainView = null;
                sMainActivity = null;
                sMainTitleText = "";
                sModalWindowId = 0;
                sSubWindows.clear();
            }
        } else {
            sWindowActivities.remove(windowId);
            if (windowView != null) {
                windowView.nativeWindowClosed(windowId);
            }
        }
        super.onDestroy();
    }

    @Override
    public void onBackPressed() {
        if (windowId != 0) {
            if (windowView != null && windowView.handleBack()) {
                return;
            }
            super.onBackPressed();
            return;
        }
        // Let the backend consume Back (closes popups/modal dialogs);
        // otherwise fall through to the default (finish the activity).
        if (view == null || !view.handleBack()) {
            super.onBackPressed();
        }
    }

    // ---- services (called by the Pascal backend via JNI) -----------------

    /** Clipboard read service (called by the Pascal backend via JNI). */
    public String getClipboard() {
        ClipboardManager cm =
                (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (cm == null || cm.getPrimaryClip() == null
                || cm.getPrimaryClip().getItemCount() < 1) {
            return "";
        }
        CharSequence text = cm.getPrimaryClip().getItemAt(0).coerceToText(this);
        return text == null ? "" : text.toString();
    }

    /** Clipboard write service (called by the Pascal backend via JNI). */
    public void setClipboard(final String text) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                ClipboardManager cm =
                        (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                if (cm != null) {
                    cm.setPrimaryClip(ClipData.newPlainText("fpGUI", text));
                }
            }
        });
    }

    /** Open a URL with the system handler (ACTION_VIEW). */
    public void openUrl(final String url) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(intent);
                } catch (Exception e) {
                    // no handler installed - nothing to do
                }
            }
        });
    }

    /** Finish the activity (Pascal side asked to close the application). */
    public void finishActivity() {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                finish();
            }
        });
    }

    // ---- secondary windows ------------------------------------------------

    /** Create a window for a secondary fpGUI window.
     *  - wtPopup (dismissOnOutside=true): always an in-app floating window
     *    (PopupWindow), created in the activity that owns the popup's
     *    reference window (ownerId; 0 = main window).
     *  - dialogs/forms: freeform system window when the platform supports it,
     *    otherwise the same in-app floating window fallback. */
    public void createSubWindow(final int id, final int x, final int y,
                                final int w, final int h, final boolean dismissOnOutside,
                                final boolean borderless, final int ownerId) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (sWindowActivities.get(id) != null || sSubWindows.get(id) != null) {
                    return;
                }
                if (!dismissOnOutside && supportsFreeform(FpActivity.this)) {
                    // fpGUI window coordinates are relative to the main
                    // window's content origin; translate to screen pixels.
                    int ox = 0, oy = 0;
                    if (view != null) {
                        int[] loc = new int[2];
                        view.getLocationOnScreen(loc);
                        ox = loc[0];
                        oy = loc[1];
                    }
                    Intent i = new Intent(FpActivity.this, FpActivity.class);
                    i.putExtra(EXTRA_WINDOW_ID, id);
                    i.putExtra(EXTRA_BORDERLESS, borderless);
                    i.putExtra(EXTRA_CONTENT_W, w);
                    i.putExtra(EXTRA_CONTENT_H, h);
                    i.putExtra(EXTRA_DISMISS_OUTSIDE, dismissOnOutside);
                    i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                            | Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
                    // Non-borderless dialogs carry a system caption: launch the
                    // task so that the CONTENT lands at the requested point
                    // (shift up by the caption height) and size the window to
                    // content + caption.
                    int decor = borderless ? 0
                            : (sDecorHeight > 0 ? sDecorHeight : decorEstimate());
                    try {
                        startActivity(i, freeformOptions(ox + x, oy + y - decor,
                                w, h + decor).toBundle());
                        return;
                    } catch (Throwable t) {
                        Log.w(TAG, "freeform launch failed, using popup: " + t);
                    }
                }
                // In-app floating window. Menus/dropdowns live in the activity
                // of the window they belong to, so they stack above it.
                FpActivity owner = ownerId > 0
                        ? sWindowActivities.get(ownerId) : FpActivity.this;
                if (owner == null) {
                    owner = FpActivity.this;
                }
                View anchor = owner.windowView != null ? owner.windowView : view;
                if (anchor == null) {
                    anchor = view;
                }
                FpSubWindow win = new FpSubWindow(owner, anchor, id,
                        x, y, w, h, dismissOnOutside);
                sSubWindows.put(id, win);
            }
        });
    }

    public void moveSubWindow(final int id, final int x, final int y,
                              final int w, final int h) {
        FpSubWindow win = sSubWindows.get(id);
        if (win != null) {
            win.moveTo(x, y, w, h);
        }
        // Freeform windows: no public API to move a live Activity window;
        // the launch bounds already carried the position.
    }

    public void setSubWindowVisible(final int id, final boolean visible) {
        FpSubWindow win = sSubWindows.get(id);
        if (win != null) {
            win.setVisible(visible);
        }
        // Freeform windows: lifecycle is create/destroy, nothing to toggle.
    }

    public void destroySubWindow(final int id) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                FpSubWindow win = sSubWindows.get(id);
                if (win != null) {
                    win.destroy();
                    sSubWindows.remove(id);
                    return;
                }
                FpActivity a = sWindowActivities.get(id);
                if (a != null) {
                    a.finish();
                }
            }
        });
    }

    /** Present a frame into a secondary window (called from the Pascal
     *  render thread; the view is thread-safe for a single producer). */
    public void presentSubFrame(final int id, ByteBuffer pixels, int w, int h) {
        FpSubWindow win = sSubWindows.get(id);
        if (win != null) {
            win.presentFrame(pixels, w, h);
            return;
        }
        FpActivity a = sWindowActivities.get(id);
        if (a != null && a.windowView != null) {
            a.windowView.presentFrame(pixels, w, h);
        }
    }
}
