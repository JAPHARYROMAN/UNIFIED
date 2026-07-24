import sys
from pathlib import Path

MODEL_SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(MODEL_SRC))
