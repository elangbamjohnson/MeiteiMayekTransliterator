#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

import coremltools as ct
import coremltools.optimize.coreml as cto
import numpy as np
import torch
from doctr.models import vitstr_base
from huggingface_hub import hf_hub_download


class ViTSTRLogitsWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model
        self.sequence_length = model.max_length
        self.embedding_size = 768
        self.output_classes = len(model.vocab) + 1

    def forward(self, image):
        features = self.model.feat_extractor(image)["features"]
        features = features[:, : self.sequence_length]
        logits = self.model.head(features.reshape(self.sequence_length, self.embedding_size))
        logits = logits.view(1, self.sequence_length, self.output_classes)
        return logits[:, 1:]


def load_model():
    model_path = hf_hub_download(repo_id="MWirelabs/ne-ocr", filename="ne_ocr_best.pt")
    vocab_path = hf_hub_download(repo_id="MWirelabs/ne-ocr", filename="ne_ocr_vocab.json")

    with open(vocab_path, encoding="utf-8") as handle:
        vocab_data = json.load(handle)

    vocab = "".join(vocab_data["vocab"][1:])
    model = vitstr_base(pretrained=False, vocab=vocab)
    model.load_state_dict(torch.load(model_path, map_location="cpu"))
    model.eval()
    return model, vocab_data


def export_coreml(output_path: Path, vocab_output_path: Path, compression: str):
    model, vocab_data = load_model()
    wrapped = ViTSTRLogitsWrapper(model).eval()
    example_input = torch.zeros(1, 3, 32, 128, dtype=torch.float32)
    traced = torch.jit.trace(wrapped, example_input)

    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        inputs=[
            ct.TensorType(
                name="image",
                shape=example_input.shape,
                dtype=np.float32,
            )
        ],
        outputs=[
            ct.TensorType(name="logits", dtype=np.float32)
        ],
        compute_units=ct.ComputeUnit.ALL,
        compute_precision=ct.precision.FLOAT16,
    )

    if compression == "int8":
        config = cto.OptimizationConfig(
            global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric", dtype=np.int8)
        )
        mlmodel = cto.linear_quantize_weights(mlmodel, config)
    elif compression == "palette4":
        config = cto.OptimizationConfig(
            global_config=cto.OpPalettizerConfig(mode="kmeans", nbits=4)
        )
        mlmodel = cto.palettize_weights(mlmodel, config)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    vocab_output_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output_path))
    with open(vocab_output_path, "w", encoding="utf-8") as handle:
        json.dump(vocab_data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def main():
    parser = argparse.ArgumentParser(description="Export MWirelabs/ne-ocr ViTSTR to Core ML.")
    parser.add_argument(
        "--output",
        default="MeiteiMayekTranslator/Models/MeiteiMayekOCR.mlpackage",
        help="Output .mlpackage path.",
    )
    parser.add_argument(
        "--vocab-output",
        default="MeiteiMayekTranslator/Models/MeiteiMayekOCRVocab.json",
        help="Output vocabulary JSON path used by the Swift decoder.",
    )
    parser.add_argument(
        "--compression",
        choices=("int8", "palette4", "none"),
        default="int8",
        help="Core ML weight compression to apply after export.",
    )
    args = parser.parse_args()

    export_coreml(Path(args.output), Path(args.vocab_output), args.compression)
    print(f"Saved Core ML model to {args.output}")
    print(f"Saved vocabulary to {args.vocab_output}")


if __name__ == "__main__":
    main()
