"""Configuration checks shared by RB5/GoPro calibration workflows."""
import json
from pathlib import Path
import numpy as np


def load_config(path):
    config = json.loads(Path(path).read_text())
    if config["mount"] not in ("eye_to_hand", "eye_in_hand", "unconfigured"):
        raise ValueError("Invalid camera mount")
    target_type = config.get("target", {"type": "charuco"})["type"]
    reference_type = config.get("reference", {"type": "none"})["type"]
    if target_type not in ("aruco", "charuco") or reference_type not in ("none", "charuco"):
        raise ValueError("Invalid target or reference type")
    if reference_type == "charuco" and (target_type != "aruco" or config["mount"] != "eye_to_hand"):
        raise ValueError("Fixed ChArUco reference requires eye_to_hand with an ArUco hand marker")
    if not all(np.isfinite(v) and v > 0 for v in config["capture"].values()):
        raise ValueError("Capture thresholds must be positive finite numbers")
    if config["robot"]["timeout_s"] <= 0:
        raise ValueError("Robot timeout must be positive")
    return config


def require_layout(config):
    if config["mount"] == "unconfigured":
        raise ValueError("Select a connected calibration layout: eye_in_hand (camera on robot, "
                         "fixed ChArUco) or eye_to_hand (fixed camera, ChArUco on robot). "
                         "Fixed camera + fixed board + FK alone cannot determine camera-to-base.")
