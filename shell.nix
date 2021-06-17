let
 pkgs = import <nixpkgs> {};

 ci-lint = pkgs.writeShellScriptBin "ci-lint" ''
 solhint 'contracts/**/*.sol'
 '';

 local-node = pkgs.writeShellScriptBin "local-node" ''
 hardhat node --fork https://eth-mainnet.alchemyapi.io/v2/''${ALCHEMY_API_KEY} --fork-block-number 12652533
 '';

 local-test = pkgs.writeShellScriptBin "local-test" ''
 hardhat test --network localhost
 '';

 manticore = pkgs.writeShellScriptBin "manticore" ''
 export d=$(mktemp -d)
 python3 -m venv ''${d}/venv
 source ''${d}/venv/bin/activate
 pip install manticore
 manticore
 '';

 security-check = pkgs.writeShellScriptBin "security-check" ''
 export d=$(mktemp -d)
 python3 -m venv ''${d}/venv
 source ''${d}/venv/bin/activate
 pip install slither-analyzer
 slither --exclude-dependencies --filter=hardhat --npx-disable .
 '';

 ci-test = pkgs.writeShellScriptBin "ci-test" ''
 ci-lint
 local-test
 security-check
 '';
in
pkgs.stdenv.mkDerivation {
 name = "shell";
 buildInputs = [
  pkgs.nodejs-14_x
  pkgs.python3
  security-check
  local-node
  local-test
  ci-test
  ci-lint
  manticore
 ];

 shellHook = ''
  source .env
  export PATH=$( npm bin ):$PATH
  # keep it fresh
  npm install
 '';
}