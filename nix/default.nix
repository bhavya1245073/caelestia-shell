{
  rev,
  lib,
  stdenv,
  makeWrapper,
  makeFontsConf,
  zsh,
  ddcutil,
  brightnessctl,
  networkmanager,
  lm_sensors,
  swappy,
  wl-clipboard,
  curl,
  coreutils,
  cliphist,
  libqalculate,
  bash,
  hyprland,
  material-symbols,
  rubik,
  nerd-fonts,
  qt6,
  quickshell,
  aubio,
  libcava,
  fftw,
  pipewire,
  xkeyboard-config,
  cmake,
  ninja,
  pkg-config,
  caelestia-cli,
  m3shapes,
  debug ? false,
  withCli ? false,
  extraRuntimeDeps ? [],
  # Extra font packages to make visible to the shell.
  #
  # FONTCONFIG_FILE below replaces fontconfig's config wholesale, and
  # makeFontsConf replaces every <dir> with the ones listed here — so a font that
  # is only installed system-wide (NixOS `fonts.packages`, i.e.
  # /run/current-system/sw/share/fonts) is invisible to the shell and renders as
  # tofu. Anything named in shell.json's `appearance.font` that is not one of the
  # three defaults has to be passed here.
  extraFonts ? [],
}: let
  version = "1.0.0";

  qs = quickshell.withModules [qt6.qtimageformats];

  runtimeDeps =
    [
      zsh
      ddcutil
      brightnessctl
      networkmanager
      lm_sensors
      swappy
      wl-clipboard
      # The launcher's GIF picker downloads the chosen GIF before putting it on the
      # clipboard (wl-copy can only serve bytes it has), and trims its cache with
      # du/ls/rm.
      curl
      coreutils
      # Clipboard history: the launcher lists, decodes and deletes entries through it,
      # and runs the `wl-paste --watch cliphist store` pair itself so that the history
      # limits in settings apply without a logout.
      cliphist
      libqalculate
      bash
      hyprland
    ]
    ++ extraRuntimeDeps
    ++ lib.optional withCli caelestia-cli;

  fontconfig = makeFontsConf {
    fontDirectories = [material-symbols rubik nerd-fonts.caskaydia-cove] ++ extraFonts;
  };

  cmakeBuildType =
    if debug
    then "Debug"
    else "RelWithDebInfo";

  cmakeVersionFlags = [
    (lib.cmakeFeature "VERSION" version)
    (lib.cmakeFeature "GIT_REVISION" rev)
    (lib.cmakeFeature "DISTRIBUTOR" "nix-flake")
  ];

  # The build sandbox has no network access so add it as a flake input instead
  m3shapesFlag = lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_M3SHAPES_EXTERNAL" "${m3shapes}";

  extras = stdenv.mkDerivation {
    inherit cmakeBuildType;
    name = "caelestia-extras${lib.optionalString debug "-debug"}";
    src = lib.fileset.toSource {
      root = ./..;
      fileset = lib.fileset.union ./../CMakeLists.txt ./../extras;
    };

    nativeBuildInputs = [cmake ninja];

    cmakeFlags =
      [
        (lib.cmakeFeature "ENABLE_MODULES" "extras")
        (lib.cmakeFeature "INSTALL_LIBDIR" "${placeholder "out"}/lib")
      ]
      ++ cmakeVersionFlags;
  };

  plugin = stdenv.mkDerivation {
    inherit cmakeBuildType;
    name = "caelestia-qml-plugin${lib.optionalString debug "-debug"}";
    src = lib.fileset.toSource {
      root = ./..;
      fileset = lib.fileset.union ./../CMakeLists.txt ./../plugin;
    };

    nativeBuildInputs = [cmake ninja pkg-config];
    buildInputs = [qt6.qtbase qt6.qtdeclarative qt6.qtshadertools libqalculate pipewire aubio libcava fftw lm_sensors];

    dontWrapQtApps = true;
    cmakeFlags =
      [
        (lib.cmakeFeature "ENABLE_MODULES" "plugin")
        (lib.cmakeFeature "INSTALL_QMLDIR" qt6.qtbase.qtQmlPrefix)
      ]
      ++ cmakeVersionFlags;
  };

  m3shapesModule = stdenv.mkDerivation {
    inherit cmakeBuildType;
    name = "caelestia-m3shapes${lib.optionalString debug "-debug"}";
    src = lib.fileset.toSource {
      root = ./..;
      fileset = ./../CMakeLists.txt;
    };

    nativeBuildInputs = [cmake ninja];
    buildInputs = [qt6.qtbase qt6.qtdeclarative];

    dontWrapQtApps = true;
    cmakeFlags =
      [
        (lib.cmakeFeature "ENABLE_MODULES" "m3shapes")
        (lib.cmakeFeature "INSTALL_QMLDIR" qt6.qtbase.qtQmlPrefix)
        m3shapesFlag
      ]
      ++ cmakeVersionFlags;
  };
in
  stdenv.mkDerivation {
    inherit version cmakeBuildType;
    pname = "caelestia-shell${lib.optionalString debug "-debug"}";
    src = ./..;

    nativeBuildInputs = [cmake ninja makeWrapper qt6.wrapQtAppsHook];
    buildInputs = [qs extras plugin m3shapesModule xkeyboard-config qt6.qtbase];
    propagatedBuildInputs = runtimeDeps;

    cmakeFlags =
      [
        (lib.cmakeFeature "ENABLE_MODULES" "shell")
        (lib.cmakeFeature "INSTALL_QSCONFDIR" "${placeholder "out"}/share/caelestia-shell")
      ]
      ++ cmakeVersionFlags;

    dontStrip = debug;

    prePatch = ''
      substituteInPlace assets/pam.d/fprint \
        --replace-fail pam_fprintd.so /run/current-system/sw/lib/security/pam_fprintd.so
      substituteInPlace assets/pam.d/howdy \
        --replace-fail pam_howdy.so /run/current-system/sw/lib/security/pam_howdy.so
    '';

    postInstall = ''
      makeWrapper ${qs}/bin/qs $out/bin/caelestia-shell \
      	--prefix PATH : "${lib.makeBinPath runtimeDeps}" \
      	--set FONTCONFIG_FILE "${fontconfig}" \
      	--set CAELESTIA_LIB_DIR ${extras}/lib \
        --set CAELESTIA_XKB_RULES_PATH ${xkeyboard-config}/share/xkeyboard-config-2/rules/base.lst \
      	--add-flags "-p $out/share/caelestia-shell"

      mkdir -p $out/lib
      ln -s ${extras}/lib/* $out/lib/
    '';

    passthru = {
      inherit plugin extras m3shapesModule;
    };

    meta = {
      description = "A fluid, morphing shell for your Linux desktop";
      homepage = "https://github.com/caelestia-dots/shell";
      license = lib.licenses.gpl3Only;
      mainProgram = "caelestia-shell";
    };
  }
