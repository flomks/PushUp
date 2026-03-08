"""
Push-Up Debug Tool
==================
Webcam-basiertes Push-Up Tracking mit MediaPipe Pose Landmarker (Tasks API)
und OpenCV.

Rollenverteilung:
  OpenCV              -- Kamera-Input, Spiegeln, Anzeige, alle Debug-Overlays
  MediaPipe Tasks API -- Skelett-Erkennung, Landmark-Koordinaten (aktueller Standard)
  Eigene Logik        -- Winkelberechnung, State Machine, Formanalyse

Metriken:
  - Ellbogenwinkel links + rechts (gemittelt)
  - Körperlinie Schulter-Hüfte-Knöchel (Hüfte durchhängen / Hintern hoch)
  - Tiefenbewertung der Rep (wie weit runter)
  - Halbe Reps erkennen (runter aber nicht tief genug)
  - Formfehler live eingeblendet

Requirements:
    pip install opencv-python mediapipe

Run:
    python debug_tools/pushup_debug.py

Controls:
    R  -- Reset Zähler und Stats
    Q  -- Beenden
    D  -- Debug-Overlay ein/aus (Gelenk-Labels + Winkel)
    F  -- Formcheck ein/aus (Körperlinie + Warnungen)
"""

from __future__ import annotations

import math
import os
import sys
import tempfile
import urllib.request

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_tasks
from mediapipe.tasks.python import vision as mp_vision
from mediapipe.tasks.python.vision.core.vision_task_running_mode import VisionTaskRunningMode

# ---------------------------------------------------------------------------
# Modell-Download (einmalig, ~10 MB, wird im Temp-Ordner gecacht)
# ---------------------------------------------------------------------------

_MODEL_URL  = (
    "https://storage.googleapis.com/mediapipe-models/"
    "pose_landmarker/pose_landmarker_full/float16/latest/"
    "pose_landmarker_full.task"
)
_MODEL_PATH = os.path.join(tempfile.gettempdir(), "pose_landmarker_full.task")


def _ensure_model() -> str:
    if not os.path.exists(_MODEL_PATH):
        print("Lade MediaPipe Pose-Modell herunter (~10 MB, einmalig)...")
        urllib.request.urlretrieve(_MODEL_URL, _MODEL_PATH)
        print(f"Modell gespeichert: {_MODEL_PATH}")
    return _MODEL_PATH


# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------

# Ellbogenwinkel-Schwellen (Grad) -- identisch mit iOS PushUpStateMachine
DOWN_ANGLE_THRESHOLD = 90.0
UP_ANGLE_THRESHOLD   = 160.0

HYSTERESIS_FRAMES = 3
COOLDOWN_FRAMES   = 15

# Formcheck
BODY_LINE_TOLERANCE_DEG = 15.0
HALF_REP_THRESHOLD      = 120.0

MIN_POSE_CONF     = 0.6
MIN_TRACKING_CONF = 0.6

# Farben (BGR)
COLOR_WHITE  = (255, 255, 255)
COLOR_GREEN  = (0,   220,   0)
COLOR_YELLOW = (0,   220, 220)
COLOR_RED    = (0,    60, 255)
COLOR_GREY   = (160, 160, 160)
COLOR_BLACK  = (0,     0,   0)

PHASE_COLORS  = {"IDLE": COLOR_GREY, "DOWN": COLOR_YELLOW, "COOLDOWN": COLOR_GREEN}
PHASE_LABELS  = {"IDLE": "Bereit",   "DOWN": "Runter",     "COOLDOWN": "Hoch!"}

# ---------------------------------------------------------------------------
# Landmark-Indizes (MediaPipe Pose Landmarker Tasks API)
# https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker
# ---------------------------------------------------------------------------

class LM:
    LEFT_SHOULDER  = 11
    RIGHT_SHOULDER = 12
    LEFT_ELBOW     = 13
    RIGHT_ELBOW    = 14
    LEFT_WRIST     = 15
    RIGHT_WRIST    = 16
    LEFT_HIP       = 23
    RIGHT_HIP      = 24
    LEFT_KNEE      = 25
    RIGHT_KNEE     = 26
    LEFT_ANKLE     = 27
    RIGHT_ANKLE    = 28


_JOINT_INDICES: dict[str, int] = {
    "ls": LM.LEFT_SHOULDER,  "rs": LM.RIGHT_SHOULDER,
    "le": LM.LEFT_ELBOW,     "re": LM.RIGHT_ELBOW,
    "lw": LM.LEFT_WRIST,     "rw": LM.RIGHT_WRIST,
    "lh": LM.LEFT_HIP,       "rh": LM.RIGHT_HIP,
    "lk": LM.LEFT_KNEE,      "rk": LM.RIGHT_KNEE,
    "la": LM.LEFT_ANKLE,     "ra": LM.RIGHT_ANKLE,
}

VIS_MIN = 0.35

# ---------------------------------------------------------------------------
# Geometrie
# ---------------------------------------------------------------------------

def angle_between(a, vertex, b) -> float | None:
    if a is None or vertex is None or b is None:
        return None
    vax, vay = a[0] - vertex[0], a[1] - vertex[1]
    vbx, vby = b[0] - vertex[0], b[1] - vertex[1]
    mag_a, mag_b = math.hypot(vax, vay), math.hypot(vbx, vby)
    if mag_a == 0 or mag_b == 0:
        return None
    cos_a = max(-1.0, min(1.0, (vax * vbx + vay * vby) / (mag_a * mag_b)))
    return math.degrees(math.acos(cos_a))


def averaged(a, b) -> float | None:
    if a is not None and b is not None:
        return (a + b) / 2.0
    return a if a is not None else b


# ---------------------------------------------------------------------------
# Landmark-Extraktion
# ---------------------------------------------------------------------------

def extract_joints(landmarks: list, w: int, h: int) -> dict[str, tuple[int, int] | None]:
    result: dict[str, tuple[int, int] | None] = {}
    for key, idx in _JOINT_INDICES.items():
        lm = landmarks[idx]
        result[key] = None if lm.visibility < VIS_MIN else (int(lm.x * w), int(lm.y * h))
    return result


# ---------------------------------------------------------------------------
# Formanalyse
# ---------------------------------------------------------------------------

class FormAnalyser:

    def __init__(self) -> None:
        self.min_elbow_angle_this_rep: float | None = None
        self.half_rep_count: int = 0

    def update(self, joints: dict, elbow_angle_val: float | None, phase: str) -> list[str]:
        warnings: list[str] = []

        # Körperlinie
        deviation = self._body_line_deviation(joints)
        if deviation is not None:
            if deviation > BODY_LINE_TOLERANCE_DEG + 20:
                warnings.append(f"Hufte haengt durch! ({deviation:.0f}deg)")
            elif deviation > BODY_LINE_TOLERANCE_DEG:
                warnings.append(f"Koerperlinie pruefen ({deviation:.0f}deg)")

        # Tiefsten Punkt tracken
        if phase == "DOWN" and elbow_angle_val is not None:
            prev = self.min_elbow_angle_this_rep
            self.min_elbow_angle_this_rep = (
                elbow_angle_val if prev is None else min(prev, elbow_angle_val)
            )

        # Rep abgeschlossen -> Tiefe bewerten
        if phase == "COOLDOWN" and self.min_elbow_angle_this_rep is not None:
            if self.min_elbow_angle_this_rep > DOWN_ANGLE_THRESHOLD:
                warnings.append(f"Nicht tief genug! Min: {self.min_elbow_angle_this_rep:.0f}deg")
            self.min_elbow_angle_this_rep = None

        # Zurück zu IDLE ohne vollständige Rep -> halbe Rep
        if phase == "IDLE" and self.min_elbow_angle_this_rep is not None:
            if self.min_elbow_angle_this_rep > HALF_REP_THRESHOLD:
                self.half_rep_count += 1
                warnings.append(f"Halbe Rep! ({self.min_elbow_angle_this_rep:.0f}deg)")
            self.min_elbow_angle_this_rep = None

        return warnings

    def reset(self) -> None:
        self.min_elbow_angle_this_rep = None
        self.half_rep_count = 0

    @staticmethod
    def _body_line_deviation(joints: dict) -> float | None:
        left  = angle_between(joints.get("ls"), joints.get("lh"), joints.get("la"))
        right = angle_between(joints.get("rs"), joints.get("rh"), joints.get("ra"))
        val   = averaged(left, right)
        return None if val is None else abs(180.0 - val)


# ---------------------------------------------------------------------------
# State Machine (identisch mit PushUpStateMachine.swift)
# ---------------------------------------------------------------------------

class PushUpStateMachine:

    IDLE = "IDLE"; DOWN = "DOWN"; COOLDOWN = "COOLDOWN"

    def __init__(self) -> None:
        self.phase = self.IDLE
        self.push_up_count = 0
        self.pending_frame_count = 0
        self.cooldown_remaining = 0

    def update(self, angle: float | None) -> bool:
        if self.phase == self.IDLE:     return self._idle(angle)
        if self.phase == self.DOWN:     return self._down(angle)
        return self._cooldown()

    def _idle(self, angle: float | None) -> bool:
        if angle is None: self.pending_frame_count = 0; return False
        if angle < DOWN_ANGLE_THRESHOLD:
            self.pending_frame_count += 1
            if self.pending_frame_count >= HYSTERESIS_FRAMES:
                self.phase = self.DOWN; self.pending_frame_count = 0
        else:
            self.pending_frame_count = 0
        return False

    def _down(self, angle: float | None) -> bool:
        if angle is None: self.pending_frame_count = 0; return False
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

    def _cooldown(self) -> bool:
        self.cooldown_remaining -= 1
        if self.cooldown_remaining <= 0: self.phase = self.IDLE
        return False

    def reset(self) -> None:
        self.phase = self.IDLE; self.push_up_count = 0
        self.pending_frame_count = 0; self.cooldown_remaining = 0


# ---------------------------------------------------------------------------
# OpenCV Zeichnen
# ---------------------------------------------------------------------------

_BONES = [
    ("ls","le"),("le","lw"), ("rs","re"),("re","rw"),  # Arme
    ("ls","rs"),                                         # Schultern
    ("ls","lh"),("rs","rh"),("lh","rh"),                # Torso
    ("lh","lk"),("lk","la"),("rh","rk"),("rk","ra"),   # Beine
]
_KEY_JOINTS = {"ls","rs","le","re","lw","rw"}


def draw_skeleton(frame, joints: dict, phase_color: tuple, show_debug: bool) -> None:
    for a, b in _BONES:
        pa, pb = joints.get(a), joints.get(b)
        if pa and pb:
            cv2.line(frame, pa, pb, COLOR_WHITE, 2, cv2.LINE_AA)
    for name, pt in joints.items():
        if pt is None: continue
        is_key = name in _KEY_JOINTS
        cv2.circle(frame, pt, 8 if is_key else 5,
                   phase_color if is_key else COLOR_GREEN, -1, cv2.LINE_AA)
        cv2.circle(frame, pt, 8 if is_key else 5, COLOR_WHITE, 1, cv2.LINE_AA)
        if show_debug and is_key:
            cv2.putText(frame, name, (pt[0]+9, pt[1]-9),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.4, COLOR_WHITE, 1, cv2.LINE_AA)


def draw_body_line(frame, joints: dict, deviation: float | None) -> None:
    for s, h, a in [("ls","lh","la"),("rs","rh","ra")]:
        ps, ph, pa = joints.get(s), joints.get(h), joints.get(a)
        if not (ps and ph and pa): continue
        color = (COLOR_GREY if deviation is None
                 else COLOR_GREEN  if deviation < BODY_LINE_TOLERANCE_DEG
                 else COLOR_YELLOW if deviation < BODY_LINE_TOLERANCE_DEG + 20
                 else COLOR_RED)
        cv2.line(frame, ps, ph, color, 3, cv2.LINE_AA)
        cv2.line(frame, ph, pa, color, 3, cv2.LINE_AA)


def draw_elbow_angles(frame, joints, left_angle, right_angle, phase_color) -> None:
    for key, val in [("le", left_angle), ("re", right_angle)]:
        pt = joints.get(key)
        if pt and val is not None:
            cv2.putText(frame, f"{val:.0f}°", (pt[0]+12, pt[1]-12),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, phase_color, 2, cv2.LINE_AA)


def draw_angle_bar(frame, angle, phase_color, w, h) -> None:
    bx, bt, bb = w-30, 60, h-130
    bh = bb - bt
    cv2.rectangle(frame, (bx, bt), (bx+18, bb), (50,50,50), -1)
    if angle is not None:
        fy = bb - int(min(1.0, max(0.0, angle/180.0)) * bh)
        cv2.rectangle(frame, (bx, fy), (bx+18, bb), phase_color, -1)
    for thr, col, lbl in [(DOWN_ANGLE_THRESHOLD, COLOR_YELLOW, f"{DOWN_ANGLE_THRESHOLD:.0f}"),
                           (UP_ANGLE_THRESHOLD,   COLOR_GREEN,  f"{UP_ANGLE_THRESHOLD:.0f}")]:
        y = bb - int((thr/180.0)*bh)
        cv2.line(frame, (bx-5,y), (bx+23,y), col, 2)
        cv2.putText(frame, lbl, (bx-42,y+5),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.38, col, 1, cv2.LINE_AA)


def draw_form_warnings(frame, warnings: list[str], w: int) -> None:
    for i, msg in enumerate(warnings):
        y = 80 + i*32; cx = w//2
        (tw, th), _ = cv2.getTextSize(msg, cv2.FONT_HERSHEY_SIMPLEX, 0.65, 2)
        cv2.rectangle(frame, (cx-tw//2-8, y-th-4), (cx+tw//2+8, y+6), (0,0,180), -1, cv2.LINE_AA)
        cv2.putText(frame, msg, (cx-tw//2, y),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.65, COLOR_WHITE, 2, cv2.LINE_AA)


def draw_hud(frame, sm: PushUpStateMachine, fa: FormAnalyser,
             angle, w, h, show_debug) -> None:
    phase_color = PHASE_COLORS[sm.phase]
    phase_label = PHASE_LABELS[sm.phase]

    overlay = frame.copy()
    cv2.rectangle(overlay, (0, h-115), (w, h), COLOR_BLACK, -1)
    cv2.addWeighted(overlay, 0.55, frame, 0.45, 0, frame)

    # Zähler
    cs = str(sm.push_up_count)
    (cw, _), _ = cv2.getTextSize(cs, cv2.FONT_HERSHEY_SIMPLEX, 3.2, 6)
    cv2.putText(frame, cs, (w//2 - cw//2, h-18),
                cv2.FONT_HERSHEY_SIMPLEX, 3.2, COLOR_WHITE, 6, cv2.LINE_AA)

    # Phase-Pill
    (lw_px, lh_px), _ = cv2.getTextSize(phase_label, cv2.FONT_HERSHEY_SIMPLEX, 0.85, 2)
    cv2.rectangle(frame, (6,10), (lw_px+26, lh_px+26), phase_color, -1, cv2.LINE_AA)
    cv2.putText(frame, phase_label, (16, lh_px+16),
                cv2.FONT_HERSHEY_SIMPLEX, 0.85, COLOR_BLACK, 2, cv2.LINE_AA)

    # Winkel
    if angle is not None:
        cv2.putText(frame, f"Winkel: {angle:.0f}°", (w-210, 38),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, COLOR_GREY, 2, cv2.LINE_AA)
    else:
        cv2.putText(frame, "Kein Arm erkannt", (w-240, 38),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.65, COLOR_RED, 2, cv2.LINE_AA)

    # Stats
    stats = [f"Reps: {sm.push_up_count}", f"Halbe: {fa.half_rep_count}"]
    if sm.phase == "DOWN" and fa.min_elbow_angle_this_rep is not None:
        stats.append(f"Min: {fa.min_elbow_angle_this_rep:.0f}°")
    for i, line in enumerate(stats):
        cv2.putText(frame, line, (12, h-90+i*28),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, COLOR_GREY, 1, cv2.LINE_AA)

    cv2.putText(frame, "R=Reset  D=Debug  F=Form  Q=Quit", (12, h-8),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (100,100,100), 1, cv2.LINE_AA)
    if show_debug:
        cv2.putText(frame, "DEBUG", (w-80, h-8),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, COLOR_YELLOW, 1, cv2.LINE_AA)


# ---------------------------------------------------------------------------
# Hauptschleife
# ---------------------------------------------------------------------------

def main() -> None:
    model_path = _ensure_model()

    base_options = mp_tasks.BaseOptions(model_asset_path=model_path)
    options      = mp_vision.PoseLandmarkerOptions(
        base_options=base_options,
        running_mode=VisionTaskRunningMode.IMAGE,
        num_poses=1,
        min_pose_detection_confidence=MIN_POSE_CONF,
        min_pose_presence_confidence=MIN_POSE_CONF,
        min_tracking_confidence=MIN_TRACKING_CONF,
        output_segmentation_masks=False,
    )

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("ERROR: Webcam nicht gefunden. Versuche VideoCapture(1).")
        sys.exit(1)

    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    sm = PushUpStateMachine()
    fa = FormAnalyser()
    show_debug = True
    show_form  = True

    print("Push-Up Debug Tool (MediaPipe Tasks API)")
    print(f"  DOWN < {DOWN_ANGLE_THRESHOLD}°  |  UP > {UP_ANGLE_THRESHOLD}°")
    print("  R=Reset  D=Debug  F=Form  Q=Quit")

    with mp_vision.PoseLandmarker.create_from_options(options) as landmarker:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            frame = cv2.flip(frame, 1)
            h, w  = frame.shape[:2]

            rgb    = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = landmarker.detect(mp_img)

            elbow_angle_val: float | None = None
            joints:          dict         = {}
            body_deviation:  float | None = None
            form_warnings:   list[str]    = []

            if result.pose_landmarks:
                landmarks       = result.pose_landmarks[0]
                joints          = extract_joints(landmarks, w, h)
                left_angle      = angle_between(joints.get("ls"), joints.get("le"), joints.get("lw"))
                right_angle     = angle_between(joints.get("rs"), joints.get("re"), joints.get("rw"))
                elbow_angle_val = averaged(left_angle, right_angle)
                body_deviation  = FormAnalyser._body_line_deviation(joints)

                if sm.update(elbow_angle_val):
                    print(f"  Rep #{sm.push_up_count}  |  Winkel: {elbow_angle_val:.1f}°")

                form_warnings = fa.update(joints, elbow_angle_val, sm.phase)
                if form_warnings:
                    print(f"  Formfehler: {', '.join(form_warnings)}")

                phase_color = PHASE_COLORS[sm.phase]
                if show_form:
                    draw_body_line(frame, joints, body_deviation)
                draw_skeleton(frame, joints, phase_color, show_debug)
                if show_debug:
                    draw_elbow_angles(frame, joints, left_angle, right_angle, phase_color)
            else:
                sm.update(None)
                fa.update({}, None, sm.phase)

            draw_angle_bar(frame, elbow_angle_val, PHASE_COLORS[sm.phase], w, h)
            if show_form and form_warnings:
                draw_form_warnings(frame, form_warnings, w)
            draw_hud(frame, sm, fa, elbow_angle_val, w, h, show_debug)

            cv2.imshow("PushUp Debug", frame)

            key = cv2.waitKey(1) & 0xFF
            if   key == ord("q"): break
            elif key == ord("r"): sm.reset(); fa.reset(); print("  Reset.")
            elif key == ord("d"):
                show_debug = not show_debug
                print(f"  Debug: {'AN' if show_debug else 'AUS'}")
            elif key == ord("f"):
                show_form = not show_form
                print(f"  Formcheck: {'AN' if show_form else 'AUS'}")

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
