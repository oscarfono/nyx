{ lib, python3Packages, git, hledger }:

python3Packages.buildPythonApplication {
  pname = "luna-core";
  version = "0.1.0";
  pyproject = true;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./pyproject.toml ./luna_core ./tests ];
  };

  build-system = [ python3Packages.setuptools ];
  dependencies = with python3Packages; [
    anthropic
    httpx
    markdown
    matrix-nio
    tzdata
  ];

  nativeCheckInputs = [ python3Packages.pytestCheckHook git hledger ];

  meta = {
    description = "The core agent of LUNA";
    mainProgram = "luna-core";
  };
}
