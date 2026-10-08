package com.fpgui;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.view.MotionEvent;
import android.view.ViewConfiguration;

/**
 * Turns a touch long-press into a mouse right-click.
 *
 * Touch devices have no right button, so a finger long-press is mapped to a
 * right-button DOWN/UP pair at the press position - exactly what a real mouse
 * right-click sends (see FpMouseGesture). The DOWN of the original touch is
 * still forwarded (focus/caret placement), but once the long-press fired the
 * remaining MOVE/UP events are swallowed so no left-click is produced.
 *
 * Only non-mouse events are handled; a real mouse keeps its own buttons.
 */
final class FpLongPressGesture {

    interface Sink {
        void send(int action, int button, float x, float y);
    }

    private static final int RIGHT_BUTTON = 2;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Sink sink;
    private final int timeout;
    private final int slop;

    private boolean down;
    private boolean fired;
    private float downX;
    private float downY;

    private final Runnable fire = new Runnable() {
        @Override
        public void run() {
            if (!down || fired) {
                return;
            }
            fired = true;
            // A complete right-button click: fpGUI opens the context menu on
            // the right-button release (TfpgBaseEdit.HandleRMouseUp etc.).
            sink.send(MotionEvent.ACTION_DOWN, RIGHT_BUTTON, downX, downY);
            sink.send(MotionEvent.ACTION_UP, RIGHT_BUTTON, downX, downY);
        }
    };

    FpLongPressGesture(Context context, Sink sink) {
        this.sink = sink;
        this.timeout = ViewConfiguration.getLongPressTimeout();
        this.slop = ViewConfiguration.get(context).getScaledTouchSlop();
    }

    private void cancelTimer() {
        handler.removeCallbacks(fire);
    }

    /** Handles one non-mouse touch event. Returns true when the event must be
     *  swallowed (the long-press already turned into a right-click). */
    boolean handle(MotionEvent event) {
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                down = true;
                fired = false;
                downX = event.getX();
                downY = event.getY();
                cancelTimer();
                handler.postDelayed(fire, timeout);
                return false;

            case MotionEvent.ACTION_MOVE:
                if (fired) {
                    return true;
                }
                final float dx = event.getX() - downX;
                final float dy = event.getY() - downY;
                if (dx * dx + dy * dy > (float) slop * slop) {
                    // A drag, not a long-press.
                    cancelTimer();
                    down = false;
                }
                return false;

            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                cancelTimer();
                down = false;
                final boolean swallow = fired;
                fired = false;
                return swallow;

            default:
                return fired;
        }
    }
}
