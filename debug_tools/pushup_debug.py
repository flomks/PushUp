"""
Push-Up Debug Tool
==================
Visualises pose detection and push-up counting via webcam.
Uses the same algorithm as the iOS app (elbow angle + state machine).

Requirements:
    pip install opencv-python mediapipe

Run:
    python debug_tools/pushup_debug.py

Controls:
    R  - reset counter
    Q  - quit
    S  - toggle side/front camera hint
"""

import math
import cv2
import mediapipe as mp

# ---------------------------------------------------------------------------
# Configuration  (mirrors PushUpStateMachine.Configuration in Swift)
# ---------------------------------------------------------------------------

DOWN_ANGLE_THRESHOLD  = 90.0   # elbow angle below this  -> DOWN phase
UP_ANGLE_THRESHOLD    = 160.0  # elbow angle above this  -> push-up counted
HYSTERESIS_FRAMES     = 3      # consecutive frames required for transition
COOLDOWN_FRAMES       = 15     # frames to ignore after counting (~500 ms)
MIN_DETECTION_CONF    = 0.6
MIN_TRACKING_CONF     = 0.6

# ---------------------------------------------------------------------------
# Geometry helper  (identical to PushUpDetector.angleBetween in Swift)
# ---------------------------------------------------------------------------

def angle_between(a, vertex, b):
    """Returns the angle at `vertex` in degrees, formed by a-vertex-b."""
    vax = a[0] - vertex[0]
    vay = a[1] - vertex[1]
    vbx = b[0] - vertex[0]
    vby = b[1] - vertex[1]

    mag_a = math.sqrt(vax**2 + vay**2)
    mag_b = math.sqrt(vbx**2 + vby**2)

    if mag_a == 0 or mag_b == 0:
        return None

    dot = vax * vbx + vay * vby
    cos_angle = max(-1.0, min(1.0, dot / (mag_a * mag_b)))
    return math.degrees(math.acos(cos_angle))


def elbow_angle(shoulder, elbow, wrist):
    """Returns elbow angle or None if any landmark is missing."""
    if shoulder is None or elbow is None or wrist is None:
        return None
    return angle_between(shoulder, elbow, wrist)


def averaged_angle(left, right):
    """Average left/right angles; use whichever is available."""
    if left is not None and right is not None:
        return (left + right) / 2.0
    return left if left is not None else right


# ---------------------------------------------------------------------------
# State machine  (mirrors PushUpStateMachine in Swift)
# ---------------------------------------------------------------------------

class PushUpStateMachine:

    IDLE     = "IDLE"
    DOWN     = "DOWN"
    COOLDOWN = "COOLDOWN"

    def __init__(self):
        self.phase                = self.IDLE
        self.push_up_count        = 0
        self.pending_frame_count  = 0
        self.cooldown_remaining   = 0

    def update(self, angle) -> bool:
        """Feed one angle measurement. Returns True when a rep is counted."""
        if self.phase == self.IDLE:
            return self._handle_idle(angle)
        elif self.phase == self.DOWN:
            return self._handle_down(angle)
        else:
            return self._handle_cooldown()

    def _handle_idle(self, angle) -> bool:
        if angle is None:
            self.pending_frame_count = 0
            return False
        if angle < DOWN_ANGLE_THRESHOLD:
            self.pending_frame_count += 1
            if self.pending_frame_count >= HYSTERESIS_FRAMES:
                self.phase = self.DOWN
                self.pending_frame_count = 0
        else:
            self.pending_frame_count = 0
        return False

    def _handle_down(self, angle) -> bool:
        if angle is None:
            self.pending_frame_count = 0
            return False
        if angle > UP_ANGLE_THRESHOLD:
            self.pending_frame_count += 1
            if self.pending_frame_count >= HYSTERESIS_FRAMES:
                self.push_up_count += 1
                self.phase = self.COOLDOWN
                self.cooldown_remaining = COOLDOWN_FRAMES
                self.pending_frame_count = 0
                return True
        else:
            self.pending_frame_count = 0
        return False

    def _handle_cooldown(self) -> bool:
        self.cooldown_remaining -= 1
        if self.cooldown_remaining <= 0:
            self.phase = self.IDLE
        return False

    def reset(self):
        self.phase               = self.IDLE
        self.push_up_count       = 0
        self.pending_frame_count = 0
        self.cooldown_remaining  = 0


# ---------------------------------------------------------------------------
# Landmark helpers
# ---------------------------------------------------------------------------

mp_pose = mp.solutions.pose
LANDMARKS = mp_pose.PoseLandmark

def get_point(landmarks, name, w, h):
    """Returns (x, y) in pixel coords, or None if visibility is low."""
    lm = landmarks[name.value]
    if lm.visibility < 0.3:
        return None
    return (int(lm.x * w), int(lm.y * h))


# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------

PHASE_COLORS = {
    PushUpStateMachine.IDLE:     (200, 200, 200),  # grey
    PushUpStateMachine.DOWN:     (0,   200, 255),  # yellow
    PushUpStateMachine.COOLDOWN: (0,   220,   0),  # green
}

PHASE_LABELS = {
    PushUpStateMachine.IDLE:     "Bereit",
    PushUpStateMachine.DOWN:     "Runter",
    PushUpStateMachine.COOLDOWN: "Hoch!",
}

def draw_angle_arc(frame, vertex, angle, color):
    """Draws the angle value next to the elbow joint."""
    if vertex is None or angle is None:
        return
    cv2.putText(
        frame,
        f"{angle:.0f}deg",
        (vertex[0] + 12, vertex[1] - 12),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        color,
        2,
        cv2.LINE_AA,
    )


def draw_skeleton(frame, landmarks, w, h, phase_color):
    """Draws the relevant joints and bones for push-up detection."""
    joints = {
        "ls": get_point(landmarks, LANDMARKS.LEFT_SHOULDER,  w, h),
        "rs": get_point(landmarks, LANDMARKS.RIGHT_SHOULDER, w, h),
        "le": get_point(landmarks, LANDMARKS.LEFT_ELBOW,     w, h),
        "re": get_point(landmarks, LANDMARKS.RIGHT_ELBOW,    w, h),
        "lw": get_point(landmarks, LANDMARKS.LEFT_WRIST,     w, h),
        "rw": get_point(landmarks, LANDMARKS.RIGHT_WRIST,    w, h),
        "lh": get_point(landmarks, LANDMARKS.LEFT_HIP,       w, h),
        "rh": get_point(landmarks, LANDMARKS.RIGHT_HIP,      w, h),
    }

    bones = [
        ("ls", "le"), ("le", "lw"),   # left arm
        ("rs", "re"), ("re", "rw"),   # right arm
        ("ls", "rs"),                  # shoulders
        ("ls", "lh"), ("rs", "rh"),   # torso sides
        ("lh", "rh"),                  # hips
    ]

    for a, b in bones:
        if joints[a] and joints[b]:
            cv2.line(frame, joints[a], joints[b], (255, 255, 255), 2, cv2.LINE_AA)

    for name, pt in joints.items():
        if pt:
            color = phase_color if name in ("le", "re") else (0, 200, 0)
            cv2.circle(frame, pt, 7, color, -1, cv2.LINE_AA)
            cv2.circle(frame, pt, 7, (255, 255, 255), 1, cv2.LINE_AA)

    return joints


def draw_hud(frame, state_machine, angle, w, h):
    """Draws the counter, phase label, and angle on the frame."""
    phase       = state_machine.phase
    count       = state_machine.push_up_count
    phase_color = PHASE_COLORS[phase]
    phase_label = PHASE_LABELS[phase]

    # Semi-transparent bottom bar
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, h - 110), (w, h), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.55, frame, 0.45, 0, frame)

    # Push-up count (large)
    cv2.putText(
        frame, str(count),
        (w // 2 - 30, h - 20),
        cv2.FONT_HERSHEY_SIMPLEX, 3.0,
        (255, 255, 255), 5, cv2.LINE_AA,
    )

    # Phase pill (top-left)
    label_size, _ = cv2.getTextSize(phase_label, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
    pill_x, pill_y = 16, 16
    cv2.rectangle(
        frame,
        (pill_x - 8, pill_y - 4),
        (pill_x + label_size[0] + 8, pill_y + label_size[1] + 8),
        phase_color, -1, cv2.LINE_AA,
    )
    cv2.putText(
        frame, phase_label,
        (pill_x, pill_y + label_size[1]),
        cv2.FONT_HERSHEY_SIMPLEX, 0.8,
        (0, 0, 0), 2, cv2.LINE_AA,
    )

    # Angle (top-right)
    if angle is not None:
        angle_text = f"Winkel: {angle:.0f}deg"
        cv2.putText(
            frame, angle_text,
            (w - 220, 40),
            cv2.FONT_HERSHEY_SIMPLEX, 0.7,
            (200, 200, 200), 2, cv2.LINE_AA,
        )
    else:
        cv2.putText(
            frame, "Kein Arm erkannt",
            (w - 240, 40),
            cv2.FONT_HERSHEY_SIMPLEX, 0.65,
            (0, 100, 255), 2, cv2.LINE_AA,
        )

    # Controls hint (bottom-left)
    cv2.putText(
        frame, "R=Reset  Q=Quit",
        (12, h - 12),
        cv2.FONT_HERSHEY_SIMPLEX, 0.5,
        (150, 150, 150), 1, cv2.LINE_AA,
    )

    # Threshold bars (right side) -- visual guide for the angle thresholds
    bar_x = w - 28
    bar_top = 60
    bar_bottom = h - 130
    bar_h = bar_bottom - bar_top

    cv2.rectangle(frame, (bar_x, bar_top), (bar_x + 16, bar_bottom), (60, 60, 60), -1)

    if angle is not None:
        # Map angle 0-180 to bar position (0 deg = bottom, 180 deg = top)
        fill_ratio = min(1.0, max(0.0, angle / 180.0))
        fill_y = bar_bottom - int(fill_ratio * bar_h)
        bar_color = phase_color
        cv2.rectangle(frame, (bar_x, fill_y), (bar_x + 16, bar_bottom), bar_color, -1)

    # Threshold markers on the bar
    down_y = bar_bottom - int((DOWN_ANGLE_THRESHOLD / 180.0) * bar_h)
    up_y   = bar_bottom - int((UP_ANGLE_THRESHOLD   / 180.0) * bar_h)
    cv2.line(frame, (bar_x - 4, down_y), (bar_x + 20, down_y), (0, 200, 255), 2)
    cv2.line(frame, (bar_x - 4, up_y),   (bar_x + 20, up_y),   (0, 220,   0), 2)
    cv2.putText(frame, f"{DOWN_ANGLE_THRESHOLD:.0f}", (bar_x - 38, down_y + 5),
                cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 200, 255), 1)
    cv2.putText(frame, f"{UP_ANGLE_THRESHOLD:.0f}",  (bar_x - 38, up_y + 5),
                cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 220,   0), 1)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def main():
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("ERROR: Webcam nicht gefunden. Kamera-Index aendern (VideoCapture(1) etc.)")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    state_machine = PushUpStateMachine()

    pose = mp_pose.Pose(
        min_detection_confidence=MIN_DETECTION_CONF,
        min_tracking_confidence=MIN_TRACKING_CONF,
        model_complexity=1,          # 0=fast, 1=balanced, 2=accurate
    )

    print("Push-Up Debug Tool gestartet.")
    print(f"  DOWN-Schwelle:  < {DOWN_ANGLE_THRESHOLD}deg")
    print(f"  UP-Schwelle:    > {UP_ANGLE_THRESHOLD}deg")
    print(f"  Hysterese:      {HYSTERESIS_FRAMES} Frames")
    print("  R=Reset  Q=Quit")

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        frame = cv2.flip(frame, 1)   # mirror so left/right feel natural
        h, w = frame.shape[:2]

        # Run MediaPipe
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        rgb.flags.writeable = False
        results = pose.process(rgb)
        rgb.flags.writeable = True

        angle = None
        phase_color = PHASE_COLORS[state_machine.phase]

        if results.pose_landmarks:
            lms = results.pose_landmarks.landmark
            joints = draw_skeleton(frame, lms, w, h, phase_color)

            left_angle  = elbow_angle(joints["ls"], joints["le"], joints["lw"])
            right_angle = elbow_angle(joints["rs"], joints["re"], joints["rw"])
            angle       = averaged_angle(left_angle, right_angle)

            # Draw angle values next to elbows
            draw_angle_arc(frame, joints["le"], left_angle,  phase_color)
            draw_angle_arc(frame, joints["re"], right_angle, phase_color)

        # Update state machine
        counted = state_machine.update(angle)
        if counted:
            print(f"  Push-Up #{state_machine.push_up_count} gezaehlt! Winkel: {angle:.1f}deg")

        draw_hud(frame, state_machine, angle, w, h)

        cv2.imshow("PushUp Debug", frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord("q"):
            break
        elif key == ord("r"):
            state_machine.reset()
            print("  Reset.")

    cap.release()
    cv2.destroyAllWindows()
    pose.close()


if __name__ == "__main__":
    main()
