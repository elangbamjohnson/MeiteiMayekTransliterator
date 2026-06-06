import torch, json
import numpy as np
from PIL import Image
from huggingface_hub import hf_hub_download
from doctr.models import vitstr_base

image_path = "/Users/johnsonelangbam/Downloads/Meetei_Mayek.png"

model_path = hf_hub_download(repo_id="MWirelabs/ne-ocr", filename="ne_ocr_best.pt")
vocab_path = hf_hub_download(repo_id="MWirelabs/ne-ocr", filename="ne_ocr_vocab.json")

with open(vocab_path, encoding="utf-8") as f:
    vocab_data = json.load(f)

vocab_str = "".join(vocab_data["vocab"][1:])

model = vitstr_base(pretrained=False, vocab=vocab_str)
model.load_state_dict(torch.load(model_path, map_location="cpu"))
model.eval()

img = Image.open(image_path).convert("RGB").resize((128, 32))
img_tensor = (
    torch.tensor(np.array(img, dtype=np.float32) / 255.0)
    .permute(2, 0, 1)
    .unsqueeze(0)
)

with torch.no_grad():
    out = model(img_tensor)

print(out["preds"][0][0])
