import argparse
import json
import time
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


def frame_stats(frame):
    mean_bgr = frame.mean(axis=(0, 1))
    std_bgr = frame.std(axis=(0, 1))
    y = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    channel_spread = (
        frame.max(axis=2).astype(np.int16) - frame.min(axis=2).astype(np.int16)
    )
    saturation = hsv[:, :, 1]
    y_mean = float(y.mean())
    y_std = float(y.std())
    return {
        "shape": list(frame.shape),
        "mean_bgr": [float(x) for x in mean_bgr],
        "std_bgr": [float(x) for x in std_bgr],
        "y_mean": y_mean,
        "y_std": y_std,
        "mean_channel_spread": float(channel_spread.mean()),
        "p95_channel_spread": float(np.percentile(channel_spread, 95)),
        "mean_saturation": float(saturation.mean()),
        "p95_saturation": float(np.percentile(saturation, 95)),
        "saturated_gt20_fraction": float((saturation > 20).mean()),
        "is_uniform_diag": bool(y_std < 2.0),
    }


def save_png(path, frame):
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    Image.fromarray(rgb).save(path)


def phase_analysis(frame, period, roi_height=960):
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).astype(np.float32)
    roi = gray[:roi_height, :]
    column_mean = roi.mean(axis=0)
    centered = column_mean - column_mean.mean()
    denom = float(
        np.sqrt(np.sum(centered[:-period] ** 2) * np.sum(centered[period:] ** 2))
    )
    lag = (
        float(np.sum(centered[:-period] * centered[period:]) / denom)
        if denom
        else 0.0
    )

    phases = []
    for phase in range(period):
        phases.append(float(centered[phase::period].mean()))

    fft = np.fft.rfft(centered)
    idx = column_mean.shape[0] // period
    mag = float(np.abs(fft[idx])) if idx < len(fft) else 0.0
    peak = int(np.argmax(np.abs(phases)))
    return {
        "representative_frame": 0,
        "roi": [0, 0, int(column_mean.shape[0]), int(roi_height)],
        "period": period,
        "lag_autocorr": lag,
        "phase_means": [round(x, 6) for x in phases],
        "phase_peak_abs": peak,
        "fft_index": int(idx),
        "fft_mag": mag,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", type=int, default=0)
    parser.add_argument("--frames", type=int, default=70)
    parser.add_argument("--warmup", type=int, default=30)
    parser.add_argument("--width", type=int, default=1920)
    parser.add_argument("--height", type=int, default=1080)
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--outdir", required=True)
    args = parser.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    cap = cv2.VideoCapture(args.index, cv2.CAP_DSHOW)
    if not cap.isOpened():
        raise SystemExit(f"could not open video index {args.index}")
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    cap.set(cv2.CAP_PROP_FPS, args.fps)

    for _ in range(args.warmup):
        cap.read()

    frames = []
    summaries = []
    start = time.time()
    for i in range(args.frames):
        ok, frame = cap.read()
        if not ok or frame is None:
            break
        frames.append(frame.copy())
        stats = frame_stats(frame)
        stats["frame"] = i
        summaries.append(stats)
    elapsed = time.time() - start
    cap.release()

    if not frames:
        raise SystemExit("no frames captured")

    keep = set(range(min(8, len(frames))))
    keep.update(range(10, len(frames), 10))
    keep.add(len(frames) - 1)
    for i in sorted(keep):
        save_png(outdir / f"idx{args.index}_frame{i:02d}.png", frames[i])

    summary = {
        "capture_dir": str(outdir.resolve()),
        "video_index": args.index,
        "elapsed_s": elapsed,
        "frames": len(frames),
        "uniform_diag_count": sum(1 for s in summaries if s["is_uniform_diag"]),
        "real_count": sum(1 for s in summaries if not s["is_uniform_diag"]),
        "mean_channel_spread": float(
            np.mean([s["mean_channel_spread"] for s in summaries])
        ),
        "mean_saturation": float(np.mean([s["mean_saturation"] for s in summaries])),
        "mean_saturated_gt20_fraction": float(
            np.mean([s["saturated_gt20_fraction"] for s in summaries])
        ),
        "frame_summary": summaries,
    }
    (outdir / "capture_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    analyses = {
        str(period): phase_analysis(
            frames[0], period, roi_height=min(960, frames[0].shape[0])
        )
        for period in (16, 24, 32)
    }
    phase = analyses["32"]
    (outdir / f"idx{args.index}_phase32_analysis.json").write_text(
        json.dumps(
            {
                **phase,
                "lag32_autocorr": phase["lag_autocorr"],
                "fft_index_period32": phase["fft_index"],
                "fft_mag_period32": phase["fft_mag"],
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    (outdir / f"idx{args.index}_periodic_analysis.json").write_text(
        json.dumps(analyses, indent=2), encoding="utf-8"
    )
    print(json.dumps({
        "outdir": str(outdir.resolve()),
        "frames": len(frames),
        "uniform_diag_count": summary["uniform_diag_count"],
        "real_count": summary["real_count"],
        "mean_channel_spread": summary["mean_channel_spread"],
        "mean_saturation": summary["mean_saturation"],
        "mean_saturated_gt20_fraction": summary["mean_saturated_gt20_fraction"],
        "lag16_autocorr": analyses["16"]["lag_autocorr"],
        "lag24_autocorr": analyses["24"]["lag_autocorr"],
        "lag32_autocorr": analyses["32"]["lag_autocorr"],
        "phase_peak_abs": phase["phase_peak_abs"],
        "fft_mag_period32": phase["fft_mag"],
    }, indent=2))


if __name__ == "__main__":
    main()
