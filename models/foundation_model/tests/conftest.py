import sys
from pathlib import Path

MODEL_SRC = Path(__file__).resolve().parents[1] / "src"
GENERATED_PYTHON = Path(__file__).resolve().parents[3] / "packages" / "generated" / "python"
sys.path.insert(0, str(MODEL_SRC))
sys.path.insert(0, str(GENERATED_PYTHON))
