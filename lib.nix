{ fetchurl }:

{
  fetchHf = { api_key ? null, owner, repo, sha256 }:
    fetchurl {
      inherit sha256;
      url = "https://huggingface.co/${owner}/${repo}";
    };
}
