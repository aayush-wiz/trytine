"""
FastAPI grounding service.

POST /locate  { "image_b64": "<base64 png/jpeg>", "instruction": "the hour digits of the start time" }
   -> { "ok": true, "x": 937, "y": 466 }

It runs cua's GTA1 grounding algorithm (grounding.py, copied verbatim) which:
  smart-resizes the screenshot, tells the model that exact resolution, asks for a
  single (x,y), and scales the answer back to the original screenshot pixels.

The grounding VLM is any litellm model id. For OpenRouter use the `openrouter/...`
prefix (needs OPENROUTER_API_KEY in the environment). Override with GROUNDING_MODEL.
"""

import os

from fastapi import FastAPI
from pydantic import BaseModel

from grounding import GTA1Config

GROUNDING_MODEL = os.environ.get("GROUNDING_MODEL", "openrouter/anthropic/claude-sonnet-4.6")

app = FastAPI(title="cua-grounding")
_grounder = GTA1Config()


class LocateRequest(BaseModel):
    image_b64: str
    instruction: str


@app.get("/health")
async def health():
    return {"ok": True, "model": GROUNDING_MODEL}


@app.post("/locate")
async def locate(req: LocateRequest):
    # strip a data-url prefix if present
    img = req.image_b64
    if img.startswith("data:") and "," in img:
        img = img.split(",", 1)[1]
    try:
        coords = await _grounder.predict_click(
            model=GROUNDING_MODEL, image_b64=img, instruction=req.instruction
        )
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}
    if not coords:
        return {"ok": False, "error": "no coordinates"}
    return {"ok": True, "x": int(coords[0]), "y": int(coords[1]), "model": GROUNDING_MODEL}
