"""
Push-Up Debug Tool
==================
Webcam-basiertes Push-Up Tracking mit MediaPipe Pose + OpenCV.

Rollenverteilung (wie in der Beschreibung):
  OpenCV    -- Kamera-Input, Spiegeln, Anzeige, alle Debug-Overlays
  MediaPipe -- Skelett-Erkennung, Landmark-Koordinaten
  Eigene Logik -- Winkelberechnung, State Machine, Formanalyse

Metriken:
  - Ellbogenwinkel (links + rechts, gemittelt)
  - Körperlinie Schulter-Hüfte-Knöchel (Hüfte durchhängen / Hintern hoch)
  - Tiefenbewertung der Rep (wie weit runter)
  - Halbe Reps erkennen (runter aber nicht hoch genug)
  - Formfehler live anzeigen

Requirements:
    pip install opencv-python mediapipe

Run:
    python debug_tools/pushup_debug.py

Controls:
    R  -- Reset Zähler und Stats
    Q  -- Beenden
    D  -- Debug-Overlay ein/aus (Landmarks + Winkel)
    F  -- Formcheck ein/aus
"""

from __future__ import annotations
import math
import sys
import cv2
import mediapipe as mp

# ---------------------------------------------------------------------------
# MediaPipe API-Kompatibilität
# Alte API (< 0.10.14): mp.solutions.pose
# Neue API (>= 0.10.14): mp.tasks.vision.PoseLandmarker
# Wir nutzen die alte API wenn verfügbar, sonst die neue.
# ---------------------------------------------------------------------------

_USE_LEGACY_API = hasattr(mp, "solutions") and hasattr(mp.solutions, "pose")

if not _USE_LEGACY_API:
    # Neue Tasks-API
    from mediapipe.tasks import python as mp_tasks
    from mediapipe.tasks.python import vision as mp_vision
    from mediapipe.tasks.python.vision import RunningMode
    import urllib.request, os, tempfile

    _MODEL_URL  = (
        "https://storage.googleapis.com/mediapipe-models/"
        "pose_landmarker/pose_landmarker_lite/float16/latest/"
        "pose_landmarker_lite.task"
    )
    _MODEL_PATH = os.path.join(tempfile.gettempdir(), "pose_landmarker_lite.task")

    def _download_model():
        if not os.path.exists(_MODEL_PATH):
            print("  Lade MediaPipe Pose-Modell herunter (~5 MB)...")
            urllib.request.urlretrieve(_MODEL_URL, _MODEL_PATH)
            print("  Modell gespeichert:", _MODEL_PATH)

    # Landmark-Indizes in der neuen API (identisch mit PoseLandmark enum)
    class _LM:
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

    LM = _LM
else:
    mp_pose = mp.solutions.pose
    LM      = mp_pose.PoseLandmark

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------

# Ellbogenwinkel-Schwellen (Grad) -- identisch mit iOS PushUpStateMachine
DOWN_ANGLE_THRESHOLD = 90.0    # unter diesem Wert -> DOWN-Phase
UP_ANGLE_THRESHOLD   = 160.0   # über diesem Wert  -> Rep gezählt

# Hysterese: wie viele aufeinanderfolgende Frames die Bedingung halten muss
HYSTERESIS_FRAMES = 3
COOLDOWN_FRAMES   = 15         # ~500 ms bei 30 FPS

# Formcheck-Schwellen
BODY_LINE_TOLERANCE_DEG = 15.0  # max. Abweichung Schulter-Hüfte-Knöchel von 180°
MIN_DEPTH_ANGLE         = 90.0  # Ellbogen muss mindestens auf diesen Winkel kommen
HALF_REP_THRESHOLD      = 120.0 # Runter aber nicht tief genug -> halbe Rep

# MediaPipe
MIN_DETECTION_CONF = 0.6
MIN_TRACKING_CONF  = 0.6

# Farben (BGR)
COLOR_WHITE   = (255, 255, 255)
COLOR_GREEN   = (0,   220,   0)
COLOR_YELLOW  = (0,   220, 220)
COLOR_RED     = (0,    60, 255)
COLOR_BLUE    = (255, 160,   0)
COLOR_GREY    = (160, 160, 160)
COLOR_BLACK   = (0,     0,   0)

PHASE_COLORS = {
    "IDLE":     COLOR_GREY,
    "DOWN":     COLOR_YELLOW,
    "COOLDOWN": COLOR_GREEN,
}
PHASE_LABELS = {
    "IDLE":     "Bereit",
    "DOWN":     "Runter",
    "COOLDOWN": "Hoch!",
}

# ---------------------------------------------------------------------------
# Geometrie-Helfer
# ---------------------------------------------------------------------------

def angle_between(a, vertex, b):
    """
    Winkel am Scheitelpunkt `vertex` zwischen den Strahlen a-vertex und b-vertex.
    Gibt None zurück wenn ein Punkt fehlt oder Vektoren die Länge 0 haben.
    """
    if a is None or vertex is None or b is None:
        return None
    vax, vay = a[0] - vertex[0], a[1] - vertex[1]
    vbx, vby = b[0] - vertex[0], b[1] - vertex[1]
    mag_a = math.hypot(vax, vay)
    mag_b = math.hypot(vbx, vby)
    if mag_a == 0 or mag_b == 0:
        return None
    cos_a = max(-1.0, min(1.0, (vax * vbx + vay * vby) / (mag_a * mag_b)))
    return math.degrees(math.acos(cos_a))


def averaged(a, b):
    """Mittelwert zweier optionaler Werte; nimmt den vorhandenen wenn einer None ist."""
    if a is not None and b is not None:
        return (a + b) / 2.0
    return a if a is not None else b


# ---------------------------------------------------------------------------
# Formanalyse
# ---------------------------------------------------------------------------

class FormAnalyser:
    """
    Analysiert die Körperhaltung pro Frame und sammelt Formfehler.

    Prüft:
      1. Körperlinie (Schulter-Hüfte-Knöchel) -- Hüfte durchhängen / Hintern hoch
      2. Tiefe der Rep -- wurde tief genug gegangen?
      3. Halbe Rep -- runter aber nicht weit genug hoch
    """

    def __init__(self):
        self.min_elbow_angle_this_rep: float | None = None  # tiefstes Punkt dieser Rep
        self.half_rep_count = 0
        self._active_warnings: list[str] = []

    def update(self, joints: dict, elbow_angle_val, phase: str) -> list[str]:
        """
        Gibt eine Liste aktiver Formfehler-Strings zurück (leer = alles gut).
        Muss jeden Frame aufgerufen werden.
        """
        warnings = []

        # -- Körperlinie prüfen (nur wenn alle drei Punkte sichtbar) --
        body_line = self._body_line_deviation(joints)
        if body_line is not None:
            if body_line > BODY_LINE_TOLERANCE_DEG + 20:
                warnings.append(f"Hufte haengt durch! ({body_line:.0f}deg)")
            elif body_line > BODY_LINE_TOLERANCE_DEG:
                warnings.append(f"Koerperlinie pruefen ({body_line:.0f}deg)")

        # -- Tiefsten Punkt dieser Rep tracken --
        if phase == "DOWN" and elbow_angle_val is not None:
            if self.min_elbow_angle_this_rep is None:
                self.min_elbow_angle_this_rep = elbow_angle_val
            else:
                self.min_elbow_angle_this_rep = min(
                    self.min_elbow_angle_this_rep, elbow_angle_val
                )

        # -- Tiefe bewerten wenn Rep abgeschlossen (Cooldown beginnt) --
        if phase == "COOLDOWN" and self.min_elbow_angle_this_rep is not None:
            depth = self.min_elbow_angle_this_rep
            if depth > MIN_DEPTH_ANGLE:
                warnings.append(f"Nicht tief genug! Min: {depth:.0f}deg")
            self.min_elbow_angle_this_rep = None  # reset für nächste Rep

        # -- Halbe Rep: war in DOWN aber Winkel nie tief genug --
        if phase == "IDLE" and self.min_elbow_angle_this_rep is not None:
            if self.min_elbow_angle_this_rep > HALF_REP_THRESHOLD:
                self.half_rep_count += 1
                warnings.append(f"Halbe Rep! ({self.min_elbow_angle_this_rep:.0f}deg)")
            self.min_elbow_angle_this_rep = None

        self._active_warnings = warnings
        return warnings

    def reset(self):
        self.min_elbow_angle_this_rep = None
        self.half_rep_count = 0
        self._active_warnings = []

    @staticmethod
    def _body_line_deviation(joints: dict):
        """
        Berechnet die Abweichung der Schulter-Hüfte-Knöchel-Linie von 180°.
        Nutzt die Seite mit besserer Sichtbarkeit.
        Gibt None zurück wenn Punkte fehlen.
        """
        # Linke Seite
        left = angle_between(joints.get("ls"), joints.get("lh"), joints.get("la"))
        # Rechte Seite
        right = angle_between(joints.get("rs"), joints.get("rh"), joints.get("ra"))
        val = averaged(left, right)
        if val is None:
            return None
        # Abweichung von einer geraden Linie (180°)
        return abs(180.0 - val)


# ---------------------------------------------------------------------------
# State Machine
# ---------------------------------------------------------------------------

class PushUpStateMachine:
    """
    Identisch mit PushUpStateMachine.swift in der iOS-App.
    IDLE -> DOWN -> COOLDOWN -> IDLE
    """

    IDLE     = "IDLE"
    DOWN     = "DOWN"
    COOLDOWN = "COOLDOWN"

    def __init__(self):
        self.phase               = self.IDLE
        self.push_up_count       = 0
        self.pending_frame_count = 0
        self.cooldown_remaining  = 0

    def update(self, angle) -> bool:
        """Gibt True zurück wenn in diesem Frame eine Rep gezählt wurde."""
        if self.phase == self.IDLE:
            return self._idle(angle)
        if self.phase == self.DOWN:
            return self._down(angle)
        return self._cooldown()

    def _idle(self, angle) -> bool:
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

    def _down(self, angle) -> bool:
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

    def _cooldown(self) -> bool:
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
# Landmark-Extraktion (MediaPipe -> Pixel-Koordinaten)
# Funktioniert mit alter API (mp.solutions) und neuer Tasks-API.
# ---------------------------------------------------------------------------

VIS_MIN = 0.35   # Mindest-Visibility damit ein Punkt als erkannt gilt

# Mapping: interner Name -> Landmark-Index (neue API) oder Enum (alte API)
_JOINT_MAP = {
    "ls": LM.LEFT_SHOULDER,
    "rs": LM.RIGHT_SHOULDER,
    "le": LM.LEFT_ELBOW,
    "re": LM.RIGHT_ELBOW,
    "lw": LM.LEFT_WRIST,
    "rw": LM.RIGHT_WRIST,
    "lh": LM.LEFT_HIP,
    "rh": LM.RIGHT_HIP,
    "lk": LM.LEFT_KNEE,
    "rk": LM.RIGHT_KNEE,
    "la": LM.LEFT_ANKLE,
    "ra": LM.RIGHT_ANKLE,
}


def _lm_index(name_or_enum):
    """Gibt den Integer-Index zurück, egal ob Enum oder int."""
    return name_or_enum if isinstance(name_or_enum, int) else name_or_enum.value


def get_pt(landmarks, lm_ref, w, h):
    """Gibt (x, y) in Pixeln zurück oder None wenn Visibility zu niedrig."""
    idx = _lm_index(lm_ref)
    lm  = landmarks[idx]
    if lm.visibility < VIS_MIN:
        return None
    return (int(lm.x * w), int(lm.y * h))


def extract_joints(landmarks, w, h) -> dict:
    """Extrahiert alle für Push-Up-Analyse relevanten Gelenke."""
    return {
        key: get_pt(landmarks, lm_ref, w, h)
        for key, lm_ref in _JOINT_MAP.items()
    }


# ---------------------------------------------------------------------------
# OpenCV Zeichnen
# ---------------------------------------------------------------------------

BONES = [
    # Arme
    ("ls", "le"), ("le", "lw"),
    ("rs", "re"), ("re", "rw"),
    # Schultern
    ("ls", "rs"),
    # Torso
    ("ls", "lh"), ("rs", "rh"),
    ("lh", "rh"),
    # Beine
    ("lh", "lk"), ("lk", "la"),
    ("rh", "rk"), ("rk", "ra"),
]

# Gelenke die für Push-Up-Zählung kritisch sind -- werden größer gezeichnet
KEY_JOINTS = {"ls", "rs", "le", "re", "lw", "rw"}


def draw_skeleton(frame, joints: dict, phase_color, show_debug: bool):
    """Zeichnet Knochen-Linien und Gelenk-Punkte."""
    # Knochen
    for a, b in BONES:
        pa, pb = joints.get(a), joints.get(b)
        if pa and pb:
            cv2.line(frame, pa, pb, COLOR_WHITE, 2, cv2.LINE_AA)

    # Gelenke
    for name, pt in joints.items():
        if pt is None:
            continue
        is_key = name in KEY_JOINTS
        radius = 8 if is_key else 5
        color  = phase_color if is_key else COLOR_GREEN
        cv2.circle(frame, pt, radius, color,       -1, cv2.LINE_AA)
        cv2.circle(frame, pt, radius, COLOR_WHITE,  1, cv2.LINE_AA)

        if show_debug and is_key:
            cv2.putText(frame, name, (pt[0] + 9, pt[1] - 9),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.4, COLOR_WHITE, 1, cv2.LINE_AA)


def draw_body_line(frame, joints: dict, deviation):
    """
    Zeichnet die Körperlinie Schulter-Hüfte-Knöchel.
    Grün = gerade, Gelb = leicht schief, Rot = deutlich schief.
    """
    # Nutze die Seite mit mehr sichtbaren Punkten
    for s, h, a in [("ls", "lh", "la"), ("rs", "rh", "ra")]:
        ps, ph, pa = joints.get(s), joints.get(h), joints.get(a)
        if ps and ph and pa:
            if deviation is None:
                color = COLOR_GREY
            elif deviation < BODY_LINE_TOLERANCE_DEG:
                color = COLOR_GREEN
            elif deviation < BODY_LINE_TOLERANCE_DEG + 20:
                color = COLOR_YELLOW
            else:
                color = COLOR_RED
            cv2.line(frame, ps, ph, color, 3, cv2.LINE_AA)
            cv2.line(frame, ph, pa, color, 3, cv2.LINE_AA)


def draw_elbow_angles(frame, joints: dict, left_angle, right_angle, phase_color):
    """Schreibt den Winkelwert neben jeden Ellbogen."""
    for elbow_key, angle_val in [("le", left_angle), ("re", right_angle)]:
        pt = joints.get(elbow_key)
        if pt and angle_val is not None:
            cv2.putText(
                frame, f"{angle_val:.0f}°",
                (pt[0] + 12, pt[1] - 12),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, phase_color, 2, cv2.LINE_AA,
            )


def draw_angle_bar(frame, angle, phase_color, w, h):
    """
    Vertikaler Balken rechts: zeigt aktuellen Winkel + Schwellenwerte.
    """
    bar_x      = w - 30
    bar_top    = 60
    bar_bottom = h - 130
    bar_h      = bar_bottom - bar_top

    # Hintergrund
    cv2.rectangle(frame, (bar_x, bar_top), (bar_x + 18, bar_bottom), (50, 50, 50), -1)

    if angle is not None:
        ratio  = min(1.0, max(0.0, angle / 180.0))
        fill_y = bar_bottom - int(ratio * bar_h)
        cv2.rectangle(frame, (bar_x, fill_y), (bar_x + 18, bar_bottom), phase_color, -1)

    # Schwellenwert-Markierungen
    for threshold, color, label in [
        (DOWN_ANGLE_THRESHOLD, COLOR_YELLOW, f"{DOWN_ANGLE_THRESHOLD:.0f}"),
        (UP_ANGLE_THRESHOLD,   COLOR_GREEN,  f"{UP_ANGLE_THRESHOLD:.0f}"),
    ]:
        y = bar_bottom - int((threshold / 180.0) * bar_h)
        cv2.line(frame, (bar_x - 5, y), (bar_x + 23, y), color, 2)
        cv2.putText(frame, label, (bar_x - 42, y + 5),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.38, color, 1, cv2.LINE_AA)


def draw_form_warnings(frame, warnings: list[str], w):
    """Zeigt Formfehler als rote Warnung oben in der Mitte."""
    for i, msg in enumerate(warnings):
        y = 80 + i * 30
        # Hintergrund-Pill
        (tw, th), _ = cv2.getTextSize(msg, cv2.FONT_HERSHEY_SIMPLEX, 0.65, 2)
        cx = w // 2
        cv2.rectangle(frame,
                      (cx - tw // 2 - 8, y - th - 4),
                      (cx + tw // 2 + 8, y + 6),
                      (0, 0, 180), -1, cv2.LINE_AA)
        cv2.putText(frame, msg, (cx - tw // 2, y),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.65, COLOR_WHITE, 2, cv2.LINE_AA)


def draw_hud(frame, sm: PushUpStateMachine, fa: FormAnalyser,
             angle, w, h, show_debug: bool):
    """Zeichnet Counter, Phase-Pill, Winkel-Info und Stats-Panel."""

    phase_color = PHASE_COLORS[sm.phase]
    phase_label = PHASE_LABELS[sm.phase]

    # Semi-transparente Leiste unten
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, h - 115), (w, h), COLOR_BLACK, -1)
    cv2.addWeighted(overlay, 0.55, frame, 0.45, 0, frame)

    # Zähler (groß, Mitte unten)
    count_str = str(sm.push_up_count)
    (cw, ch), _ = cv2.getTextSize(count_str, cv2.FONT_HERSHEY_SIMPLEX, 3.2, 6)
    cv2.putText(frame, count_str,
                (w // 2 - cw // 2, h - 18),
                cv2.FONT_HERSHEY_SIMPLEX, 3.2, COLOR_WHITE, 6, cv2.LINE_AA)

    # Phase-Pill (oben links)
    (lw_px, lh_px), _ = cv2.getTextSize(phase_label, cv2.FONT_HERSHEY_SIMPLEX, 0.85, 2)
    px, py = 16, 16
    cv2.rectangle(frame,
                  (px - 10, py - 6),
                  (px + lw_px + 10, py + lh_px + 8),
                  phase_color, -1, cv2.LINE_AA)
    cv2.putText(frame, phase_label, (px, py + lh_px),
                cv2.FONT_HERSHEY_SIMPLEX, 0.85, COLOR_BLACK, 2, cv2.LINE_AA)

    # Winkel (oben rechts)
    if angle is not None:
        cv2.putText(frame, f"Winkel: {angle:.0f}°",
                    (w - 210, 38),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, COLOR_GREY, 2, cv2.LINE_AA)
    else:
        cv2.putText(frame, "Kein Arm erkannt",
                    (w - 240, 38),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.65, COLOR_RED, 2, cv2.LINE_AA)

    # Stats-Panel (unten links)
    stats = [
        f"Reps:       {sm.push_up_count}",
        f"Halbe Reps: {fa.half_rep_count}",
    ]
    if sm.phase == "DOWN" and fa.min_elbow_angle_this_rep is not None:
        stats.append(f"Min Winkel: {fa.min_elbow_angle_this_rep:.0f}°")

    for i, line in enumerate(stats):
        cv2.putText(frame, line,
                    (12, h - 90 + i * 28),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, COLOR_GREY, 1, cv2.LINE_AA)

    # Steuerung (ganz unten links)
    cv2.putText(frame, "R=Reset  D=Debug  F=Form  Q=Quit",
                (12, h - 8),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (100, 100, 100), 1, cv2.LINE_AA)

    # Debug-Modus-Indikator
    if show_debug:
        cv2.putText(frame, "DEBUG ON",
                    (w - 110, h - 8),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, COLOR_YELLOW, 1, cv2.LINE_AA)


# ---------------------------------------------------------------------------
# Hauptschleife
# ---------------------------------------------------------------------------

def _process_frame_legacy(pose_ctx, frame):
    """Verarbeitet einen Frame mit der alten mp.solutions API."""
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    rgb.flags.writeable = False
    results = pose_ctx.process(rgb)
    rgb.flags.writeable = True
    if results.pose_landmarks:
        return results.pose_landmarks.landmark
    return None


def _process_frame_new(landmarker, frame):
    """Verarbeitet einen Frame mit der neuen MediaPipe Tasks API."""
    import mediapipe as mp
    from mediapipe.framework.formats import landmark_pb2
    rgb   = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = landmarker.detect(mp_img)
    if result.pose_landmarks:
        return result.pose_landmarks[0]   # erste Person
    return None


def main():
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("ERROR: Webcam nicht gefunden.")
        print("       Versuche VideoCapture(1) oder VideoCapture(2) fuer externe Webcam.")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    sm         = PushUpStateMachine()
    fa         = FormAnalyser()
    show_debug = True
    show_form  = True

    # Pose-Detektor je nach verfügbarer API initialisieren
    if _USE_LEGACY_API:
        print("  MediaPipe: legacy API (mp.solutions.pose)")
        pose_ctx   = mp_pose.Pose(
            min_detection_confidence=MIN_DETECTION_CONF,
            min_tracking_confidence=MIN_TRACKING_CONF,
            model_complexity=1,
        )
        process_fn = lambda f: _process_frame_legacy(pose_ctx, f)
        cleanup_fn = pose_ctx.close
    else:
        print("  MediaPipe: neue Tasks API (PoseLandmarker)")
        _download_model()
        base_opts  = mp_tasks.BaseOptions(model_asset_path=_MODEL_PATH)
        opts       = mp_vision.PoseLandmarkerOptions(
            base_options=base_opts,
            running_mode=RunningMode.IMAGE,
            num_poses=1,
            min_pose_detection_confidence=MIN_DETECTION_CONF,
            min_tracking_confidence=MIN_TRACKING_CONF,
        )
        landmarker = mp_vision.PoseLandmarker.create_from_options(opts)
        process_fn = lambda f: _process_frame_new(landmarker, f)
        cleanup_fn = landmarker.close

    print("Push-Up Debug Tool")
    print(f"  DOWN < {DOWN_ANGLE_THRESHOLD}°  |  UP > {UP_ANGLE_THRESHOLD}°  |  Hysterese: {HYSTERESIS_FRAMES} Frames")
    print("  R=Reset  D=Debug-Overlay  F=Formcheck  Q=Quit")
    print()

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        frame = cv2.flip(frame, 1)
        h, w  = frame.shape[:2]

        landmarks       = process_fn(frame)
        elbow_angle_val = None
        joints          = {}
        body_deviation  = None
        form_warnings   = []

        if landmarks is not None:
            joints = extract_joints(landmarks, w, h)

            left_angle      = angle_between(joints.get("ls"), joints.get("le"), joints.get("lw"))
            right_angle     = angle_between(joints.get("rs"), joints.get("re"), joints.get("rw"))
            elbow_angle_val = averaged(left_angle, right_angle)
            body_deviation  = FormAnalyser._body_line_deviation(joints)

            counted = sm.update(elbow_angle_val)
            if counted:
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
        if key == ord("q"):
            break
        elif key == ord("r"):
            sm.reset()
            fa.reset()
            print("  Reset.")
        elif key == ord("d"):
            show_debug = not show_debug
            print(f"  Debug-Overlay: {'AN' if show_debug else 'AUS'}")
        elif key == ord("f"):
            show_form = not show_form
            print(f"  Formcheck: {'AN' if show_form else 'AUS'}")

    cap.release()
    cv2.destroyAllWindows()
    cleanup_fn()


if __name__ == "__main__":
    main()
