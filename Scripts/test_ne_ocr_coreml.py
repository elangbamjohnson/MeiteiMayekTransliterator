#!/usr/bin/env python3
import argparse
import json

import coremltools as ct
import numpy as np
from PIL import Image


def load_vocab(path: str) -> list[str]:
    with open(path, encoding="utf-8") as handle:
        vocab_data = json.load(handle)
    return vocab_data["vocab"][1:] + ["<eos>"]


def image_array(path: str) -> np.ndarray:
    image = Image.open(path).convert("RGB").resize((128, 32))
    pixels = np.array(image, dtype=np.float32) / 255.0
    return np.transpose(pixels, (2, 0, 1))[None, :, :, :]


def decode(logits: np.ndarray, embedding: list[str]) -> str:
    indexes = logits.argmax(axis=-1)[0]
    characters: list[str] = []
    for index in indexes:
        token = embedding[int(index)]
        if token == "<eos>":
            break
        characters.append(token)
    return "".join(characters)


def main():
    parser = argparse.ArgumentParser(description="Run the exported NE-OCR Core ML model.")
    parser.add_argument(
        "image",
        nargs="?",
        default="/Users/johnsonelangbam/Downloads/Meetei_Mayek.png",
        help="Path to a word or line crop image.",
    )
    parser.add_argument(
        "--model",
        default="MeiteiMayekTranslator/Models/MeiteiMayekOCR.mlpackage",
        help="Path to the exported .mlpackage.",
    )
    parser.add_argument(
        "--vocab",
        default="MeiteiMayekTranslator/Models/MeiteiMayekOCRVocab.json",
        help="Path to the exported vocabulary JSON.",
    )
    args = parser.parse_args()

    model = ct.models.MLModel(args.model, compute_units=ct.ComputeUnit.CPU_ONLY)
    output = model.predict({"image": image_array(args.image)})
    print(decode(output["logits"], load_vocab(args.vocab)))


if __name__ == "__main__":
    main()
