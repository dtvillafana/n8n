{
  description = "Nix packages for this n8n checkout";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      eachSystem = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "n8n";
        };
    in
    {
      packages = eachSystem (
        system:
        let
          pkgs = pkgsFor system;
          inherit (pkgs) lib;
          nodejs = pkgs.nodejs_24;
          pnpm = pkgs.pnpm_12;
          python = pkgs.python3.withPackages (ps: [
            ps.websockets
            ps.urllib3
          ]);
          n8n =
            (pkgs.n8n.override {
              inherit nodejs;
              pnpm_11 = pnpm;
            }).overrideAttrs
              (
                finalAttrs: old: {
                  version = (builtins.fromJSON (builtins.readFile ./packages/cli/package.json)).version;
                  src = lib.cleanSourceWith {
                    src = self;
                    filter =
                      path: type:
                      lib.cleanSourceFilter path type
                      && !(builtins.elem (baseNameOf path) [
                        "node_modules"
                        "dist"
                        "compiled"
                        ".turbo"
                        ".venv"
                        ".secrets"
                        ".n8n"
                        "__pycache__"
                      ])
                      && !(lib.hasPrefix ".env" (baseNameOf path));
                  };

                  pnpmDeps = pkgs.fetchPnpmDeps {
                    inherit (finalAttrs) pname version src;
                    inherit pnpm;
                    fetcherVersion = 4;
                    hash = "sha256-tgIYe8rFk3wD+lFaBI6mgu8XoJUNCWihewXK2w3eOKc=";
                  };

                  nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.pkg-config ];
                  buildInputs = old.buildInputs ++ [ pkgs.rdkafka ];
                  env = {
                    npm_config_nodedir = "${nodejs}";
                    NODE_OPTIONS = "--max-old-space-size=4096 --no-node-snapshot";
                    TURBO_TELEMETRY_DISABLED = "1";
                    CI = "true";
                  };

                  buildPhase = ''
                        runHook preBuild
                    substituteInPlace packages/frontend/editor-ui/node_modules/sass-embedded/dist/lib/src/compiler-path.js \
                      --replace-fail 'compilerCommand = (() => {' 'compilerCommand = (() => { return ["${lib.getExe pkgs.dart-sass}"];'

                    # Node metadata generation loads SQLite during the workspace build.
                    pushd packages/cli/node_modules/sqlite3
                    npm_config_sqlite=${lib.getDev pkgs.sqlite} node-gyp rebuild --release
                    popd

                    pnpm build --filter=n8n --concurrency=1

                        NODE_ENV=production DOCKER_BUILD=true pnpm --filter=n8n --prod \
                          --config.inject-workspace-packages=true --config.package-import-method=copy deploy \
                          --offline --ignore-scripts --no-optional compiled
                        rm -f compiled/pnpm-workspace.yaml compiled/pnpm-lock.yaml \
                          compiled/node_modules/.pnpm-workspace-state-v1.json

                        # Compile native modules after deployment so pnpm retains their outputs.
                        pushd compiled/node_modules/sqlite3
                        npm_config_sqlite=${lib.getDev pkgs.sqlite} node-gyp rebuild --release
                        popd
                        pushd compiled/node_modules/isolated-vm
                        rm -rf prebuilds
                        # The timer header does not include the definition of uint32_t.
                        sed -i '1i#include <cstdint>' src/lib/timer.h
                        node-gyp rebuild --release -j "$NIX_BUILD_CORES"
                        popd
                        for kafka in compiled/node_modules/.pnpm/@confluentinc+kafka-javascript@*/node_modules/@confluentinc/kafka-javascript; do
                          pushd "$kafka"
                          # Use the headers from the Nix librdkafka package.
                          substituteInPlace binding.gyp \
                            --replace-fail '/usr/include/librdkafka' '${lib.getDev pkgs.rdkafka}/include/librdkafka'
                          BUILD_LIBRDKAFKA=0 node-gyp rebuild --release
                          popd
                        done
                        runHook postBuild
                  '';

                  # pnpm deploy replaces the nixpkgs workspace-pruning step.
                  preInstall = "";
                  installPhase = ''
                    runHook preInstall
                    mkdir -p "$out/lib/n8n" "$out/bin"
                    cp -a compiled/. "$out/lib/n8n/"
                    makeWrapper ${lib.getExe nodejs} "$out/bin/n8n" \
                      --add-flags "--no-node-snapshot $out/lib/n8n/bin/n8n" \
                      --set N8N_RELEASE_TYPE stable \
                      --prefix PATH : ${
                        lib.makeBinPath [
                          nodejs
                          python
                        ]
                      }
                    makeWrapper ${lib.getExe nodejs} "$out/bin/n8n-task-runner" \
                      --add-flags "--no-node-snapshot $out/lib/n8n/node_modules/@n8n/task-runner/dist/start.js"
                    mkdir -p "$out/lib/@n8n/task-runner-python/.venv/bin"
                    cp -a packages/@n8n/task-runner-python/src "$out/lib/@n8n/task-runner-python/"
                    ln -s ${lib.getExe python} "$out/lib/@n8n/task-runner-python/.venv/bin/python"
                    makeWrapper ${lib.getExe python} "$out/bin/n8n-task-runner-python" \
                      --add-flags "$out/lib/@n8n/task-runner-python/src/main.py" \
                      --prefix PYTHONPATH : "$out/lib/@n8n/task-runner-python"
                    runHook postInstall
                  '';

                  passthru = { };
                }
              );
        in
        {
          inherit n8n;
          default = n8n;
        }
      );

      formatter = eachSystem (system: (pkgsFor system).nixfmt);
    };
}
