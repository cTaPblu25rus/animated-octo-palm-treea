"""Генерация озвучки из data/voice.json синтезатором Piper (голоса с датасетом CC0).

Запуск:  python3 tools/make_voice.py <папка с моделями>
В папке должны лежать v.onnx (+ .json) — рассказчик (ru_RU-dmitri-medium)
и b.onnx (+ .json) — босс (ru_RU-denis-medium). Нужны piper-tts и ffmpeg.
Рассказчик: чуть медленнее, лёгкое эхо. Босс: голос понижен, сильное эхо.
"""
import json
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
models = Path(sys.argv[1])
lines = json.loads((root / "data" / "voice.json").read_text(encoding="utf-8"))
out_dir = root / "assets" / "voice"
out_dir.mkdir(parents=True, exist_ok=True)

FILTERS = {
    "narrator": "aecho=0.8:0.7:60:0.25,loudnorm=I=-16",
    "boss": "asetrate=22050*0.78,aresample=22050,atempo=1.12,aecho=0.8:0.8:90|180:0.4|0.25,loudnorm=I=-15",
}
MODEL = {"narrator": "v.onnx", "boss": "b.onnx"}
SPEED = {"narrator": "1.12", "boss": "1.2"}

for key, line in lines.items():
    wav = models / f"{key}.wav"
    subprocess.run(
        [sys.executable, "-I", "-m", "piper", "-m", str(models / MODEL[line["who"]]),
         "--length-scale", SPEED[line["who"]], "-f", str(wav)],
        input=line["text"].encode("utf-8"), check=True, capture_output=True)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-af", FILTERS[line["who"]],
         "-ac", "1", "-ar", "22050", "-c:a", "libvorbis", "-q:a", "4", str(out_dir / f"{key}.ogg")],
        check=True)
    print("ok", key)
