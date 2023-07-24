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

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, ggml-src, whisper-src }:
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
        myLib = pkgs.callPackage ./lib.nix {};
        convert-hf-to-ggml-model = hf-model: pkgs.runCommand "ggml-model" {} ''
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
        whisper = { cuda }:
          pkgs.stdenv.mkDerivation {
            src = whisper-src;
            name = "whisper";
            nativeBuildInputs = [ cuda.cuda_nvcc ];
            buildInputs =
              [ cuda.libcublas cuda.cuda_cudart pkgs.SDL2 pkgs.SDL2.dev ];
            CUDA_PATH = cuda.cudatoolkit;
            WHISPER_CUBLAS=1;
            NVCCFLAGS="--forward-unknown-to-host-compiler";
            makeFlags= [ "WHISPER_CUBLAS=1" "NVCCFLAGS=--forward-unknown-to-host-compiler"];
            postBuild = ''
              make command stream
              mkdir -p $out/bin
              cp command $out/bin/command
              cp stream $out/bin/stream
            '';
            dontInstall = true;
          };
        mkVoice = { cuda, prog }:
          let
            whisp = (whisper {inherit cuda;});
            mdl = (whisper-model {
              size = "small.en";
              sha256 = "xhONbVjsyDIgl+D5h8MvG+i7ChhTKj+I9zTRu/nEHl0=";
            });
          in pkgs.writeShellScriptBin "comm" ''
            ${whisp}/bin/${prog} -m ${mdl} $@
          '';
          voice-command = mkVoice { cuda = pkgs.cudaPackages; prog="command";};
          voice-stream = mkVoice { cuda = pkgs.cudaPackages; prog="stream";};
        ggml = { cmake, cuda }:
          pkgs.stdenv.mkDerivation {
            name = "ggml";
            src = ggml-src;
            nativeBuildInputs = [ cmake cuda.cuda_nvcc ];
            buildInputs = [ cuda.libcublas cuda.cuda_cudart ];
            CUDA_PATH = cuda.cudatoolkit;
            cmakeFlags = [
              "-DGGML_CUBLAS=ON"
              #"-DCMAKE_CODE_COMPILER=${cuda.cuda_nvcc}/bin/nvcc"
              "-DCUDAToolkit_ROOT=${cuda.cudatoolkit}"
              #"-DCUDA_CUDART_LIBRARY=${cuda.cuda_cudart}/lib/libcudart.so"
            ];
            postBuild = ''
              make starcoder starcoder-quantize
              mkdir -p $out/bin
              cp bin/starcoder $out/bin/starcoder
            '';
          };
          ggml-example = { cmake, cuda, target}:
          pkgs.stdenv.mkDerivation {
            name = "ggml";
            src = ggml-src;
            nativeBuildInputs = [ cmake cuda.cuda_nvcc ];
            buildInputs = [ cuda.libcublas cuda.cuda_cudart ];
            CUDA_PATH = cuda.cudatoolkit;
            cmakeFlags = [
              "-DGGML_CUBLAS=ON"
              #"-DCMAKE_CODE_COMPILER=${cuda.cuda_nvcc}/bin/nvcc"
              "-DCUDAToolkit_ROOT=${cuda.cudatoolkit}"
              #"-DCUDA_CUDART_LIBRARY=${cuda.cuda_cudart}/lib/libcudart.so"
            ];
            postBuild = ''
              make ${target} ${target}-quantize
              mkdir -p $out/bin
              cp bin/${target} $out/bin/${target}
            '';
          };

      in {
        packages = {
          inherit py voice-stream;
          convert-model = convert-hf-to-ggml-model "bigcode/gpt_bigcode-santacoder";
          replit-model = myLib.fetchHf { owner = "replit"; repo = "replit-code-v1-3b"; sha256 = "5zY3k2fP2JPMza1EsmAWrBX6N/qXGmKCtqZ/rJGF4/I="; };
          replit-bin = ggml-example {
            cmake = pkgs.cmake;
            cuda = pkgs.cudaPackages;
            target = "replit";
          };
          whisper-small = (whisper-model {
            size = "small.en";
            sha256 = "xhONbVjsyDIgl+D5h8MvG+i7ChhTKj+I9zTRu/nEHl0=";
          });
          whisper = pkgs.callPackage myLib.whisper { src=whisper-src; };
          python = py;
          ggml = (ggml {
            cmake = pkgs.cmake;
            cuda = pkgs.cudaPackages;
          });
          #default = voice-stream;
          default = pkgs.callPackage myLib.ggml {src=ggml-src; targets = ["starcoder" "replit"];};
        };
      });
}
