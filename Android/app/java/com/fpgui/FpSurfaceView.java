package com.fpgui;

import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.util.DisplayMetrics;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;

import java.nio.ByteBuffer;

/**
 * The surface the fpGUI backend renders into, and the source of its input
 * events. Every native method is registered by the Pascal library from
 * JNI_OnLoad (see fpg_android_bridge.pas).
 *
 * Input events arrive on the Java UI thread; they are queued and wake the
 * Pascal event loop, which owns rendering and the widget logic.
 */
public class FpSurfaceView extends SurfaceView implements SurfaceHolder.Callback {

    // Registered from JNI_OnLoad; signatures must match fpg_android_bridge.pas.
    // presenter: 0 = Java Canvas (default, works everywhere incl. emulators),
    //            1 = native ANativeWindow lock (opt-in via manifest meta-data).
    // supportsFreeform: device reports freeform window management (diagnostics;
    // the Java side decides the per-window launch mode itself).
    // token: instance id of the owning FpActivity; the backend ignores
    // surface/stop callbacks from superseded instances (borderless main
    // window re-attach).
    public native void nativeInit(Activity activity, View view,
                                  String filesDir, String cacheDir,
                                  String externalDir, float density,
                                  int presenter, boolean supportsFreeform);
    private native void nativeSurfaceCreated(int token, Activity activity, Surface surface);
    // package-visible: FpActivity reports the initial display metrics
    native void nativeSurfaceChanged(int token, int width, int height, float density);
    private native void nativeSurfaceDestroyed(int token);
    // button: 0 = plain touch, 1 = left, 2 = right, 3 = middle (mouse).
    // Package-visible: a popup window forwards events that fall outside its
    // own content rectangle (freeform decoration band) to the main window.
    native void nativeTouch(int action, float x, float y, int button);
    native void nativeHover(float x, float y);
    private native void nativeWheel(int delta);
    private native boolean nativeKey(int keyCode, boolean down, int metaState, int unicode);
    private native void nativeText(String text);
    private native void nativeDelete(int before, int after);
    private native boolean nativeBack();
    public native void nativeStop(int token);

    private int instanceToken = 0;
    private final FpMouseGesture mouseGesture = new FpMouseGesture();
    private final FpMouseGesture.Sink mouseSink = new FpMouseGesture.Sink() {
        @Override
        public void send(int action, int button, float x, float y) {
            nativeTouch(action, x, y, button);
        }
    };
    private final FpLongPressGesture longPressGesture;
    private final FpLongPressGesture.Sink longPressSink = new FpLongPressGesture.Sink() {
        @Override
        public void send(int action, int button, float x, float y) {
            nativeTouch(action, x, y, button);
        }
    };

    void setInstanceToken(int token) {
        instanceToken = token;
    }

    public FpSurfaceView(Context context) {
        super(context);
        longPressGesture = new FpLongPressGesture(context, longPressSink);
        getHolder().addCallback(this);
        setFocusable(true);
        setFocusableInTouchMode(true);
    }

    /** Shows or hides the soft keyboard. Called by the backend when the
     *  widget focus changes (always hops to the UI thread). */
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
                    imm.restartInput(FpSurfaceView.this);
                    imm.showSoftInput(FpSurfaceView.this, InputMethodManager.SHOW_IMPLICIT);
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

    /** Routes committed text and editing keys from the IME to the backend. */
    private class FpInputConnection extends BaseInputConnection {

        FpInputConnection() {
            super(FpSurfaceView.this, false);
        }

        @Override
        public boolean commitText(CharSequence text, int newCursorPosition) {
            if (text != null && text.length() > 0) {
                nativeText(text.toString());
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
            nativeDelete(beforeLength, afterLength);
            return true;
        }

        @Override
        public boolean sendKeyEvent(KeyEvent event) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                nativeKey(event.getKeyCode(), true,
                        event.getMetaState(), event.getUnicodeChar());
                return true;
            }
            if (event.getAction() == KeyEvent.ACTION_UP) {
                nativeKey(event.getKeyCode(), false,
                        event.getMetaState(), event.getUnicodeChar());
                return true;
            }
            return false;
        }
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        nativeSurfaceCreated(instanceToken, (Activity) getContext(), holder.getSurface());
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        float density = getResources().getDisplayMetrics().density;
        nativeSurfaceChanged(instanceToken, width, height, density);
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        nativeSurfaceDestroyed(instanceToken);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (FpMouseGesture.isMouse(event)) {
            // Exactly one DOWN/UP pair per mouse gesture, with the correct
            // button (see FpMouseGesture) - right-click context menus need it.
            mouseGesture.handle(event, mouseSink);
            return true;
        }
        // Touch: a long-press becomes a right-click (context menu).
        if (longPressGesture.handle(event)) {
            return true;
        }
        nativeTouch(event.getActionMasked(), event.getX(), event.getY(), 0);
        return true;
    }

    /** Mouse hover moves: Android delivers ACTION_HOVER_MOVE through
     *  onHoverEvent (not onGenericMotionEvent), so the fpGUI hover feed
     *  must be wired here - otherwise the menu bar never sees the pointer
     *  and cannot switch open menus. */
    @Override
    public boolean onHoverEvent(MotionEvent event) {
        final boolean isMouse =
                (event.getSource() & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE;
        if (!isMouse) {
            return super.onHoverEvent(event);
        }
        if (event.getActionMasked() == MotionEvent.ACTION_HOVER_MOVE) {
            nativeHover(event.getX(), event.getY());
        }
        return true;
    }

    /** Scroll wheel (no touch equivalent). */
    @Override
    public boolean onGenericMotionEvent(MotionEvent event) {
        final boolean isMouse =
                (event.getSource() & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE;
        if (!isMouse) {
            return super.onGenericMotionEvent(event);
        }
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_SCROLL:
                {
                    float v = event.getAxisValue(MotionEvent.AXIS_VSCROLL);
                    if (v != 0) {
                        // wheel up (away from the user) scrolls up
                        nativeWheel(v > 0 ? -1 : 1);
                    }
                }
                return true;
            default:
                return super.onGenericMotionEvent(event);
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (nativeKey(keyCode, true, event.getMetaState(), event.getUnicodeChar())) {
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (nativeKey(keyCode, false, event.getMetaState(), event.getUnicodeChar())) {
            return true;
        }
        return super.onKeyUp(keyCode, event);
    }

    /** Offers the Back key to the backend; true when it consumed the event
     *  (e.g. it closed a popup or modal dialog). */
    public boolean handleBack() {
        return nativeBack();
    }

    // ---- Java Canvas presentation fallback --------------------------------
    // Used when the backend detects that the ANativeWindow buffers are not
    // CPU-mappable (host-side GL emulators such as LDPlayer in speed mode):
    // the frame is copied into a bitmap and drawn with the classic
    // SurfaceHolder Canvas path. ARGB_8888 bitmaps use the same RGBA byte
    // order as the backend's screen buffer.

    private Bitmap presenterBitmap;

    /** Draw one tightly packed frame (stride = width*4, RGBA bytes). Called
     *  from the Pascal render thread; lockCanvas is safe off the UI thread
     *  for a single producer. */
    public void presentFrame(ByteBuffer pixels, int width, int height) {
        SurfaceHolder holder = getHolder();
        Canvas canvas = null;
        try {
            canvas = holder.lockCanvas();
            if (canvas == null) {
                return;
            }
            if (presenterBitmap == null
                    || presenterBitmap.getWidth() != width
                    || presenterBitmap.getHeight() != height) {
                presenterBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
            }
            pixels.rewind();
            presenterBitmap.copyPixelsFromBuffer(pixels);
            canvas.drawBitmap(presenterBitmap, 0, 0, null);
        } catch (Exception e) {
            // surface gone / bitmap issue: skip this frame
        } finally {
            if (canvas != null) {
                try {
                    holder.unlockCanvasAndPost(canvas);
                } catch (Exception e) {
                    // ignore
                }
            }
        }
    }
}
