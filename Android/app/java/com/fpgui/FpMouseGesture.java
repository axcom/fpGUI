package com.fpgui;

import android.view.InputDevice;
import android.view.MotionEvent;

/**
 * Maps mouse MotionEvents to exactly one DOWN/UP pair per gesture.
 *
 * Android delivers a mouse click as ACTION_DOWN + ACTION_BUTTON_PRESS
 * (ACTION_BUTTON_RELEASE + ACTION_UP on release), but the plain
 * ACTION_DOWN/UP may carry an empty getButtonState() and some emulators only
 * send one of the two sequences. The DOWN is therefore deferred until the
 * button is known (BUTTON_PRESS / MOVE / UP) and duplicates are suppressed,
 * so Pascal always receives one DOWN and one UP with the correct button -
 * right-click context menus depend on the right button being recognised.
 */
final class FpMouseGesture {

    interface Sink {
        void send(int action, int button, float x, float y);
    }

    private boolean active;
    private boolean pendingDown;
    private int pendingButton;
    private int lastButton;

    static boolean isMouse(MotionEvent event) {
        return (event.getSource() & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE;
    }

    static int actionButtonToId(int actionButton) {
        if (actionButton == MotionEvent.BUTTON_SECONDARY) {
            return 2;
        }
        if (actionButton == MotionEvent.BUTTON_TERTIARY) {
            return 3;
        }
        if (actionButton == MotionEvent.BUTTON_PRIMARY) {
            return 1;
        }
        return 0;
    }

    static int buttonStateToId(int buttonState) {
        if ((buttonState & MotionEvent.BUTTON_SECONDARY) != 0) {
            return 2;
        }
        if ((buttonState & MotionEvent.BUTTON_TERTIARY) != 0) {
            return 3;
        }
        if ((buttonState & MotionEvent.BUTTON_PRIMARY) != 0) {
            return 1;
        }
        return 0;
    }

    /** Returns the button to use for a deferred DOWN (never 0). */
    private int pendingOrPrimary() {
        return pendingButton != 0 ? pendingButton : 1;
    }

    void handle(MotionEvent event, Sink sink) {
        final float x = event.getX();
        final float y = event.getY();
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                if (active) {
                    return;
                }
                active = true;
                pendingDown = true;
                pendingButton = buttonStateToId(event.getButtonState());
                return;   // wait for the real button

            case MotionEvent.ACTION_BUTTON_PRESS: {
                final int b = actionButtonToId(event.getActionButton());
                if (pendingDown) {
                    pendingDown = false;
                    lastButton = b != 0 ? b : pendingOrPrimary();
                    sink.send(MotionEvent.ACTION_DOWN, lastButton, x, y);
                    return;
                }
                if (!active) {
                    active = true;
                    lastButton = b != 0 ? b : 1;
                    sink.send(MotionEvent.ACTION_DOWN, lastButton, x, y);
                }
                return;
            }

            case MotionEvent.ACTION_MOVE:
                if (pendingDown) {
                    pendingDown = false;
                    lastButton = pendingOrPrimary();
                    sink.send(MotionEvent.ACTION_DOWN, lastButton, x, y);
                }
                sink.send(MotionEvent.ACTION_MOVE, lastButton, x, y);
                return;

            case MotionEvent.ACTION_BUTTON_RELEASE: {
                final int b = actionButtonToId(event.getActionButton());
                if (pendingDown) {
                    pendingDown = false;
                    lastButton = b != 0 ? b : pendingOrPrimary();
                    sink.send(MotionEvent.ACTION_DOWN, lastButton, x, y);
                }
                if (b != 0) {
                    lastButton = b;
                }
                if (active) {
                    sink.send(MotionEvent.ACTION_UP, lastButton, x, y);
                    active = false;
                }
                return;
            }

            case MotionEvent.ACTION_UP:
                if (pendingDown) {
                    pendingDown = false;
                    lastButton = pendingOrPrimary();
                    sink.send(MotionEvent.ACTION_DOWN, lastButton, x, y);
                }
                if (active) {
                    sink.send(MotionEvent.ACTION_UP, lastButton, x, y);
                    active = false;
                }
                return;

            case MotionEvent.ACTION_CANCEL:
                if (pendingDown) {
                    pendingDown = false;
                    lastButton = pendingOrPrimary();
                    sink.send(MotionEvent.ACTION_DOWN, lastButton, x, y);
                }
                if (active) {
                    sink.send(MotionEvent.ACTION_CANCEL, lastButton, x, y);
                    active = false;
                }
                return;

            default:
                return;
        }
    }
}
