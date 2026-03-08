"""
Push-Up Debug Tool
==================
Webcam-basiertes Push-Up Tracking mit MediaPipe Pose Landmarker (Tasks API)
und OpenCV.

Rollenverteilung:
  OpenCV              -- Kamera-Input, Spiegeln, Anzeige, alle Overlays
  MediaPipe Tasks API -- Skelett-Erkennung, Landmark-Koordinaten
  PushUpAnalyser      -- State Machine + Formanalyse als eine kohärente Einheit

Metriken:
  - Ellbogenwinkel links + rechts (gemittelt)
  - Körperlinie Schulter-Hüfte-Knöchel
  - Tiefenbewertung pro Rep
  - Halbe Reps (runter aber nicht tief genug, dann abgebrochen)
  - Formfehler live eingeblendet

Requirements:
    pip install opencv-python mediapipe

Run:
    python debug_tools/pushup_debug.py

Controls:
    R  -- Reset          D  -- Debug-Overlay
    F  -- Formcheck      Q  -- Beenden
"""

from __future__ import annotations

import math
import os
import sys
import tempfile
import urllib.request
from dataclasses import dataclass, field
from enum import Enum, auto

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_tasks
from mediapipe.tasks.python import vision as mp_vision
from mediapipe.tasks.python.vision.core.vision_task_running_mode import VisionTaskRunningMode

# ─────────────────────────────────────────────────────────────────────────────
# Modell
# ─────────────────────────────────────────────────────────────────────────────

# pose_landmarker_lite  -- ~3 MB,  schnellster Start, für Debug-Tool ausreichend
# pose_landmarker_full  -- ~10 MB, genauer, langsamerer Start
# pose_landmarker_heavy -- ~25 MB, genaueste, sehr langsamer Start
_MODEL_NAME = "pose_landmarker_lite"
_MODEL_URL  = (
    f"https://storage.googleapis.com/mediapipe-models/"
    f"pose_landmarker/{_MODEL_NAME}/float16/latest/{_MODEL_NAME}.task"
)
_MODEL_PATH = os.path.join(tempfile.gettempdir(), f"{_MODEL_NAME}.task")


def ensure_model() -> str:
    if not os.path.exists(_MODEL_PATH):
        print("Lade Pose-Modell herunter (~10 MB, einmalig)...")
        urllib.request.urlretrieve(_MODEL_URL, _MODEL_PATH)
        print(f"Gespeichert: {_MODEL_PATH}")
    return _MODEL_PATH


# ─────────────────────────────────────────────────────────────────────────────
# Konfiguration
# ─────────────────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Config:
    # Ellbogenwinkel-Schwellen (identisch mit iOS PushUpStateMachine)
    down_threshold:  float = 90.0    # unter diesem Wert  → DOWN
    up_threshold:    float = 160.0   # über diesem Wert   → Rep gezählt

    # Hysterese & Cooldown
    hysteresis:      int   = 3       # Frames die Bedingung halten muss
    cooldown_frames: int   = 15      # ~500 ms bei 30 FPS

    # Formcheck
    body_line_warn:  float = 15.0    # Abweichung Schulter-Hüfte-Knöchel (Grad)
    body_line_error: float = 35.0    # ab hier roter Alarm
    half_rep_min:    float = 115.0   # Ellbogen muss mindestens so weit runter

    # Körperposition & Varianten-Erkennung
    # Alle Werte arbeiten mit normalisierten Y-Koordinaten (0=oben, 1=unten im Bild).
    # Schulter und Hüfte haben ähnliche Y-Werte wenn die Person horizontal liegt.
    horizontal_y_diff:   float = 0.15  # max. |shoulder_y - hip_y| für "liegt horizontal"
    horizontal_confirm:  int   = 10    # Frames die Bedingung halten muss (Hysterese)
    # Variante: Differenz Handgelenk-Y minus Knöchel-Y (normalisiert)
    # Positiv = Handgelenk tiefer im Bild = Hände tiefer als Füße = Decline
    # Negativ = Knöchel tiefer im Bild   = Füße tiefer als Hände = Incline
    variant_threshold:   float = 0.08  # min. Differenz für Decline/Incline-Erkennung
    variant_confirm:     int   = 20    # Frames für stabile Varianten-Erkennung

    # MediaPipe
    pose_conf:       float = 0.6
    track_conf:      float = 0.6
    vis_min:         float = 0.35    # Mindest-Visibility für Gelenk-Erkennung


CFG = Config()

# ─────────────────────────────────────────────────────────────────────────────
# Farben & Stil  (BGR)
# ─────────────────────────────────────────────────────────────────────────────

class C:
    WHITE   = (255, 255, 255)
    BLACK   = (  0,   0,   0)
    GREY    = (140, 140, 140)
    GREEN   = (  0, 210,  80)
    YELLOW  = ( 30, 210, 255)
    ORANGE  = ( 20, 140, 255)
    RED     = (  0,  60, 220)
    BLUE    = (220, 120,  30)
    DARK    = ( 18,  18,  18)
    # Phasen
    IDLE    = (140, 140, 140)
    DOWN    = ( 30, 210, 255)
    COOLDOWN= (  0, 210,  80)


PHASE_COLOR = {"IDLE": C.IDLE, "DOWN": C.DOWN, "COOLDOWN": C.COOLDOWN}
PHASE_LABEL = {"IDLE": "Bereit", "DOWN": "Runter", "COOLDOWN": "Hoch!"}

FONT       = cv2.FONT_HERSHEY_SIMPLEX
FONT_BOLD  = cv2.FONT_HERSHEY_DUPLEX

# ─────────────────────────────────────────────────────────────────────────────
# Landmark-Indizes  (MediaPipe Pose Landmarker Tasks API)
# ─────────────────────────────────────────────────────────────────────────────

class LM:
    LEFT_SHOULDER  = 11;  RIGHT_SHOULDER = 12
    LEFT_ELBOW     = 13;  RIGHT_ELBOW    = 14
    LEFT_WRIST     = 15;  RIGHT_WRIST    = 16
    LEFT_HIP       = 23;  RIGHT_HIP      = 24
    LEFT_KNEE      = 25;  RIGHT_KNEE     = 26
    LEFT_ANKLE     = 27;  RIGHT_ANKLE    = 28


_JOINT_MAP: dict[str, int] = {
    "ls": LM.LEFT_SHOULDER,  "rs": LM.RIGHT_SHOULDER,
    "le": LM.LEFT_ELBOW,     "re": LM.RIGHT_ELBOW,
    "lw": LM.LEFT_WRIST,     "rw": LM.RIGHT_WRIST,
    "lh": LM.LEFT_HIP,       "rh": LM.RIGHT_HIP,
    "lk": LM.LEFT_KNEE,      "rk": LM.RIGHT_KNEE,
    "la": LM.LEFT_ANKLE,     "ra": LM.RIGHT_ANKLE,
}

Pt = tuple[int, int] | None
Joints = dict[str, Pt]


def extract_joints(landmarks: list, w: int, h: int) -> Joints:
    """Rohe Pixel-Koordinaten — werden für State Machine und Winkelberechnung verwendet."""
    out: Joints = {}
    for key, idx in _JOINT_MAP.items():
        lm = landmarks[idx]
        out[key] = None if lm.visibility < CFG.vis_min else (int(lm.x * w), int(lm.y * h))
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Skeleton Smoother  — EMA-Glättung nur für die Anzeige
#
# Strategie:
#   - Rohe Joints → PushUpAnalyser (Winkel, State Machine) — kein Lag
#   - Geglättete Joints → Renderer (Skelett, Körperlinie, Winkeltext)
#
# EMA-Formel:  smooth = alpha * raw + (1 - alpha) * smooth_prev
#   alpha = 0.35  →  ~3 Frames Glättung, kaum Lag
#
# Reset-Logik:
#   Wenn ein Gelenk für >= RESET_FRAMES Frames fehlt und dann wieder
#   auftaucht, wird der EMA-Zustand sofort auf den neuen Wert gesetzt
#   statt langsam hinzugleiten — verhindert sichtbare "Sprünge".
# ─────────────────────────────────────────────────────────────────────────────

class SkeletonSmoother:
    """
    Exponential Moving Average auf Gelenk-Koordinaten.
    Nur für die Darstellung verwenden — nicht für Winkelberechnung.
    """

    ALPHA       = 0.35   # Glättungsfaktor: höher = reaktiver, niedriger = glatter
    RESET_FRAMES = 6     # Frames ohne Gelenk nach denen der EMA-Zustand resettet wird

    def __init__(self) -> None:
        # Float-Koordinaten des letzten geglätteten Frames
        self._smooth: dict[str, tuple[float, float]] = {}
        # Zählt wie viele Frames ein Gelenk in Folge fehlt
        self._missing: dict[str, int] = {}

    def smooth(self, joints: Joints) -> Joints:
        """
        Gibt geglättete Joints zurück.
        Rohe Joints bleiben unverändert — diese Methode erstellt eine Kopie.
        """
        result: Joints = {}

        for key, pt in joints.items():
            if pt is None:
                # Gelenk fehlt: Fehlzähler erhöhen
                self._missing[key] = self._missing.get(key, 0) + 1
                # Geglätteten Wert behalten solange er noch frisch ist,
                # danach None zurückgeben damit das Gelenk nicht "eingefroren" wirkt
                if self._missing.get(key, 0) <= self.RESET_FRAMES and key in self._smooth:
                    sx, sy = self._smooth[key]
                    result[key] = (int(sx), int(sy))
                else:
                    result[key] = None
                    self._smooth.pop(key, None)
            else:
                missing_count = self._missing.get(key, 0)
                self._missing[key] = 0

                rx, ry = float(pt[0]), float(pt[1])

                if key not in self._smooth or missing_count >= self.RESET_FRAMES:
                    # Erstes Auftreten oder nach längerem Fehlen: direkt setzen
                    self._smooth[key] = (rx, ry)
                else:
                    # EMA
                    sx, sy = self._smooth[key]
                    nx = self.ALPHA * rx + (1.0 - self.ALPHA) * sx
                    ny = self.ALPHA * ry + (1.0 - self.ALPHA) * sy
                    self._smooth[key] = (nx, ny)

                sx, sy = self._smooth[key]
                result[key] = (int(sx), int(sy))

        return result

    def reset(self) -> None:
        self._smooth.clear()
        self._missing.clear()


# ─────────────────────────────────────────────────────────────────────────────
# Körperposition & Push-Up-Variante
#
# Erkennung basiert auf normalisierten Y-Koordinaten der Landmarks
# (lm.y, Wertebereich 0=oben im Bild, 1=unten im Bild).
# Pixel-Koordinaten werden NICHT verwendet — sie hängen von der
# Kameraposition ab und wären unzuverlässig.
#
# Horizontal-Erkennung:
#   Wenn |shoulder_y - hip_y| < horizontal_y_diff liegt die Person
#   annähernd horizontal (Push-Up-Position). Im Stehen ist die Schulter
#   deutlich höher (kleineres Y) als die Hüfte.
#
# Varianten-Erkennung (nur wenn horizontal):
#   wrist_y - ankle_y > +threshold  → Decline  (Füße erhöht, Hände tiefer)
#   wrist_y - ankle_y < -threshold  → Incline  (Hände erhöht, Füße tiefer)
#   sonst                           → Normal
#
# Alle Übergänge haben eine Hysterese (N Frames) damit kurze Ausreißer
# keine falschen Wechsel auslösen.
# ─────────────────────────────────────────────────────────────────────────────

class PushUpVariant(Enum):
    UNKNOWN = auto()   # noch nicht erkannt / Person steht
    NORMAL  = auto()   # Standard Push-Up
    DECLINE = auto()   # Füße erhöht (schwerer)
    INCLINE = auto()   # Hände erhöht (leichter)

    @property
    def label(self) -> str:
        return {
            PushUpVariant.UNKNOWN: "?",
            PushUpVariant.NORMAL:  "Normal",
            PushUpVariant.DECLINE: "Decline",
            PushUpVariant.INCLINE: "Incline",
        }[self]

    @property
    def color(self) -> tuple:
        return {
            PushUpVariant.UNKNOWN: C.GREY,
            PushUpVariant.NORMAL:  C.GREEN,
            PushUpVariant.DECLINE: C.ORANGE,
            PushUpVariant.INCLINE: C.BLUE,
        }[self]


@dataclass
class PositionState:
    is_horizontal: bool          = False
    variant:       PushUpVariant = PushUpVariant.UNKNOWN


class PositionClassifier:
    """
    Erkennt ob die Person horizontal liegt und welche Push-Up-Variante
    sie ausführt. Arbeitet ausschließlich mit normalisierten Landmark-Y-Werten.

    Alle Übergänge sind hysteresiert damit kurze Ausreißer (z.B. ein Frame
    mit schlechter Erkennung) keine falschen Wechsel auslösen.
    """

    def __init__(self, cfg: Config = CFG) -> None:
        self.cfg     = cfg
        self.state   = PositionState()
        # Hysterese-Zähler für Horizontal-Erkennung
        self._horiz_counter: int = 0   # positiv = Frames horizontal, negativ = Frames nicht
        # Hysterese-Zähler für Varianten-Erkennung
        self._variant_counter: dict[PushUpVariant, int] = {}

    def update(self, landmarks: list | None) -> PositionState:
        """
        Verarbeitet einen Frame. Gibt den aktuellen PositionState zurück.
        landmarks: rohe MediaPipe NormalizedLandmark-Liste oder None.
        """
        if landmarks is None:
            self._decay()
            return self.state

        # Normalisierte Y-Werte der relevanten Punkte
        # Mittelwert links/rechts für Robustheit
        def y(idx_a: int, idx_b: int) -> float | None:
            la, lb = landmarks[idx_a], landmarks[idx_b]
            va = la.y if la.visibility >= self.cfg.vis_min else None
            vb = lb.y if lb.visibility >= self.cfg.vis_min else None
            if va is not None and vb is not None:
                return (va + vb) / 2.0
            return va if va is not None else vb

        shoulder_y = y(LM.LEFT_SHOULDER, LM.RIGHT_SHOULDER)
        hip_y      = y(LM.LEFT_HIP,      LM.RIGHT_HIP)
        wrist_y    = y(LM.LEFT_WRIST,    LM.RIGHT_WRIST)
        ankle_y    = y(LM.LEFT_ANKLE,    LM.RIGHT_ANKLE)

        # ── Horizontal-Erkennung ──────────────────────────────────────────
        is_horiz_now = (
            shoulder_y is not None
            and hip_y is not None
            and abs(shoulder_y - hip_y) < self.cfg.horizontal_y_diff
        )

        if is_horiz_now:
            self._horiz_counter = min(
                self._horiz_counter + 1, self.cfg.horizontal_confirm
            )
        else:
            self._horiz_counter = max(self._horiz_counter - 1, 0)

        self.state.is_horizontal = self._horiz_counter >= self.cfg.horizontal_confirm

        # ── Varianten-Erkennung (nur wenn horizontal) ─────────────────────
        if not self.state.is_horizontal or wrist_y is None or ankle_y is None:
            self._variant_counter.clear()
            if not self.state.is_horizontal:
                self.state.variant = PushUpVariant.UNKNOWN
            return self.state

        diff = wrist_y - ankle_y   # positiv = Hände tiefer = Decline

        if diff > self.cfg.variant_threshold:
            raw_variant = PushUpVariant.DECLINE
        elif diff < -self.cfg.variant_threshold:
            raw_variant = PushUpVariant.INCLINE
        else:
            raw_variant = PushUpVariant.NORMAL

        # Hysterese: Variante muss N Frames stabil sein
        for v in list(PushUpVariant):
            if v == PushUpVariant.UNKNOWN:
                continue
            if v == raw_variant:
                self._variant_counter[v] = min(
                    self._variant_counter.get(v, 0) + 1,
                    self.cfg.variant_confirm,
                )
            else:
                self._variant_counter[v] = max(
                    self._variant_counter.get(v, 0) - 1, 0
                )

        # Variante mit höchstem Zähler gewinnt (muss Schwelle erreicht haben)
        best_v, best_c = PushUpVariant.NORMAL, 0
        for v, c in self._variant_counter.items():
            if c >= self.cfg.variant_confirm and c > best_c:
                best_v, best_c = v, c

        self.state.variant = best_v
        return self.state

    def _decay(self) -> None:
        """Zähler langsam abbauen wenn keine Landmarks vorhanden."""
        self._horiz_counter = max(self._horiz_counter - 1, 0)
        if self._horiz_counter == 0:
            self.state.is_horizontal = False
            self.state.variant       = PushUpVariant.UNKNOWN

    def reset(self) -> None:
        self.state            = PositionState()
        self._horiz_counter   = 0
        self._variant_counter = {}


# ─────────────────────────────────────────────────────────────────────────────
# Geometrie
# ─────────────────────────────────────────────────────────────────────────────

def angle_at(a: Pt, vertex: Pt, b: Pt) -> float | None:
    """Winkel am Scheitelpunkt `vertex` in Grad. None wenn ein Punkt fehlt."""
    if a is None or vertex is None or b is None:
        return None
    ax, ay = a[0] - vertex[0], a[1] - vertex[1]
    bx, by = b[0] - vertex[0], b[1] - vertex[1]
    ma, mb = math.hypot(ax, ay), math.hypot(bx, by)
    if ma == 0 or mb == 0:
        return None
    return math.degrees(math.acos(max(-1.0, min(1.0, (ax*bx + ay*by) / (ma*mb)))))


def best(a: float | None, b: float | None) -> float | None:
    """Mittelwert wenn beide vorhanden, sonst der vorhandene Wert."""
    if a is not None and b is not None:
        return (a + b) / 2.0
    return a if a is not None else b


# ─────────────────────────────────────────────────────────────────────────────
# Phase-Enum
# ─────────────────────────────────────────────────────────────────────────────

class Phase(Enum):
    IDLE     = auto()
    DOWN     = auto()
    COOLDOWN = auto()

    @property
    def key(self) -> str:
        return self.name


# ─────────────────────────────────────────────────────────────────────────────
# PushUpAnalyser  — State Machine + Formanalyse als eine Einheit
#
# Bug-Fix gegenüber vorheriger Version:
#   FormAnalyser.update() wurde NACH sm.update() aufgerufen. Wenn die State
#   Machine in diesem Frame von DOWN → COOLDOWN wechselte, sah der
#   FormAnalyser bereits phase=COOLDOWN, aber min_elbow_angle_this_rep war
#   noch nicht für die COOLDOWN-Prüfung bereit (DOWN-Tracking lief im
#   gleichen Frame noch nicht). Außerdem wurde die halbe-Rep-Logik nie
#   getriggert weil man von DOWN direkt zu COOLDOWN geht — nie zu IDLE ohne
#   Rep.
#
#   Fix: State Machine und Formanalyse sind jetzt eine Klasse. Die Übergänge
#   werden explizit als Events behandelt (on_enter_down, on_rep_counted,
#   on_rep_aborted) statt durch nachträgliches Phase-Vergleichen.
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class RepResult:
    """Ergebnis einer abgeschlossenen oder abgebrochenen Rep."""
    counted:     bool         # True = vollständige Rep
    half:        bool         # True = abgebrochen (halbe Rep)
    min_angle:   float | None # tiefster Ellbogenwinkel dieser Rep
    warnings:    list[str] = field(default_factory=list)


class PushUpAnalyser:
    """
    Kombiniert State Machine und Formanalyse.
    Verarbeitet einen Winkelwert + Gelenke pro Frame.
    Gibt RepResult zurück wenn eine Rep abgeschlossen oder abgebrochen wurde.
    """

    def __init__(self, cfg: Config = CFG) -> None:
        self.cfg              = cfg
        self.phase            = Phase.IDLE
        self.rep_count        = 0
        self.half_count       = 0
        self._pending         = 0          # Hysterese-Zähler
        self._cooldown_left   = 0
        self._min_angle: float | None = None   # tiefster Winkel dieser Rep

    # ── Public API ────────────────────────────────────────────────────────────

    def update(
        self,
        elbow_angle: float | None,
        joints: Joints,
    ) -> tuple[list[str], RepResult | None]:
        """
        Verarbeitet einen Frame.
        Gibt (frame_warnings, rep_result) zurück.
          frame_warnings  -- Formfehler die JETZT aktiv sind (Körperlinie etc.)
          rep_result      -- gesetzt wenn in diesem Frame eine Rep endete
        """
        frame_warnings = self._check_body_line(joints)
        rep_result     = None

        if self.phase == Phase.IDLE:
            rep_result = self._tick_idle(elbow_angle)
        elif self.phase == Phase.DOWN:
            rep_result = self._tick_down(elbow_angle)
        else:
            self._tick_cooldown()

        return frame_warnings, rep_result

    def reset(self) -> None:
        self.phase          = Phase.IDLE
        self.rep_count      = 0
        self.half_count     = 0
        self._pending       = 0
        self._cooldown_left = 0
        self._min_angle     = None

    # ── State-Tick-Methoden ───────────────────────────────────────────────────

    def _tick_idle(self, angle: float | None) -> RepResult | None:
        if angle is None:
            self._pending = 0
            return None
        if angle < self.cfg.down_threshold:
            self._pending += 1
            if self._pending >= self.cfg.hysteresis:
                # Übergang IDLE → DOWN
                self.phase    = Phase.DOWN
                self._pending = 0
                self._min_angle = angle   # ersten Wert sofort setzen
        else:
            self._pending = 0
        return None

    def _tick_down(self, angle: float | None) -> RepResult | None:
        if angle is None:
            # Pose verloren während DOWN → halbe Rep
            return self._abort_rep("Pose verloren")

        # Tiefsten Punkt tracken
        if self._min_angle is None or angle < self._min_angle:
            self._min_angle = angle

        if angle > self.cfg.up_threshold:
            self._pending += 1
            if self._pending >= self.cfg.hysteresis:
                # Vollständige Rep
                return self._complete_rep()
        else:
            self._pending = 0

        return None

    def _tick_cooldown(self) -> None:
        self._cooldown_left -= 1
        if self._cooldown_left <= 0:
            self.phase = Phase.IDLE

    # ── Rep-Abschluss ─────────────────────────────────────────────────────────

    def _complete_rep(self) -> RepResult:
        self.rep_count     += 1
        self.phase          = Phase.COOLDOWN
        self._cooldown_left = self.cfg.cooldown_frames
        self._pending       = 0

        warnings: list[str] = []
        min_a = self._min_angle
        if min_a is not None and min_a > self.cfg.down_threshold:
            warnings.append(f"Nicht tief genug (min {min_a:.0f}°)")

        result = RepResult(counted=True, half=False, min_angle=min_a, warnings=warnings)
        self._min_angle = None
        return result

    def _abort_rep(self, reason: str = "") -> RepResult:
        """
        Wird aufgerufen wenn die Person aus DOWN zurück zu IDLE geht
        ohne die UP-Schwelle zu erreichen (halbe Rep).
        """
        min_a = self._min_angle
        is_half = min_a is not None and min_a <= self.cfg.half_rep_min

        if is_half:
            self.half_count += 1

        self.phase      = Phase.IDLE
        self._pending   = 0
        self._min_angle = None

        warnings = []
        if is_half:
            label = f"Halbe Rep! (min {min_a:.0f}°)"
            if reason:
                label += f" – {reason}"
            warnings.append(label)

        return RepResult(counted=False, half=is_half, min_angle=min_a, warnings=warnings)

    # ── Formcheck ─────────────────────────────────────────────────────────────

    def _check_body_line(self, joints: Joints) -> list[str]:
        """Prüft Schulter-Hüfte-Knöchel-Linie. Gibt Warnungen zurück."""
        left  = angle_at(joints.get("ls"), joints.get("lh"), joints.get("la"))
        right = angle_at(joints.get("rs"), joints.get("rh"), joints.get("ra"))
        val   = best(left, right)
        if val is None:
            return []
        dev = abs(180.0 - val)
        if dev > self.cfg.body_line_error:
            return [f"Hüfte hängt durch! ({dev:.0f}°)"]
        if dev > self.cfg.body_line_warn:
            return [f"Körperlinie prüfen ({dev:.0f}°)"]
        return []

    # ── Hilfsmethode für Zeichnen ─────────────────────────────────────────────

    def body_line_deviation(self, joints: Joints) -> float | None:
        left  = angle_at(joints.get("ls"), joints.get("lh"), joints.get("la"))
        right = angle_at(joints.get("rs"), joints.get("rh"), joints.get("ra"))
        val   = best(left, right)
        return None if val is None else abs(180.0 - val)


# ─────────────────────────────────────────────────────────────────────────────
# Renderer  — alle OpenCV-Zeichenoperationen
# ─────────────────────────────────────────────────────────────────────────────

_BONES = [
    ("ls","le"),("le","lw"),  ("rs","re"),("re","rw"),   # Arme
    ("ls","rs"),                                           # Schultern
    ("ls","lh"),("rs","rh"),  ("lh","rh"),                # Torso
    ("lh","lk"),("lk","la"),  ("rh","rk"),("rk","ra"),   # Beine
]
_KEY_JOINTS = {"ls","rs","le","re","lw","rw"}


class Renderer:

    @staticmethod
    def skeleton(frame, joints: Joints, phase_color: tuple, show_labels: bool) -> None:
        # Knochen
        for a, b in _BONES:
            pa, pb = joints.get(a), joints.get(b)
            if pa and pb:
                cv2.line(frame, pa, pb, (*C.WHITE[:3], 180), 2, cv2.LINE_AA)

        # Gelenke
        for name, pt in joints.items():
            if pt is None:
                continue
            is_key = name in _KEY_JOINTS
            r      = 9 if is_key else 5
            color  = phase_color if is_key else C.GREEN
            # Glow-Effekt: größerer halbtransparenter Kreis dahinter
            if is_key:
                overlay = frame.copy()
                cv2.circle(overlay, pt, r + 5, color, -1, cv2.LINE_AA)
                cv2.addWeighted(overlay, 0.25, frame, 0.75, 0, frame)
            cv2.circle(frame, pt, r, color, -1, cv2.LINE_AA)
            cv2.circle(frame, pt, r, C.WHITE, 1, cv2.LINE_AA)
            if show_labels and is_key:
                cv2.putText(frame, name, (pt[0]+10, pt[1]-10),
                            FONT, 0.38, C.WHITE, 1, cv2.LINE_AA)

    @staticmethod
    def body_line(frame, joints: Joints, deviation: float | None) -> None:
        if deviation is None:
            color = C.GREY
        elif deviation < CFG.body_line_warn:
            color = C.GREEN
        elif deviation < CFG.body_line_error:
            color = C.YELLOW
        else:
            color = C.RED
        for s, h, a in [("ls","lh","la"), ("rs","rh","ra")]:
            ps, ph, pa = joints.get(s), joints.get(h), joints.get(a)
            if ps and ph and pa:
                cv2.line(frame, ps, ph, color, 3, cv2.LINE_AA)
                cv2.line(frame, ph, pa, color, 3, cv2.LINE_AA)

    @staticmethod
    def elbow_angles(frame, joints: Joints, la: float | None,
                     ra: float | None, color: tuple) -> None:
        for key, val in [("le", la), ("re", ra)]:
            pt = joints.get(key)
            if pt is None or val is None:
                continue
            # Hintergrund-Pill für bessere Lesbarkeit
            text = f"{val:.0f}°"
            (tw, th), _ = cv2.getTextSize(text, FONT_BOLD, 0.65, 2)
            tx, ty = pt[0] + 14, pt[1] - 14
            cv2.rectangle(frame, (tx-4, ty-th-2), (tx+tw+4, ty+4),
                          (*C.DARK, 160), -1, cv2.LINE_AA)
            cv2.putText(frame, text, (tx, ty), FONT_BOLD, 0.65, color, 2, cv2.LINE_AA)

    @staticmethod
    def angle_bar(frame, angle: float | None, phase_color: tuple,
                  w: int, h: int) -> None:
        """Schlanker vertikaler Balken rechts mit Schwellenwert-Markierungen."""
        bx, bt, bb = w - 22, 55, h - 125
        bh = bb - bt
        bar_w = 10

        # Hintergrund (abgerundet simuliert durch Rechteck)
        cv2.rectangle(frame, (bx, bt), (bx + bar_w, bb), (40, 40, 40), -1, cv2.LINE_AA)

        if angle is not None:
            ratio = min(1.0, max(0.0, angle / 180.0))
            fy    = bb - int(ratio * bh)
            cv2.rectangle(frame, (bx, fy), (bx + bar_w, bb), phase_color, -1, cv2.LINE_AA)

        # Schwellenwert-Linien
        for thr, col, lbl in [
            (CFG.down_threshold, C.DOWN,     f"{CFG.down_threshold:.0f}°"),
            (CFG.up_threshold,   C.COOLDOWN, f"{CFG.up_threshold:.0f}°"),
        ]:
            y = bb - int((thr / 180.0) * bh)
            cv2.line(frame, (bx - 6, y), (bx + bar_w + 6, y), col, 2, cv2.LINE_AA)
            cv2.putText(frame, lbl, (bx - 38, y + 5),
                        FONT, 0.36, col, 1, cv2.LINE_AA)

    @staticmethod
    def position_badge(frame, pos: PositionState, w: int) -> None:
        """
        Zeigt Körperposition (horizontal/stehend) und Push-Up-Variante
        als Badge oben rechts in der oberen Leiste an.
        """
        if not pos.is_horizontal:
            label = "Stehend"
            color = C.GREY
        else:
            label = pos.variant.label
            color = pos.variant.color

        (tw, th), _ = cv2.getTextSize(label, FONT_BOLD, 0.62, 2)
        px = w - tw - 90   # links vom Winkel-Wert
        py = 10
        cv2.rectangle(frame,
                      (px - 8, py),
                      (px + tw + 8, py + th + 12),
                      (*color[:3],), -1, cv2.LINE_AA)
        # Dunkler Text auf farbigem Hintergrund
        cv2.putText(frame, label, (px, py + th + 4),
                    FONT_BOLD, 0.62, C.BLACK, 2, cv2.LINE_AA)

        # Kleines "Horizontal"-Indikator-Icon (einfache Linie)
        if pos.is_horizontal:
            ix = px - 22
            iy = py + (th + 12) // 2
            cv2.line(frame, (ix - 8, iy), (ix + 8, iy), color, 3, cv2.LINE_AA)
            cv2.circle(frame, (ix - 8, iy), 3, color, -1, cv2.LINE_AA)
            cv2.circle(frame, (ix + 8, iy), 3, color, -1, cv2.LINE_AA)

    @staticmethod
    def warnings(frame, msgs: list[str], w: int, y_start: int = 72) -> None:
        for i, msg in enumerate(msgs):
            y  = y_start + i * 34
            cx = w // 2
            (tw, th), _ = cv2.getTextSize(msg, FONT, 0.62, 2)
            # Pill-Hintergrund
            cv2.rectangle(frame,
                          (cx - tw//2 - 10, y - th - 5),
                          (cx + tw//2 + 10, y + 7),
                          (0, 0, 160), -1, cv2.LINE_AA)
            cv2.rectangle(frame,
                          (cx - tw//2 - 10, y - th - 5),
                          (cx + tw//2 + 10, y + 7),
                          C.RED, 1, cv2.LINE_AA)
            cv2.putText(frame, msg, (cx - tw//2, y),
                        FONT, 0.62, C.WHITE, 2, cv2.LINE_AA)

    @staticmethod
    def hud(frame, analyser: PushUpAnalyser, pos: PositionState,
            angle: float | None, w: int, h: int, show_debug: bool) -> None:
        phase_color = PHASE_COLOR[analyser.phase.key]
        phase_label = PHASE_LABEL[analyser.phase.key]

        # ── Untere Leiste ──────────────────────────────────────────────────
        overlay = frame.copy()
        cv2.rectangle(overlay, (0, h - 110), (w, h), C.DARK, -1)
        cv2.addWeighted(overlay, 0.72, frame, 0.28, 0, frame)

        # Trennlinie
        cv2.line(frame, (0, h - 110), (w, h - 110), (50, 50, 50), 1)

        # Rep-Zähler (groß, Mitte)
        count_str = str(analyser.rep_count)
        (cw, ch), _ = cv2.getTextSize(count_str, FONT_BOLD, 3.4, 6)
        cv2.putText(frame, count_str, (w//2 - cw//2, h - 16),
                    FONT_BOLD, 3.4, C.WHITE, 6, cv2.LINE_AA)

        # Halbe Reps (rechts vom Zähler, klein)
        if analyser.half_count > 0:
            half_str = f"½ {analyser.half_count}"
            cv2.putText(frame, half_str, (w//2 + cw//2 + 12, h - 40),
                        FONT, 0.7, C.ORANGE, 2, cv2.LINE_AA)

        # Stats links unten
        cv2.putText(frame, f"Reps: {analyser.rep_count}",
                    (14, h - 82), FONT, 0.5, C.GREY, 1, cv2.LINE_AA)
        cv2.putText(frame, f"Halbe: {analyser.half_count}",
                    (14, h - 60), FONT, 0.5, C.GREY, 1, cv2.LINE_AA)
        if analyser.phase == Phase.DOWN and analyser._min_angle is not None:
            cv2.putText(frame, f"Min: {analyser._min_angle:.0f}°",
                        (14, h - 38), FONT, 0.5, C.YELLOW, 1, cv2.LINE_AA)

        # Variante rechts unten (neben Steuerung)
        if pos.is_horizontal:
            var_label = pos.variant.label
            var_color = pos.variant.color
            (vw, vh), _ = cv2.getTextSize(var_label, FONT_BOLD, 0.6, 2)
            vx = w - vw - 14
            vy = h - 82
            cv2.rectangle(frame, (vx - 6, vy - vh - 4), (vx + vw + 6, vy + 6),
                          var_color, -1, cv2.LINE_AA)
            cv2.putText(frame, var_label, (vx, vy),
                        FONT_BOLD, 0.6, C.BLACK, 2, cv2.LINE_AA)
            # "Horizontal"-Indikator darunter
            cv2.putText(frame, "Horizontal",
                        (vx - 2, vy + 22), FONT, 0.42, C.GREY, 1, cv2.LINE_AA)
        else:
            cv2.putText(frame, "Stehend",
                        (w - 90, h - 82), FONT, 0.5, C.GREY, 1, cv2.LINE_AA)

        # Steuerung rechts unten
        cv2.putText(frame, "R=Reset  D=Debug  F=Form  Q=Quit",
                    (w - 290, h - 10), FONT, 0.42, (80, 80, 80), 1, cv2.LINE_AA)

        # ── Obere Leiste ───────────────────────────────────────────────────
        overlay2 = frame.copy()
        cv2.rectangle(overlay2, (0, 0), (w, 52), C.DARK, -1)
        cv2.addWeighted(overlay2, 0.65, frame, 0.35, 0, frame)
        cv2.line(frame, (0, 52), (w, 52), (50, 50, 50), 1)

        # Phase-Pill (oben links)
        (lw_px, lh_px), _ = cv2.getTextSize(phase_label, FONT_BOLD, 0.82, 2)
        pill_x, pill_y = 10, 8
        cv2.rectangle(frame,
                      (pill_x, pill_y),
                      (pill_x + lw_px + 20, pill_y + lh_px + 14),
                      phase_color, -1, cv2.LINE_AA)
        cv2.putText(frame, phase_label,
                    (pill_x + 10, pill_y + lh_px + 7),
                    FONT_BOLD, 0.82, C.BLACK, 2, cv2.LINE_AA)

        # Winkel (oben rechts)
        if angle is not None:
            angle_text = f"{angle:.0f}°"
            (aw, ah), _ = cv2.getTextSize(angle_text, FONT_BOLD, 1.1, 2)
            cv2.putText(frame, angle_text,
                        (w - aw - 50, ah + 12),
                        FONT_BOLD, 1.1, phase_color, 2, cv2.LINE_AA)
            # Kleines Label darunter
            cv2.putText(frame, "Ellbogen",
                        (w - aw - 44, ah + 30),
                        FONT, 0.38, C.GREY, 1, cv2.LINE_AA)
        else:
            cv2.putText(frame, "Kein Arm",
                        (w - 110, 36), FONT, 0.6, C.RED, 2, cv2.LINE_AA)

        # DEBUG-Badge
        if show_debug:
            cv2.rectangle(frame, (w - 78, 8), (w - 8, 30), (40, 40, 40), -1, cv2.LINE_AA)
            cv2.putText(frame, "DEBUG", (w - 72, 26),
                        FONT, 0.45, C.YELLOW, 1, cv2.LINE_AA)

        # Fortschrittsbalken unter Phase-Pill (zeigt Hysterese-Fortschritt)
        if analyser._pending > 0:
            progress = min(1.0, analyser._pending / CFG.hysteresis)
            bar_w    = lw_px + 20
            filled   = int(bar_w * progress)
            cv2.rectangle(frame,
                          (pill_x, pill_y + lh_px + 16),
                          (pill_x + bar_w, pill_y + lh_px + 20),
                          (60, 60, 60), -1)
            cv2.rectangle(frame,
                          (pill_x, pill_y + lh_px + 16),
                          (pill_x + filled, pill_y + lh_px + 20),
                          phase_color, -1)


# ─────────────────────────────────────────────────────────────────────────────
# Hauptschleife
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    import time
    model_path = ensure_model()

    # VIDEO-Modus statt IMAGE:
    #   - Modell wird sofort beim create_from_options() initialisiert → kein
    #     Lag beim ersten Frame
    #   - MediaPipe nutzt temporales Tracking zwischen Frames → genauer und
    #     CPU-schonender als IMAGE (kein vollständiger Re-Detect jeden Frame)
    #   - Erfordert monoton steigenden Timestamp in Millisekunden
    options = mp_vision.PoseLandmarkerOptions(
        base_options=mp_tasks.BaseOptions(model_asset_path=model_path),
        running_mode=VisionTaskRunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=CFG.pose_conf,
        min_pose_presence_confidence=CFG.pose_conf,
        min_tracking_confidence=CFG.track_conf,
        output_segmentation_masks=False,
    )

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("ERROR: Webcam nicht gefunden. Versuche VideoCapture(1).")
        sys.exit(1)

    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    analyser    = PushUpAnalyser()
    smoother    = SkeletonSmoother()
    classifier  = PositionClassifier()
    show_debug  = True
    show_form   = True

    print("Push-Up Debug Tool")
    print(f"  Modell: {_MODEL_NAME}")
    print(f"  DOWN < {CFG.down_threshold}°  |  UP > {CFG.up_threshold}°  |  Hysterese: {CFG.hysteresis} Frames")
    print("  R=Reset  D=Debug  F=Form  Q=Quit\n")

    start_time = time.monotonic()   # Referenzzeitpunkt für Timestamps

    with mp_vision.PoseLandmarker.create_from_options(options) as landmarker:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            frame = cv2.flip(frame, 1)
            h, w  = frame.shape[:2]

            # Monoton steigender Timestamp in Millisekunden (VIDEO-Modus Pflicht)
            timestamp_ms = int((time.monotonic() - start_time) * 1000)

            # MediaPipe Pose Detection
            mp_img = mp.Image(
                image_format=mp.ImageFormat.SRGB,
                data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB),
            )
            result = landmarker.detect_for_video(mp_img, timestamp_ms)

            elbow_angle: float | None = None
            joints: Joints            = {}
            all_warnings: list[str]   = []
            raw_lms                   = None

            if result.pose_landmarks:
                raw_lms = result.pose_landmarks[0]
                joints  = extract_joints(raw_lms, w, h)   # roh → für Logik

                # Winkel + State Machine auf rohen Koordinaten (kein Lag)
                left_angle  = angle_at(joints.get("ls"), joints.get("le"), joints.get("lw"))
                right_angle = angle_at(joints.get("rs"), joints.get("re"), joints.get("rw"))
                elbow_angle = best(left_angle, right_angle)

                frame_warnings, rep_result = analyser.update(elbow_angle, joints)
                all_warnings = frame_warnings

                if rep_result is not None:
                    if rep_result.counted:
                        w_str = f"  ✓ Rep #{analyser.rep_count}"
                        if elbow_angle is not None:
                            w_str += f"  |  Winkel: {elbow_angle:.1f}°"
                        if rep_result.warnings:
                            w_str += f"  |  {', '.join(rep_result.warnings)}"
                        print(w_str)
                        all_warnings += rep_result.warnings
                    elif rep_result.half:
                        print(f"  ½ Halbe Rep  |  {', '.join(rep_result.warnings)}")
                        all_warnings += rep_result.warnings

                # Geglättete Koordinaten nur für die Darstellung
                smooth_joints = smoother.smooth(joints)

                phase_color = PHASE_COLOR[analyser.phase.key]
                if show_form:
                    dev = analyser.body_line_deviation(smooth_joints)
                    Renderer.body_line(frame, smooth_joints, dev)
                Renderer.skeleton(frame, smooth_joints, phase_color, show_debug)
                if show_debug:
                    Renderer.elbow_angles(frame, smooth_joints, left_angle, right_angle, phase_color)
            else:
                smoother.smooth({})
                analyser.update(None, {})

            # Körperposition & Variante (rohe Landmarks, unabhängig von Pixel-Coords)
            pos = classifier.update(raw_lms)

            Renderer.angle_bar(frame, elbow_angle, PHASE_COLOR[analyser.phase.key], w, h)
            if show_form and all_warnings:
                Renderer.warnings(frame, all_warnings, w)
            Renderer.hud(frame, analyser, pos, elbow_angle, w, h, show_debug)

            cv2.imshow("PushUp Debug", frame)

            key = cv2.waitKey(1) & 0xFF
            if   key == ord("q"): break
            elif key == ord("r"):
                analyser.reset()
                smoother.reset()
                classifier.reset()
                print("  Reset.")
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
