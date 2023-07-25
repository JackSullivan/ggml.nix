{
  description = "Basic flake for multisystem nixpkgs";

  inputs = {
    ggml-src = {
      url = "github:ggerganov/ggml";
      flake = false;
    };

    whisper-src = {
      url = "github:ggerganov/whisper.cpp";
      flake = false;
    };

  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, ggml-src
    , whisper-src}:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = nixpkgs.lib;
        unstable = nixpkgs-unstable.legacyPackages.${system};
        py = unstable.python3.withPackages (ps:
          with ps; [
            accelerate
            numpy
            pytorch
            torchvision
            torchaudio
            transformers
            sentencepiece
            einops
          ]);
        myLib = pkgs.callPackage ./lib.nix { };
        convert-hf-to-ggml-model = hf-model:
          pkgs.runCommand "ggml-model" { } ''
            mkdir -p $out/cache
            export TRANSFORMERS_CACHE=$out/cache
            ${py}/bin/python ${ggml-src}/examples/starcoder/convert-hf-to-ggml.py ${hf-model} --outfile $out/ggml-model.bin 
          '';
        whisper-model = { size, sha256 }:
          pkgs.fetchurl {
            url =
              "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${size}.bin";
            inherit sha256;
          };
          whisper-small = (whisper-model {
            size = "small.en";
            sha256 = "xhONbVjsyDIgl+D5h8MvG+i7ChhTKj+I9zTRu/nEHl0=";
          });
        voiceCommand = let
          whisp = pkgs.callPackage myLib.whisper { src = whisper-src; };
          model = whisper-small;
        in pkgs.symlinkJoin {
          name = "whisper-commands";
          paths = map (comm:
            pkgs.writeShellScriptBin comm "${whisp}/bin/${comm} -m ${model}") [
              "command"
              "stream"
            ];
        };
      in {
        packages = {
          inherit py voiceCommand;
          convert-model =
            convert-hf-to-ggml-model "bigcode/gpt_bigcode-santacoder";
          replit-model = myLib.fetchHf {
            owner = "replit";
            repo = "replit-code-v1-3b";
            sha256 = "b59+qBNy4MCmHWHSuPOz1Ek5S31VBDtEJAzeic+WWNs=";
          };
          whisper = pkgs.callPackage myLib.whisper { src = whisper-src; };
          python = py;
          default = pkgs.callPackage myLib.ggml {
            src = ggml-src;
            targets = [ "starcoder" "replit" ];
          };
        };
      });
}
