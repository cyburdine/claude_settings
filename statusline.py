#!/usr/bin/env python3
"""Two-row Claude Code status line. No jq, no bash — pure Python 3 stdlib.

Row 1: folder (cyan) · model (white) · tokens (blue) · thinking (green/grey) · effort (by level)
Row 2: ctx meter (per-dot gradient) · 5h meter (risk color) · 7d meter (risk color)
"""

import sys
import json
import time
import math


def c256(code):
    return f"\033[38;5;{code}m"


RESET = "\033[0m"
CYAN = c256(51)
GREEN = c256(49)
YELLOW = c256(226)
RED = c256(196)
GREY = c256(245)      # labels, separators, reset times
DIM_GREY = c256(240)  # unfilled dots

# Row-1 field colors (restores the per-field coloring of the old statusline.sh;
# grey 245 stands in for the old ANSI faint, which is unreadable on black).
MODEL_C = c256(231)   # bright white
TOKENS_C = c256(111)  # light blue
THINK_ON_C = c256(49)
THINK_OFF_C = GREY
EFFORT_C = {
    "max": c256(196),
    "xhigh": c256(201),
    "high": c256(226),
    "med": c256(49),
    "low": GREY,
}

FILLED_CH = "●"
EMPTY_CH = "○"
BAR_WIDTH = 10

# Per-position gradient for the ctx bar: green -> red across 10 dots.
CTX_GRADIENT = [46, 82, 118, 154, 190, 226, 220, 214, 208, 196]

# ctx meter is scaled to a self-imposed working budget, not the model's full
# context window: 600k input tokens = 100% (fully red). Past that, it pins at 100%.
CTX_BUDGET_TOKENS = 600_000

FIVE_HOUR_WINDOW = 18000    # seconds
SEVEN_DAY_WINDOW = 604800   # seconds


def compact_tokens(n):
    try:
        n = int(n)
    except (TypeError, ValueError):
        n = 0
    if n >= 1_000_000:
        v = n / 1_000_000
        s = f"{v:.1f}".rstrip("0").rstrip(".")
        return f"{s}M"
    if n >= 1000:
        v = n / 1000
        s = f"{v:.1f}".rstrip("0").rstrip(".")
        return f"{s}k"
    return str(n)


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def clamp_pct(p):
    try:
        p = float(p)
    except (TypeError, ValueError):
        p = 0.0
    return clamp(p, 0.0, 100.0)


def filled_count(pct):
    pct = clamp_pct(pct)
    filled = math.ceil(pct / 100 * BAR_WIDTH)
    if pct > 0 and filled == 0:
        filled = 1
    if pct < 100 and filled == BAR_WIDTH:
        filled = BAR_WIDTH - 1
    return int(clamp(filled, 0, BAR_WIDTH))


def render_bar_single(pct, color):
    """Single-color bar (used for 5h/7d meters)."""
    filled = filled_count(pct)
    empty = BAR_WIDTH - filled
    return f"{color}{FILLED_CH * filled}{RESET}{DIM_GREY}{EMPTY_CH * empty}{RESET}"


def render_bar_gradient(pct):
    """Ctx bar with a fixed per-dot positional gradient (green -> red)."""
    filled = filled_count(pct)
    dots = []
    for i in range(BAR_WIDTH):
        if i < filled:
            dots.append(f"{c256(CTX_GRADIENT[i])}{FILLED_CH}{RESET}")
        else:
            dots.append(f"{DIM_GREY}{EMPTY_CH}{RESET}")
    return "".join(dots)


def fmt_reset(resets_at, now):
    try:
        resets_at = float(resets_at)
    except (TypeError, ValueError):
        return None
    diff = resets_at - now
    if diff < 0:
        diff = 0
    total_min = int(diff // 60)
    h = total_min // 60
    m = total_min % 60
    if h > 0:
        return f"↻{h}h{m:02d}m"
    return f"↻{m}m"


def risk_color(used, resets_at, now, window_len):
    """Color a 5h/7d bar by projected overshoot risk, not raw percentage."""
    used = clamp_pct(used)

    if resets_at is None:
        # Fallback to raw thresholds when we have no reset time to project against.
        if used < 70:
            return GREEN
        if used < 90:
            return YELLOW
        return RED

    try:
        resets_at = float(resets_at)
    except (TypeError, ValueError):
        resets_at = now

    remaining = max(0.0, resets_at - now)
    # Guard against clock skew pushing resets_at further out than the window itself.
    remaining = min(remaining, window_len)
    elapsed = clamp(window_len - remaining, 0.0, window_len)

    if used >= 100:
        return RED
    if elapsed < 60 or used <= 0:
        return GREEN  # too little signal to project

    burn_per_sec = used / elapsed
    projected_additional = burn_per_sec * remaining
    headroom = 100 - used
    if headroom <= 0:
        return RED

    risk = projected_additional / headroom
    if risk < 0.85:
        return GREEN
    if risk < 1.15:
        return YELLOW
    return RED


def meter_ctx(pct):
    pct = clamp_pct(pct)
    bar = render_bar_gradient(pct)
    return f"{GREY}ctx{RESET} {bar} {round(pct):>3}%{RESET}"


def meter_risk(label, pct, resets_at, now, window_len):
    pct = clamp_pct(pct)
    color = risk_color(pct, resets_at, now, window_len)
    bar = render_bar_single(pct, color)
    out = f"{GREY}{label}{RESET} {bar} {round(pct):>3}%{RESET}"
    reset_s = fmt_reset(resets_at, now) if resets_at is not None else None
    if reset_s:
        out += f" {GREY}{reset_s}{RESET}"
    return out


def safe_get(d, *path, default=None):
    cur = d
    for key in path:
        if not isinstance(cur, dict):
            return default
        cur = cur.get(key)
    return default if cur is None else cur


def fallback_line():
    bar = f"{DIM_GREY}{EMPTY_CH * BAR_WIDTH}{RESET}"
    print(f"{CYAN}?{RESET}")
    print(f"{GREY}ctx{RESET} {bar}   0%{RESET}")


def main():
    now = time.time()

    try:
        raw = sys.stdin.read()
    except Exception:
        raw = ""

    try:
        data = json.loads(raw) if raw and raw.strip() else {}
        if not isinstance(data, dict):
            data = {}
    except Exception:
        data = {}

    try:
        # ---- Row 1 ----
        cur_dir = safe_get(data, "workspace", "current_dir", default="") or ""
        folder = cur_dir.rstrip("/").split("/")[-1] if cur_dir else "?"
        row1_parts = [f"{CYAN}{folder}{RESET}"]

        model_name = safe_get(data, "model", "display_name")
        if model_name:
            row1_parts.append(f"{MODEL_C}{model_name}{RESET}")

        cw_size = safe_get(data, "context_window", "context_window_size")
        total_input = safe_get(data, "context_window", "total_input_tokens")
        if cw_size:
            try:
                cw_size_i = int(cw_size)
            except (TypeError, ValueError):
                cw_size_i = 0
            try:
                total_input_i = int(total_input) if total_input is not None else 0
            except (TypeError, ValueError):
                total_input_i = 0
            row1_parts.append(
                f"{TOKENS_C}{compact_tokens(total_input_i)} / {compact_tokens(cw_size_i)}{RESET}"
            )

        thinking_enabled = safe_get(data, "thinking", "enabled")
        think_c = THINK_ON_C if thinking_enabled else THINK_OFF_C
        row1_parts.append(
            f"{think_c}thinking {'on' if thinking_enabled else 'off'}{RESET}"
        )

        effort_level = safe_get(data, "effort", "level")
        if effort_level:
            lvl = str(effort_level)
            if lvl == "medium":
                lvl = "med"
            row1_parts.append(f"{EFFORT_C.get(lvl, GREY)}effort {lvl}{RESET}")

        sep1 = f"{GREY} · {RESET}"
        row1 = sep1.join(row1_parts)

        # ---- Row 2 ----
        meters = []

        cw_size_val = safe_get(data, "context_window", "context_window_size")
        total_input_val = safe_get(data, "context_window", "total_input_tokens")
        try:
            cw_size_f = float(cw_size_val) if cw_size_val else 0.0
        except (TypeError, ValueError):
            cw_size_f = 0.0
        try:
            total_input_f = float(total_input_val) if total_input_val else 0.0
        except (TypeError, ValueError):
            total_input_f = 0.0

        if not total_input_f:
            # Fall back to the reported percentage of the real context window.
            reported = safe_get(data, "context_window", "used_percentage")
            try:
                reported_f = float(reported) if reported is not None else 0.0
            except (TypeError, ValueError):
                reported_f = 0.0
            total_input_f = reported_f / 100 * cw_size_f

        used_pct = total_input_f / CTX_BUDGET_TOKENS * 100
        meters.append(meter_ctx(used_pct))

        five_hour = safe_get(data, "rate_limits", "five_hour")
        if isinstance(five_hour, dict) and five_hour.get("used_percentage") is not None:
            meters.append(meter_risk(
                "5h", five_hour.get("used_percentage"), five_hour.get("resets_at"),
                now, FIVE_HOUR_WINDOW,
            ))

        seven_day = safe_get(data, "rate_limits", "seven_day")
        if isinstance(seven_day, dict) and seven_day.get("used_percentage") is not None:
            meters.append(meter_risk(
                "7d", seven_day.get("used_percentage"), seven_day.get("resets_at"),
                now, SEVEN_DAY_WINDOW,
            ))

        sep2 = f"{GREY}  ·  {RESET}"
        row2 = sep2.join(meters)

        print(row1)
        print(row2)
    except Exception:
        fallback_line()

    sys.exit(0)


if __name__ == "__main__":
    main()
