# Créditos e licenças

O fluxo ColorOS deriva das ferramentas originais QuantumROM. Estes créditos históricos preservam a atribuição; vários componentes One UI citados foram retirados. A licença original do repositório está em LICENSE. APKs, firmware e ferramentas de terceiros conservam suas próprias licenças.

### Credits:
#### 1. Samsung Firmware Downloader.
- martinetd
- https://github.com/martinetd/samloader
- Used for downloading Samsung firmware.

#### 2. Multi Disabler.
- ianmacd
- https://github.com/ianmacd/multidisabler-samsung
- Used for disabling Samsung security and data encryption.

#### 3. Bluetooth Library Patcher.
- 3arthur6
- https://github.com/3arthur6/BluetoothLibraryPatcher
- Used for patching Samsung Bluetooth libraries.

#### 4. UN1CA Project.
- salvogiangri
- https://github.com/salvogiangri/UN1CA

#### Components Used from UN1CA.
- Android 17 OMX/C2 seccomp `mremap` compatibility rule, adapted to the checked ColorOS vendor patch stage.
- `HEX_PATCH` function (modified from UN1CA implementation)
- Knox Patch (from UN1CA)
- Secure Folder Patch (from UN1CA)
- Knox Guard Patch (from UN1CA)
- Secure Flag Patch (from UN1CA)
- SSRM Patch (from UN1CA)
- Some SELinux patches followed the UN1CA implementation.

#### 5. App optimization stuck fix.
- ExtremeXT
- https://github.com/ExtremeXT
- For app optimization stuck fix.

#### 6. Google photos unlimited backup.
- VehanRajintha
- https://github.com/VehanRajintha/Free-Unlimited-Google-Cloud-Backup-Magisk-Module

#### 7. ChatGPT.
- https://chat.openai.com
- For providing bash commands and bash functions according to the project requirements and instructions.

#### 8. GoFile Uploader.
- Sushrut1101
- https://github.com/Sushrut1101/GoFile-Upload

#### 9. OMC Decoder.
- fei-ke
- https://github.com/fei-ke/OmcTextDecoder

#### 10. apktool.
- iBotPeaches
- https://github.com/ibotpeaches/apktool



Ferramentas mantidas: img2sdat/AOSP platform_build, apktool, extratores EROFS/ext4, lpunpack e builders ext4/F2FS. Os avisos e referências presentes em bin foram preservados. Calibrações r8s/y2s/z3s: LineageOS, conforme device.json dos targets.

Compilador de políticas SELinux: projeto SELinux/AOSP (libsepol/secilc 3.7), a partir dos fontes locais do android-tools usados pelo UN1CA. Fontes completas, licença e reprodução em bin/selinux.

Compatibilidade BPF Exynos990: Ats0c_ e módulo local UN1CA platform/exynos990/patches/tethering_legacy (gates de versão, programas4.19 e consumidores opcionais), adaptados para a ColorOS17. Assinatura APEX: avbtool/signapk AOSP fornecidos pelo checkout UN1CA.
