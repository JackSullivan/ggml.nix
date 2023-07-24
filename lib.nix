{ lib, fetchgit, stdenv, SDL2 }:

with builtins; {
  fetchHf = { api_key ? null, owner, repo, sha256 }:
    fetchgit {
      inherit sha256;
      url = "https://huggingface.co/${owner}/${repo}";
    };
  ggml = { src, cmake, cudaPackages ? null, targets ? null }:
    let
      cudaStuff = if isNull cudaPackages then {
        nativeBuildInputs = [ cmake ];
      } else
        (with cudaPackages; {
          nativeBuildInputs = [ cmake cuda_nvcc ];
          buildInputs = [ libcublas cuda_cudart ];
          CUDA_PATH = cudatoolkit;
          cmakeFlags =
            [ "-DGGML_CUBLAS=ON" "-DCUDAToolkit_ROOT=${cudatoolkit}" ];
        });
      targetStuff = if isNull targets then
        { }
      else {
        postBuild = ''
          mkdir -p $out/bin
        '' + (lib.concatMapStringsSep "\n" (target: ''
          make ${target}
          cp bin/${target} $out/bin/${target}'') targets);
      };
    in stdenv.mkDerivation ({
      inherit src;
      name = "ggml";
    } // cudaStuff // targetStuff);
  whisper = { src, cudaPackages ? null }:
    let
      cudaStuff = if isNull cudaPackages then
        { }
      else
        (with cudaPackages; {
          nativeBuildInputs = [ cuda_nvcc ];
          buildInputs = [ libcublas cuda_cudart SDL2 SDL2.dev ];
          CUDA_PATH = cudatoolkit;
          WHISPER_CUBLAS = 1;
          NVCCFLAGS = "--forward-unknown-to-host-compiler";
          makeFlags = [
            "WHISPER_CUBLAS=1"
            "NVCCFLAGS=--forward-unknown-to-host-compiler"
          ];
        });
    in stdenv.mkDerivation ({
      name = "whisper";
      inherit src;
      postBuild = ''
        make command stream
        mkdir -p $out/bin
        cp command $out/bin/command
        cp stream $out/bin/stream
      '';
      dontInstall = true;
    } // cudaStuff);
}
