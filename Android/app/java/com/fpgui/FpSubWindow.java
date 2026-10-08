package com.fpgui;

import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.view.Gravity;
import android.view.InputDevice;
import android.view.MotionEvent;
import android.view.View;
import android.widget.PopupWindow;

import java.nio.ByteBuffer;

/**
 * One floating window inside the activity: a {@link PopupWindow} hosting a
 * plain {@link View} that draws the frames handed over from Pascal (the same
 * Java Canvas presentation model as the main view). Every fpGUI secondary
 * window (dialogs, menus, the character map, ...) gets its own real window
 * instead of being composited into the main window's buffer, so:
 *   - the main window's repaints can never erase an overlaid dialog;
 *   - each window receives its own pointer events with local coordinates;
 *   - z-order and outside-touch behaviour follow the PopupWindow rules.
 *
 * A plain View is used instead of a SurfaceView on purpose: destroying a
 * SurfaceView makes emulators with host-side GL translation (LDPlayer)
 * reconnect their renderer pipe, which crashes the process. A View has no
 * surface of its own, so showing/hiding/destroying popups is always safe.
 *
 * All coordinates are device pixels. The window is intentionally NOT
 * focusable: the main surface view keeps the keyboard/IME focus and the
 * Pascal side routes keys to the active modal form (see TopModalForm).
 */
public class FpSubWindow {

    private final Activity activity;
    private final View anchor;
    private final int id;

    private final FrameView frameView;
    private PopupWindow popup;
    private Bitmap bitmap;
    private int width;
    private int height;
    private boolean visible;
    private boolean dismissed;
    private final FpMouseGesture mouseGesture = new FpMouseGesture();
    private final FpMouseGesture.Sink mouseSink = new FpMouseGesture.Sink() {
        @Override
        public void send(int action, int button, float x, float y) {
            nativeSubTouch(id, action, x, y, button);
        }
    };

    private final class FrameView extends View {
        FrameView(Context context) {
            super(context);
        }

        @Override
        protected void onAttachedToWindow() {
            super.onAttachedToWindow();
            // The first frame may have been presented before this view
            // existed; ask the backend for a repaint.
            nativeSubWindowAttached(FpSubWindow.this.id);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            synchronized (FpSubWindow.this) {
                if (bitmap != null) {
                    canvas.drawBitmap(bitmap, 0, 0, null);
                }
            }
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            dispatchTouch(event);
            return true;
        }

        /** Android routes ACTION_HOVER_MOVE through onHoverEvent, not
         *  onGenericMotionEvent. */
        @Override
        public boolean onHoverEvent(MotionEvent event) {
            final boolean isMouse =
                    (event.getSource() & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE;
            if (!isMouse) {
                return super.onHoverEvent(event);
            }
            if (event.getActionMasked() == MotionEvent.ACTION_HOVER_MOVE) {
                nativeSubHover(FpSubWindow.this.id, event.getX(), event.getY());
            }
            return true;
        }

        @Override
        public boolean onGenericMotionEvent(MotionEvent event) {
            final boolean isMouse =
                    (event.getSource() & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE;
            if (!isMouse) {
                return super.onGenericMotionEvent(event);
            }
            if (event.getActionMasked() == MotionEvent.ACTION_SCROLL) {
                float v = event.getAxisValue(MotionEvent.AXIS_VSCROLL);
                if (v != 0) {
                    nativeSubWheel(FpSubWindow.this.id, v > 0 ? -1 : 1);
                }
                return true;
            }
            return super.onGenericMotionEvent(event);
        }
    }

    public FpSubWindow(Activity activity, View anchor, int id,
                       int x, int y, int w, int h, boolean dismissOnOutside) {
        this.activity = activity;
        this.anchor = anchor;
        this.id = id;
        this.width = Math.max(1, w);
        this.height = Math.max(1, h);
        // dismissOnOutside is kept in the API: outside touches now always
        // pass through and Pascal's A1 logic closes the popup chain.

        frameView = new FrameView(activity);

        popup = new PopupWindow(frameView, width, height);
        popup.setFocusable(false);
        popup.setTouchable(true);
        // Outside touches are NOT consumed: they reach the window underneath
        // (menu bar / edit / dialog) and Pascal's A1 logic closes the popup
        // chain and delivers the click - desktop-style menu switching.
        popup.setOutsideTouchable(false);
        popup.setOnDismissListener(new PopupWindow.OnDismissListener() {
            @Override
            public void onDismiss() {
                dismissed = true;
                visible = false;
                nativeSubWindowDismissed(FpSubWindow.this.id);
            }
        });
        showAt(x, y);
    }

    private void dispatchTouch(MotionEvent event) {
        if (FpMouseGesture.isMouse(event)) {
            mouseGesture.handle(event, mouseSink);
            return;
        }
        nativeSubTouch(id, event.getActionMasked(), event.getX(), event.getY(), 0);
    }

    /** Convert fpGUI window coordinates to coordinates inside the anchor's
     *  window. x/y are device pixels relative to the main window's content
     *  origin (the fpGUI virtual screen origin); the popup may belong to a
     *  secondary (freeform) activity, so the main origin and the anchor's
     *  window origin are both taken into account. */
    private void toAnchorWindow(int x, int y, int[] out) {
        int[] mainLoc = new int[2];
        FpActivity.getMainViewLocation(mainLoc);
        int[] aScreen = new int[2];
        anchor.getLocationOnScreen(aScreen);
        int[] aWin = new int[2];
        anchor.getLocationInWindow(aWin);
        out[0] = mainLoc[0] + x - aScreen[0] + aWin[0];
        out[1] = mainLoc[1] + y - aScreen[1] + aWin[1];
    }

    private void showAt(final int x, final int y) {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (popup.isShowing()) {
                    return;
                }
                dismissed = false;
                int[] loc = new int[2];
                toAnchorWindow(x, y, loc);
                try {
                    popup.showAtLocation(anchor, Gravity.NO_GRAVITY, loc[0], loc[1]);
                    visible = true;
                } catch (Exception e) {
                    // window token not ready yet: retry on the next frame
                    anchor.postDelayed(new Runnable() {
                        @Override
                        public void run() {
                            showAt(x, y);
                        }
                    }, 50);
                }
            }
        });
    }

    /** Move/resize (device pixels), called from the Pascal render thread. */
    public void moveTo(final int x, final int y, final int w, final int h) {
        width = Math.max(1, w);
        height = Math.max(1, h);
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (!popup.isShowing()) {
                    return;
                }
                int[] loc = new int[2];
                toAnchorWindow(x, y, loc);
                popup.update(loc[0], loc[1], width, height);
            }
        });
    }

    public void setVisible(final boolean show) {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (show) {
                    if (!popup.isShowing()) {
                        // position is unknown here; caller moves first
                        showAt(0, 0);
                    }
                    visible = true;
                } else if (popup.isShowing()) {
                    visible = false;
                    popup.dismiss();
                }
            }
        });
    }

    public void destroy() {
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                visible = false;
                if (popup.isShowing()) {
                    popup.dismiss();
                }
                popup.setOnDismissListener(null);
                synchronized (FpSubWindow.this) {
                    bitmap = null;
                }
            }
        });
    }

    /** Draw one tightly packed frame (stride = width*4, RGBA bytes) into this
     *  window's view. Called from the Pascal render thread. */
    public void presentFrame(ByteBuffer pixels, int w, int h) {
        if (!visible || dismissed) {
            return;
        }
        synchronized (this) {
            if (bitmap == null || bitmap.getWidth() != w || bitmap.getHeight() != h) {
                bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            }
            pixels.rewind();
            bitmap.copyPixelsFromBuffer(pixels);
        }
        frameView.postInvalidate();
    }

    // Registered by JNI_OnLoad on FpSubWindow.
    private static native void nativeSubWindowAttached(int id);
    private static native void nativeSubWindowDismissed(int id);
    private static native void nativeSubTouch(int id, int action, float x, float y, int button);
    private static native void nativeSubHover(int id, float x, float y);
    private static native void nativeSubWheel(int id, int delta);
}
