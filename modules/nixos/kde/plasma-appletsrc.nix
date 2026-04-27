{...}: {
  programs.plasma.panels = [
    {
      location = "bottom";
      widgets = [
        {
          kickoff = {
            icon = "kali-panel-menu-large";
          };
        }
        "org.kde.plasma.pager"
        {
          iconTasks = {
            launchers = [
              "applications:org.kde.dolphin.desktop"
              "applications:google-chrome.desktop"
              "applications:cursor.desktop"
              "applications:tableplus.desktop"
              "applications:org.kde.konsole.desktop"
            ];
          };
        }
        "org.kde.plasma.marginsseparator"
        {
          systemTray = {
            items = {
              extra = [
                "org.kde.plasma.manage-inputmethod"
                "org.kde.plasma.brightness"
                "org.kde.plasma.volume"
                "org.kde.plasma.battery"
                "org.kde.plasma.vault"
                "org.kde.plasma.clipboard"
                "org.kde.plasma.devicenotifier"
                "org.kde.plasma.bluetooth"
                "org.kde.kdeconnect"
                "org.kde.plasma.cameraindicator"
                "org.kde.kscreen"
                "org.kde.plasma.keyboardlayout"
                "org.kde.plasma.networkmanagement"
                "org.kde.plasma.notifications"
                "org.kde.plasma.mediacontroller"
              ];
              configs.battery.showPercentage = true;
            };
          };
        }
        "org.kde.plasma.digitalclock"
        "org.kde.plasma.showdesktop"
      ];
    }
  ];

  programs.plasma.desktop.widgets = [
    {
      systemMonitor = {
        title = "Total CPU Use";
        displayStyle = "org.kde.ksysguard.linechart";
        position = {
          horizontal = 16;
          vertical = 32;
        };
        size = {
          width = 464;
          height = 352;
        };
        sensors = [
          {
            name = "cpu/all/usage";
            color = "39,119,255";
            label = "CPU Usage";
          }
        ];
        totalSensors = ["cpu/all/usage"];
        textOnlySensors = ["cpu/all/cpuCount" "cpu/all/coreCount"];
      };
    }
    {
      systemMonitor = {
        title = "Memory Usage";
        displayStyle = "org.kde.ksysguard.linechart";
        position = {
          horizontal = 80;
          vertical = 528;
        };
        size = {
          width = 464;
          height = 304;
        };
        sensors = [
          {
            name = "memory/physical/used";
            color = "39,119,255";
            label = "RAM Used";
          }
        ];
        totalSensors = ["memory/physical/usedPercent"];
        textOnlySensors = ["memory/physical/total"];
      };
    }
    {
      systemMonitor = {
        title = "Network Speed";
        displayStyle = "org.kde.ksysguard.linechart";
        position = {
          horizontal = 1040;
          vertical = 32;
        };
        size = {
          width = 448;
          height = 352;
        };
        sensors = [
          {
            name = "network/all/download";
            color = "39,119,255";
            label = "Down";
          }
          {
            name = "network/all/upload";
            color = "255,175,39";
            label = "Up";
          }
        ];
      };
    }
    {
      systemMonitor = {
        title = "Hard Disk Activity";
        displayStyle = "org.kde.ksysguard.linechart";
        position = {
          horizontal = 1488;
          vertical = 32;
        };
        size = {
          width = 400;
          height = 352;
        };
        sensors = [
          {
            name = "disk/all/write";
            color = "39,119,255";
            label = "Write";
          }
          {
            name = "disk/all/read";
            color = "255,175,39";
            label = "Read";
          }
        ];
      };
    }
    {
      name = "org.kde.plasma.battery";
      position = {
        horizontal = 480;
        vertical = 0;
      };
      size = {
        width = 560;
        height = 240;
      };
    }
    {
      name = "org.kde.plasma.volume";
      position = {
        horizontal = 672;
        vertical = 752;
      };
      size = {
        width = 528;
        height = 256;
      };
    }
    {
      name = "org.kde.plasma.cameraindicator";
      position = {
        horizontal = 896;
        vertical = 640;
      };
      size = {
        width = 96;
        height = 96;
      };
    }
    {
      name = "org.kde.kscreen";
      position = {
        horizontal = 1200;
        vertical = 752;
      };
      size = {
        width = 528;
        height = 256;
      };
    }
  ];
}
