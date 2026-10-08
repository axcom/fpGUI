package com.fpgui;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;

import java.nio.ByteBuffer;

/**
 * Content view of one freeform secondary window (plain View, no SurfaceView:
 * destroying a SurfaceView makes emulators with host-side GL translation
 * reconnect their renderer pipe, which crashes the process).
 *
 * Frames arrive from the Pascal render thread via presentFrame(); input is
 * forwarded to the backend with this window's id. Native methods are
 * registered from JNI_OnLoad on this class.
 */
public class FpWindowView extends View {

    private final int windowId;
    private Bitmap bitmap;
    private int lastX = Integer.MIN_VALUE, lastY, lastW, lastH;
    private final FpMouseGesture mouseGesture = new FpMouseGesture();
    private final FpMouseGesture.Sink mouseSink = new FpMouseGesture.Sink() {
        @Override
        public void send(int action, int button, float x, float y) {
            nativeWindowTouch(windowId, action, x, y, button);
        }
    };
    private final FpLongPressGesture longPressGesture;
    private final FpLongPressGesture.Sink longPressSink = new FpLongPressGesture.Sink() {
        @Override
        public void send(int action, int button, float x, float y) {
            nativeWindowTouch(windowId, action, x, y, button);
        }
    };

    public FpWindowView(Context context, int windowId) {
        super(context);
        this.windowId = windowId;
        longPressGesture = new FpLongPressGesture(context, longPressSink);
        setFocusable(true);
        setFocusableInTouchMode(true);
    }

    // ---- rendering -------------------------------------------------------

    @Override
    protected void onDraw(Canvas canvas) {
        synchronized (this) {
            if (bitmap != null) {
                canvas.drawBitmap(bitmap, 0, 0, null);
            }
        }
    }

    /** Draw one tightly packed frame (stride = width*4, RGBA bytes). Called
     *  from the Pascal render thread. */
    public void presentFrame(ByteBuffer pixels, int w, int h) {
        synchronized (this) {
            if (bitmap == null || bitmap.getWidth() != w || bitmap.getHeight() != h) {
                bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            }
            pixels.rewind();
            bitmap.copyPixelsFromBuffer(pixels);
        }
        postInvalidate();
        // The window is revealed by FpActivity after the freeform entrance
        // animation / size correction has settled (revealing on the first
        // frame would show the window while it is still moving).
    }

    // ---- IME -------------------------------------------------------------

    /** Shows or hides the soft keyboard for this window (hops to UI thread). */
    public void setKeyboardVisible(final boolean visible) {
        post(new Runnable() {
            @Override
            public void run() {
                InputMethodManager imm = (InputMethodManager)
                        getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
                if (imm == null) {
                    return;
                }
                if (visible) {
                    requestFocus();
                    imm.restartInput(FpWindowView.this);
                    imm.showSoftInput(FpWindowView.this, InputMethodManager.SHOW_IMPLICIT);
                } else {
                    imm.hideSoftInputFromWindow(getWindowToken(), 0);
                }
            }
        });
    }

    @Override
    public boolean onCheckIsTextEditor() {
        return true;
    }

    @Override
    public InputConnection onCreateInputConnection(EditorInfo outAttrs) {
        outAttrs.inputType = EditorInfo.TYPE_CLASS_TEXT;
        outAttrs.imeOptions = EditorInfo.IME_ACTION_DONE
                | EditorInfo.IME_FLAG_NO_EXTRACT_UI
                | EditorInfo.IME_FLAG_NO_FULLSCREEN;
        return new FpInputConnection();
    }

    private class FpInputConnection extends BaseInputConnection {
        FpInputConnection() {
            super(FpWindowView.this, false);
        }

        @Override
        public boolean commitText(CharSequence text, int newCursorPosition) {
            if (text != null && text.length() > 0) {
                nativeWindowText(windowId, text.toString());
            }
            return true;
        }

        @Override
        public boolean setComposingText(CharSequence text, int newCursorPosition) {
            // Composition is not previewed; the commit delivers the text.
            return true;
        }

        @Override
        public boolean deleteSurroundingText(int beforeLength, int afterLength) {
            nativeWindowDelete(windowId, beforeLength, afterLength);
            return true;
        }

        @Override
        public boolean sendKeyEvent(KeyEvent event) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                nativeWindowKey(windowId, event.getKeyCode(), true,
                        event.getMetaState(), event.getUnicodeChar());
                return true;
            }
            if (event.getAction() == KeyEvent.ACTION_UP) {
                nativeWindowKey(windowId, event.getKeyCode(), false,
                        event.getMetaState(), event.getUnicodeChar());
                return true;
            }
            return false;
        }
    }

    // ---- geometry / focus reporting --------------------------------------

    private void reportBounds() {
        if (getWidth() <= 0 || getHeight() <= 0) {
            return;
        }
        int[] loc = new int[2];
        getLocationOnScreen(loc);
        // Report relative to the main window's content origin: fpGUI window
        // positions are virtual-screen coordinates, and createSubWindow adds
        // that origin back when translating to screen pixels. Reporting
        // absolute screen coordinates here would double the origin for every
        // window created afterwards (e.g. submenus).
        int[] mainLoc = new int[2];
        FpActivity.getMainViewLocation(mainLoc);
        int rx = loc[0] - mainLoc[0];
        int ry = loc[1] - mainLoc[1];
        int w = contentWidth();
        int h = contentHeight();
        if (rx == lastX && ry == lastY && w == lastW && h == lastH) {
            return;
        }
        lastX = rx;
        lastY = ry;
        lastW = w;
        lastH = h;
        nativeWindowBoundsChanged(windowId, lastX, lastY, lastW, lastH);
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        // The first frame may have been presented before the view was
        // laid out (postInvalidate is then lost): redraw so the popup is
        // not blank.
        synchronized (this) {
            if (bitmap != null) {
                postInvalidate();
            }
        }
        reportBounds();
    }

    private final Runnable boundsPoll = new Runnable() {
        @Override
        public void run() {
            reportBounds();
            postDelayed(this, 250);
        }
    };

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        synchronized (this) {
            if (bitmap != null) {
                postInvalidate();
            }
        }
        postDelayed(boundsPoll, 250);
    }

    @Override
    protected void onDetachedFromWindow() {
        removeCallbacks(boundsPoll);
        super.onDetachedFromWindow();
    }

    @Override
    public void onWindowFocusChanged(boolean hasWindowFocus) {
        super.onWindowFocusChanged(hasWindowFocus);
        if (hasWindowFocus) {
            nativeWindowFocused(windowId);
        }
    }

    // ---- input forwarding ------------------------------------------------

    private int contentWidth() {
        synchronized (this) {
            return bitmap != null ? bitmap.getWidth() : getWidth();
        }
    }

    private int contentHeight() {
        synchronized (this) {
            return bitmap != null ? bitmap.getHeight() : getHeight();
        }
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (FpMouseGesture.isMouse(event)) {
            mouseGesture.handle(event, mouseSink);
            return true;
        }
        // Touch: a long-press becomes a right-click (context menu).
        if (longPressGesture.handle(event)) {
            return true;
        }
        nativeWindowTouch(windowId, event.getActionMasked(),
                event.getX(), event.getY(), 0);
        return true;
    }

    /** Mouse hover: Android routes ACTION_HOVER_MOVE through onHoverEvent
     *  (not onGenericMotionEvent). */
    @Override
    public boolean onHoverEvent(MotionEvent event) {
        final boolean isMouse =
                (event.getSource() & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE;
        if (!isMouse) {
            return super.onHoverEvent(event);
        }
        if (event.getActionMasked() == MotionEvent.ACTION_HOVER_MOVE) {
            nativeWindowHover(windowId, event.getX(), event.getY());
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
                nativeWindowWheel(windowId, v > 0 ? -1 : 1);
            }
            return true;
        }
        return super.onGenericMotionEvent(event);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (nativeWindowKey(windowId, keyCode, true,
                event.getMetaState(), event.getUnicodeChar())) {
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (nativeWindowKey(windowId, keyCode, false,
                event.getMetaState(), event.getUnicodeChar())) {
            return true;
        }
        return super.onKeyUp(keyCode, event);
    }

    /** Back key: let the backend close the window/menu chain; false = finish. */
    public boolean handleBack() {
        return nativeWindowBack(windowId);
    }

    // Registered from JNI_OnLoad; signatures must match fpg_android_bridge.pas.
    native void nativeWindowAttached(int id, FpActivity activity, FpWindowView view);
    private native void nativeWindowTouch(int id, int action, float x, float y, int button);
    private native void nativeWindowHover(int id, float x, float y);
    private native void nativeWindowWheel(int id, int delta);
    private native void nativeWindowText(int id, String text);
    private native boolean nativeWindowKey(int id, int keyCode, boolean down,
                                           int metaState, int unicode);
    private native void nativeWindowDelete(int id, int before, int after);
    native boolean nativeWindowBack(int id);
    private native void nativeWindowBoundsChanged(int id, int x, int y, int w, int h);
    native void nativeWindowClosed(int id);
    private native void nativeWindowFocused(int id);
}
