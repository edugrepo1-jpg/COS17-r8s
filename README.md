# ColorOS 17 — Exynos990 build system

Build de ColorOS para Galaxy S20 (x1s), S20+ (y2s), S20 Ultra (z3s) e S20 FE Exynos (r8s/SM-G780F). Os patches de One UI e as ferramentas legadas QuantumROM sem uso foram retirados. O nome `QuantumROM` foi mantido nas pastas de entrada para preservar os caminhos existentes.

## Construir

Na raiz do projeto:

```bash
bash build.sh x1s erofs
bash build.sh r8s erofs --patch-only
bash build.sh x1s erofs -z
bash build.sh x1s erofs -p vendor
```

Targets: `x1s`, `y2s`, `z3s`, `r8s` ou os modelos aceitos em build.sh. Formatos: `erofs`, `ext4`, `f2fs`. `--patch-only` prepara/aplica sem reconstruir imagens; `-p`/`--partition` limita a saída a `system`, `product`, `vendor` ou `odm`; `-z`/`--zip` gera também o ZIP flasheável e exige as quatro partições. EROFS tem verificação completa; os demais formatos ainda exigem validação adicional.

## Entradas necessárias

- Para converter uma entrada EXT4 em EROFS, coloque-a em `FW/ColorOS/system.img` e execute `bash build.sh x1s erofs`. O formato de saída independe do formato da entrada. Se já existir `FW/ColorOS/system`, mova essa extração antes de trocar a imagem; ela é reutilizada. Os hashes dos patches ainda precisam corresponder à mesma base ColorOS.
- Base ColorOS compatível com os hashes do manifesto em `FW/ColorOS/system`, com `FW/ColorOS/config/system_{fs_config,file_contexts}`. O fluxo também mantém extração de system.img/super e arquivos de firmware quando necessário.
- Vendor/ODM em `QuantumROM/Devices/<modelo>/extra/{vendor,odm}.img`: SM-G980F para x1s, SM-G986B para y2s, SM-G988B para z3s, SM-G780F para r8s.
- Configuração/calibração em `QuantumROM/targets/<target>/{device.json,bringup.sh}`.
- Para `--zip`, template completo em `QuantumROM/targets/<target>/zip`: instalador, metadados, super metadata, boot.img e dtbo.img. No r8s, kernel/DTB/DTBO foram atualizados em 10/11 com o conjunto da Artisan com ChargeMax V3, preservando o ramdisk da COS. Confira o estado e as pendências no diagnóstico r8s antes do primeiro teste.

Não são baixadas ROMs ou bibliotecas automaticamente. Não se deve trocar a base sem revisar os checksums dos patches. O build não usa Stock, Mods, VNDK, MTK_SPECIAL, extra_blobs ou os empacotadores antigos.

A base atual é ColorOS 17.0.0 / Android 17 (API 37), `PLK110_11.C.76_1760_202610051308`, segurança 2026-09-01. Framework, patches nativos, configurações, SDK da câmera e TeleService foram adaptados com novos hashes fechados. Veja o [relatório da migração](QuantumROM/patches/coloros/diagnostics/android17-rebase-2026-10-27.md) para os resultados e limites de validação. O histórico da 16.0.5 continua no [relatório anterior](QuantumROM/patches/coloros/diagnostics/base-refresh-2026-10-19.md).

Debloat unificado: [manifesto](QuantumROM/patches/coloros/debloat.json) e [documentação](QuantumROM/patches/coloros/DEBLOAT.md). Os componentes OEM preservados vêm da nova firmware; os payloads dos fixes e os preloads continuam ativos.

Compatibilidade vendor antigo na 17: mappings SELinux 30.0 e APEX VNDK30 recuperados da 16.0.5, com compilação completa da política obrigatória antes das imagens. [Detalhes e validação](QuantumROM/patches/coloros/diagnostics/android17-selinux-vndk30-2026-10-29.md). As imagens anteriores à correção precisam ser reconstruídas.

Rede/BPF da 17: [APEX adaptado e assinado para o kernel Exynos990 4.19](QuantumROM/patches/coloros/diagnostics/android17-network-bpf-2026-10-29.md). O build usa o payload verificado; kernel/boot/DTBO permanecem os existentes.

O ZIP usa a identidade registrada em `build-info.json` durante a verificação das imagens: versão, fingerprint, incremental, API, segurança e timestamp. Antes de empacotar, confere novamente os hashes das quatro imagens. Saídas antigas sem essa identidade precisam ser reconstruídas; `--patch-only` não produz imagens novas.

[Revisão do build em 22/10/2026](QuantumROM/patches/coloros/diagnostics/build-audit-2026-10-22.md): câmera original conferida e preservada, proteção da imagem de product, saída F2FS raw, preservação de entradas sparse e do ZIP anterior em falhas. Inclui os pontos ainda manuais e os testes executados.

## Organização

```text
build.sh                         # entrada da build
scripts/QuantumRom.sh            # somente helpers usados pela ColorOS
scripts/extract_img.sh           # extração F2FS por montagem
scripts/source_zip.sh            # exportação da source
bin/                             # ferramentas e dependências mantidas
QuantumROM/
  Devices/<modelo>/config         # parâmetros do grupo dinâmico
  Devices/<modelo>/extra/         # vendor.img e odm.img de entrada
  targets/<target>/               # bringup, calibração e template do ZIP
  patches/coloros/                # manifesto, patches, payloads, testes e documentação
FW/ColorOS/                      # firmware local de entrada
out/
  target/<target>/               # imagens, relatórios e ZIP flasheável
  cache/<target>/                # extrações e árvore preparada
  logs/<target>/                 # logs de build
  logs/source-cleanup/           # relatório da limpeza e testes
  archive/                       # histórico e referências retirados da raiz
  source/                        # ZIPs exportados da source
```

A pasta minúscula `out` é preservada. `OUT` maiúsculo foi retirado. WORK e logs de investigação foram movidos para `out/archive/port-history`. Kernels/recoveries extras não usados pelo gerador foram guardados em `out/archive/device-kernels`. Restos legados sem permissão para remoção física ficam em `out/archive/legacy-quantum`, fora da source.

## Salvar a source

```bash
bash scripts/source_zip.sh
```

O ZIP é gravado e verificado em `out/source`, junto de um SHA256. Inclui código, patches, ferramentas, vendor/odm de entrada e templates dos quatro targets. Usa ZIP64 sem compressão adicional, pois boa parte dos blobs já está comprimida; por isso será grande.

**FW/ColorOS e todo o out ficam fora do ZIP.** Ao restaurar a source em outra pasta, forneça novamente a base ColorOS com seus metadados. Não há caches, logs pessoais ou resultados de build dentro do arquivo. Para conservar também a ROM de entrada, salve FW separadamente.

## Dependências e testes

Linux com Bash, Python 3, JDK 17+, patch, 7z, Brotli, file/blkid, lz4, simg2img/img2simg e e2fsprogs. A verificação EROFS usa fsck.erofs do sistema. As ferramentas binárias do projeto podem exigir as bibliotecas compartilhadas correspondentes. Extração F2FS por montagem requer privilégios de montagem e getfattr. Nenhum script instala pacotes ou atualiza o sistema operacional automaticamente.

```bash
python3 -m unittest discover -s QuantumROM/patches/coloros/tests -v
bash -n build.sh scripts/*.sh QuantumROM/targets/*/bringup.sh
```

O pipeline valida hashes/bytes de entrada, DEX, compilação SELinux completa, metadados e o orçamento do grupo dinâmico. Isso não substitui testes físicos de boot, display, rádio e biometria. Não altere scripts durante uma build em execução.

Detalhes: [manual ColorOS](QuantumROM/patches/coloros/README.md), [product](QuantumROM/patches/coloros/PRODUCT_LAYOUT.md), [histórico completo](RELATORIO_COLOROS_E_BUILD_SYSTEM.md), [créditos](CREDITS.md) e [licença](LICENSE).

A build normal gera system.img, product.img, vendor.img e odm.img. A separação validada no x1s é aplicada depois dos patches; com `-z`, todos os payloads new.dat.br e os tamanhos do dynamic_partitions_op_list são gerados a partir dessas imagens. Não é mais necessário fornecer product.* no template.

## Adaptação r8s em andamento — 10/11/2026

[Estado técnico, migração da Artisan e pendências](QuantumROM/patches/coloros/diagnostics/r8s-artisan-transfer-2026-11-10.md). O `FW/ColorOS/system.img` fornecido continua intacto. A imagem de kernel do template r8s agora vem da build Artisan 4.0.2 concluída em 09/11, com ChargeMax V3 ativo, dados de placa r8s e ramdisk original da COS preservado. O kernel foi recompilado com `close_range` na execução42790120462, verificado e reempacotado com o ramdisk COS preservado. Isso ainda não comprova boot da COS17. A montagem do ZIP fica para depois das correções, conforme solicitado.
