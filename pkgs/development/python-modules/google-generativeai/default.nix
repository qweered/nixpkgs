{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  google-ai-generativelanguage,
  google-api-core,
  google-api-python-client,
  google-auth,
  protobuf,
  pydantic,
  pythonOlder,
  setuptools,
  tqdm,
  typing-extensions,
}:

buildPythonPackage rec {
  pname = "google-generativeai";
  version = "0.8.4";
  pyproject = true;

  disabled = pythonOlder "3.9";

  src = fetchFromGitHub {
    owner = "google";
    repo = "generative-ai-python";
    tag = "v${version}";
    hash = "sha256-Snsp6hP1BKNLSFGbcotdhmluTuuBPZBcLkNY8mtOl6o=";
  };

  pythonRelaxDeps = [ "google-ai-generativelanguage" ];

  build-system = [ setuptools ];

  dependencies = [
    google-ai-generativelanguage
    google-api-core
    google-api-python-client
    google-auth
    protobuf
    pydantic
    tqdm
    typing-extensions
  ];

  # Issue with the google.ai module. Check with the next release
  doCheck = false;

  pythonImportsCheck = [ "google.generativeai" ];

  meta = with lib; {
    description = "Python client library for Google's large language model PaLM API";
    homepage = "https://github.com/google/generative-ai-python";
    changelog = "https://github.com/google/generative-ai-python/releases/tag/v${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ fab ];
  };
}
