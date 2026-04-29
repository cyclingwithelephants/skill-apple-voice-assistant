{
  description = "Apple Voice Assistant skill and nix-darwin services";

  outputs = { self }: {
    darwinModules.default = self.darwinModules.apple-voice-assistant;

    darwinModules.apple-voice-assistant = { config, lib, ... }:
      let
        cfg = config.services.apple-voice-assistant;

        # The service is installed for a normal macOS login user, because Voice
        # Memos syncs into that user's Library and the runtime needs that user's
        # TCC/iCloud visibility. Callers must choose the user explicitly.
        home = cfg.home;

        # Runtime state is kept outside the skill source so the skill can be a
        # read-only Nix store path while logs, locks, and seen-file data persist.
        stateDir = cfg.stateDir;

        # This is the iCloud Voice Memos sync location used as the launchd
        # WatchPaths trigger. It is configurable because Apple has used more
        # than one recordings path across macOS releases and app variants.
        recordingsDir = cfg.recordingsDir;

        # The watcher talks to the Hermes runtime through environment
        # variables rather than hardcoded paths. Defaults match the conventional
        # Hermes layout, but every value can be overridden by module config.
        environment = {
          HOME = home;
          HERMES_HOME = cfg.runtimeHome;
          APPLE_VOICE_ASSISTANT_PYTHON = cfg.python;
        } // cfg.environment;
      in {
        options.services.apple-voice-assistant = {
          enable = lib.mkEnableOption "Apple Voice Assistant launchd services";

          user = lib.mkOption {
            type = lib.types.str;
            description = "macOS user that owns Voice Memos sync data and runs the LaunchAgents.";
          };

          group = lib.mkOption {
            type = lib.types.str;
            default = "staff";
            description = "macOS group used for LaunchAgent execution and state directory ownership.";
          };

          home = lib.mkOption {
            type = lib.types.str;
            default = "/Users/${cfg.user}";
            description = "Home directory for the LaunchAgent user.";
          };

          skillPath = lib.mkOption {
            type = lib.types.path;
            default = self.outPath;
            description = "Path to this skill source; defaults to the pinned flake source.";
          };

          recordingsDir = lib.mkOption {
            type = lib.types.str;
            default = "${home}/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings";
            description = "Directory that launchd watches for new Voice Memos recordings.";
          };

          stateDir = lib.mkOption {
            type = lib.types.str;
            default = "${home}/.local/state/apple-voice-assistant";
            description = "Persistent directory for logs, lock files, seen-set data, and processed records.";
          };

          runtimeHome = lib.mkOption {
            type = lib.types.str;
            default = "${home}/.hermes";
            description = "Assistant runtime home exposed to the watcher as HERMES_HOME.";
          };

          python = lib.mkOption {
            type = lib.types.str;
            default = "${cfg.runtimeHome}/hermes-agent/venv/bin/python";
            description = "Python interpreter used by watcher helper code and assistant handoff checks.";
          };

          environment = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Additional environment variables for both watcher and healthcheck jobs.";
          };
        };

        config = lib.mkIf cfg.enable {
          # Activation prepares only mutable runtime state. The skill source is
          # not copied or modified; launchd runs scripts from cfg.skillPath.
          system.activationScripts.postActivation.text = lib.mkAfter ''
            install -d -m 0755 -o ${cfg.user} -g ${cfg.group} "${stateDir}"
            install -d -m 0755 -o ${cfg.user} -g ${cfg.group} "${stateDir}/processed"
            touch "${stateDir}/seen.txt" "${stateDir}/watcher.log"
            chown -R ${cfg.user}:${cfg.group} "${stateDir}"
          '';

          # Watcher LaunchAgent: this is the declarative equivalent of
          # install/com.cyclingwithelephants.apple-voice-assistant.plist. It
          # fires when Voice Memos sync writes files, with a short interval as a
          # fallback for missed filesystem events.
          launchd.agents.apple-voice-assistant.serviceConfig = {
            Label = "com.cyclingwithelephants.apple-voice-assistant";
            UserName = cfg.user;
            GroupName = cfg.group;
            ProgramArguments = [ "${cfg.skillPath}/install/watcher.sh" ];
            WatchPaths = [ recordingsDir ];
            StartInterval = 10;
            RunAtLoad = true;
            ThrottleInterval = 10;
            StandardOutPath = "${stateDir}/launchd.out.log";
            StandardErrorPath = "${stateDir}/launchd.err.log";
            EnvironmentVariables = environment;
          };

          # Healthcheck LaunchAgent: this mirrors the companion plist and runs
          # daily. It warns when the watcher log has been silent long enough to
          # suggest sync, launchd, or runtime breakage.
          launchd.agents.apple-voice-assistant-healthcheck.serviceConfig = {
            Label = "com.cyclingwithelephants.apple-voice-assistant-healthcheck";
            UserName = cfg.user;
            GroupName = cfg.group;
            ProgramArguments = [ "${cfg.skillPath}/install/healthcheck.sh" ];
            StartCalendarInterval = [{ Hour = 9; Minute = 0; }];
            StandardOutPath = "${stateDir}/healthcheck.out.log";
            StandardErrorPath = "${stateDir}/healthcheck.err.log";
            EnvironmentVariables = environment;
          };
        };
      };
  };
}
