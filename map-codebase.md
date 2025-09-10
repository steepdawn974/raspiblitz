flowchart TD
  %% ========== START ==========
  A[build_sdcard.sh]:::start

  %% ========== BOOT & BACKGROUND ==========
  subgraph BOOT_AND_BG[Boot & Background Services]
    B[_bootstrap.sh]
    C[_background.scan.sh]
    D[_background.sh]
    E[_cache.sh]
  end

  %% ========== SSH UI ==========
  subgraph SSH_UI[SSH User Interface]
    F[home.admin/00raspiblitz.sh]
    G[home.admin/00mainMenu.sh]
    G1[home.admin/00settingsMenuBasics.sh]
    G2[home.admin/00settingsMenuServices.sh]
    G3[home.admin/00parallelChainsMenu.sh]
    G4[home.admin/00parallelMainnetServices.sh]
    G5[home.admin/00parallelTestnetServices.sh]
    G6[home.admin/98repairMenu.sh]
    G7[home.admin/99updateMenu.sh]
    G8[home.admin/99systemMenu.sh]
    G9[home.admin/99connectMenu.sh]
    G10[home.admin/99lndMenu.sh]
    G11[home.admin/99lndRepairMenu.sh]
    G12[home.admin/99clMenu.sh]
    G13[home.admin/99clRepairMenu.sh]
    G14[home.admin/00infoBlitz.sh]
    G15[home.admin/00infoLCD.sh]
  end

  %% ========== SETUP CONTROLLERS ==========
  subgraph SETUP_UI[Setup Controllers (interactive)]
    S1[home.admin/setup.scripts/controlSetupDialog.sh]
    S2[home.admin/setup.scripts/controlSetupExtendedDialog.sh]
    S3[home.admin/setup.scripts/controlFinalDialog.sh]
    S4[home.admin/setup.scripts/eventBlockchainSync.sh]
  end

  %% ========== PROVISIONING ==========
  subgraph PROVISIONING[Provisioning Phases]
    P0[home.admin/_provision.setup.sh]
    P1[home.admin/_provision.update.sh]
    P2[home.admin/_provision.migration.sh]
    P3[home.admin/_provision.xfinal.sh]
    P4[home.admin/_provision_.sh]
  end

  %% ========== CONFIG SCRIPTS (subset) ==========
  subgraph CONFIG_SCRIPTS[Config Scripts (subset of many)]
    CS0[home.admin/config.scripts/blitz.conf.sh]
    CS1[home.admin/config.scripts/blitz.data.sh]
    CS2[home.admin/config.scripts/blitz.ssh.sh]
    CS3[home.admin/config.scripts/blitz.display.sh]
    CS4[home.admin/config.scripts/blitz.bootdrive.sh]
    CS5[home.admin/config.scripts/internet.sh]
    CS6[home.admin/config.scripts/internet.wifi.sh]
    CS7[home.admin/config.scripts/internet.letsencrypt.sh]
    CS8[home.admin/config.scripts/internet.dyndomain.sh]
    CS9[home.admin/config.scripts/bitcoin.monitor.sh]
    CS10[home.admin/config.scripts/bitcoin.install.sh]
    CS11[home.admin/config.scripts/bitcoin.update.sh]
    CS12[home.admin/config.scripts/lnd.install.sh]
    CS13[home.admin/config.scripts/lnd.credentials.sh]
    CS14[home.admin/config.scripts/lnd.unlock.sh]
    CS15[home.admin/config.scripts/lnd.backup.sh]
    CS16[home.admin/config.scripts/lnd.monitor.sh]
    CS17[home.admin/config.scripts/cl.install.sh]
    CS18[home.admin/config.scripts/cl.install-service.sh]
    CS19[home.admin/config.scripts/cl.hsmtool.sh]
    CS20[home.admin/config.scripts/cl.backup.sh]
    CS21[home.admin/config.scripts/cl.monitor.sh]
    CS22[home.admin/config.scripts/blitz.web.sh]
    CS23[home.admin/config.scripts/blitz.web.api.sh]
    CS24[home.admin/config.scripts/blitz.web.ui.sh]
    CS25[home.admin/config.scripts/blitz.passwords.sh]
    CS26[home.admin/config.scripts/blitz.copychain.sh]
    CS27[home.admin/config.scripts/blitz.hardware.sh]
  end

  %% ========== BONUS / APP MENUS (subset) ==========
  subgraph BONUS_APPS[Bonus/App Menus (subset)]
    BA1[home.admin/config.scripts/bonus.electrs.sh]
    BA2[home.admin/config.scripts/bonus.fulcrum.sh]
    BA3[home.admin/config.scripts/bonus.btc-rpc-explorer.sh]
    BA4[home.admin/config.scripts/bonus.lit.sh]
    BA5[home.admin/config.scripts/bonus.lndg.sh]
    BA6[home.admin/config.scripts/bonus.lnbits.sh]
    BA7[home.admin/config.scripts/bonus.mempool.sh]
    BA8[home.admin/config.scripts/bonus.specter.sh]
    BA9[home.admin/config.scripts/bonus.joinmarket.sh]
    BA10[home.admin/config.scripts/bonus.jam.sh]
    BA11[home.admin/config.scripts/bonus.thunderhub.sh]
    BA12[home.admin/config.scripts/internet.zerotier.sh]
    BA13[home.admin/config.scripts/internet.tailscale.sh]
    BA14[home.admin/config.scripts/bonus.sphinxrelay.sh]
    BA15[home.admin/config.scripts/bonus.helipad.sh]
    BA16[home.admin/config.scripts/bonus.squeaknode.sh]
    BA17[home.admin/config.scripts/bonus.labelbase.sh]
    BA18[home.admin/config.scripts/bonus.telegraf.sh]
    BA19[home.admin/config.scripts/bonus.albyhub.sh]
    %% ... many more under home.admin/config.scripts/*
  end

  %% ========== EDGES FROM build_sdcard ==========
  A -->|"Copies repo + installs scripts/assets"| B
  A -->|"Autostart SSH UI (.bashrc) -> 00raspiblitz.sh"| F

  %% ========== BOOT FLOW ==========
  B -->|"initial cache + state mgmt"| E
  B -->|"wait for scan first loop"| C
  B -->|"setup storage/wifi/etc"| CS1
  B --> CS2
  B --> CS5
  B --> CS6
  B --> CS3
  B --> CS4
  B --> CS22

  %% ========== BACKGROUND SERVICES ==========
  D --> P3
  D --> CS8
  D --> CS5
  D --> CS9
  D --> CS15
  D --> CS25
  D --> CS7

  C -->|"imports + monitors"| E
  C --> CS27
  C --> CS5
  C --> CS1
  C --> CS9
  C --> CS16
  C --> CS21

  %% ========== SSH UI FLOW ==========
  F -->|"reads state + handles special modes"| CS26
  F --> E
  F -->|"calls setup controllers when needed"| S1
  F --> S2
  F --> S3
  F --> S4
  F -->|"main menu"| G

  %% ========== MAIN MENU to submenus/APPS ==========
  G --> G10
  G --> G12
  G --> G9
  G --> G8
  G --> G3
  G --> G2
  G --> G1
  G --> G6
  G --> G7
  G --> G14
  G --> G15
  G -->|"Apps & Services"| BA1
  G --> BA2
  G --> BA3
  G --> BA4
  G --> BA5
  G --> BA6
  G --> BA7
  G --> BA8
  G --> BA9
  G --> BA10
  G --> BA11
  G --> BA12
  G --> BA13
  G --> BA14
  G --> BA15
  G --> BA16
  G --> BA17
  G --> BA18
  G --> BA19

  %% ========== PROVISIONING ==========
  %% Bootstrap orchestrates system copy / setup; then provision phases handle install/config.
  B -->|"provision flow (setup/migration/update)"| P0
  B --> P1
  B --> P2

  %% Provisioning calls into config scripts
  P0 --> CS1
  P0 --> CS10
  P0 --> CS11
  P0 --> CS12
  P0 --> CS13
  P0 --> CS15
  P0 --> CS14
  P0 --> CS17
  P0 --> CS18
  P0 --> CS19
  P0 --> CS20
  P0 --> CS25

  P1 --> CS11
  P1 --> CS12
  P1 --> CS17

  P2 --> CS1
  P2 --> CS12
  P2 --> CS17

  %% ========== STYLES ==========
  classDef start fill:#e3f2fd,stroke:#1976d2,color:#0d47a1,font-weight:bold;
  classDef group fill:#f5f5f5,stroke:#9e9e9e,color:#424242;
  class BOOT_AND_BG,SSH_UI,PROVISIONING,CONFIG_SCRIPTS,BONUS_APPS group;

  %% ========== CLICKS (links to relative paths) ==========
  click A "build_sdcard.sh" "build_sdcard.sh"
  click B "home.admin/_bootstrap.sh" "_bootstrap.sh"
  click C "home.admin/_background.scan.sh" "_background.scan.sh"
  click D "home.admin/_background.sh" "_background.sh"
  click E "home.admin/_cache.sh" "_cache.sh"

  click F "home.admin/00raspiblitz.sh" "00raspiblitz.sh"
  click G "home.admin/00mainMenu.sh" "00mainMenu.sh"
  click G1 "home.admin/00settingsMenuBasics.sh" "00settingsMenuBasics.sh"
  click G2 "home.admin/00settingsMenuServices.sh" "00settingsMenuServices.sh"
  click G3 "home.admin/00parallelChainsMenu.sh" "00parallelChainsMenu.sh"
  click G4 "home.admin/00parallelMainnetServices.sh" "00parallelMainnetServices.sh"
  click G5 "home.admin/00parallelTestnetServices.sh" "00parallelTestnetServices.sh"
  click G6 "home.admin/98repairMenu.sh" "98repairMenu.sh"
  click G7 "home.admin/99updateMenu.sh" "99updateMenu.sh"
  click G8 "home.admin/99systemMenu.sh" "99systemMenu.sh"
  click G9 "home.admin/99connectMenu.sh" "99connectMenu.sh"
  click G10 "home.admin/99lndMenu.sh" "99lndMenu.sh"
  click G11 "home.admin/99lndRepairMenu.sh" "99lndRepairMenu.sh"
  click G12 "home.admin/99clMenu.sh" "99clMenu.sh"
  click G13 "home.admin/99clRepairMenu.sh" "99clRepairMenu.sh"
  click G14 "home.admin/00infoBlitz.sh" "00infoBlitz.sh"
  click G15 "home.admin/00infoLCD.sh" "00infoLCD.sh"

  click S1 "home.admin/setup.scripts/controlSetupDialog.sh" "controlSetupDialog.sh"
  click S2 "home.admin/setup.scripts/controlSetupExtendedDialog.sh" "controlSetupExtendedDialog.sh"
  click S3 "home.admin/setup.scripts/controlFinalDialog.sh" "controlFinalDialog.sh"
  click S4 "home.admin/setup.scripts/eventBlockchainSync.sh" "eventBlockchainSync.sh"

  click P0 "home.admin/_provision.setup.sh" "_provision.setup.sh"
  click P1 "home.admin/_provision.update.sh" "_provision.update.sh"
  click P2 "home.admin/_provision.migration.sh" "_provision.migration.sh"
  click P3 "home.admin/_provision.xfinal.sh" "_provision.xfinal.sh"
  click P4 "home.admin/_provision_.sh" "_provision_.sh"

  click CS0 "home.admin/config.scripts/blitz.conf.sh" "blitz.conf.sh"
  click CS1 "home.admin/config.scripts/blitz.data.sh" "blitz.data.sh"
  click CS2 "home.admin/config.scripts/blitz.ssh.sh" "blitz.ssh.sh"
  click CS3 "home.admin/config.scripts/blitz.display.sh" "blitz.display.sh"
  click CS4 "home.admin/config.scripts/blitz.bootdrive.sh" "blitz.bootdrive.sh"
  click CS5 "home.admin/config.scripts/internet.sh" "internet.sh"
  click CS6 "home.admin/config.scripts/internet.wifi.sh" "internet.wifi.sh"
  click CS7 "home.admin/config.scripts/internet.letsencrypt.sh" "internet.letsencrypt.sh"
  click CS8 "home.admin/config.scripts/internet.dyndomain.sh" "internet.dyndomain.sh"
  click CS9 "home.admin/config.scripts/bitcoin.monitor.sh" "bitcoin.monitor.sh"
  click CS10 "home.admin/config.scripts/bitcoin.install.sh" "bitcoin.install.sh"
  click CS11 "home.admin/config.scripts/bitcoin.update.sh" "bitcoin.update.sh"
  click CS12 "home.admin/config.scripts/lnd.install.sh" "lnd.install.sh"
  click CS13 "home.admin/config.scripts/lnd.credentials.sh" "lnd.credentials.sh"
  click CS14 "home.admin/config.scripts/lnd.unlock.sh" "lnd.unlock.sh"
  click CS15 "home.admin/config.scripts/lnd.backup.sh" "lnd.backup.sh"
  click CS16 "home.admin/config.scripts/lnd.monitor.sh" "lnd.monitor.sh"
  click CS17 "home.admin/config.scripts/cl.install.sh" "cl.install.sh"
  click CS18 "home.admin/config.scripts/cl.install-service.sh" "cl.install-service.sh"
  click CS19 "home.admin/config.scripts/cl.hsmtool.sh" "cl.hsmtool.sh"
  click CS20 "home.admin/config.scripts/cl.backup.sh" "cl.backup.sh"
  click CS21 "home.admin/config.scripts/cl.monitor.sh" "cl.monitor.sh"
  click CS22 "home.admin/config.scripts/blitz.web.sh" "blitz.web.sh"
  click CS23 "home.admin/config.scripts/blitz.web.api.sh" "blitz.web.api.sh"
  click CS24 "home.admin/config.scripts/blitz.web.ui.sh" "blitz.web.ui.sh"
  click CS25 "home.admin/config.scripts/blitz.passwords.sh" "blitz.passwords.sh"
  click CS26 "home.admin/config.scripts/blitz.copychain.sh" "blitz.copychain.sh"
  click CS27 "home.admin/config.scripts/blitz.hardware.sh" "blitz.hardware.sh"

  click BA1 "home.admin/config.scripts/bonus.electrs.sh" "bonus.electrs.sh"
  click BA2 "home.admin/config.scripts/bonus.fulcrum.sh" "bonus.fulcrum.sh"
  click BA3 "home.admin/config.scripts/bonus.btc-rpc-explorer.sh" "bonus.btc-rpc-explorer.sh"
  click BA4 "home.admin/config.scripts/bonus.lit.sh" "bonus.lit.sh"
  click BA5 "home.admin/config.scripts/bonus.lndg.sh" "bonus.lndg.sh"
  click BA6 "home.admin/config.scripts/bonus.lnbits.sh" "bonus.lnbits.sh"
  click BA7 "home.admin/config.scripts/bonus.mempool.sh" "bonus.mempool.sh"
  click BA8 "home.admin/config.scripts/bonus.specter.sh" "bonus.specter.sh"
  click BA9 "home.admin/config.scripts/bonus.joinmarket.sh" "bonus.joinmarket.sh"
  click BA10 "home.admin/config.scripts/bonus.jam.sh" "bonus.jam.sh"
  click BA11 "home.admin/config.scripts/bonus.thunderhub.sh" "bonus.thunderhub.sh"
  click BA12 "home.admin/config.scripts/internet.zerotier.sh" "internet.zerotier.sh"
  click BA13 "home.admin/config.scripts/internet.tailscale.sh" "internet.tailscale.sh"
  click BA14 "home.admin/config.scripts/bonus.sphinxrelay.sh" "bonus.sphinxrelay.sh"
  click BA15 "home.admin/config.scripts/bonus.helipad.sh" "bonus.helipad.sh"
  click BA16 "home.admin/config.scripts/bonus.squeaknode.sh" "bonus.squeaknode.sh"
  click BA17 "home.admin/config.scripts/bonus.labelbase.sh" "bonus.labelbase.sh"
  click BA18 "home.admin/config.scripts/bonus.telegraf.sh" "bonus.telegraf.sh"
  click BA19 "home.admin/config.scripts/bonus.albyhub.sh" "bonus.albyhub.sh"