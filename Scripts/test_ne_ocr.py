#!/usr/bin/env python3
import argparse
import json

import numpy as np
import torch
from doctr.models import vitstr_base
from huggingface_hub import hf_hub_download
from PIL import Image


def load_model():
    model_path = hf_hub_download(repo_id="MWirelabs/ne-ocr", filename="ne_ocr_best.pt")
    vocab_path = hf_hub_download(repo_id="MWirelabs/ne-ocr", filename="ne_ocr_vocab.json")

    with open(vocab_path, encoding="utf-8") as handle:
        vocab_data = json.load(handle)

    vocab = "".join(vocab_data["vocab"][1:])
    model = vitstr_base(pretrained=False, vocab=vocab)
    model.load_state_dict(torch.load(model_path, map_location="cpu"))
    model.eval()
    return model


def image_tensor(path: str) -> torch.Tensor:
    image = Image.open(path).convert("RGB").resize((128, 32))
    pixels = np.array(image, dtype=np.float32) / 255.0
    return torch.tensor(pixels).permute(2, 0, 1).unsqueeze(0)


def main():
    parser = argparse.ArgumentParser(description="Run the NE-OCR PyTorch model on a word/line crop.")
    parser.add_argument(
        "image",
        nargs="?",
        default="/Users/johnsonelangbam/Downloads/Meetei_Mayek.png",
        help="Path to a word or line crop image.",
    )
    args = parser.parse_args()

    model = load_model()
    with torch.no_grad():
        output = model(image_tensor(args.image))
    print(output["preds"][0][0])


if __name__ == "__main__":
    main()
