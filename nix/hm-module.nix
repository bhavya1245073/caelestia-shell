self: {
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) system;

  cli-default = self.inputs.caelestia-cli.packages.${system}.default;
  shell-default = self.packages.${system}.with-cli;

  cfg = config.programs.caelestia;
in {
  imports = [
    (lib.mkRenamedOptionModule ["programs" "caelestia" "environment"] ["programs" "caelestia" "systemd" "environment"])
  ];
  options = with lib; {
    programs.caelestia = {
      enable = mkEnableOption "Enable Caelestia shell";
      package = mkOption {
        type = types.package;
        default = shell-default;
        description = "The package of Caelestia shell";
      };
      systemd = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable the systemd service for Caelestia shell";
        };
        target = mkOption {
          type = types.str;
          description = ''
            The systemd target that will automatically start the Caelestia shell.
          '';
          default = config.wayland.systemd.target;
        };
        environment = mkOption {
          type = types.listOf types.str;
          description = "Extra Environment variables to pass to the Caelestia shell systemd service.";
          default = [];
          example = [
            "QT_QPA_PLATFORMTHEME=gtk3"
          ];
        };
      };
      settings = mkOption {
        type = types.attrsOf types.anything;
        default = {};
        description = "Caelestia shell settings";
      };
      mutableSettings = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Seed shell.json/cli.json instead of symlinking them.

          By default `settings` is written as a read-only symlink into the Nix
          store. That makes the config fully declarative, but the shell cannot
          write to it: the Nexus settings GUI saves by rewriting shell.json, so
          every change it makes fails, and anything that persists state through
          the config (Hyprland overrides, GIF keys and saved GIFs, per-monitor
          tweaks) cannot work at all.

          With this enabled, `settings` becomes a set of defaults that are merged
          into a real, writable file on activation, with the existing file taking
          precedence. Nix still declares the baseline and new keys appear on
          rebuild, while anything changed in the GUI survives.

          The tradeoff: once a key exists in the file, Nix no longer controls it,
          and a key removed in the GUI comes back on the next activation.
        '';
      };
      extraConfig = mkOption {
        type = types.str;
        default = "";
        description = "Caelestia shell extra configs written to shell.json";
      };
      cli = {
        enable = mkEnableOption "Enable Caelestia CLI";
        package = mkOption {
          type = types.package;
          default = cli-default;
          description = "The package of Caelestia CLI"; # Doesn't override the shell's CLI, only change from home.packages
        };
        settings = mkOption {
          type = types.attrsOf types.anything;
          default = {};
          description = "Caelestia CLI settings";
        };
        extraConfig = mkOption {
          type = types.str;
          default = "";
          description = "Caelestia CLI extra configs written to cli.json";
        };
      };
    };
  };

  config = let
    cli = cfg.cli.package;
    shell = cfg.package;

    mkConfig = c:
      lib.pipe (
        if c.extraConfig != ""
        then c.extraConfig
        else "{}"
      ) [
        builtins.fromJSON
        (lib.recursiveUpdate c.settings)
        builtins.toJSON
      ];
    shouldGenerate = c: c.extraConfig != "" || c.settings != {};

    # Merge the Nix-declared defaults underneath whatever is already on disk.
    #
    # jq's `*` is a recursive object merge where the right side wins, which is
    # exactly the precedence needed: the user's saved settings beat the defaults,
    # but keys they have never touched still appear.
    #
    # A store symlink left over from a generation built with mutableSettings = false
    # is replaced rather than written through, since writing through it would fail
    # against the read-only store.
    seedConfig = name: c:
      lib.optionalString (shouldGenerate c) ''
        _cae_defaults=${pkgs.writeText "caelestia-${name}-defaults.json" (mkConfig c)}
        _cae_target="${config.xdg.configHome}/caelestia/${name}"
        run mkdir -p "$(dirname "$_cae_target")"

        if [ -L "$_cae_target" ] || [ ! -s "$_cae_target" ]; then
          run rm -f "$_cae_target"
          run install -m 0644 "$_cae_defaults" "$_cae_target"
        elif ${lib.getExe pkgs.jq} -e . "$_cae_target" >/dev/null 2>&1; then
          if ! ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$_cae_defaults" "$_cae_target" > "$_cae_target.hm-new"; then
            run rm -f "$_cae_target.hm-new"
            warnEcho "caelestia: failed to merge defaults into $_cae_target, leaving it alone"
          else
            run mv -f "$_cae_target.hm-new" "$_cae_target"
          fi
        else
          # Invalid JSON. Refuse to touch it: the shell also refuses to save over a
          # file it could not load, and clobbering it would destroy the only copy.
          warnEcho "caelestia: $_cae_target is not valid JSON, not merging defaults"
        fi
      '';
  in
    lib.mkIf cfg.enable {
      systemd.user.services.caelestia = lib.mkIf cfg.systemd.enable {
        Unit = {
          Description = "Caelestia Shell Service";
          After = [cfg.systemd.target];
          PartOf = [cfg.systemd.target];
          X-Restart-Triggers = lib.mkIf (!cfg.mutableSettings && cfg.settings != {}) [
            "${config.xdg.configFile."caelestia/shell.json".source}"
          ];
        };

        Service = {
          Type = "exec";
          ExecStart = "${shell}/bin/caelestia-shell";
          Restart = "on-failure";
          RestartSec = "5s";
          TimeoutStopSec = "5s";
          Environment =
            [
              "QT_QPA_PLATFORM=wayland"
            ]
            ++ cfg.systemd.environment;

          Slice = "session.slice";
        };

        Install = {
          WantedBy = [cfg.systemd.target];
        };
      };

      xdg.configFile = {
        "caelestia/shell.json" = lib.mkIf (!cfg.mutableSettings && shouldGenerate cfg) {
          text = mkConfig cfg;
        };
        "caelestia/cli.json" = lib.mkIf (!cfg.mutableSettings && shouldGenerate cfg.cli) {
          text = mkConfig cfg.cli;
        };
      };

      # Runs before systemd units are restarted, so the shell always starts against
      # the merged file.
      home.activation.caelestiaSettings = lib.mkIf cfg.mutableSettings (
        lib.hm.dag.entryBefore ["reloadSystemd"] ''
          ${seedConfig "shell.json" cfg}
          ${seedConfig "cli.json" cfg.cli}
        ''
      );

      home.packages = [shell] ++ lib.optional cfg.cli.enable cli;
    };
}
