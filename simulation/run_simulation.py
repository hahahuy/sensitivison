import math
import random

# ── PeekState constants ───────────────────────────────────────────────────────
class PeekState:
    CLEAR     = "clear"
    UNCERTAIN = "uncertain"
    PEEKING   = "PEEKING"

# ── PeekConfig ────────────────────────────────────────────────────────────────
class PeekConfig:
    def __init__(self, yaw_hard=30.0, yaw_soft=20.0,
                 pitch_hard=35.0, pitch_soft=25.0,
                 blur_hold_ms=800, enroll_threshold=0.55,
                 no_face_clear_s=2.0):
        self.yaw_hard      = yaw_hard
        self.yaw_soft      = yaw_soft
        self.pitch_hard    = pitch_hard
        self.pitch_soft    = pitch_soft
        self.blur_hold_ms  = blur_hold_ms
        self.enroll_thresh = enroll_threshold
        self.no_face_s     = no_face_clear_s

    @staticmethod
    def low():
        return PeekConfig(40, 30, 45, 35, 500)

    @staticmethod
    def high():
        return PeekConfig(20, 12, 22, 15, 1200)

# ── Detection engine (mirrors peek_detection_service.dart) ────────────────────
class DetectionEngine:
    def __init__(self, config=None):
        self.cfg           = config or PeekConfig()
        self._last_peek_ms = None
        self._last_face_ms = None
        self._current      = PeekState.CLEAR

    def process(self, face_count, yaw=0.0, pitch=0.0,
                has_enrollment=False, enrollment_matches=True, now_ms=0):
        if face_count == 0:
            if (self._last_face_ms is not None and
                    now_ms - self._last_face_ms >= self.cfg.no_face_s * 1000):
                return self._emit(PeekState.CLEAR, now_ms)
            return self._current

        self._last_face_ms = now_ms

        if face_count > 1:
            return self._emit(PeekState.PEEKING, now_ms)

        ay = abs(yaw)
        ap = abs(pitch)

        if ay > self.cfg.yaw_hard or ap > self.cfg.pitch_hard:
            return self._emit(PeekState.PEEKING, now_ms)

        if has_enrollment:
            if not enrollment_matches:
                return self._emit(PeekState.PEEKING, now_ms)
            if ay > self.cfg.yaw_soft or ap > self.cfg.pitch_soft:
                return self._emit(PeekState.PEEKING, now_ms)
            return self._emit(PeekState.CLEAR, now_ms)

        if ay > self.cfg.yaw_soft or ap > self.cfg.pitch_soft:
            return self._emit(PeekState.UNCERTAIN, now_ms)

        return self._emit(PeekState.CLEAR, now_ms)

    def _emit(self, state, now_ms):
        if state == PeekState.PEEKING:
            self._last_peek_ms = now_ms
        elif (self._last_peek_ms is not None and
              now_ms - self._last_peek_ms < self.cfg.blur_hold_ms):
            self._current = PeekState.PEEKING
            return self._current
        self._current = state
        return self._current

# ── Cosine similarity helpers ─────────────────────────────────────────────────
def cosine_sim(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na  = math.sqrt(sum(x * x for x in a))
    nb  = math.sqrt(sum(x * x for x in b))
    denom = na * nb
    return 0.0 if denom == 0 else dot / denom

def l2norm(v):
    n = math.sqrt(sum(x * x for x in v))
    return v if n == 0 else [x / n for x in v]

# ── Frame ─────────────────────────────────────────────────────────────────────
class Frame:
    def __init__(self, offset_ms, face_count=1, yaw=0.0, pitch=0.0,
                 has_enrollment=False, enrollment_matches=True, note=None):
        self.offset_ms         = offset_ms
        self.face_count        = face_count
        self.yaw               = yaw
        self.pitch             = pitch
        self.has_enrollment    = has_enrollment
        self.enrollment_matches = enrollment_matches
        self.note              = note

def fmt_ts(ms):
    mm  = ms // 60000
    ss  = (ms % 60000) // 1000
    ms2 = ms % 1000
    return f"{mm:02d}:{ss:02d}.{ms2:03d}"

def run_scenario(name, frames, assertions, config=None):
    engine  = DetectionEngine(config)
    results = {}

    print()
    print("─" * 58)
    print(f"  Scenario: {name}")
    print("─" * 58)

    for f in frames:
        state = engine.process(
            face_count=f.face_count, yaw=f.yaw, pitch=f.pitch,
            has_enrollment=f.has_enrollment,
            enrollment_matches=f.enrollment_matches,
            now_ms=f.offset_ms,
        )
        results[f.offset_ms] = state
        state_pad = state.ljust(9)
        note_str  = f"  // {f.note}" if f.note else ""
        print(f"  [{fmt_ts(f.offset_ms)}] "
              f"faces={f.face_count} "
              f"yaw={f.yaw:5.1f}deg "
              f"pitch={f.pitch:5.1f}deg  "
              f"-> {state_pad}{note_str}")

    print()
    passed = True
    for at_ms, expected in assertions:
        actual = results.get(at_ms)
        ok = actual == expected
        if not ok:
            passed = False
        tick = "OK" if ok else "FAIL"
        print(f"  [{tick}] At {at_ms:4d}ms: expected {expected:<9s}, got {actual}")
    return passed

# ── Scenarios ──────────────────────────────────────────────────────────────────
scenarios = [
    (
        "A - Owner looking straight (no enrollment)",
        [
            Frame(0,   yaw=2.0, pitch=1.0, note="owner, straight"),
            Frame(100, yaw=4.0, pitch=2.0),
            Frame(200, yaw=3.0, pitch=1.5),
            Frame(300, yaw=5.0, pitch=3.0),
        ],
        [(300, PeekState.CLEAR)],
        None,
    ),
    (
        "B - Shoulder-surfer: hard angle (yaw > 30 deg)",
        [
            Frame(0,   yaw=5.0,  note="owner, clear"),
            Frame(100, yaw=5.0),
            Frame(200, yaw=35.0, note="surfer enters"),
            Frame(300, yaw=38.0),
            Frame(400, yaw=40.0),
        ],
        [
            (100, PeekState.CLEAR),
            (200, PeekState.PEEKING),
            (400, PeekState.PEEKING),
        ],
        None,
    ),
    (
        "C - Debounce: blur holds 800ms after angle resolves",
        [
            Frame(0,   yaw=35.0, note="trigger peek"),
            Frame(300, yaw=5.0,  note="face straightened (300ms < 800ms hold)"),
            Frame(600, yaw=5.0,  note="600ms - still in hold window"),
            Frame(900, yaw=5.0,  note="900ms - hold expired"),
        ],
        [
            (0,   PeekState.PEEKING),
            (300, PeekState.PEEKING),
            (600, PeekState.PEEKING),
            (900, PeekState.CLEAR),
        ],
        None,
    ),
    (
        "D - Two faces -> immediate PEEKING + debounce",
        [
            Frame(0,    face_count=1, yaw=5.0, note="owner alone"),
            Frame(100,  face_count=2, yaw=5.0, note="second person appears"),
            Frame(200,  face_count=2, yaw=3.0),
            Frame(999,  face_count=1, yaw=3.0, note="second leaves (799ms after last trigger @ 200ms - still held)"),
            Frame(1100, face_count=1, yaw=3.0, note="1100ms: 900ms after last trigger @ 200ms - hold expired"),
        ],
        [
            (100,  PeekState.PEEKING),
            (200,  PeekState.PEEKING),
            (999,  PeekState.PEEKING),
            (1100, PeekState.CLEAR),
        ],
        None,
    ),
    (
        "E - No face > noFaceClearSeconds (2s) -> clear",
        [
            Frame(0,    face_count=1, yaw=5.0, note="face present"),
            Frame(500,  face_count=0, note="face gone, 0.5s"),
            Frame(1500, face_count=0, note="still gone, 1.5s (< 2s)"),
            Frame(2500, face_count=0, note="gone 2.5s (> 2s threshold)"),
        ],
        [
            (1500, PeekState.CLEAR),
            (2500, PeekState.CLEAR),
        ],
        None,
    ),
    (
        "F - Soft angle (20-30 deg), no enrollment -> uncertain",
        [
            Frame(0,   yaw=5.0,  note="owner, straight"),
            Frame(100, yaw=25.0, note="soft angle (>20, <30), no enroll"),
            Frame(200, yaw=22.0),
        ],
        [
            (0,   PeekState.CLEAR),
            (100, PeekState.UNCERTAIN),
            (200, PeekState.UNCERTAIN),
        ],
        None,
    ),
    (
        "G - Enrolled owner below soft angle -> clear (match suppresses uncertain)",
        [
            Frame(0,   yaw=5.0,  has_enrollment=True, enrollment_matches=True,
                  note="owner enrolled, straight"),
            Frame(100, yaw=15.0, has_enrollment=True, enrollment_matches=True,
                  note="yaw=15 (below soft=20) + match -> clear"),
            Frame(200, yaw=25.0, has_enrollment=True, enrollment_matches=True,
                  note="yaw=25 (above soft=20) + match -> PEEKING (spec: over-soft-threshold always peeks)"),
            Frame(200, yaw=5.0,  has_enrollment=True, enrollment_matches=False,
                  note="straight but enrollment mismatch (different person) -> PEEKING"),
        ],
        [
            (100, PeekState.CLEAR),
        ],
        None,
    ),
    (
        "H - High-sensitivity config (yawHard=20 deg)",
        [
            Frame(0,   yaw=5.0,  note="straight"),
            Frame(100, yaw=22.0, note="would be uncertain on default, PEEKING on high"),
        ],
        [
            (0,   PeekState.CLEAR),
            (100, PeekState.PEEKING),
        ],
        PeekConfig.high(),
    ),
]

# ── Cosine similarity demo ────────────────────────────────────────────────────
print()
print("=" * 58)
print("  PeekShield  -  Detection Algorithm Simulation v1.0")
print("=" * 58)

print()
print("─" * 58)
print("  Cosine Similarity Verification")
print("─" * 58)

rng = random.Random(42)
owner_emb = l2norm([rng.gauss(0, 1) for _ in range(128)])

rng2 = random.Random(42)
noisy = l2norm([owner_emb[i] + (rng2.random() - 0.5) * 0.05 for i in range(128)])

rng3 = random.Random(999)
diff_emb = l2norm([rng3.gauss(0, 1) for _ in range(128)])

sim_self = cosine_sim(owner_emb, owner_emb)
sim_same = cosine_sim(owner_emb, noisy)
sim_diff = cosine_sim(owner_emb, diff_emb)

print(f"  Self similarity (same vector):   {sim_self:.4f}  (expect ~1.0)")
print(f"  Same person + noise:             {sim_same:.4f}  (expect > 0.55)")
print(f"  Different person:                {sim_diff:.4f}  (expect < 0.55)")

sim_ok = sim_self > 0.999 and sim_same > 0.55 and sim_diff < 0.55
print(f"  [{'OK' if sim_ok else 'FAIL'}] Cosine similarity thresholds are correct")

# ── Run scenarios ─────────────────────────────────────────────────────────────
results_list = []
for name, frames, assertions, cfg in scenarios:
    results_list.append(run_scenario(name, frames, assertions, cfg))

# ── Summary ───────────────────────────────────────────────────────────────────
total_passed = sum(results_list) + (1 if sim_ok else 0)
total        = len(scenarios) + 1
failed       = total - total_passed

print()
print("=" * 58)
print(f"  RESULTS: {total_passed} / {total} passed  |  {failed} failed")
print("=" * 58)
print()

if failed > 0:
    raise SystemExit(f"{failed} scenario(s) FAILED")
