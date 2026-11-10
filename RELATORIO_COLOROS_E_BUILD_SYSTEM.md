# Histórico do port ColorOS e situação do build system

Atualizado em 15/10/2026. Última revisão: target r8s e limpeza da source ColorOS.

Este relatório consolida o trabalho registrado na conversa e nos relatórios de `WORK/coloros-*`. A primeira parte cobre o port até o início da integração no QuantumROM. A segunda preserva o histórico da integração e registra as atualizações até o estado atual. Não é uma certificação de funcionamento de cada recurso nos três aparelhos: a maior parte dos testes físicos foi feita no x1s conectado por ADB.

## Estado atual em 15/10/2026

**O fluxo já constrói system, vendor e odm do x1s e verifica as imagens no host.** O primeiro boot da nova distribuição ART ainda precisa de teste. As imagens x1s verificadas foram produzidas antes da remoção OTA; é necessário reconstruí-las para incluir esse último patch. y2s/z3s têm configuração e patches preparados, mas não tiveram imagens finais construídas nesta rodada, conforme solicitado pelo usuário.


**Correção posterior do OTA:** a remoção de `system/system/system_ext/app/OTA` foi retirada do manifesto após o usuário relatar o desaparecimento da entrada ColorOS em Sobre o dispositivo. O estágio OTA atual tem 11 operações: nove remoções e dois patches de init. As descrições anteriores de remoção de OTA.apk são históricas; o próximo build preserva o APK original.

O ponto de entrada foi renomeado pelo usuário de `sixteen.sh` para **`build.sh`**. O comando atual é:

```bash
bash build.sh x1s erofs
# Somente preparar e aplicar os patches:
bash build.sh x1s erofs --patch-only
```

A entrada é sempre `FW/ColorOS`. Os únicos argumentos obrigatórios são target (`x1s`, `y2s`, `z3s`, `r8s` ou modelo Samsung aceito) e formato (`erofs`, `ext4`, `f2fs`). Tethering, CSC, IMEI e seleção da pasta de firmware foram retirados. O script deve continuar na raiz do projeto.

| Item | Situação atual |
| --- | --- |
| Fixes do port | Integrados ao manifesto: framework, binários, configurações, debloat, OTA, vendor, bringup e limpeza ART. |
| Imagens finais | `out/target/<target>/{system,vendor,odm}.img`, `SHA256SUMS`, `build-info.json`. |
| Cache | `out/cache/<target>`; conserva extrações vendor/odm, DEX, ferramentas e árvore preparada. |
| Logs | `out/logs/<target>/build-*.log`; `build.log` aponta para o último. Cada patch descreve suas ações. |
| Testes de host | 16 testes passaram após integrar r8s; preparação/aplicação real e reaplicação r8s sem mudanças também verificadas. |
| Product | Conteúdo em system; não é necessário obter product.new.dat.br de outra ROM. A exclusão da partição lógica exige coordenar boot e instalador. |
| ZIP flasheável | Gerador integrado via `bash build.sh <target> <fs> -z`; parte de `QuantumROM/targets/<target>/zip` e grava `ColorOS-16.0.1-<target>-@miguelbarretoo.zip`. Ainda não foi gravado no aparelho. |
| Validação física pendente | Primeiro boot/ART e conferência funcional da nova build; isso impede garantir o funcionamento após flash. |

Os comandos de seis argumentos e as pendências descritas nas seções históricas abaixo representam o estado da época. Para uso atual, siga este resumo e a seção 8.

## 1. Bases e forma de trabalho

- Port: ColorOS 16, base PJX110, extraída em `FW/ColorOS/system`.
- Primeiro aparelho: Galaxy S20 Exynos, x1s. Depois foram preparados y2s, Galaxy S20+, e z3s, Galaxy S20 Ultra.
- Stock S20: SM-G981B_AUT, disponibilizada para consultar serviços, calibrações, configurações e bibliotecas Samsung.
- Repositório UN1CA_y2slte: referência para ferramentas de assinatura, blobs e implementação Samsung.
- Donor S23 FE: system de SM-S711B, fornecido posteriormente. Foi utilizado onde a versão recente era compatível, especialmente no NFC; não houve substituição indiscriminada das bibliotecas globais pelo donor.
- Kernel informado: arquivo `kerneldoalessandro.zip`, com referência ao repositório Android-Artisan/exynos990. Seu código exato não foi identificado apenas pelo identificador `dirty`. O usuário confirmou que o mesmo kernel funcionava com reconhecimento facial na One UI.

Os testes ao vivo usaram propriedades, comandos e montagens temporárias por ADB. Uma montagem temporária não equivale a uma mudança persistente na imagem: os fixes aprovados foram transferidos para as árvores extraídas. Houve reinícios de Android/compositor para carregar código novo; algumas sessões ficaram com tela preta e precisaram de recuperação do compositor ou reinício completo.

Módulos KernelSU não foram adotados como solução de persistência, porque o KernelSU disponível no aparelho não funcionava corretamente. O problema do KernelSU ficou para outra investigação.

## 2. Histórico anterior ao build system

### 2.1. Logcat não iniciava

O erro inicial era `Failed to wait for logd.ready to become true`.

O diagnóstico identificou `/system/bin/logd` com o label genérico `system_file`. Isso impedia a transição de domínio do serviço no init, inclusive em permissive. O label foi corrigido para `u:object_r:logd_exec:s0` nos metadados de empacotamento. O usuário confirmou que o logcat passou a funcionar.

Esse fix é de metadados da imagem; não basta copiar o executável logd ou alterar seu chmod.

### 2.2. Falha de segmentação ao construir EROFS

O `BUILD_IMG` falhava no `mkfs.erofs`. Foi mantido o workaround de xattrs inline, com `-x 2147483647`, para evitar o caminho de xattrs compartilhados que derrubava o binário disponível.

O helper continuou usando LZ4HC. Houve construção e verificação de imagens de teste durante os fixes anteriores. O workaround permanece em `scripts/QuantumRom.sh`; o novo fluxo não o retirou.

### 2.3. Primeira rodada de instabilidade e HALs incompatíveis

Foram investigados os registros de `instabilidade.txt`, procurando consultas repetidas a interfaces Oplus/Qualcomm que não existiam no vendor Exynos.

Principais alterações:

- `framework.jar`: `PerformanceManager.getPerformanceService()` passa a devolver ausência do serviço. Os consumidores examinados já tinham caminhos para serviço indisponível.
- `surfaceflinger`: quatro consultas específicas ao serviço IPerformance ausente foram substituídas pelo resultado de ausência, preservando as outras consultas de serviços.
- `oplus-framework.jar`: a consulta AFS incompatível retorna os cinco controles neutros existentes, sem consultar a interface de kernel ausente.
- Workload classifier Qualcomm: APK e pré-compilados removidos, com retirada de suas entradas de broadcast, economia e resolução.
- Sidecars `.fsv_meta` de JARs modificados e seus registros de metadados foram removidos.

O objetivo foi eliminar trabalho inútil e falhas de compatibilidade. Não houve promessa de FPS ou autonomia quantificados.

### 2.4. Debloat solicitado

Foi verificada a lista fornecida de `my_product/app`, `my_product/del-app`, `my_stock/app`, `my_stock/del-app` e `my_stock/priv-app`, removendo os diretórios encontrados.

A lista incluía serviços e aplicativos como AONService, OplusCamera, teclados chineses, ADS, Instant, OCR, FileEncryption, serviços de ativação, Pictorial, atualizador, temas, Music, assistente de voz, loja, integração de dispositivos e outros aplicativos indicados pelo usuário. Alguns nomes não existiam nesta versão da base.

A lista foi preservada no manifesto de patches. Atualizações manuais posteriores de Play Store e APK do KernelSU não foram tratadas como fixes de compatibilidade nem incorporadas como novos prebuilts do build system.

### 2.5. Resolução e enquadramento da imagem

A resolução padrão da ColorOS não correspondia ao painel Samsung. A imagem ficava concentrada num canto, enquanto a resolução alta preenchia a tela.

Foram ajustados:

- Dimensões declaradas em propriedades e comportamento de `OplusResolutionSwitchImpl`.
- Caminho de seleção da resolução física, em vez de depender somente de tamanho lógico por WindowManager.
- Tratamento Samsung MRES/DDI em `vendor/lib64/libexynosdisplay.so`.
- Posteriormente, atualização do viewport de entrada para acompanhar a resolução sem apagar e acender a tela.

O estado final solicitado foi FHD 1080×2400 como resolução padrão e QHD 1440×3200 como alta. O usuário esclareceu que não desejava a reversão pedida em uma mensagem intermediária.

### 2.6. Digital reconhecida como sensor traseiro

Foram consultados os serviços Samsung e os dados de calibração do S20. O framework e os recursos Oplus foram adaptados para o sensor ultrassônico sob a tela.

Alterações principais:

- Tipo e geometria do sensor em `HidlFingerprintSensorConfig`.
- Identificação ultrassônica em `OplusFingerprintSupportUtils`.
- Remoção da declaração óptica incompatível e seleção do recurso ultrassônico.
- Propriedades públicas de tipo, tamanho e posição do círculo.
- Contextos das três propriedades públicas necessários para a leitura pela interface.

Após etapas adicionais, o usuário confirmou cadastro e autenticação funcionando. O círculo e o efeito visual ainda precisaram dos ajustes posteriores descritos abaixo.

### 2.7. Atraso do botão de ligar/desligar a tela

Foram investigados `botãodeligar.txt` e os registros posteriores de digital.

O trabalho envolveu a identificação de projeto/hardware em `ProjectManager` e o caminho nativo de entrada que dependia de integração privada incompatível. O patch nativo ficou em `lib_inputflingerEx.so`.

O usuário confirmou, depois de reconstruir e flashear a imagem, que o atraso e os fixes de digital daquela etapa estavam resolvidos. As primeiras tentativas não eliminaram imediatamente o problema; a confirmação corresponde ao conjunto final.

### 2.8. Bluetooth conectava, mas o áudio permanecia no alto-falante

Os testes foram realizados com o WAAW SENSE 210. O S23 FE foi inspecionado, mas não fornecia o HAL A2DP legado necessário. A biblioteca global libchrome da ColorOS também não era compatível com a ABI exigida pelo HAL S20.

Fix final de vendor:

1. Módulo de saída `a2dp` antes de `a2dpsink` em `audio_policy_configuration.xml`, preservando as rotas Samsung restantes.
2. HAL A2DP Samsung de 32 bits com `libchrome.so` e `libevent.so` privados em `vendor/lib/hw`.
3. RUNPATH local para não substituir as bibliotecas globais.
4. Patch de quatro bytes no HAL: a ColorOS enviava seis campos de codec, enquanto o HAL esperava um sétimo campo de compartilhamento. O campo inexistente passou a ser inicializado como desligado, sem a leitura que causava timeout.
5. Regra SELinux restrita de conexão de socket entre o HAL de áudio e `bluetooth_30_0`.
6. Metadados dos arquivos acrescentados atualizados.

O usuário confirmou áudio chegando ao fone. Não foi feita validação física de todos os codecs, chamadas e dispositivos Bluetooth possíveis.

### 2.9. Comparação do vendor e restauração de MIDAS

O vendor extraído foi comparado com o aparelho. As diferenças relevantes incluíam os modelos Samsung MIDAS de processamento de câmera.

Por pedido explícito do usuário, o conjunto MIDAS do x1s foi restaurado para corresponder ao aparelho. Os arquivos anteriores ficaram como referência em WORK. Esse ajuste não deve copiar os modelos de câmera do x1s para y2s ou z3s.

### 2.10. Brilho pelo painel não alterava o painel físico

O HAL Samsung respondia a comandos diretos, mas o controle da ColorOS não chegava corretamente ao hardware.

A primeira abordagem de substituir o caminho do compositor foi rejeitada depois de resultar em tela preta. O original foi restaurado e o aparelho recuperado.

A segunda abordagem, confirmada pelo usuário, preserva as chamadas originais do compositor e envia o nível normalizado ao Samsung lights por `LogicalLight.setColor`, no `BacklightAdapter` do display principal. Displays externos mantêm o caminho original.

O serviço antigo de polling `brightness_fix` foi desativado para não disputar o brilho com o caminho nativo. O usuário confirmou que o slider passou a controlar o brilho.

### 2.11. Crash de previsão GPS

A interpretação de fragmentos inválidos de GPS gerava `NumberFormatException` em `DeepThinkerDelegate`.

Foi acrescentado o tratamento que devolve o resultado desconhecido já existente, sem derrubar a execução. Casos inválidos, vazios e válidos foram exercitados durante aquela investigação.

### 2.12. Nome do dispositivo

Foram corrigidas as propriedades que exibiam `Version 3.1` e a identidade comercial do donor. Os nomes passaram a acompanhar Galaxy S20, Galaxy S20+ e Galaxy S20 Ultra durante os respectivos bringups.

Alguns snapshots antigos continham o prefixo comercial chinês junto do nome Samsung. O novo bringup estabelece os nomes exatos de cada target a partir do cadastro do dispositivo.

### 2.13. Reconhecimento facial: avanço parcial e limitação restante

O serviço facial da ColorOS acrescentava uma instância virtual AIDL inexistente e faltava a configuração do sensor HIDL Samsung.

Foram aplicados:

- Retorno apenas das instâncias AIDL realmente declaradas.
- Inclusão do sensor HIDL Samsung `1:8:4095` somente quando a configuração original estava vazia.
- Preservação da classificação forte da digital; o facial foi tratado conservadoramente como conveniência.

O cadastro passou a abrir, mas a captura não foi concluída. A investigação avançou por buffers, heaps, HAL stock, kernel e câmera segura. Houve erros TEE/secure-camera, incluindo `-3011` e SMC/SSAPI 9102.

O usuário confirmou que o mesmo kernel funcionava na One UI, portanto não ficou demonstrado que o kernel fosse a causa isolada. As tentativas com outro serviço facial não resolveram a captura e foram retiradas.

Por decisão do usuário, a correção completa ficou adiada. Foram mantidos o registro correto do serviço e a eliminação do spam em repouso. **O reconhecimento facial completo continua sem solução validada.**

### 2.14. URCC, propriedade do compositor e consulta térmica

Outra rodada de spam foi tratada em três frentes:

- `libexynosdisplay.so`: a leitura repetida de `persist.sys.sf.hs_mode`, sem permissão adequada, foi direcionada ao nome já permitido `vendor.display.sf.hs`, preservando o comportamento de ausência/default.
- `liboplus-uah-client.so`, 32 e 64 bits: caminhos de conexão privada e inicialização do URCC ausente passam a usar o fallback de serviço indisponível.
- `thermal_fix.sh`: a consulta completa `dumpsys display` a cada ciclo foi substituída por `cmd display get-displays --type internal` e classificação leve de estado.

O restante do comportamento do script térmico e suas proteções foi preservado. Uma comparação de sessões mostrou menos GCs e eliminou as mensagens de dumpsys completo, mas não constituiu benchmark controlado de bateria ou FPS.

### 2.15. 120 Hz, oscilação e toque desalinhado

O painel permanecia em 60 Hz, ou alternava entre 48 e 60 Hz. O trabalho passou a selecionar o modo físico FHD/120 Hz e a tratar a resolução Samsung corretamente.

A primeira seleção produziu imagem parcial e, depois, oscilações. O temporizador de idle que alternava os modos foi desligado. O usuário confirmou estabilização.

Outro ajuste atualizou o viewport de toque imediatamente na troca de resolução. O usuário confirmou que os toques passaram a acertar a posição correta sem desligar e ligar a tela.

A configuração não promete QHD a 120 Hz: os modos continuam sujeitos ao que o painel e o HAL Samsung suportam.

### 2.16. Dados móveis fracos ou sem navegação

O registro LTE existia, mas um fallback Oplus convertia o retry indicado pelo modem em um prazo extremamente longo.

Em `telephony-common.jar`, o fallback de `IOplusDataManager.resetDelayTimeForAuTelstraOperator` foi corrigido para preservar o prazo recebido, em vez de produzir `2147483647` naquele caminho.

Uma renovação temporária do rádio recuperou a navegação no teste, confirmada pelo usuário no quarto com Wi-Fi desligado. Isso não prova todas as condições futuras de cobertura. O patch permanente é o de retry; não foi incluída uma renovação contínua de rádio como serviço.

O usuário pediu para descartar IMS por enquanto. **IMS/VoLTE/VoWiFi não foram implementados.**

### 2.17. NFC ausente ou sem handover Bluetooth

Foi usado o NfcNci recente do S23 FE, com JNI compatível e configuração Samsung S20, mantendo HAL e firmware do chip.

O conjunto final inclui:

- Tratamento da extensão opcional de vendor não disponível.
- Classes NFC auxiliares do donor necessárias ao serviço.
- Manifesto, XML de permissões privilegiadas e acesso a APIs internas para o pacote NFC.
- Assinatura do APK com certificado dedicado, usando a ferramenta signapk referenciada no UN1CA.
- Mapeamento desse certificado para o seinfo NFC.
- Concessões restritas de permissões de sistema, exigindo pacote, appId, flags de sistema/privilegiado e certificado corretos.
- Correção de `start vendor.nfc_hal_service` para o nome real `nfc_hal_service`.
- Permissões padrão `BLUETOOTH_CONNECT` e `BLUETOOTH_SCAN` vinculadas ao pacote/certificado.

O usuário confirmou que a tag NFC do fone Sony passou a executar o pareamento. Pagamentos, Wallet e elemento seguro não foram validados.

Não houve desativação global de verificação de assinatura. A chave privada do NFC não é conteúdo de firmware nem dos payloads do novo build system; o APK fornecido ao build já está assinado.

### 2.18. Animação de pressionar a digital

A digital autenticava, mas não disparava o efeito de toque da ColorOS.

O conversor HIDL foi adaptado para encaminhar os eventos Samsung de pressionar/soltar aos comandos Oplus existentes: vendor 10002 para 1201; 10004/10007 para 1202. Os eventos originais continuam sendo encaminhados.

O usuário confirmou que os efeitos visuais passaram a aparecer. Não foram alterados tokens, força da autenticação ou o resultado de reconhecimento para produzir o efeito.

### 2.19. Blur e caminho opcional de GC

Por autorização do usuário, foi testado o desligamento do blur. Houve melhora visual parcial, e o ajuste foi salvo nas propriedades e no init que aplica a preferência de interface.

No `oplus-services.jar`, o callback de configuração do GC passou a usar o valor explícito de desativação `2` para a otimização opcional incompatível com interfaces de kernel ausentes.

Isso não equivale a desativar o GC do Android. As durações das animações foram mantidas.

### 2.20. Vibração e spam do HAL

Os logs de `aquecimento.txt` mostravam efeitos e intensidades proprietários incompatíveis com o HAL Samsung.

Foram removidas três declarações LM/QCOM em dois XMLs de recursos Oplus. Isso seleciona o caminho genérico Android de vibração, preservando o motor e o HAL.

O usuário confirmou que a vibração do teclado e dos gestos passou a funcionar, inclusive relatando que antes não funcionava. Nem todo log Samsung em nível E representava uma falha; operações normais não foram tratadas como defeito.

### 2.21. Áudio de gravação de vídeo distorcido

O usuário confirmou que a gravação de voz comum estava normal e o problema ocorria somente nos vídeos.

Foi aplicado um patch de quatro bytes no HAL de áudio Samsung para o caminho de preprocessamento CAMCORDER, fonte 5, que era incompatível nessa combinação. A fonte MIC e os outros caminhos foram preservados.

O usuário confirmou que o áudio dos vídeos passou a funcionar perfeitamente.

### 2.22. Hotspot não ativava

A configuração solicitava um limite de clientes que dependia da capacidade de desconexão forçada não anunciada pelo HAL Samsung.

O `oplus-wifi-service.jar` passou a usar o limite padrão do driver quando essa capacidade não existe; com suporte, conserva o valor solicitado. SSID, senha e demais configurações não foram substituídos.

O usuário confirmou ativação e conexão. A navegação compartilhada não foi testada naquela sessão, por falta de créditos móveis.

### 2.23. Novos spams do compositor, Power HAL e AudioX

Foram integrados:

- Fallback existente para metadados Oplus vazios no SurfaceFlinger, evitando repetição de processamento/logs.
- Tratamento sem log repetido do retorno HWC UNSUPPORTED, preservando o retorno de falha e os demais erros.
- Desativação apenas do início do monitor dexopt do Power HAL que consultava um cpuset inexistente. O objeto QoS, os boosts e os outros caminhos do serviço permaneceram.
- Desativação somente de `AudioxService`, cujo efeito não existia no HAL, com script idempotente de compatibilidade. O app de efeitos inteiro e o audioserver não foram desativados.

O usuário relatou melhora progressiva, sem medição controlada de consumo ou FPS.

### 2.24. ZIP parado em 4%

A instalação ficava em `patch system image unconditionally` no PBRP informado pelo usuário.

O próprio usuário identificou e corrigiu o updater-binary desatualizado, confirmando que o ZIP voltou a flashear. Essa solução não foi um patch feito por mim no kernel ou no system. O novo build system ainda não implementa montagem automática de ZIP nem entrega um recovery novo.

### 2.25. Bringup y2s, z3s e retorno ao x1s

Foram transportados somente os deltas de compatibilidade compatíveis com as bases nativas examinadas. Bibliotecas foram comparadas por hash antes de reaplicar as instruções; câmera, modem, firmwares e modelos específicos dos outros aparelhos foram preservados.

A calibração y2s/z3s foi extraída das referências LineageOS disponibilizadas. Os nomes e densidades acompanharam os targets.

| Target | Centro e raio no painel nativo | Círculo / distância inferior | Densidade QHD / FHD |
| --- | --- | --- | --- |
| x1s | 720, 2428 / 163 | 326 / 772 | 560 / 480 |
| y2s | 720, 2500 / 150 | 300 / 700 | 600 / 450 |
| z3s | 720, 2500 / 150 | 300 / 700 | 560 / 420 |

Foram criados scripts Python de adaptação e retorno em WORK. O usuário informou ter feito suas builds e, posteriormente, voltado ao x1s.

Uma restauração de snapshot de build.prop apagou algumas propriedades de desempenho aprovadas depois daquele snapshot. Isso foi identificado durante a integração: o novo manifesto as estabelece explicitamente, evitando que a troca de target dependa desse snapshot antigo.

### 2.26. ART, classpath e compilação de aplicativos

O bootclasspath ainda citava QPerformance.jar vazio e UxPerformance.jar ausente. Somente essas entradas foram removidas.

Na investigação anterior ao build system, as imagens ART foram regeneradas pelo odrefresh da própria ROM em diretório isolado. Houve validação com ART de 32/64 bits e comprovação de uso das imagens. Após o flash posterior, o boot também confirmou o ART em uso.

A compilação `speed` de launcher, SystemUI, Ajustes e Chamadas gerou artefatos reais em `/data`, verificados nos mapeamentos dos processos. O usuário relatou melhora significativa.

Também foi desativada a compilação extra Oplus no primeiro uso de apps, preservando a otimização normal em background.

Esses caches de aplicativos não foram copiados para o system: são dependentes dos APKs e do ART instalados. Não foi acrescentada uma rotina automática de compilação pesada em cada boot.

### 2.27. Vulkan e interrupção de transições

O teste de Vulkan no HWUI dos aplicativos não resolveu o problema e foi revertido; os apps permaneceram com skiagl.

O teste posterior de Vulkan no RenderEngine do compositor, `skiavkthreaded`, foi aprovado pelo usuário e salvo. São componentes diferentes.

Para o problema de fechar um app e abrir outro rapidamente:

- `interrupt_remote_animation=false` apresentou melhora parcial e foi mantido.
- `persist.wm.debug.nav_blockable_animation=false` piorou o comportamento e foi removido, inclusive do armazenamento persistente.
- As escalas de duração das animações não foram encurtadas para mascarar as interrupções.

Tentativas de autorização do Hyper HAL e de relaxar o script térmico também foram revertidas. Não fazem parte do conjunto aprovado.

### 2.28. Indicador de carregamento da bateria

O Android carregava, mas o raio do ícone desaparecia depois da Dynamic Island.

Foi ajustado somente o fallback de ausência/erro do HAL em `OplusBatteryServiceFeature.getPsyBatteryNotify`, de -1 para 0. Códigos reais de falha do HAL foram preservados.

O usuário confirmou que o raio passou a permanecer corretamente.

### 2.29. Incidente da digital após reinício e correção do cadastro

Depois de reinícios durante as experiências de interface, o círculo sumiu e os cadastros deixaram de aparecer corretamente. O problema não foi tratado como simples efeito visual.

A investigação encontrou a relação entre HAL reconectado, usuário ativo não selecionado e enumeração com grupo inválido. Houve recuperação do estado possível com os dados ainda presentes; o usuário confirmou uma digital retornando e conseguiu cadastrar outra.

Fixes permanentes finais:

1. `HidlToAidlSensorAdapter.serviceDied`: invalida também o usuário em cache, para a próxima sessão selecionar o grupo correto.
2. `HidlToAidlCallbackConverter.onEnumerate`: grupo negativo gera erro de hardware indisponível; não é convertido numa lista vazia válida. A limpeza legítima continua existindo.
3. `onEnrollResult`: converte progresso positivo Samsung 0..100 à escala aceita pela UI ColorOS, com teto 35. Zero real continua sendo a única indicação de conclusão.

O usuário confirmou círculo, autenticação e progresso/vibração do cadastro funcionando. Pediu a inclusão desses fixes sem novos ajustes de otimização, e essa restrição foi mantida.

Os índices, backups de recuperação e templates pessoais não foram incorporados como payloads de imagem ou de build.

### 2.30. Limites de acesso às ferramentas

Houve um bloqueio transitório de ferramentas/execução, tratado na conversa como possível limite de conta. A checagem posterior não sustentou a afirmação de cota esgotada, e o acesso autorizado voltou a funcionar.

Isso não demonstrou falha do ADB do aparelho, nem gerou um patch de Android. Esta integração de build é feita no host e não exige um celular conectado.

## 3. O que foi construído para o QuantumROM

### 3.1. Arquivos e responsabilidades

| Arquivo/pasta | Papel atual |
| --- | --- |
| `scripts/QuantumRom.sh` | Mantém os helpers One UI e acrescenta as funções públicas ColorOS, preparação e despacho de bringup. Erros de extração passaram a ser propagados. |
| `sixteen.sh` | Valida target e argumentos, prepara a árvore, aplica o conjunto e chama BUILD_IMG para system, vendor e odm. |
| `QuantumROM/targets/x1s` | Script de bringup e cadastro do S20. |
| `QuantumROM/targets/y2s` | Script de bringup e cadastro do S20+. |
| `QuantumROM/targets/z3s` | Script de bringup e cadastro do S20 Ultra. |
| `QuantumROM/patches/coloros/apply.py` | Aplicação conferida de smali, deltas hexadecimais, textos, propriedades, payloads, remoções e metadados. |
| `QuantumROM/patches/coloros/prepare.py` | Prepara system e extrai vendor/odm das imagens do target. |
| `QuantumROM/patches/coloros/manifest.json` | Inventário de operações, hashes, offsets e metadados. |
| `QuantumROM/patches/coloros/smali` | Patches dos seis JARs, afetando nove DEX. |
| `QuantumROM/patches/coloros/text` | Patches de scripts, XMLs, política e configurações. |
| `QuantumROM/patches/coloros/payload` | Arquivos acrescentados, incluindo NFC assinado, dependências A2DP e MIDAS exclusivo de x1s. |
| `QuantumROM/patches/coloros/tools/ColorosDex.java` | Desmontagem/montagem com as bibliotecas do apktool já disponível. |
| `QuantumROM/patches/coloros/tests` | Testes de integridade, geometria, propriedades, remoção, metadados e preparação sem alterar as fontes. |
| `QuantumROM/patches/coloros/README.md` | Manual de uso e catálogo técnico. |

Os scripts não dependem dos backups de investigação em WORK para encontrar um JAR corrigido. Os patches e payloads necessários foram reunidos no pacote ColorOS. WORK passa a servir para preparação, cache, relatórios e backups da execução.

### 3.2. Como os patches são aplicados

- JARs: patches smali, montados com opcodes API 33 para evitar o DEX041 incompatível encontrado numa experiência anterior. DEX e entradas não afetados conservam seu conteúdo.
- Nativos: hashes de entrada/saída e bytes no offset esperado. Não se assume que encontrar um NOP em qualquer ponto do binário signifique patch aplicado.
- Textos: hash e patch sem fuzz, com validação do resultado.
- Bluetooth: inserção verificada do módulo A2DP, preservando as outras rotas do XML do target.
- SELinux: regra A2DP restrita e metadados explícitos, incluindo logd e JNI NFC.
- Bringup: nome, densidades, geometria no framework, propriedades e um único init de calibração do target.
- Gravação: as operações são preparadas antes do commit da etapa completa; os arquivos são substituídos atomicamente.
- Cache DEX: somente resultados com checksum conhecido são aceitos. Não deve permitir que um cache encubra uma entrada de versão desconhecida.

A quantidade de operações não é a quantidade de bugs: várias entradas removem pré-compilados ou correspondem a arquivos de um mesmo fix.

### 3.3. Origem definitiva de vendor e odm

Conforme a última orientação do usuário, o fluxo usa:

| Target | Origem |
| --- | --- |
| x1s | `QuantumROM/Devices/SM-G980F/extra/vendor.img` e `odm.img` |
| y2s | `QuantumROM/Devices/SM-G986B/extra/vendor.img` e `odm.img` |
| z3s | `QuantumROM/Devices/SM-G988B/extra/vendor.img` e `odm.img` |

As imagens não foram duplicadas dentro de targets. O campo `partition_source` no cadastro de cada dispositivo referencia essas pastas.

A preparação produz `WORK/coloros-build/<target>/firmware`, contendo `system`, `vendor`, `odm` e `config`. A build passa a usar essa árvore. O ODM é preservado como base do dispositivo e reempacotado; não foi inventado um novo patch de hardware para ele.

Os arquivos de system e das bases extraídas usam links físicos quando possível para poupar espaço. Os patches substituem os arquivos em vez de editá-los em seu inode compartilhado; os metadados recebem cópias independentes. Os testes cobrem a preservação das fontes nessa operação.

### 3.4. Interface e saídas

```bash
# Preparar e aplicar, sem gerar imagens:
bash sixteen.sh x1s false ColorOS AUT 0 erofs --patch-only

# Preparar, aplicar e tentar a build completa:
bash sixteen.sh x1s false ColorOS AUT 0 erofs
bash sixteen.sh y2s false ColorOS AUT 0 erofs
bash sixteen.sh z3s false ColorOS AUT 0 erofs
```

As saídas previstas são `OUT/<target>/system.img`, `vendor.img` e `odm.img`.

Os seis argumentos originais foram preservados. O primeiro aceita codename ou modelo Samsung. Tethering One UI, CSC e IMEI foram mantidos na interface, mas não comandam novos patches neste fluxo ColorOS.

Não há montagem automática de ZIP, flash ou instalação de recovery nesse fluxo.

## 4. Situação verificada no momento da interrupção

### 4.1. O que passou

| Verificação | Resultado |
| --- | --- |
| Sintaxe dos scripts Bash atuais | Passou. |
| Seis testes automatizados atuais | Passaram na conferência deste relatório. |
| Montagem dos nove DEX afetados | Foi exercitada e os checksums dos resultados foram registrados. |
| Aplicação dos patches sobre cópias dos originais | Passou após correções da integração. |
| Reaplicação na mesma árvore de teste | Zero mudanças adicionais. |
| Troca de calibração x1s → y2s → z3s → x1s | Passou. |
| Deltas de vendor y2s/z3s e reaplicação | Passaram, preservando arquivos específicos de câmera no teste. |
| `sixteen.sh --patch-only` com vendor/odm reais de Devices, x1s | Terminou com sucesso, mas a árvore produzida antecede o último estreitamento da limpeza ART. |
| Mesmo fluxo com fontes reais, y2s | Terminou com sucesso com a limpeza ART mais restrita. |
| Mesmo fluxo com fontes reais, z3s | Terminou com sucesso com a limpeza ART mais restrita. |
| Build completa de imagens pelo novo fluxo | Ainda não executada. |
| Flash/primeiro boot do resultado do novo fluxo | Ainda não executado. |

Os fixes individuais tiveram as confirmações físicas descritas na primeira parte. Isso não substitui testar o produto final gerado pelo novo pipeline.

### 4.2. Correções realizadas durante os testes da integração

- Um patch de configuração NFC falhava porque o original não terminava em quebra de linha. O formato do diff foi corrigido.
- A remoção de diretório de app tentava inicialmente ler o diretório como arquivo. A ordem do tratamento foi corrigida e ganhou teste.
- A primeira aplicação não incluía de imediato alguns metadados de diretórios novos, causando diferenças na segunda aplicação. A preparação dos metadados passou a considerar os pais que serão criados; a reaplicação passou a ser estável.
- A validação de entrada DEX foi posicionada antes do aproveitamento de cache, para não aceitar uma origem desconhecida por existir um resultado em cache.
- Erros dos extratores deixaram de ser mascarados pelo chmod/chown final do helper.
- O tamanho de imagem informado pelo helper passou a seguir o symlink da fonte. Os primeiros logs x1s mostram 89/86 bytes, que eram tamanhos dos links; a extração usou as imagens reais e terminou. Os logs posteriores mostram os tamanhos reais.
- A limpeza ART foi restringida: não se remove mais todo `system_ext/framework/oat`; removem-se os artefatos específicos do Wi-Fi modificado. Os artefatos de boot incompatíveis continuam sendo invalidados.

### 4.3. Pendência concreta na árvore x1s já preparada

A primeira execução real do x1s ocorreu antes da última alteração de limpeza ART e removeu também os pré-compilados de outros JARs em `system_ext/framework/oat`.

O código atual já não contém essa remoção ampla. Entretanto, a pasta preparada de x1s ainda representa aquela execução anterior: a conferência encontrou zero arquivos remanescentes nesse oat, enquanto y2s/z3s preservam 880.

**Antes de usar a árvore preparada x1s para a build final, ela deve ser refeita pelo fluxo atual.** A preparação recompõe a árvore a partir das fontes e do cache de partições; isso restaura os pré-compilados não relacionados. Não é necessário desfazer os fixes no aparelho para resolver essa pendência.

### 4.4. ART: mudança que exige teste de primeiro boot

Na investigação anterior, o ART foi regenerado com sucesso usando o compilador da própria ROM. A integração atual adota outro método de distribuição: invalida os artefatos antigos do system e deixa a regeneração para o fluxo odsign/odrefresh em `/data`, que já é chamado pelo init desta ROM.

Isso evita distribuir um boot image ligado ao framework ou à geometria de outro modelo e dispensa celular conectado durante a build. Porém, **o primeiro boot dessa nova distribuição ainda não foi testado**. A existência do fluxo no init e os testes anteriores do compilador não comprovam, por si só, que a nova imagem iniciará corretamente em todos os targets.

Este é um dos pontos que precisam ser validados antes de chamar o novo pipeline de homologado.

## 5. Respostas registradas em 14/10/2026 — histórico

### Todos os patches estão aplicando corretamente?

Os testes de aplicação realizados passaram: originais em cópias de trabalho, reaplicação, troca de target e preparação real com as imagens fornecidas. Não houve um patch rejeitado sem tratamento deixado como sucesso.

Isso é uma confirmação de aplicação no host, não de funcionamento integral após flash. A pasta x1s já produzida precisa ser regenerada para corresponder à revisão atual do manifesto.

### Já está buildável?

O fluxo está implementado para gerar system, vendor e odm, e os comandos estão disponíveis. **Ainda não foi executada uma build completa pelo novo sixteen.sh; portanto, não posso afirmar que ela já foi concluída com sucesso de ponta a ponta.**

O estado correto é: aplicação de patches testada; geração e boot das imagens ainda pendentes de validação.

### O que falta?

1. Refazer a preparação x1s com a revisão atual da limpeza ART.
2. Executar a build completa e conferir se o mkfs conclui para system, vendor e odm.
3. Verificar integridade das imagens, permissões/labels, symlinks e tamanhos em relação às partições de destino.
4. Validar primeiro boot e regeneração ART, começando pelo x1s disponível.
5. Revalidar na imagem resultante digital, brilho, resolução/toque, 120 Hz, áudio/Bluetooth, dados, hotspot, NFC e carregamento; os outros modelos precisam de seus próprios testes físicos.
6. Só depois considerar o pipeline homologado e produzir os ZIPs finais pelo mecanismo escolhido pelo usuário.

Continuam fora desta conclusão: reconhecimento facial completo, IMS/VoLTE/VoWiFi, bug do KernelSU e novos experimentos de otimização.

## 6. Evidências locais

- `WORK/quantum-coloros-test.log`: aplicação sobre originais, reaplicação e troca dos três targets.
- `WORK/quantum-coloros-test-run/dex-results.json`: resultados registrados da montagem dos DEX.
- `WORK/quantum-coloros-vendors-test.log`: aplicação e reaplicação dos vendors y2s/z3s.
- `WORK/quantum-coloros-build-x1s.log`: primeira preparação real x1s, anterior ao último ajuste de ART.
- `WORK/quantum-coloros-build-y2s.log`: preparação real y2s.
- `WORK/quantum-coloros-build-z3s.log`: preparação real z3s.
- `WORK/coloros-build/<target>/last-run.json`: arquivos modificados na execução correspondente.
- `WORK/coloros-*/README*`: relatórios das investigações anteriores, com limites e resultados de cada sessão.
- `QuantumROM/patches/coloros/README.md`: manual do fluxo atual.

Este documento foi criado para registrar o estado atual; não foi usado como justificativa para marcar como testado um empacotamento ou boot que ainda não aconteceu.

## 7. Atualização de 15/10/2026 — build x1s concluída no host, anterior ao patch OTA

Esta seção atualiza o estado histórico acima. Por solicitação do usuário, somente x1s teve as imagens construídas e verificadas nesta etapa; a fila y2s/z3s foi encerrada antes de iniciá-las.

### Estrutura e fluxo entregues

- Imagens em `out/target/<target>`; caches e árvore preparada em `out/cache/<target>`; logs datados e relatórios em `out/logs/<target>`.
- `sixteen.sh` prepara as bases específicas, aplica os patches, constrói system/vendor/odm e valida o resultado. `--patch-only` continua disponível.
- Geração de fs_config/file_contexts preserva registros existentes e acrescenta apenas os ausentes, sem executar milhares de subprocessos por imagem.
- Cada mkfs grava arquivo temporário; uma falha não publica imagem incompleta nem substitui a imagem anterior.
- A verificação EROFS lê todos os arquivos codificados, confere labels críticos extraídos da imagem, calcula SHA256 e verifica o orçamento do grupo dinâmico.

A primeira execução foi interrompida antes de ODM porque o script foi editado enquanto Bash ainda o executava. System e vendor já haviam concluído. A execução foi retomada para construir ODM e verificar as três imagens; terminou com código 0. Os dois logs foram preservados, sem apresentar a execução interrompida como sucesso.

### Resultado x1s

| Imagem | Bytes |
| --- | ---: |
| system.img | 5901848576 |
| vendor.img | 1201156096 |
| odm.img | 442368 |

As imagens estão em `out/target/x1s`, com `SHA256SUMS` e `build-info.json`. Todas passaram por `fsck.erofs --extract`. Foram conferidos os labels de logd, JNI/APK NFC, Power HAL e bibliotecas A2DP. O grupo fornecido tem limite de 9432989696 bytes; restam 2329542656 bytes antes de considerar outras partições. Mantendo o product observado no aparelho (753106944 bytes), ainda cabem no grupo. Isso não substitui verificar o instalador e os tamanhos lógicos individuais ao criar um novo ZIP.

Nove testes de host passaram. A validação sem gravação reaplicou as etapas framework (6 operações), native (6), config (25), debloat (63), vendor (35), bringup e ART (187), sem encontrar alteração pendente na árvore preparada. Evidência: `out/logs/x1s/fix-validation.json`. São todos os fixes registrados no manifesto, incluindo os últimos ajustes de digital; não foi acrescentado um novo experimento de otimização.

O system anterior em OUT tinha 6028423168 bytes; o novo tem 5901848576. A limpeza ART encontra 155 arquivos presentes na base, totalizando 360139252 bytes sem compressão. A diferença comprimida é de 126574592 bytes. Nenhum debloat adicional foi introduzido nesta etapa.

### Product e limite da validação

A inspeção ADB confirmou product embutido no system e a partição lógica product existente sem montagem separada, inclusive nos namespaces do init e system_server. Não é necessário obter product.new.dat.br de outra ROM para preencher o ZIP. A investigação e as exigências para alterar o layout estão em `QuantumROM/patches/coloros/PRODUCT_LAYOUT.md`.

Não foi construído nem homologado um novo ZIP flasheável. Para testar estas três imagens mantendo o layout atual, não se deve excluir ou recriar product inadvertidamente. Um ZIP que usa remove_all_groups precisa de layout, metadata, updater e fstab coerentes.

Não houve flash ou reinício do aparelho nesta etapa. O primeiro boot com regeneração ART ainda não foi validado; portanto, as imagens estão construídas e verificadas no host, mas não há garantia de boot ou homologação após flash. Permanecem pendentes o primeiro boot e a conferência funcional dos fixes na imagem nova. y2s/z3s também precisam de build e teste próprios.

### Logs detalhados de patches

Adicionado o padrão `Processing … patch` para cada grupo, arquivo, bringup, metadados e commit. Cada operação descreve a ação e seus valores relevantes (propriedades, offsets binários, origem do asset e patches DEX). Os estados distinguem validação sem mudanças, mudanças preparadas, target ignorado, erro e gravação efetiva após validar toda a etapa. O tratamento de falhas foi preservado. A suíte atual passou com 10 testes, incluindo logs de reaplicação e falha sem modificar o arquivo original. Esta alteração afeta somente o log do host; não requer reconstruir as imagens x1s já verificadas.

Uma conferência adicional dos 752 arquivos do diretório framework da imagem x1s confirmou conteúdo idêntico à árvore corrigida; relatório em `out/logs/x1s/framework-image-comparison.json`. Essa extração pontual ocorreu antes do pedido do usuário para preferir montagem em futuras inspeções.

### Interface simplificada e renomeação para build.sh

A interface atual substitui os comandos históricos de seis argumentos deste relatório: `bash build.sh x1s erofs` (ou y2s/z3s e ext4/f2fs). A entrada é sempre FW/ColorOS. `--patch-only` continua opcional como terceiro argumento. Tethering, CSC, IMEI e seleção da pasta de firmware foram retirados do ponto de entrada ColorOS. As imagens existentes não precisam ser reconstruídas por essa mudança de interface.

### Remoção de OTA integrada

O script `patch-disable-ota/extras.sh` serviu como referência de alvos; não foi executado no host nem no aparelho. A nova etapa `ota` do manifesto é chamada automaticamente pelo fluxo completo de `build.sh` para x1s/y2s/z3s. Remove OTA, SystemAppUpdateService, cotad, bspFwUpdate e seis arquivos de configuração/init associados, além de aplicar dois patches exatos nos arquivos de init para retirar as chamadas aos daemons e a definição de bspFwUpdate. Mantém otapreopt, update_engine_client e serviços Google. Não limpa dados ou caches no aparelho. O helper manual é PATCH_COLOROS_OTA.

Os testes de host agora totalizam 12, incluindo remoção/reaplicação para os três targets e preservação de componentes essenciais. A entrada foi atualizada de sixteen.sh para build.sh na documentação operacional e nos testes, acompanhando a renomeação feita pelo usuário. As imagens já existentes ainda precisam ser reconstruídas para incluir a remoção OTA.

## 8. Funcionamento consolidado do build atual

### Entrada, targets e partições

O comando `bash build.sh x1s erofs` usa `FW/ColorOS/system` como base do system. Se necessário, o fluxo chama os extratores existentes para preparar essa entrada. As partições vendor/odm são escolhidas pelo campo `partition_source` do target:

| Target | Modelos aceitos | Vendor/ODM de origem |
| --- | --- | --- |
| x1s | SM-G980F, SM-G981B | `QuantumROM/Devices/SM-G980F/extra/{vendor,odm}.img` |
| y2s | SM-G985F, SM-G986B | `QuantumROM/Devices/SM-G986B/extra/{vendor,odm}.img` |
| z3s | SM-G988B | `QuantumROM/Devices/SM-G988B/extra/{vendor,odm}.img` |

O bringup aplica identidade Galaxy S20/S20+/S20 Ultra, densidades e geometria da digital conforme `QuantumROM/targets/<target>/device.json`. Os targets não compartilham a calibração da digital. Os modelos MIDAS restaurados pertencem somente ao x1s; as bases dos outros modelos preservam seus próprios arquivos de câmera. ODM é reempacotado sem patches novos de hardware.

### Reutilização do cache e reaplicação

A extração de vendor/odm é reutilizada enquanto caminho, tamanho e data de modificação das imagens de entrada coincidirem com a assinatura do cache. Essa assinatura não é um hash integral da imagem. Os binários envolvidos nos patches continuam sujeitos às verificações de conteúdo previstas no manifesto.

A preparação recompõe a árvore do target a cada execução, usando o system extraído e as partições em cache. Não é uma aplicação incremental cega sobre a última imagem. Os patches validam novamente as entradas, reconhecem resultados já corrigidos e aplicam apenas o necessário; o cache de DEX só é aproveitado quando os checksums conferem. As gravações por substituição atômica preservam os arquivos-base que foram compartilhados por links físicos.

Uma build completa sempre executa o empacotamento das três imagens. `--patch-only` encerra antes disso, deixando a árvore em `out/cache/<target>/firmware`. Essa opção não atualiza as imagens finais existentes.

### Etapas e logs

A sequência atual é framework → native → config → debloat → ota → vendor → bringup → art → metadados → commit. Todas as etapas do conjunto são preparadas e validadas antes do commit. As quantidades atuais de operações no manifesto são:

| Etapa | Operações |
| --- | ---: |
| framework | 6 |
| native | 6 |
| config | 25 |
| debloat | 63 |
| ota | 12 |
| vendor | 35 |
| art | 187 |

O bringup é implementado pelo código de calibração, por isso não aparece como uma lista de operações no manifesto.

O terminal e o log datado exibem `Processing … patch` para grupos e arquivos. As mensagens descrevem propriedades, offsets, origem de assets e patches DEX, distinguindo preparação, entrada já corrigida, target ignorado, falha e gravação efetiva. É possível acompanhar com:

```bash
tail -f out/logs/x1s/build.log
```

Os helpers manuais incluem `PATCH_COLOROS_OTA`; o caminho normal continua sendo `build.sh`, que executa a transação completa. Não é preciso chamar os patches separadamente. Não se deve editar o script enquanto uma build o está executando.

### OTA: alcance e verificação

A etapa remove dez alvos do script de referência: os diretórios dos apps OTA e SystemAppUpdateService, os binários cotad e bspFwUpdate, cotad.rc, três XMLs de extensão OTA/COTA, a permissão de com.oplus.cota e a configuração forceota_dexopt. Dois patches de texto adicionais retiram as chamadas de inicialização nos arquivos init.rc e init.oplus.rootdir.rc e a definição do serviço bspFwUpdate.

A remoção usa o mecanismo existente do manifesto: arquivos ausentes são inofensivos e arquivos presentes são retirados da árvore preparada. Não deixa cópias .bak dentro da imagem. Os backups do mecanismo de patches ficam no cache de trabalho do computador. Não executa comandos de recovery, não remonta partições do aparelho e não apaga caches de OTA em /data.

A suíte verificou remoção e reaplicação para os três targets, preservando componentes ART e de atualização Google. A validação com entradas reais também confirmou os hashes finais dos dois arquivos de init e a ausência das chamadas removidas; a segunda execução não produziu alterações. Evidência: `out/logs/x1s/ota-patch-validation.log`.

### Evidências atuais e próximos testes

- `out/logs/x1s/host-tests.log`: 12 testes passaram.
- `out/logs/x1s/ota-patch-validation.log`: aplicação/reaplicação dos arquivos reais de OTA em árvore temporária; bases preservadas.
- `out/logs/x1s/patch-log-validation.log`: validação dos patches com logs detalhados, anterior à inclusão da etapa OTA.
- `out/logs/x1s/fix-validation.json`: validação do conjunto anterior ao OTA, sem alterações inesperadas.
- `out/logs/x1s/framework-image-comparison.json`: 752 arquivos do framework da imagem coincidem com a árvore corrigida.
- `out/target/x1s/build-info.json` e `SHA256SUMS`: relatório e hashes das imagens verificadas antes da integração OTA.
- `out/logs/product-inspection.txt` e `product-boot-fstab-{x1s,y2s,z3s}.txt`: inspeção de product e dos fstabs fornecidos.

O próximo passo é reconstruir x1s com `bash build.sh x1s erofs` para incorporar OTA, conferir a nova verificação automática e testar o primeiro boot. As mudanças de logs e argumentos não alteram o conteúdo da ROM por si sós; a etapa OTA altera e exige nova imagem. Depois do boot, conferir os fixes de digital, tela/toque, 120 Hz, brilho, áudio/Bluetooth, rádio, hotspot, NFC e carregamento. O facial completo, IMS e KernelSU continuam sem solução nesta integração.

Esta atualização documental não executou nova build nem flash. Não foram realizadas novas extrações de imagens; a preferência do usuário por montagem em futuras inspeções permanece registrada. A validação de conteúdo automática completa continua específica de EROFS; ext4/f2fs não receberam a mesma homologação. O futuro ZIP deverá tratar product e metadata de forma coerente, conforme `QuantumROM/patches/coloros/PRODUCT_LAYOUT.md`.

### Prefixo chinês no nome de mercado

O bringup preserva o prefixo 一加 em `ro.vendor.oplus.market.name`: x1s = `一加 Galaxy S20`, y2s = `一加 Galaxy S20+`, z3s = `一加 Galaxy S20 Ultra`. As propriedades de modelo e o nome Bluetooth continuam usando apenas Galaxy S20/S20+/S20 Ultra. A mudança entra no próximo build; não houve reconstrução de imagem ou alteração no aparelho nesta etapa.

## 9. Atualização — gerador de ZIP flasheável

Foi integrado um gerador de ZIP em `QuantumROM/patches/coloros/build-zip.py`, acionado por `bash build.sh <target> <fs> -z` (ou `--zip`) depois da verificação das imagens. `--patch-only` continua encerrando antes das imagens e não gera ZIP.

Funcionamento:

1. Copia o template `QuantumROM/targets/<target>/zip` — mantido à mão com `META-INF` (update-binary, updater-script, metadata/otacert), o payload de product já definido, `boot.img`/`dtbo.img` do kernel e `unsparse_super_empty.img` — para `out/target/<target>/.zip`, um ambiente de trabalho oculto no mesmo volume das imagens (não usa o `/tmp` do sistema).
2. Copia `system.img`, `vendor.img` e `odm.img` recém-construídos para dentro dele.
3. Reescreve `dynamic_partitions_op_list` no formato do `GENERATE_OP_LIST` do UN1CA: `remove_all_groups`, `add_group <grupo> <tamanho>` e `add`/`resize` para system, vendor, product e odm. Grupo/tamanho vêm de `STOCK_FLASHABLE_ZIP_GROUP_NAME`/`STOCK_FLASHABLE_ZIP_GROUP_SIZE`; o tamanho de product é o já definido no template. A soma é conferida contra o grupo.
4. Converte system/vendor/odm em `.new.dat` (`bin/external_img2sdat/img2sdat`) e comprime para `.new.dat.br` com Brotli qualidade 6, gerando os `.transfer.list`/`.patch.dat` correspondentes.
5. Empacota com `7z -mx=0` (**sem compressão**) e grava `ColorOS-16.0.1-<target>-@miguelbarretoo.zip` em `out/target/<target>`.

O template de cada target precisa existir; no momento apenas `x1s` tem a pasta `zip`. y2s/z3s precisam de seus templates para gerar o ZIP. Os `.img` de boot/dtbo e o `unsparse_super_empty.img` vêm do template; a opção respondeu "não" a extrair do `boot-dtbo.<target>.zip`.

Isso gera o artefato no host; **não houve flash nem boot de validação**. O boot de um ZIP que usa `remove_all_groups` recria system/vendor/product/odm com os tamanhos das imagens e depende da coerência com o `unsparse_super_empty.img` e o fstab do boot, como descrito em `PRODUCT_LAYOUT.md`. O product embutido no system continua sendo o conteúdo efetivo; o payload de product do template é mantido para preservar a partição lógica exigida pelo fstab.

### Correção da regressão em Sobre o dispositivo

O usuário confirmou que a entrada/tela ColorOS desapareceu após aplicar a remoção OTA. A inspeção encontrou referências de Settings.apk ao pacote `com.oplus.ota` e à ação `com.oplus.ota.MAIN`. O manifesto original de OTA.apk declara `com.oplus.otaui.activity.EntryActivity`, que atende essa ação. Isso identifica a remoção do pacote como causa provável da perda da entrada.

Foi retirada somente a operação que excluía `system/system/system_ext/app/OTA`. O APK original e seus arquivos voltam a ser incluídos quando a próxima preparação recompõe a árvore a partir de FW/ColorOS. As nove outras remoções e os dois patches de init foram mantidos. O teste de remoção agora verifica explicitamente a preservação de OTA.apk nos três targets, além de ART e componentes Google. Não foi necessário editar ou assinar APK.

Essa solução preserva o componente da interface; não representa um bloqueio completo de toda atividade OTA, pois o APK ainda contém serviços e código de consulta. Se for necessário impedir também essas consultas preservando a interface, isso exige um patch específico posterior. Não houve alteração no aparelho nem nova imagem nesta etapa; o retorno visual da entrada precisa ser confirmado após rebuild e flash.

### Digital z3s — análise do log s20u-fingerprint.txt

O usuário relatou desaparecimento do círculo durante cadastro no S20 Ultra. A captura mostra o ícone sendo desenhado e, em seguida, o trustlet retornando 48, o HAL enviando error(8,1001), o cadastro terminando com falha e o Android ocultando o overlay. Não é apenas uma falha de geometria. A mensagem DeviceEnableInt/-1 não basta para atribuir a causa a IRQ; a chamada de desabilitação também aparece no encerramento.

Não foi encontrado suporte suficiente nos logs para um patch causal seguro no system. Nenhum fix experimental foi injetado, nenhuma imagem foi reconstruída e o S20 base não foi usado como substituto de teste. A falha permanece aberta. Diagnóstico detalhado e referências de linhas: `QuantumROM/patches/coloros/diagnostics/z3s-fingerprint.md`. Os patches existentes de reconexão, proteção de enumeração e progresso permanecem integrados, mas não foram apresentados como solução deste erro do ambiente seguro.

### KernelSU Next preinstalado — análise da versão antiga

A base e as árvores preparadas x1s/z3s contêm o mesmo APK com manifesto v3.4.0 / versionCode 33294 / pacote com.rifsxd.ksunext. O helper legado ADD_KERNELSU_NEXT fixa v3.2.0, porém não é chamado pelo fluxo atual. A ColorOS instala os del-app pelo OplusRemovableAppManager, com condições de primeiro boot/upgrade e verificações de versão e assinatura; trocar a cópia na imagem não garante atualização da cópia já instalada em /data. Alterações apenas na árvore de cache são perdidas na próxima preparação.

Não havia aparelho disponível no ADB para confirmar o caminho da versão antiga instalada. Não foi aplicado patch, trocado APK nem construído system nesta análise. Diagnóstico e comandos de conferência/atualização pontual em `QuantumROM/patches/coloros/diagnostics/ksu-preload.md`. A causa no aparelho permanece uma hipótese até ler seu estado instalado.

### Play Store em del-app — análise

Foi encontrada uma Play Store já presente em `my_product/priv-app/Phonesky/Phonesky.apk`, além do APK novo acrescentado pelo usuário em my_stock/del-app. Ambos declaram o pacote com.android.vending. A cópia em del-app está sujeita às regras de preload da ColorOS e não garante substituir/reinstalar a existente. Não houve troca dos APKs nem patch neste diagnóstico; o estado instalado/habilitado no aparelho não foi confirmado. Evidências adicionais em `QuantumROM/patches/coloros/diagnostics/ksu-preload.md`.

### Integração do r8s / Galaxy S20 FE Exynos (SM-G780F)

O target fornecido pelo usuário ainda continha bringup, identidade, calibração e instalador copiados de y2s. Foram corrigidos device.json, BRINGUP_R8S e os pontos de entrada de build, preparação, aplicação, verificação de imagens e geração de ZIP. O SM-G781B não foi incluído como r8s: é uma variante Snapdragon fora desta base Exynos.

Vendor e ODM vêm de `QuantumROM/Devices/SM-G780F/extra`. A tree oficial LineageOS lineage-24.0, revisão `1dcaf8f41ff1d82f04bae1d932aff4c44ba4c273`, fornece sensor `540|2144|100`, tipo udfps_optical e solicitação de eventos de toque. O BoardConfig indica densidade 420. O círculo foi definido com diâmetro 200 e distância inferior 256, em 1080×2400. A referência está em https://github.com/LineageOS/android_device_samsung_r8s/blob/1dcaf8f41ff1d82f04bae1d932aff4c44ba4c273/vendor.prop.

O framework agora calibra os quatro targets com sequências DEX verificadas e distingue sensor ultrassônico (tipo AIDL 2) de óptico (tipo AIDL 3). O r8s usa `persist.vendor.fingerprint.sensor_type=optical` e feature óptica; o init público preserva os valores após carregar propriedades persistidas. Os inits dos demais modelos são retirados da árvore do target, sem alterar cadastros. As configurações e o tipo ultrassônico dos outros modelos foram preservados.

O nome é Galaxy S20 FE, com nome de mercado 一加 Galaxy S20 FE. Densidade 420 em system/my_product/vendor. Os valores de resolução baixa e alta ficam ambos 1080×2400; os recursos de troca física de resolução/QHD são retirados, e o arquivo de compatibilidade usa largura 1080 e escala 1:1. A calibração continua idempotente, inclusive quando o framework passa por normalização para aplicar os patches comuns.

As bibliotecas de display e áudio de r8s não têm os mesmos hashes dos outros modelos. Foram adicionadas variantes por target no manifesto, sempre com hashes e bytes/offsets próprios. Em libexynosdisplay.so foi adaptada a propriedade privada do compositor; a função convertIfDDI alterada nos outros modelos não existe nessa biblioteca e não foi inventada ou copiada. Em audio.primary.exynos990.so, o patch CAMCORDER foi localizado em select_preprocess_solutions, offset 0x15a8e, preservando os outros caminhos. O Power HAL aceitou o patch comum. Modelos MIDAS de x1s não são copiados para r8s.

Foram adicionados os parâmetros do grupo dinâmico ao config SM-G780F: super 9437184000 bytes / grupo 9432989696, conforme a base oficial universal9830-common. O nome group_basic acompanha o template existente. O updater-script e os metadados identificam agora r8s/SM-G780F.

Por instrução explícita posterior do usuário, boot.img e dtbo.img NÃO foram substituídos. O gerador aponta para `QuantumROM/targets/r8s/zip`, como nos demais targets. Os arquivos presentes ainda são os herdados do template y2s; o usuário vai fornecer os corretos antes do flash. Não se deve interpretar a conclusão da integração como validação desses arquivos.

Validação executada: extração das bases r8s, aplicação completa, execução real de `bash build.sh r8s erofs --patch-only` e reaplicação sem mudanças. No framework real, todos os arquivos do JAR permanecem idênticos à base corrigida após normalizar de volta somente geometria/tipo do sensor. Relatórios em `out/logs/r8s/validation.json`, `patches-first.json`, `patch-only-console.log`, `idempotence.log` e `host-tests.log`.

Os testes cobrem também troca de geometria/tipo entre targets, rejeição de instrução inesperada, tela fixa FHD/feature óptica, calibração idempotente, seleção da variante binária com hash correto e rejeição de hash de outro modelo. Não foi executada uma build completa de imagens r8s, gerado ZIP novo ou feito flash. Primeiro boot, iluminação HBM do sensor óptico, cadastro e desbloqueio dependem de validação física no r8s.

Comandos atuais: `bash build.sh r8s erofs` para imagens; `bash build.sh r8s erofs -z` para incluir o ZIP após o usuário ajustar boot/dtbo; `bash build.sh r8s erofs --patch-only` para somente preparar e aplicar.

Resultado final da suíte nesta integração r8s: **16 testes passaram**. Os arquivos boot/dtbo do template permaneceram com seus checksums anteriores.

## 9. Limpeza da source e preservação da build em andamento — 15/10/2026

O usuário solicitou retirar o legado QuantumROM/One UI e preservar todo o out minúsculo e seus caches, pois havia uma build r8s em execução. A build foi observada primeiro na verificação EROFS e depois na geração do ZIP. Não foi interrompida, reiniciada ou usada como teste da limpeza.

### Código e arquivos mantidos

O ponto de entrada permanece build.sh. scripts/QuantumRom.sh mantém seu caminho por compatibilidade, mas foi reduzido a 490 linhas e dez funções: DETECT_FILESYSTEM, EXTRACT_FIRMWARE, EXTRACT_SUPER_IMG, EXTRACT_FIRMWARE_IMG, GEN_FS_CONFIG, GEN_FILE_CONTEXTS, BUILD_IMG, COLOROS_PATCH_STAGE, BRINGUP_COLOROS e PREPARE_COLOROS_TARGET. Foram retiradas 64 funções legadas, incluindo patches One UI e wrappers que não são chamados pelo build ColorOS. A filtragem antiga PREPARE_PARTITIONS foi retirada da extração em modo all; ela dependia da configuração antiga e não é necessária para extrair uma imagem selecionada no fluxo atual.

Os entrypoints shell foram publicados por substituição atômica de arquivo, preservando descritores já abertos da build em execução. O código dos builders e seus parâmetros foi preservado, inclusive o workaround EROFS de xattrs. Variáveis de configuração One UI sem uso foram retiradas de build.sh. O helper de extração F2FS, as dependências Python do extrator ext4, img2sdat e as ferramentas dos três formatos foram mantidos.

QuantumROM conserva somente Devices dos quatro targets, patches/coloros e targets. Cada Devices/<modelo> agora tem config com os dois parâmetros usados de grupo dinâmico e extra/{vendor,odm}.img. Os templates completos de ZIP dos quatro targets foram preservados, incluindo product.*, instaladores, metadados, boot/dtbo e super metadata. O conteúdo dos patches e a calibração dos aparelhos não foram modificados pela limpeza.

### Legado retirado e histórico preservado

Foram retirados Mods, MTK_SPECIAL, VNDKs, extra_blobs, logo, usefull_things, os antigos flashable_zip/images_zip, o patch FOD antigo fora do manifesto e os modelos sem target ColorOS (SM-G781B e SM-N986B). Também saíram os scripts antigos de debloat, câmera One UI, instalação automática de pacotes, smali_patch e empacotamento, o diretório system da raiz, o updater-script da raiz, omc-decoder.jar e lpmake. Lpunpack permanece para a extração de super.

O OUT maiúsculo foi apagado, conforme autorizado; não era o mesmo caminho que out. FW foi preservado como entrada local de firmware. WORK e os logs de investigação da raiz foram movidos para out/archive/port-history. Kernels/recoveries extras não chamados pelo build ficaram em out/archive/device-kernels, para não perder os arquivos que o usuário ainda pode precisar ao ajustar boot/dtbo.

Alguns diretórios legados pertenciam a nobody e não puderam ser apagados fisicamente; sudo -n informou que exigia senha. Esses restos foram retirados da árvore da source e guardados em out/archive/legacy-quantum. Não foram incluídos no ZIP da source. Não foi solicitada senha nem alterada a propriedade dos dados do usuário.

README.md da raiz foi substituído por instruções ColorOS, com entradas necessárias, targets, dependências, organização, comandos e limitações. A licença original e os créditos foram preservados em LICENSE, CREDITS.md e avisos das ferramentas. O README original foi guardado no histórico. As referências históricas a WORK/Stock neste relatório descrevem locais anteriores à limpeza; o histórico WORK está agora em out/archive/port-history/WORK.

### Exportação da source e validação

Novo comando: `bash scripts/source_zip.sh`. Exporta build.sh, scripts, bin, QuantumROM, os READMEs/relatório, licença e créditos. Inclui os blobs de entrada vendor/odm e templates necessários dos quatro targets, mas não inclui FW nem qualquer conteúdo de out. Isso exclui caches, logs pessoais, resultados de build e diretórios arquivados. Ao restaurar em outra pasta, a base FW/ColorOS e seus metadados precisam ser fornecidos separadamente.

O exportador usa ZIP64 sem compressão adicional, verifica o ZIP com 7z t e publica o resultado em out/source, junto de SHA256. A publicação só ocorre após a verificação do temporário. O tamanho será de vários gigabytes por incluir firmware de entrada e product dos templates, já comprimidos.

Os 17 testes de host passaram após a limpeza. O novo teste de exportação confirma presença de código/configuração/ferramentas, exclusão de FW/out/__pycache__, integridade CRC e checksum. Também foi construído um EROFS pequeno real com o helper reduzido, verificado com fsck.erofs, extraído e comparado ao conteúdo original. O primeiro ensaio usou uma fixture sem registros de raiz em fs_config; a fixture foi corrigida e o teste completo passou. Não foi necessário alterar a lógica do builder por esse ensaio.

Evidências: out/logs/source-cleanup/functions.json, removed-and-archived.json, host-tests.log, image-smoke.log e source-zip.log. Os testes não substituem validar boot/radio/biometria nas imagens reais, e não houve flash nesta limpeza.

A exportação completa de aproximadamente 7 GB foi iniciada e interrompida pelo assistente para evitar disputa de I/O com a build r8s do usuário. Somente o processo 7z dessa exportação foi terminado; o temporário foi removido pelo trap. Nenhum ZIP completo da source foi publicado nesta etapa. O exportador e seu teste de integridade em fixture estão prontos para uso após a build.


## Revisão de entrada EXT4 e preservação da câmera — 19/10/2026

- Confirmado o fluxo de extração EXT4 e reconstrução EROFS, independente do formato da entrada. Corrigida a tentativa do extrator de aplicar UID/GID Android aos arquivos do host: esses valores continuam preservados no fs_config, sem exigir root para chown.
- Removido `system/my_product/app/OplusCamera` do debloat. A próxima preparação usa o app presente na base original; não é feito download nem restauração se ele já tiver sido apagado da própria entrada em FW/ColorOS.
- Adicionado teste real com uma imagem EXT4 pequena, reconstrução EROFS e extração de conferência, verificando conteúdo, symlink, metadados UID/GID/SELinux e preservação da imagem original. Isso não equivale a uma build completa ou teste de boot da ROM.


## Atualização dos patches para a entrada ColorOS mais recente — 19/10/2026

A entrada `PJX110_11.A.01_001_202607141743`, Android 16 / segurança 2026-07-01 / incremental MysticGSI 1784517970393, mudou todos os nove DEX usados pelos patches. O bloqueio de checksum impediu aplicar o código antigo sem revisão.

Foram rebased os nove patches smali e recompilados os seis JARs, adaptados os pontos do SurfaceFlinger e dos imports QTI de 32/64 bits pelos símbolos/código reais, atualizados os patches de texto e os hashes exatos de entrada/saída. Foi ajustada a validação do índice do campo UDFPS e retirada a declaração de sensor traseiro presente nessa entrada. Os scripts antigos de brilho e polling térmico não existem nesta ROM, portanto suas operações foram retiradas do manifesto. Não houve novos experimentos de otimização. OplusCamera permanece fora do debloat e OTA.apk continua preservado.

O fluxo real `bash build.sh x1s erofs --patch-only` passou, alterando 335 arquivos na árvore preparada. A reaplicação fez zero alterações. Vinte testes de host e a checagem de sintaxe passaram. Foram conferidos hashes e conteúdo dos JARs/binários/configurações, XMLs, calibração x1s, label logd e preservação dos arquivos críticos de entrada. A conversão da geometria no DEX real foi validada para os quatro targets e de volta ao x1s.

Detalhes em [revisão da base](QuantumROM/patches/coloros/diagnostics/base-refresh-2026-10-19.md); evidências em `out/logs/base-refresh/verification.json`, `host-tests.log`, `patch-only-console.log`, `idempotence.log` e relatórios de símbolos/offsets. Manifesto e patches anteriores foram guardados em `out/logs/base-refresh/`. O manifesto distribuído passa a corresponder à nova entrada revisada; outra versão exige nova revisão.

Nenhuma imagem foi reconstruída ou flasheada nesta revisão. Falta validar boot e os recursos físicos no aparelho. O fluxo completo foi executado somente para x1s.


## Assistente inicial e idioma — 19/10/2026

Restaurado `OplusBootReg.apk` (`com.coloros.bootreg`) diretamente do `my_stock.img` original fornecido em `mysticgsi/tmp/coloros/images`. O MysticGSI remove esse pacote durante a conversão; o debloat ColorOS deste projeto não o removia. A etapa config agora instala o APK intacto, verificado por SHA256, em `system/my_stock/priv-app/OplusBootReg`, com metadados UID/GID/modo/SELinux da referência. As permissões e default grants já estavam presentes na base. Não foram importados caches compilados nem alteradas flags de provisionamento/dados do usuário.

Aplicado à árvore preparada x1s, com hashes iguais ao arquivo original. Reaplicação completa: zero alterações. Vinte e um testes passaram. O patch vale para todos os targets nas próximas preparações. Não houve rebuild/flash nem teste físico do assistente nesta etapa.

O celular foi definido como português do Brasil por ADB (`persist.sys.locale=pt-BR`, configuração ativa `pt-rBR`). Durante a operação foram capturados crashes recorrentes de system_server em `WifiChannelUtilization.refreshChannelStatsAndChannelUtilization`, por array nulo no scan Wi-Fi. O Wi-Fi foi desligado temporariamente; sua correção ficou para a investigação dos soft reboots solicitada pelo usuário. O idioma padrão da imagem não foi modificado.

Detalhes em [assistente inicial](QuantumROM/patches/coloros/diagnostics/setup-wizard.md); testes e logs em `out/logs/setup-language/`.


## 23. Correções da base nova após o flash — 19/10/2026

Investigação ao vivo no x1s e integração no manifesto, sem novos experimentos de otimização:

- O AudioPolicyManager preferia a política Qualcomm de my_product em PCM24 ao vendor Samsung em PCM16. A etapa vendor agora gera a política selecionada a partir do próprio vendor do target, após A2DP, validando e convertendo includes para /vendor/etc. Preserva as diferenças de cada modelo. A distorção desapareceu no teste do usuário; volume ainda aguarda confirmação completa.
- Overlay estático para evitar acesso a radioStats nulo no framework Wi-Fi desta base, usando o caminho de override já existente e valores desconhecidos (-1). Scans passaram sem reiniciar system_server. Não modifica o APEX.
- O teste de abrir o painel revelou outro problema: ANR de SystemUI, bloqueado em qtiInitAppType/libgui ao consultar vendor.perfservice. Parado o serviço Qualcomm, o usuário conseguiu abrir o menu. O patch de init acrescenta disabled ao serviço, sem afetar serviços Samsung nem outras regras do arquivo. Conexão/navegação aguardam teste.
- Crash de Ajustes por processorModel nulo: adicionada a propriedade real ro.product.cpuinfo=Exynos 990. Reteste físico do cadastro da digital pendente; não se alteraram templates.
- Restaurado OplusCamera.apk original de my_product.img, com assinatura preservada, hash conferido e metadados de imagem. A observação da seção anterior sobre não restaurar câmera já removida da entrada foi superada por esta recuperação explícita do donor original. O APK ficou na árvore preparada, sem instalação ao vivo.
- OplusBootReg restaurado anteriormente continua incluído. A sessão sem assistente tinha os indicadores de provisionamento zerados; foram concluídos somente no aparelho para permitir testar HOME/gestos, sem adicionar bypass de setup à build.
- Relógio: o crash capturado foi DeadSystemException durante a queda anterior do sistema. Ainda não foi comprovado um defeito independente no seletor de toque.
- O teclado Sogou já estava instalado no aparelho, porém nenhum IME estava selecionado. Foi ativado por ime enable/ime set; não foi baixado nem substituído APK de teclado.

Aplicação x1s: seis arquivos alterados (incluindo metadados), depois um arquivo de init; primeira reaplicação sem mudanças. Vinte e dois testes de host passaram. Fontes do RRO em QuantumROM/patches/coloros/overlays/ExynosWifiCompat, capturas e relatórios em out/logs/setup-language. As alterações de áudio e overlays ativas por ADB estão em montagens RAM e desaparecem no reboot completo; a imagem flasheada ainda é a anterior. Sem imagem ou ZIP novo gerado nesta etapa.

Detalhamento e estado dos testes: [diagnóstico da atualização](QuantumROM/patches/coloros/diagnostics/base-refresh-2026-10-19.md).


Validação adicional: após selecionar o teclado, ADB mostrou autenticação WPA2 concluída, endereço IPv4 recebido e respostas do gateway pelo Wi-Fi (2/2 pings). system_server continuou com PID 8977 e vendor.perfservice permaneceu parado. O teste ICMP externo não teve resposta e a rede Wi-Fi ainda não estava marcada VALIDATED; conexão com o roteador não é comprovação de navegação. A reaplicação final do manifesto resultou em zero alterações e os 22 testes de host passaram novamente. Retestes de volume, digital e HOME foram solicitados.


### Confirmação do usuário após os testes ao vivo

Em 19/10/2026, o usuário confirmou que o teclado apareceu e a conexão Wi-Fi funcionou sem travar. Em resposta ao teste conjunto de cadastro da digital, retorno à tela inicial e áudio com volume até zero, confirmou: “foi, digital, wifi, tudo funcionando!”. Os testes solicitados ficam registrados como aprovados pelo usuário; a resposta não detalhou separadamente cada etapa do áudio e dos gestos. Não houve geração ou flash de outra imagem nesta etapa. Os patches permanecem integrados no manifesto e na árvore preparada x1s; o comportamento após flash e primeiro boot, incluindo câmera e SetupWizard restaurados, ainda exige validação. Os testes em montagens RAM não persistem após reboot completo.


## Barras de sinal e chamadas — correção confirmada em 19/10/2026

O usuário confirmou chamadas e barras funcionando, com imagem e digital normais. A chamada era barrada por ro.oplus.radio.checkservice=true no build.prop CN, que exigia o serviço Oplus ausente. O build define a propriedade como false. As barras usavam dois níveis OEM zerados; framework.jar/classes4.dex agora recorre ao nível real do Android quando ambos são zero, preservando níveis OEM existentes e zero em ausência de sinal.

Ambos aplicados em out/cache/x1s/firmware e integrados no manifesto para próximas builds. Sem novos patches em vendor/odm. A fonte de entrada foi preservada. Vinte e dois testes de host passaram, o probe no Android aprovou fallback/OEM/ausência de sinal, o patch smali reproduziu o fonte revisado com fuzz=0 e a reaplicação completa resultou em zero alterações. Os outros DEX do JAR, incluindo digital, permaneceram iguais. Nenhuma imagem foi gerada ou flasheada nesta etapa; os testes ativos por ADB são temporários até o flash. IMS/VoLTE/VoWiFi não foram corrigidos por esta mudança.

Detalhes: [sinal e chamadas](QuantumROM/patches/coloros/diagnostics/radio-signal-calls.md).


## Wi-Fi após flash: prioridade corrigida — 19/10/2026

O usuário reportou novas quedas após flashear. A captura confirmou a mesma exceção radioStats nulo: o overlay original Oplus usa prioridade 1000, acima dos 999 do fix v1. Com ambos habilitados no boot, o original revertia o recurso para false. O teste temporário anterior não tinha o overlay Oplus ativo e não cobriu esse conflito.

O fix v2 usa prioridade 1001, versionCode 2 e o mesmo certificado/recursos. O APK Oplus e suas outras configurações foram preservados. Reiniciada a interface com os dois overlays presentes e ativos, o lookup passou a true vindo do v2. O aparelho conectou e o usuário confirmou “tudo funcionando!”.

Aplicado na árvore preparada x1s e integrado no build system. Adicionado teste da prioridade no APK compilado contra a prioridade 1000 do donor; 23 testes de host passaram. O teste ao vivo permanece em RAM até reempacotar/flashear; uma nova imagem não foi gerada. Boot completo da imagem v2 ainda requer validação.

Detalhes: [Wi-Fi após flash](QuantumROM/patches/coloros/diagnostics/wifi-priority-after-flash.md).


## Nome do processador em Ajustes — 20/10/2026

Adicionada à tabela externa my_stock/etc/extension/config_processor_com.android.settings.xml a entrada model_name="Exynos 990", com name_cn e name_en iguais a "Exynos 990 Octa core". A propriedade ro.product.cpuinfo continua identificando o modelo real como Exynos 990; a tabela fornece o texto de apresentação de Ajustes. Patch de texto com hashes exatos integrado ao manifesto e aplicado em out/cache/x1s/firmware. XML validado, demais entradas preservadas e reaplicação sem alterações. Não houve alteração do APK de Ajustes, teste visual ao vivo ou geração de imagem nesta etapa.


## Flickering em vídeos e desbloqueio — 20/10/2026

O log tela.txt mostrou três falhas de WIN_CONFIG sem buffer de composição final e 237 avisos de handle nulo no HWC Samsung, com Full HD/120 Hz já ativo. Testado `debug.sf.disable_client_composition_cache=1` com reinício do compositor/interface. Na captura seguinte não reapareceram as falhas; o usuário repetiu vídeos e desbloqueios e confirmou tudo funcionando, autorizando a inclusão na imagem.

Adicionada a propriedade ao manifesto e ao system/build.prop da árvore preparada x1s. Fonte preservada; sem mudanças novas em vendor, resolução ou biometria. Trata-se de mitigação de compatibilidade com possível custo extra de renderização, ainda sem medição prolongada de bateria. Não foi gerada nem flasheada outra imagem.

Detalhes: [flickering](QuantumROM/patches/coloros/diagnostics/display-flicker.md).

### 20/10/2026 — investigação de câmera após atualização

Corrigidos XML e file_contexts do SDK OnePlus acrescentado à build, preservando as quatro bibliotecas do donor. Aplicação na árvore x1s e idempotência verificadas. A correção de labels dos tmpfs ao vivo fez o PackageManager registrar o SDK, mas a câmera OnePlus ainda falha por plataforma APS desconhecida. A GCam permanece em diagnóstico: capturado deadlock entre biblioteca própria do app e controle de fluxo do liblog Oplus; teste por bind mount aprovado pelo usuário, agora integrado como hexpatch restrito por hash e offset na etapa native e aplicado à árvore extraída x1s. Estado, comandos, hashes e rollback em [diagnóstico das câmeras](QuantumROM/patches/coloros/diagnostics/cameras-2026-10-20.md).

### Encerramento solicitado — câmera em 20/10/2026

Persistidos na build e na árvore `out/cache/x1s/firmware`: correção completa da GCam (liblog), XML/labels do SDK e compatibilidade parcial da OnePlus até o preview traseiro Foto 1×. SDK v3 salvo no payload com hash e configuração/JNI necessários. A reaplicação não produz alterações. Foto/JPEG, frontal e modos extras da OnePlus ainda não estão resolvidos; os experimentos de captura com regressão ficaram fora da build e o aparelho foi restaurado ao conjunto de preview aprovado. Vendor/ODM e assinaturas dos APKs permanecem intactos. Nenhuma imagem foi reempacotada ou flasheada nesta etapa. O [diagnóstico das câmeras](QuantumROM/patches/coloros/diagnostics/cameras-2026-10-20.md) começa com o estado exato de continuidade e separa baseline aprovado dos testes rejeitados.

### Atualização da validação OnePlus — 20/10/2026

Usuário confirmou gravação e salvamento de vídeos traseiros até 4K a 30 fps com as alterações atuais. Permanecem dois problemas: crash ao trocar para a frontal e captura de fotos sem funcionar. Apenas documentação atualizada nesta etapa; nenhum novo patch, repack ou teste ADB.

### Frontal OnePlus em Foto — continuação em 20/10/2026

Preview frontal confirmado pelo usuário. Integrado SDK front-only (SHA256 a0fc8dec6c8698a8f789aa05da105870b238ea9e1e7f91526f7d566ea12f6ff2) ao payload, manifest e árvore x1s: somente front_main no Exynos usa simple_photo_case, evitando o stream MFNR incompatível. Aplicação idempotente e 24 testes host aprovados. Fotos/JPEG e Retrato seguem sem funcionar; novos testes de captura permanecem temporários por ADB, fora da build. Nenhum repack ou flash.

### Pausa da investigação OnePlus — 20/10/2026

A pedido do usuário, encerrados os testes desta sessão e salvo checkpoint detalhado no [diagnóstico das câmeras](QuantumROM/patches/coloros/diagnostics/cameras-2026-10-20.md). Única novidade aprovada e integrada à build: preview frontal em Foto via SDK front-only, com hash conferido na árvore e payload e 24 testes host aprovados. Fotos/JPEG continuam intermitentes nos experimentos, com salvamento e liberação do botão incorretos; Retrato continua pendente. Nenhum experimento de captura foi promovido. Aparelho restaurado por bind ao SDK front-only e app parado; hash igual ao da build. Último candidato de categoria foi apenas compilado, sem teste. Nenhum repack/flash ou alteração nova em vendor/ODM. Não retomar testes de câmera automaticamente ao trabalhar nos próximos bugs.

### Conjunto cumulativo de câmera mantido na build por solicitação explícita

Após a pausa, o usuário pediu manter todos os patches na árvore de build. Instalado o último conjunto cumulativo testado, sdk-jpeg-category.jar (SHA256 fe3ed2a9019301b07c34f0ba8be4e3dbb23b4256993038d8a63718bffd326b80), no payload e na árvore x1s; manifest atualizado, aplicação atômica e idempotência confirmadas. Inclui frontal e avanços experimentais da captura JPEG. **Fotos continuam intermitentes, o botão pode bloquear e Retrato não funciona.** A inclusão preserva o progresso solicitado, sem declarar a câmera corrigida. Candidato posterior apenas compilado não foi incluído. Aparelho permanece no bind front-only restaurado; não foi flasheado nem reempacotado. O diagnóstico de câmeras começa com este estado atualizado e mantém o checkpoint anterior para rollback.

### Esclarecimento do usuário — frontal e Retrato

O crash da frontal em modo Foto foi resolvido. O crash restante ocorre no modo Retrato. A captura/salvamento intermitente de fotos é um problema separado ainda pendente. Este esclarecimento atualiza o estado atual; relatos anteriores do crash da frontal são históricos. Nenhum patch foi alterado nesta atualização.


## Dynamic Island — 21/10/2026

Restaurado o UMS original (com.oplus.pantanal.ums, versão 16.56.2), removido pela conversão MysticGSI. Recuperado diretamente de my_stock.img por montagem EROFS/FUSE somente leitura; APK original intacto, SHA256 e06518b2df790e9700335e6a3ec3e08f8044592294db6b7655d35dac36bdfee8. Incluído no payload, etapa config para todos os targets, metadados e árvore preparada x1s. Aplicação idempotente e 25 testes de host aprovados.

Teste ADB: instalado o APK original e recarregados SystemUI e o serviço de bateria, sem apagar dados. Usuário confirmou cápsulas de música e carregamento funcionando. Nenhuma mudança nova em vendor/ODM ou nos patches de câmera; Metis continua removido.

Cronômetro continua pendente: o Relógio original 16.18.8 contém um código OCS que expirou em 02/08/2026. Scanner retorna erro 1003 e exclui seus cartões. Hash do APK no telefone, FW e imagem donor coincide; não foi causado por edição do APK. Não alterados data, assinatura ou validação OCS. Precisa de uma autorização válida para esse APK ou versão compatível do Relógio.

Nenhuma imagem foi reconstruída/flasheada. O funcionamento em boot completo da restauração deve ser validado após build/flash. Detalhes e evidências em [dynamic-island-2026-10-21.md](QuantumROM/patches/coloros/diagnostics/dynamic-island-2026-10-21.md).


### OCS: cronômetro corrigido e expiração ignorada — 21/10/2026

Após esclarecer o escopo, o usuário autorizou ignorar somente vencimento OCS para todos os APKs, preservando assinatura, permissões e demais verificações. Confirmou o cronômetro funcionando ao vivo e solicitou integração à build. Este estado substitui a pendência de cronômetro registrada acima.

Incluído hexpatch na etapa framework para todos os targets. Modifica duas instruções do OpenCapabilityService.apk e atualiza checksums DEX/CRCs ZIP, usando o helper existente. Preserva tamanho, layout, recursos, manifesto, certificados e Signing Block originais, sem recompilar o APK nem adicionar outro motor de patch. Hash final ff318d59795810476e336a31116a77500a9a77c5eae01b81a396a96504e450a8, aplicado à árvore x1s e ao telefone por bind temporário; aplicação idempotente. Nenhuma mudança em vendor/ODM ou APKs clientes.

26 testes de host aprovados, incluindo integridade binária e preservação dos metadados de assinatura. Probe ART confirmou expiração ignorada para dois pacotes, mantendo revogação, UID e TTL; provider real aceitou Relógio (1001) e rejeitou família inválida (1002). Música, carregamento e cronômetro receberam confirmação física durante a investigação; não foram declaradas outras funções corrigidas.

A cópia RAM final foi refeita em tmpfs maior depois que a origem de teste anterior ficou sem espaço. Hash/tamanho finais conferidos; detalhes dos mounts e rollback no diagnóstico. Nenhuma imagem reconstruída/flasheada. O APK modificado destina-se ao preload; preservar seu bloco original não equivale a reassinar criptograficamente o novo conteúdo. Falta validação de boot completo da imagem.

Detalhes: [Dynamic Island e OCS](QuantumROM/patches/coloros/diagnostics/dynamic-island-2026-10-21.md).


## 21/10/2026 — experimento com product separado (x1s)

Criados split-product.py e scripts/build-split-product.sh. Aplicados todos os patches atuais antes de separar a árvore; preservados a entrada e o fluxo normal. Geradas somente system.img (4070678528 bytes) e product.img (1447489536 bytes), em out/target/x1s/split-product/. Product contém o product anterior mais my_product em subdiretório; /product é ponto real de montagem, /system/product e /my_product são links. Metadados foram remapeados sem substituir labels, permissões ou capabilities dos arquivos. 27 testes passaram; ambas as imagens passaram pela validação EROFS e de labels; 11 arquivos críticos coincidem com a árvore patcheada nas imagens montadas. Vendor/ODM/boot/dtbo não foram reconstruídos nem flasheados. Product atual (753106944 bytes) precisa ser ampliada para comportar a imagem. ZIP padrão não foi migrado. Boot aguarda teste do usuário. Detalhes: QuantumROM/patches/coloros/diagnostics/split-product-2026-10-21.md.


## 21/10/2026 — correção do primeiro boot com product separado

O teste do usuário entrou em bootloop: PackageManagerService reclamava de android.ext.shared, e os logs mostravam /product/etc ausente. A separação havia mantido skip_mount.cfg da GSI bloqueando /product e /product/*. Corrigido o helper para remover somente essas regras na cópia separada, por escrita atômica, mantendo as demais e preservando entrada/cache normal. Teste cobre liberação de product, preservação da origem e rejeição de outros padrões bloqueadores. GoogleExtShared existe e declara a biblioteca requerida; não foi suprimida a exigência do PackageManager.

Regenerados system.img e product.img na saída split-product. 27 testes passaram; ambas passaram pela verificação EROFS e sete labels críticos, incluindo GoogleExtShared. Conteúdo da configuração corrigida foi conferido na imagem final por leitura do extent indicado pelo dump.erofs, pois a revisão da montagem FUSE expirou. Hashes e resultados atuais no diagnóstico split-product-2026-10-21.md e SHA256SUMS da saída. Usuário já havia restaurado seu backup; o agente não alterou o aparelho. Novo boot aguarda teste manual.


## 21/10/2026 — product separado confirmado e integrado ao ZIP

O usuário confirmou boot e funcionamento normal do segundo par no x1s. A separação corrigida agora é aplicada por build.sh após os patches, na cópia de empacotamento: gera system/product dessa cópia e vendor/odm da árvore normal. --patch-only permanece antes da separação. Verificação padrão, hashes e orçamento agora incluem as quatro imagens.

O ZIP converte as quatro imagens reais para new.dat.br/transfer.list/patch.dat e gera dynamic_partitions_op_list com os tamanhos reais de cada uma. Removida a leitura do tamanho fixo de product. Rejeita imagens ausentes, vazias ou desalinhadas; ignora payloads/op lists legados nos templates. Arquivados os 16 arquivos antigos dos quatro templates em out/archive/zip-product-legacy-20261021, fora da source exportada. ODM foi mantido porque o instalador recria o grupo e grava essa partição. Boot/dtbo, metadata e update-binary continuam nos templates.

27 testes passaram, incluindo um ZIP completo de fixture com img2sdat/Brotli/7z e comparação do product descomprimido com a imagem nova; testes também cobrem tamanhos/op list, origem das imagens e --patch-only. Documentação atualizada. Não foi executada uma nova build completa da ROM nem flash nesta etapa. Comando: bash build.sh x1s erofs -z; saída em out/target/x1s.

## Câmera — 4K60 em 21/10/2026

Gravação traseira4K60 validada pelo usuário e ffprobe no x1s: H.264,3840×2160,799 quadros em13,331133s (~59,94fps). Integradas apenas as duas consultas de configuração4K60 ao SDK aprovado v2; manifest/payload/árvorex1s usam SHA256 `93e35c925da82cbeef73247d84f66fcbd3cb38211e3c2f4fb4b8d409c4fcbce5`. Instalação atômica/idempotência/hardlinks conferidos, sem repack/flash. 8K24/30 e finalização/qualidade/HDR das fotos continuam pendentes. Consulte `QuantumROM/patches/coloros/diagnostics/cameras-2026-10-20.md`.

Investigação 8K24/30: o HEVC Exynos anuncia ambas as taxas, mas o SDK/Camera2 atual não expõe o stream 7680×4320; consulta dentro do app confirmou metadados até 4K60 nos IDs0/2 e rejeição dos IDs adicionais20/50/52/54. 8K não implementado. Probes temporários retirados, aparelho restaurado ao v6 validado em4K60 e tmpfs antigos liberados. Evidências e limites detalhados no MD de câmeras.


## Câmera — 21/10/2026: salvamento e vídeo

Corrigida a publicação dos JPEGs da OnePlus: finalizador JNI não reconhecia Exynos, e fotos ficavam pendentes/ocultas. SDK e duas dependências originais em product/lib64 integrados ao manifest/payload/árvore x1s. Usuário confirmou detalhes EXIF e fotos publicadas. Removida espera pelo HAL Oppo ausente no serviço de boost de vídeo ARM32; inícioFHD caiu de~19s para212ms e foi confirmado fisicamente. Nenhum vendor do Ace3Pro foi importado.

Bringup agora define explicitamente ro.product.model pelo nome comercial do target; x1s passa a Galaxy S20 após nova build/boot. Identificação de hardware no vendor e assertsSM do ZIP mantidos. Nome novo não validado em foto após flash.

Fotos de diagnóstico não foram apagadas por nossos comandos: foi observada limpeza de item pendente pelo próprio app. Cópia dos arquivos presentes preservada em out/cache/bugs-update/camera-replace-20261021/photos-before-finalize. Pós-processamento APS/HDR/granulado, Retrato e8K continuam abertos. Não houve repack/flash. Evidências, hashes e rollback temporário no relatório QuantumROM/patches/coloros/diagnostics/cameras-2026-10-20.md, seção de salvamento JPEG/atraso de vídeo.


## Retrato — pausa de21/10/2026

Mantidos na build todos os fixes cumulativos de câmera. SDK atual a954fc40d8210bad4ae5d11424896a8591bc2d662c86e0e8cfe24d0a6c9ec2b0 acrescenta caminho de Retrato com câmera única no Exynos e dependências Arcsoft originais em product/lib64. Manifest/payload/árvore x1s e metadados atualizados atomicamente. Usuário confirmou que o Retrato abre na traseira e frontal, **mas não tira fotos**. Investigação pausada por pedido explícito; não retomar automaticamente. Foto/EXIF, gravação sem atraso e4K60 preservados. Nenhum repack/flash. Histórico, estado temporário e limitações no MD de câmeras, seção de Retrato.


### Pendência adicional de câmera —21/10/2026

Usuário informou que o modo Pro também não captura fotos. Registrado sem retomar testes ou alterar patches; causa não investigada. Captura de Retrato e Pro continuam pendentes.

## Revisão do build e câmera no debloat — 22/10/2026

Conferida a câmera diretamente na imagem original my_product.img da OnePlus: APK de 173260781 bytes, SHA256 18e6ecdb217bd4b46ad12e13270dc3bf52d271f93d2010ea040c3e0963393f9b, idêntico ao payload atual e com assinatura preservada. A system.img GSI de entrada não contém o app no caminho original, e a extração não contém OplusCamera.apk; a operação install do build já o restaura. O manifesto já não removia OplusCamera. Reforçado o teste para impedir remoção também por diretórios ancestrais ou outros grupos, e acrescentada a checagem do APK/label na product EROFS final. A lista completa da Mystic não foi importada, pois removeria componentes restaurados como UMS e SetupWizard.

Corrigida a saída F2FS para raw alinhado a4096, evitando tamanho de partição/ZIP inconsistente. O ZIP novo agora passa por7z t antes de substituir o anterior. A extração de entradas Android sparse passa a usar temporário, sem substituir a imagem de entrada. Corrigida descrição desatualizada do payload no README.

30 testes passaram, sem skips; sintaxe Bash passou. Aplicação real x1s --patch-only:364 arquivos alterados; reaplicação completa:zero alterações. Separação temporária real confirmou APK/SDK/adapter nos caminhos e labels de product corretos. Não foram reconstruídas imagens completas nem feito flash/ADB. Evidências em out/logs/build-audit-20261022. Auditoria detalhada, incluindo limites do cache de system, extração de arquivos completos, templates, concorrência, F2FS e outros targets: QuantumROM/patches/coloros/diagnostics/build-audit-2026-10-22.md. Retrato/Pro/HDR/8K continuam pendentes, sem novos testes de câmera.

## Diagnóstico de publicação de fotos no z3s — 22/10/2026

Logs novos confirmaram `thumbnail_category_fail` e foto pendente, sem a antiga exceção Unknown Platform. Os fixes recentes estão nas imagens locais, mas a categoria não chega válida ao consumidor no aparelho remoto. Preparado kit Linux com SDK instrumentado e collect.sh, todo em inglês, em out/diagnostics/z3s-camera-exif-v1 e ZIP ao lado. Bind via ADB root em tmpfs, coleta e rollback automáticos, sem flash ou limpeza de dados. Build normal e payload preservados. SDK diagnóstico849830714ba6aff38caa53fc6bfb73c5ba27b8e7c82ef746ad1a17884e71161c; baselinea954fc40d8210bad4ae5d11424896a8591bc2d662c86e0e8cfe24d0a6c9ec2b0.34 testes de host passaram, incluindo falhas/interrupção do coletor com ADB simulado. Ainda não executado no telefone. Detalhes em QuantumROM/patches/coloros/diagnostics/camera-z3s-exif-2026-10-22.md.

Retorno posterior do tester: SDK ativo0f27305312e1f764bd7c76abde0d27903277b69cf055d021421244e4af14439d, exatamente o category-v2 histórico, e duas bibliotecas finalizadoras ausentes. Os fixes recentes não estão ativos nesses caminhos do aparelho. Não se pode atribuir os logs ao SDK a954 nem determinar ainda se há product antigo ou mount encobrindo arquivos novos. Coletor revisão2 usa modelo Samsung de boot, aceita vendor reescrito apenas com identificação válida, registra preflight completo e mantém recusa de SDK incompatível. Pacote novo em out/diagnostics/z3s-camera-exif-v1-preflight-v2.zip, em inglês; JAR diagnóstico inalterado, sem upgrade automático ou flash.35 testes passaram. Detalhes no diagnóstico z3s.

## 23/10/2026 — Reconhecimento facial AIDL e círculo da câmera (x1s)

Cadastro/autenticação passaram a funcionar com o HAL nativo fornecido em samsa-hals.zip, modo CPU, preferência AIDL no AuthService$Injector e permissões específicas de worker/memfd em Enforcing. O pacote smali/Megvii incompatível não foi aplicado. Teste sem hooks de diagnóstico também autenticou. O círculo foi calibrado com base no overlay LineageOS x1s e confirmado pelo usuário em `678,39:762,123`.

O conjunto foi integrado ao manifest/apply.py, device.json do x1s, metadados e verificador de labels. Bibliotecas/execução ficam em vendor, propriedades em system/my_product e o cache de política em ODM é removido para recompilar o CIL atualizado. Usar as quatro imagens geradas pelo fluxo normal, não só system. Outros targets preservados até validação própria.

Warning aceito pelo usuário: preview de cadastro facial girado/esticado, sem correção visual. Biometria continua WEAK e anti-spoofing não foi validado. Nenhum template pessoal ou hook de diagnóstico entra na source. Imagens integradas ainda precisam de teste de boot por flash. Procedimento, hashes, evidências e limites: `QuantumROM/patches/coloros/diagnostics/faceunlock-zip-audit-2026-10-23.md`.

## 23/10/2026 — Instant / Instant Service restaurados

A pedido do usuário, removidas as exclusões de Instant e InstantService do debloat e restaurados os APKs originais com suas assinaturas, além das44 bibliotecas ARM64 externas do runtime Instant. Fonte: my_stock.img original do donor; o diretório extraído pela Mystic já estava sem Instant. Instalação por hash no manifesto config, payload e metadados adicionados, sem oat do donor. Vale para todos os targets. Árvore extraída x1s atualizada. No celular, restauro temporário como apps de sistema via overlay de my_stock/app e recarga do Android. Confirmação funcional dos widgets ainda necessária. Diagnóstico: `QuantumROM/patches/coloros/diagnostics/flagship-widgets-2026-10-21.md`.

**Validação dos widgets em23/10/2026:** usuário confirmou que todos voltaram após restaurar Instant e InstantService, com imagem normal. Fix já integrado na build; restauração ao vivo permanece temporária em RAM.


## 23/10/2026 — SMS de envio e recebimento integrados

Usuário confirmou ambos funcionando. Corrigidos quatro fallbacks Oplus em telephony-common.jar: DEFAULT da fábrica não substitui o scanner AOSP, repairSmsNumber preserva destinatário, URI temporária de recebimento usa content://sms/raw e oemCheck padrão permite continuar para os filtros/entrega Android. Mensagens pendentes foram entregues normalmente ao Google Mensagens, sem exclusão manual.

SamsungSmsReady substitui o comando manual de diagnóstico: FW_READY=1 só após construir os phones e registrar os receptores, e novamente em RIL_CONNECTED quando o framework já estiver pronto. Usa a transação HIDL2.2 da stock, sem callbacks próprios nem novo serviço root/policy. Patch incremental com validação de hashes em smali/telephony-common.jar/sms-samsung.patch, integrado à etapa framework para todos os targets; só x1s validado fisicamente.

40 testes passaram; aplicação real, ZIP/DEX e idempotência conferidos. Árvore de trabalho x1s atualizada, extração original preservada. Não foram geradas imagens ou ZIP; próximos builds incorporam o patch. Boot por flash, SIM2/multipart/MMS e demais aparelhos ainda não validados. Diagnóstico completo: QuantumROM/patches/coloros/diagnostics/sms-notification-2026-10-23.md. Atraso de áudio continua sendo investigado separadamente.


## 23/10/2026 — Atraso no som das notificações corrigido

Pilha capturada durante o atraso mostrou audioserver bloqueado em AServiceManager_getService, tentando inicializar vendor.oplus.hardware.performance.IPerformance/default, ausente no vendor Samsung. A função OplusPerformanceController::initHal agora retorna false imediatamente em oplus_performance_shared.so e nas cópias embarcadas de libaudioclientextimpl.so, ARM32/ARM64. O caminho normal de reprodução continua; não altera mixer, volume, HAL Samsung ou limites térmicos.

Usuário confirmou notificações funcionando e música/volume normais. Os quatro hexpatches entraram na etapa native com hashes e offsets estritos, logs detalhados do mecanismo existente e teste de integridade/idempotência/recusa de entrada desconhecida. Aplicados à árvore de trabalho x1s, mantendo a extração original intacta; repetição sem alterações. Próximas builds incorporam o fix, sem depender dos binds do teste. Não foram geradas imagens/ZIP. Só x1s validado fisicamente; Bluetooth/chamadas e demais modelos não foram retestados. Procedimento e hashes: QuantumROM/patches/coloros/diagnostics/sms-notification-2026-10-23.md.


## 24/10/2026 — Breeno / HeyTapSpeechAssist restaurado para teste

O crash ao perguntar era ActivityNotFoundException no ColorDirectService: com.heytap.speechassist estava ausente. Restaurados o APK original12.8.6 e67 libs ARM64 externas (68 arquivos,197.959.928bytes), retirado do debloat e adicionados installs por hash e metadados à etapa config. Sem recompilar/ressinar o APK, sem oat do donor. Árvore x1s atualizada, teste de payload passou e aplicação repetida sem alterações.

No celular, overlay em RAM sobre my_stock/priv-app com hashes/labels conferidos; PackageManager reconhece o app privilegiado e a Activity SEND/image/* agora resolve. Sem permissões manuais extras ou mudança de SELinux. Teste funcional solicitado ao usuário, ainda pendente. Biblioteca extra libSlpBase.so de TTS não foi encontrada no donor e não foi acrescentada; download automático não confirmado. Não geradas imagens/ZIP. Diagnóstico: QuantumROM/patches/coloros/diagnostics/breeno-crash-2026-10-24.md.


## 24/10/2026 — Setup Wizard: provider Find My Phone restaurado

Reset real revelou loop de crashes de GuidePage ao registrar observer no provider ausente com.coloros.findmyphone.provider.SharedProvider. OplusBootReg já estava instalado; faltava sua dependência FindMyPhone removida na base. Restaurado o APK original9.0.12 com três libs ARM64 embarcadas, assinatura intacta, sem alterar provisionamento/contas nem código do assistente. Usuário confirmou que a tela de configuração voltou após teste em RAM.

Integrado à etapa config para todos os targets, com hash e metadados estritos; árvore de trabalho x1s atualizada. Teste de regressão cobre a dependência e a ausência de remoção conflitante. Não gerada imagem/ZIP; falta teste por flash e conclusão de todas as páginas. Detalhes: QuantumROM/patches/coloros/diagnostics/setup-wizard.md.


## 24/10/2026 — Play Store completa e Gboard na build

Usado MindTheGapps16 como referência de instalação privilegiada/permissões, preservando GmsCore e GSF já existentes da ColorOS. APK fornecido da Play Store52.9.21 substitui o placeholder com.android.vending22.7.54 em GooglePlayServicesUpdater.apk, com assinatura Google compatível; não é duplicado em del-app ou Phonesky. Gboard18.4.4 ARM64 fornecido entra em my_product/app/LatinIMEGooglePrebuilt. APKs intactos, sem resign ou extração das libs embarcadas. Uptodown-com.android.vending.apk é com.uptodown e não foi usado.

Adicionados installs/metadados e duas permissões específicas de download para vending; allowlist MTG e sysconfig Google já existiam. Oat do placeholder removido. Dois testes novos passaram; aplicação da config repetiu sem alterações na árvore x1s. Original FW/ColorOS preservado. Teste em RAM preparado/carregado por ADB para confirmar execução, sem provisionar o telefone à força. Não geradas imagens/ZIP. Diagnóstico: QuantumROM/patches/coloros/diagnostics/google-preloads-2026-10-24.md.


Ajuste do teste de Play Store: a substituição no mesmo caminho continuou mostrando metadados antigos do placeholder. Layout final mudou para my_product/priv-app/Phonesky/Phonesky.apk, com remoção completa do diretório GooglePlayServicesUpdater na etapa art, sem duplicar com.android.vending. Testes e árvore x1s atualizados, entrada original preservada. Nenhuma limpeza de dados/contas foi feita.


Complemento do preload Google: no namespace de app de sistema, o teste procurou libs fora do APK. A build agora inclui cópias ARM64 extraídas dos próprios APKs em lib/arm64:9 Play Store +15 Gboard, mantendo assinaturas/alinhamento originais e sem variantes de outros ABIs. Três testes de APKs, XML e correspondência das libs passaram; config repetida sem alterações. Versão52.9.21 e launcher registrados, Gboard presente; teste de login/download/digitação ainda pendente.


## 2026-10-24 — KernelSU Next 3.4.1 como preload removível

A pedido do usuário, o gerenciador não entra em app/priv-app. O APK original com.rifsxd.ksunext, versão v3.4.1/code33333, fica em system/my_stock/del-app/KernelSU_Next_v3.4.1_33333-release.apk, com SHA256 eff4b9df6dc438a3fee3b298e4fb87843e7c95f16b6daabdd3161d51968ba2ff. Assinatura APKv2 e integridade verificadas; não foi reempacotado ou reassinado. Os quatro targets compartilham essa instalação. A etapa art remove apenas o APK3.4.0 e o diretório legado KernelSU-Next conhecidos, evitando versões concorrentes. Metadados root:root0644/system_file.

Usa-se o mecanismo nativo OplusRemovableAppManager: my_stock/del-app está em PREINSTALLED_PATH_LIST; scanPreinstalledAppsInner considera primeiro boot, upgrade e master clear. O código inspecionado mantém o estado de pacote desinstalado pelo usuário. Não foi acrescentado serviço que reinstala a cada boot, nem alteradas flags globais de primeiro boot. O APK final deve ser copiado pelo instalador OEM para /data/app como app normal, removível. A inspeção smali registrada em out/cache/ksu-code-inspection veio da análise anterior; o teste automático de primeiro boot desta base atual permanece pendente.

No aparelho já provisionado, usa-se instalação normal do mesmo APK para testar versão e flags; isso não comprova instalação automática após reset. Não se modifica kernel, ksud ativo, cadastros, contas ou dados do aparelho. A compatibilidade do kernel com o gerenciador é independente deste preload.

Validação Google em 24/10: o usuário confirmou a tela de login da Play Store após as libs e a presença do Gboard. Preferiu não fazer login; download e digitação não foram confirmados separadamente.

Teste ao vivo concluído: adb install retornou Success. PackageManager registrou versão v3.4.1/code33333 em /data/app, flags HAS_CODE/ALLOW_CLEAR_USER_DATA/ALLOW_BACKUP, sem SYSTEM. O gerenciador é removível. Não foi executada instalação de root/kernel ou reset; primeiro boot automático continua não testado.


## IMS PhhIms — 24/10/2026

Integrado o PhhIms testado em RAM, com correções de contexto ColorOS, recursos MMTEL, início de áudio no200semSDP e notificação de encerramento. Seleção automática por overlay validada sem override ADB; registro LTE confirmado. Usuário confirmou chamadas e relatou VoLTE/VoWiFi; áudio nos dois sentidos ainda não testado. System recebe APK/libs/permissões; product recebe overlay; vendor intacto. Patch compartilhado pelos quatro targets, físico apenas x1s. Build já em andamento deve ser refeita se passou dos patches. [Diagnóstico e limites](QuantumROM/patches/coloros/diagnostics/ims-phh-2026-10-24.md).


## 24/10/2026 — 8K integrado por target

Adicionado o checkpoint8K com alvo30fps para x1s, y2s e z3s: seleção do SDK no estágio ART e hexpatch verificado no provider Samsung no estágio vendor. r8s foi excluído de ambos; sua câmera mantém o checkpoint anterior. Aplicação/reaplicação e exclusão foram testadas no host com cópias das bases preparadas. O kit de diagnóstico z3s acompanha o novo SDK. Não houve geração de imagens nesta rodada.

O vídeo real validado no x1s foi7680×4320/H.264 com AAC, média próxima de27fps. O foco de perto e o travamento ao tentar0,6× em8K permanecem conhecidos; a integração foi solicitada nesse estado. y2s/z3s ainda precisam de teste físico. Deve-se atualizar vendor junto com system/product para expor o sensor8K. Detalhes em QuantumROM/patches/coloros/diagnostics/camera-8k-2026-10-24.md.


## 24/10/2026 — facial y2s e investigação IMS com dois SIMs

O tester y2s ainda executava o backend facial Samsung, com falha ret=-3011. A integração nova estava restrita ao x1s; foram habilitadas para y2s as sete operações de framework/HAL/VINTF/init/SELinux e a verificação de labels das imagens. Quatro testes dedicados e uma transação repetida sobre cópias reais da base y2s passaram, com zero mudanças na reaplicação. O cadastro facial no aparelho ainda precisa de teste após a nova build e atualização de system/vendor/odm.

IMS segue sem alteração: o usuário informou dois SIMs, mas os logs não incluem o buffer radio usado pelo PhhIms. O tester está offline; aguardam-se comparação de um/dois SIMs e logs de rádio para identificar a causa. Relatório completo: QuantumROM/patches/coloros/diagnostics/y2s-face-ims-2026-10-24.md.


## 24/10/2026 — integração facial comum a todos os targets

Por solicitação do usuário, removidas as restrições de target das sete operações faciais já existentes. Framework AIDL, executável e quatro bibliotecas CPU, VINTF, init, file contexts e CIL agora também entram no z3s e no r8s. verify-images.py exige os labels do novo HAL em todos os vendors. A exclusão do r8s no 8K foi preservada. Nenhuma alteração IMS adicional.

Os vendors preparados do z3s/r8s têm a declaração HIDL, init e tipos SELinux esperados; os arquivos novos não substituem bibliotecas existentes. Os DEXs services/classes.dex desses targets coincidem com a entrada já validada no y2s. Aplicação/reaplicação em cópias reais de VINTF/init/CIL/file_contexts/ODM/metadados passou para ambos. Quatro testes faciais (incluindo os quatro targets) e dois testes 8K passaram. Nenhum dado biométrico foi apagado, SELinux permanece enforcing e as configurações da digital não foram modificadas.

É necessário reconstruir e atualizar system, vendor e odm. Nenhuma imagem foi gerada nesta rodada. Cadastro e autenticação foram testados fisicamente apenas no x1s; os demais targets ainda dependem de teste nos aparelhos. A limitação do preview girado/esticado permanece.

## 24/10/2026 — microfone nas chamadas VoLTE

Corrigida captura silenciada do PhhIms mediante CAPTURE_AUDIO_OUTPUT no manifest do APK e privapp allowlist restrita ao serviço, preservando código/libs e assinante. Usuário confirmou áudio no x1s. Integrado na etapa config para os quatro targets, com hash e migração do payload anterior. Recebimento de chamadas ainda em investigação; demais targets não testados fisicamente. Detalhes em QuantumROM/patches/coloros/diagnostics/ims-phh-2026-10-24.md.

## 25/10/2026 — integração final dos fixes IMS de áudio e recebimento

Usuário confirmou no x1s recebimento de chamadas e áudio nos dois sentidos com os testes e autorizou ambos na build. Microfone: CAPTURE_AUDIO_OUTPUT solicitada e concedida somente ao PhhIms. Recebimento: TeleService inicializa o PstnIncomingCallNotifier também no Exynos, por modem. Ambos entram na etapa config comum a x1s/y2s/z3s/r8s, com hashes, labels e idempotência; validação física somente x1s. O TeleService prebuilt mantém o bloco do certificado para scan em partição de sistema, não é APK para adb install. Diff e helper de reprodução preservados em QuantumROM/patches/coloros/ims. Vendor/odm inalterados. Rebuild necessário; não foram geradas novas imagens nesta etapa. Ver diagnostics/ims-phh-2026-10-24.md para limites e detalhes.

Validação final da integração IMS: 4 testes IMS + 1 split-product passaram; TeleService reproduzido com o mesmo SHA256 do teste funcional. Comparação contra a base confirmou manifest, recursos, segunda DEX e demais entradas intactos, além do bloco de certificado preservado.

## 26/10/2026 — três logs de IMS do y2s

Analisados ims-y2s1.txt, ims-y2s2.txt e ims-y2s3.txt. O terceiro demonstra 54 crashes de telefonia ao usar template User-Agent IMS nulo no caminho Exynos, com eventos de mudança de SIM e nove ciclos NFC. Incluídos guard no oplus-telephony-common.jar, limpeza de seu código pré-compilado e remoção do APK IMS Qualcomm incompatível, comuns aos quatro targets. PhhIms e seus fixes anteriores, NFC, APNs e vendor/odm preservados. Os arquivos 1/2 mostram EDGE sem resposta de modem/SIP suficiente para determinar a perda de LTE; esse caso permanece pendente. Testes de aplicação real do JAR nos quatro targets, idempotência, rejeição de outra base e limpeza isolada foram adicionados. Coletor Linux em QuantumROM/patches/coloros/tools/collect-y2s-radio.sh. Sem teste físico do y2s ou geração de imagens. Relatório detalhado: QuantumROM/patches/coloros/diagnostics/y2s-ims-2026-10-26.md.

Validação desta rodada: 9 testes passaram (3 novos + 6 regressões de payloads, IMS e split-product), além de sintaxe Python/Bash. LTE/dados e registro IMS dual SIM continuam dependendo do novo teste físico com buffer radio.

## 26/10/2026 — PowerShare em teste temporário

Localizada a tela original ColorOS e habilitada feature de suporte por bind; usuário confirmou que o item permaneceu no menu ao voltar. Adaptador temporário de OplusBatteryServiceFeature para o controle Samsung wc_tx_en passou em leitura/desligamento via Binder; transmissor continua desligado. Bateria abaixo de30% e bloqueio USB impedem ainda validar ativação/energia. Usuário está carregando para teste acima de35%. Protótipo e rollback registrados em QuantumROM/patches/coloros/diagnostics/powershare-2026-10-26.md; nenhuma operação PowerShare foi habilitada no manifest da build nesta etapa.

## 26/10/2026 — PowerShare validado e integrado

O x1s detectou receptor Qi e reportou corrente/contador de energia. O teste v2 confirmou ligar, desligar pelo botão e desligar o transmissor ao conectar USB; estado final desligado com SELinux Enforcing. Corrigido o protocolo de estado do primeiro protótipo (cliente exige enable/disable, não 1/0). Adaptador no patch comum de oplus-services.jar, feature XML dedicada, permissão init somente para wc_tx_en e piso de UI de 30%, preservando limiar maior. Integrado aos quatro targets; somente x1s testado fisicamente. Sem nova imagem/ZIP nesta etapa, sem certificação de carga completa do receptor ou timeout. [Detalhes e hashes](QuantumROM/patches/coloros/diagnostics/powershare-2026-10-26.md).

## 26/10/2026 — chamadas x1s após novo flash

Payloads IMS/TeleService instalados conferem com a build. Diagnóstico identificou perda de rede IMS com backoff de modem e chamada GSM fantasma em DISCONNECTING. Renovação de rádio recuperou registro; recarga dos processos de telefonia/IMS limpou a chamada presa. Usuário confirmou saída, recebimento e áudio funcionando. Nenhum novo patch binário foi instalado: os patches já existentes permanecem na build; prevenção permanente da recorrência ainda exige reproduzir/capturar a transição causadora. VoWiFi isolado não foi demonstrado pelo registro LTE desta sessão. [Diagnóstico e limites](QuantumROM/patches/coloros/diagnostics/x1s-ims-postflash-2026-10-26.md).

## 26/10/2026, 21h20 — y2s ainda sem dados após fix IMS

Analisados y2s-radio-20261026-212055-tZU8Dv e boasorte.txt. Sem crash User-Agent observado, mas aparelho registrado em HSUPA com dados habilitados e sem data call. Captura curta sem SETUP_DATA_CALL não determina causa. Identificada variante física G985F LTE usando vendor de G986B 5G; DTBO comum do template também precisa de comparação com a variante/kernel corretos. Coletor aprimorado com histórico radio e TelephonyDebugService, instruções em inglês e teste somente leitura aprovado. Nenhum novo patch binário/rede nem flash foi feito. Detalhes em QuantumROM/patches/coloros/diagnostics/y2s-ims-2026-10-26.md.

## 27/10/2026 — manifesto de debloat para a preparação ColorOS 17

Migradas as 60 remoções fixas e unidas à lista fornecida pelo usuário em QuantumROM/patches/coloros/debloat.json: 135 regras e 12 preservações explícitas para recursos anteriormente restaurados. O manifesto principal aponta para uma operação debloat; apply.py expande curingas apenas nos grupos/partições conhecidos, considera installs pendentes e registra remoções, ausências e preservações. Remoção de diretório symlink não percorre seu destino. Fluxo/targets e fonte de firmware preservados. Oito testes direcionados passaram, incluindo quatro targets, hardlinks, idempotência, limites de caminho e dependências IMS/widgets/setup/câmera. Nenhuma extração, build completa, flash ou rebase binário da 17 foi executado. Documentação: QuantumROM/patches/coloros/DEBLOAT.md.

## 27/10/2026 — ajuste solicitado no debloat e nas restaurações OEM

Este estado substitui o bloco de preservações da etapa anterior: debloat.json contém somente debloat, com 129 regras. Nomes que queremos manter foram retirados diretamente das listas; curingas não possuem exceções. Removidas 118 operações de restauração OEM e seus metadados para OplusBootReg/OplusCamera/UMS/Instant/InstantService/HeyTapSpeechAssist/FindMyPhone. APKs e libs passam a vir exclusivamente da firmware de entrada. Os arquivos antigos no payload não foram apagados, mas não são instalados. Mantidos KernelSU Next, Gboard e Play Store. Após esclarecimento explícito do usuário, os payloads dos fixes (IMS, facial, câmera, NFC, Bluetooth etc.) continuam ativos. Testes de restauração OEM foram atualizados para verificar retenção dos arquivos da base e ausência de reinstalação. Nenhum rebase binário completo, build/flash ou alteração no aparelho foi realizado.

## 27/10/2026 — migração completa dos patches para ColorOS 17

Rebase sobre PLK110 / Android 17 API 37 / segurança 2026-09-01, preservando a firmware de entrada. Framework recompilado nas novas divisões DEX, nativos relocalizados por símbolos/instruções, configurações regeneradas, SDK/adapter da câmera e TeleService atualizados para as versões da 17. Hashes fechados continuam obrigatórios; correções upstream e fluxos novos foram preservados. Sem novas otimizações experimentais. Mantidas as decisões de debloat, OEMs da base e payloads/preloads dos fixes.

Incluído patch UN1CA de mremap/MREMAP_MAYMOVE na política seccomp C2 dos quatro vendors. Templates dos quatro ZIPs atualizados para 17.0.0, fingerprint PLK110, incremental B.3bd95df-15a2df3-15dafac, API37, segurança e timestamp atuais. A build registra identidade junto às imagens verificadas; o ZIP confere hashes/tamanhos e atualiza os metadados automaticamente, rejeitando imagens antigas ou alteradas. Dynamic partitions continuam dimensionadas pelas quatro imagens reais.

Detalhes, hashes, evidências e limites: [migração Android17](QuantumROM/patches/coloros/diagnostics/android17-rebase-2026-10-27.md). Não houve build de imagens, ZIP final, ADB ou flash nesta sessão; saídas antigas não se tornam 17 apenas por atualizar os templates.

Validação final desta migração: 70 testes de host passaram; aplicação completa `--patch-only` concluída com saída 0 nos quatro targets (x1s/y2s/z3s/r8s); reaplicação no x1s sem mudanças. Metadados reais dos quatro templates conferidos contra as árvores preparadas. Limite: ainda não há novas imagens/ZIP 17 nem validação física dessa base.

## 29/10/2026 — primeiro teste da 17: aborto no init

Usuário construiu/flasheou o ZIP e relatou retorno a fastboot. ADB no recovery confirmou no last_kmsg: compilação SELinux aborta porque falta system/etc/selinux/mapping/30.0.cil, exigido pelo vendor 30.0. Arquivo ausente na base 17 original e na imagem instalada. Checks anteriores de aplicação/EROFS/ZIP não cobriam compilação combinada da política; essa compatibilidade precisa ser resolvida e verificada antes de novo flash. Apenas coleta e montagens EROFS somente leitura; sem patch, flash, reboot ou limpeza de dados. [Diagnóstico](QuantumROM/patches/coloros/diagnostics/android17-boot-failure-2026-10-29.md).

## 29/10/2026 — port SELinux 30.0 e restauração VNDK30

Mappings 30.0.cil e 30.0.compat.cil da 16.0.5 integrados por payload/hash nos quatro targets, sem substituir a política principal da 17 ou alterar regras. As combinações completas compilaram nos quatro vendors. O próprio secilc Android17 executado em /tmp do recovery x1s produziu política idêntica à do host, sem carregar a política. Build agora compila SELinux após bringup e antes das imagens; compilador reproduzível com fontes/licenças em bin/selinux. Validação EROFS passou a exigir os mappings e VNDK30.

Após pedido do usuário, confirmado VNDK30 ausente na base 17 e exigido pelo vendor; APEX original de 114761728 bytes recuperado da 16.0.5, com assinatura/container preservados, AVB/hash tree e chave conferidos. Incluído no manifesto comum e nos metadados, aplicado às quatro árvores preparadas. 15 testes direcionados passaram. Não houve geração de novas imagens/ZIP nem flash/boot. [Detalhes](QuantumROM/patches/coloros/diagnostics/android17-selinux-vndk30-2026-10-29.md).

## 29/10/2026 — comparação com o bringup y2s do amigo

Lido ColorOS17_y2s_System_Vendor_Changes.md; usuário confirmou mesmos boot/DTBO/vendor e ausência dos binários/diffs do amigo. Já presentes SELinux30/VNDK30, propriedades básicas e guarda de inputflinger. Aplicado apenas complemento verificável de mídia: fallback media_profiles.xml copiado do vendor de cada target (MD5 idêntico ao documento) e early-init selecionando o perfil Samsung e Codec2 AIDL, suportado pela base. Metadados e verificação EROFS atualizados, quatro árvores preparadas corrigidas e SELinux recompilado. 16 testes direcionados passaram. Preservados display/densidades/identidade Exynos; não copiados rootsvc/ADB TCP/stubs ou patches binários de rede sem conteúdo reproduzível. Não houve flash/reboot/build de imagens. [Comparação e pendências](QuantumROM/patches/coloros/diagnostics/android17-y2s-friend-boot-review-2026-10-29.md).

## 29/10/2026 — rede e BPF Android17 implementados

Confirmado BPF habilitado no boot template; kernel não modificado. Adaptada a compatibilidade UN1CA Exynos990 aos nossos binários/APEX: gates 5.4/5.10/5.15 no loader, gate5.4 no netd, programas ingress/egress 4.19 habilitados para API37 e dois consumidores opcionais de ring buffer desativados. Preservados loaders reais, init/handshake, netd, DNS, BPF maps/firewall e APKs internos. APEX reconstruído com metadados originais e re-assinado corretamente (AVB + APKv3), reproduzido duas vezes com hash idêntico. Instalado no manifesto/árvores preparadas dos quatro targets, com hashes fechados e checagem de imagem. Sete testes novos e 20 regressões passaram; SELinux compilou nos quatro. Sem flash, boot/DTBO/vendor novos ou validação física. [Relatório](QuantumROM/patches/coloros/diagnostics/android17-network-bpf-2026-10-29.md).

## 29/10/2026 — novo boot: espera do TEE Samsung

Duas tentativas montaram as partições, compilaram/carregaram SELinux e ativaram o bootstrap APEX/VNDK30, mas pararam em post-fs: tzdaemon sai com código1 e init espera vendor.tzdaemon Ready. Ainda não alcança o fluxo de rede/BPF. Conferidos MD do amigo (sem patch TEE explícito), dependências/namespaces em raiz isolada e permissões principais via consulta offline da política. Causa interna ainda desconhecida; nenhuma desativação de TEE/SELinux, flash ou mudança de kernel. Preparado vendor separado com logs kmsg/full para próximo teste; não faz parte do build normal. Trabalho pausado a pedido do usuário. [Evidências e retomada](QuantumROM/patches/coloros/diagnostics/android17-tee-boot-2026-10-29.md).

## 30/10/2026 — causa do bloqueio TEE identificada

Logcat persistente revelou tzdaemon: Can't open /dev/tzdev: Permission denied. Ueventd17 não carregava /vendor/ueventd.rc; o import canônico /vendor/etc/ueventd.rc não existia, deixando dispositivos com permissões padrão0600/root. Integrado import das regras Samsung por target, com validação/idempotência/metadados e checagem das imagens; aplicado nos quatro targets. Treze testes de boot/SELinux/mídia/OMX passaram. Vendor x1s de teste mantém logger v4; produção recebe só o import, sem permissive ou mudança de kernel. Boot físico com o fix ainda pendente. [Relatório](QuantumROM/patches/coloros/diagnostics/android17-tee-boot-2026-10-29.md).


### 30/10/2026 — avanço real no boot Android 17

O teste confirmou o fix do import ueventd: TEE Samsung fica Ready, init avança e APEX/compilação iniciam. Próximo bloqueio encontrado nos tombstones: SurfaceFlinger aborta por mapper ausente. Integrado patch mínimo de libui (32/64 bits) permitindo tentar os mappers HIDL 3/2 existentes, preservando preferência por 5/4 e validação de carregamento. Teste automatizado passou; system de diagnóstico em construção e boot físico pendente. Detalhes em `QuantumROM/patches/coloros/diagnostics/android17-tee-boot-2026-10-29.md`.

Imagem gráfica x1s validada: `out/diagnostics/x1s/graphics-boot/system.img`, SHA256 `886f359ad8a09ab1cf34fcda0552bd1cd6339c0ee65ccf33ace875c1ee49c114`. Flashear somente system mantendo o vendor do último teste. Integridade, labels e hashes internos passaram; boot físico pendente.


### 30/10/2026 — segundo ajuste gráfico Android 17

A imagem anterior estava corretamente flasheada, mas não cobria uma cópia do mapper incorporada pelo compilador em GraphicBuffer. O patch agora cobre também esse caminho e a pré-carga (cinco sites em 32/64 bits). Restaurado o label específico de `/dev/ion`, removido do platform file_contexts da base nova; o log mostrou o HAL bloqueado pelo label genérico. Sem novas permissões ou permissive. Dois testes passaram e a política completa compilou. Novas imagens diagnósticas system/vendor em `out/diagnostics/x1s/graphics-boot-v2`; validação final e teste físico pendentes. Detalhes no MD de TEE/boot.

Gráficos v2 prontos: `out/diagnostics/x1s/graphics-boot-v2/system.img` e `vendor.img`. Integridade EROFS, labels e arquivos internos validados; tamanhos iguais às partições atuais confirmados por ADB. Flashear ambos, mantendo product. Boot físico pendente.


### 31/10/2026 — reinício na bootanimation: metadados clatd

Corrigido o empacotamento do APEX tethering: o extrator removia setuid/setgid, deixando clatd 0755 em vez de 06755 e causando abort de system_server/ClatCoordinator, seguido de reboot pelo BootMonitor. O produtor preserva e verifica os modos de todos os arquivos e o payload corrigido já está no build dos quatro targets, com hashes e assinaturas atualizados. Sete testes passaram. SHA256 do novo APEX: `61f9ffe8e175793f1c3c75347cd5c255060b4ae26ea7be76de1abbf527f6d42a`. Nenhuma imagem de partição foi gerada nesta etapa. Rebuild normal e flash de system são suficientes para aplicar esse fix; boot físico pendente.


## 31/10/2026 — boot confirmado, geometria da barra e teste de fluidez

O usuário confirmou boot, digital e reconhecimento facial após o fix clatd. A barra tinha bateria/sinal deslocados: o donor fornecia largura estável 1272 para painel nativo 1440. A SystemUI classificava o furo central como direito e aplicava padding de 715 pixels. O teste com recursos estáveis 1440×3200 reduziu o padding a 95 e o usuário confirmou a posição correta.

Integrado RRO estático ColorOSExynosDisplayCompat em my_product/overlay, prioridade 1001, com somente os dois inteiros config_stableDeviceDisplayWidth/Height. x1s/y2s/z3s usam 1440×3200; r8s usa 1080×2400. Também corrigido screenwidth no XML de troca de resolução para a largura nativa. Não altera escolha de resolução/taxa, calibração biométrica nem display-manager-state em /data. Idmap com policy product passou no aparelho sem ignorar overlayable. A reaplicação dos patches foi testada nos quatro targets.

Para fluidez, Launcher, SystemUI, Ajustes e Chamadas foram compilados com ART speed no aparelho; os quatro confirmaram status speed/reason cmdline. Esse cache fica em /data e não equivale a um payload compilado portátil na imagem. Aparelho estava em QHD/60 Hz; Full HD/120 Hz ainda precisa de comparação. Não foram removidas proteções térmicas nem alterados clocks.

O log mostrava spam de SchedAssist com fd UX inválido e buscas de URCC inexistente. Patches 32/64 bits agora silenciam somente o log desse fd (mantendo retorno -1 e ioctl válido) e retornam o erro -1 já usado pelo getter URCC ausente. Hashes/opcodes/base desconhecida são validados. Teste nativo confirma o limite das alterações. Uma captura de 35 segundos após recarga não mostrou o spam SchedAssist nem “Urcc is not declared”; houve duas mensagens do chamador UAH na inicialização. A carga não é equivalente à captura anterior: isso não prova ganho de FPS.

As quatro bibliotecas estão no manifesto comum e no stage x1s, além do teste temporário por bind em /dev/coloros17-ui-native. Após recarga dos zygotes, o usuário relatou tela preta. Reiniciado vendor.hwcomposer-2-3 a pedido; serviços window/overlay voltaram. Reaplicados os overlays fabricados de teste, perdidos na recarga. Confirmação visual e teste de fluidez ainda pendentes. Houve um crash de com.oplus.gesture antes do desbloqueio por acesso a armazenamento CE; não foi tratado como crash de system_server nem desativado o recurso sem reprodução após PIN.

Não foram geradas imagens de partição nesta etapa. Para distribuir geometria e bibliotecas, o próximo build precisa de system e product novos; vendor não foi alterado nesta etapa. Evidências desta sessão: out/logs/x1s/android17-ui-2026-10-31.


### 31/10/2026 — Full HD: densidade e seleção pelo menu

Usuário confirmou que a tela voltou, mas Full HD/taxa alta deixava a interface enorme e ainda havia engasgos nas animações sobrepostas. ADB confirmou modo físico 1080×2400 a 120 Hz, porém densidade 560 e ausência de override: a frequência estava correta, a escala não. Teste inicial com 480; valor final x1s corrigido para Full HD 420 / QHD 560, preservando o mesmo tamanho lógico entre as duas resoluções.

O patch de OplusResolutionSwitchImpl agora chama resetDensityIfNeed depois de updateResolutionId no caminho setResolution. Reutiliza o cálculo e aplicação existentes; preserva os demais patches de resolução, toque e modos. As propriedades ro.density.screenzoom.fdh/qdh recebem cinco níveis proporcionais ao perfil de cada target, com default no índice 2, substituindo as listas inconsistentes do donor. r8s continua Full HD fixo. DEX reconstruído da firmware original: SHA256 92aa7be62b653802f37f264d19916163e843e577f3e8f99debf28b5505dbaade. A comparação de classes mostrou a alteração de resolução e somente a normalização adicional de um campo boolean false para seu default implícito em OplusTsaService; sem mudança funcional nesse serviço.

Novo teste test_resolution_density.py cobre os quatro perfis, níveis de zoom, reaplicação e montagem do DEX desde a base original com validação de hash. O primeiro teste encontrou diferença entre o hash de uma montagem de cache e o produzido desde a base; o manifesto passou a fixar a saída real do build. Resultado final registrado em density-tests.log. A árvore preparada x1s recebe o JAR e bringup novos, mantendo os outros DEX. A firmware original permanece intacta.

AssistantScreen estava em /my_stock/app/AssistantScreen nesta base, enquanto o debloat só o listava em my_bigball. Em captura de aproximadamente nove segundos, gerou 609 avisos HWUI de retângulo fora da tela e apareceu com 62,9% de CPU em um snapshot. Force-stop sozinho não bastou: o processo voltou. Desativado temporariamente para o usuário 0, sem apagar dados; para restaurar: adb shell pm enable --user 0 com.coloros.assistantscreen. Adicionado também my_stock/app/AssistantScreen à lista de debloat, preservando a regra antiga. Depois de desativar, a captura seguinte não teve esses avisos, mas isso não mede ganho de FPS.

No aparelho estão ativos Full HD/420 dpi, o teste sem AssistantScreen e animationBlurrySwitch=0. O novo JAR de densidade ainda NÃO foi carregado por bind no aparelho: requer recarga de framework ou flash da próxima build, seguido de teste QHD → Full HD pelo menu. Não considerar a correção permanente fisicamente validada apenas pelo wm density temporário.

As capturas de trace ficaram em out/logs/x1s/android17-ui-2026-10-31. Ainda não houve reprodução confirmada pelo usuário dentro da janela de trace; os eventos observados não permitem atribuir a causa das animações paralelas. Temperatura normal (AP 33,5 °C e thermal status 0). Não foram encurtadas animações, alterados clocks ou removidas proteções térmicas. Nenhuma imagem de partição foi gerada; próxima build deve atualizar system e product.

Validação final desta etapa: 2 testes de densidade/DEX, 2 de geometria, 4 de debloat e 31 testes de regressão em test_patches.py passaram. A confirmação física de QHD → Full HD com o framework novo e a reprodução das animações paralelas continuam pendentes.


### Animações paralelas: teste Vulkan pendente

Após o usuário responder pronto, coletados os gfxinfo recentes: Chamadas registrava 96 quadros e 68 janky desde o início das estatísticas; Ajustes 23 e 4. São amostras acumuladas, não uma comparação A/B controlada. Launcher reporta zero no contador agregado: não usar os percentis 4950 ms desse contador como medida válida. Os três renderizavam em Skia/OpenGL; Chamadas continua ART speed/cmdline. Logs também mostram adiamento de resume até fim da animação de recentes, que pode ocorrer normalmente em gestos; não foi tratado como causa comprovada.

Teste temporário: debug.hwui.renderer=skiavk e reabertura de Launcher/Ajustes/Chamadas, sem reiniciar framework. Launcher confirmou Pipeline=Skia (Vulkan). Sem integração permanente desse teste até avaliação visual. Captura circular atrace iniciada com buffer 32768 KB e tags dos quatro apps; desta vez permanece ativa até a resposta do usuário. Na retomada, encerrar imediatamente com o comando em vulkan-test-state.json, guardar o trace e capturar gfxinfo dos apps. Se regredir, limpar a propriedade e reabrir os três apps. A densidade permanente está no build, mas o framework novo ainda não foi carregado no aparelho; não confundir wm density 420 com validação do menu.


## 31/10/2026 — revisão dos patches Mystic após teste Vulkan

Usuário informou que Vulkan ainda engasga. Trace encerrado, salvo temporariamente em /tmp/coloros17-ui/vulkan-animations.atrace (278 MB). Chamadas confirmou Skia/Vulkan, 130 quadros acumulados/92 janky (70,77%), comparável em ordem de grandeza aos 96/68 da amostra anterior, mas sem controle de sequência/tempo. Não resolveu visualmente. Propriedade debug.hwui.renderer limpa e três apps reiniciados, voltando ao backend original. Nenhum patch Vulkan acrescentado ao build.

Revisados diretamente tools/porting/pipeline.py, vendors/oplus.py e patches/all/17/product.prop e rw-system.sh no repo local /mnt/caddy/coisas_do_miguel/Port/mysticgsi. Não há pasta patches/37/coloros nesse checkout; perfil ColorOS mais recente disponível é 36. Isso impede atribuir automaticamente todos os efeitos da imagem à versão atual do checkout.

Mystic injeta offsets SF/app -1 em product, limpa overrides early/high-fps, remove libdolphin.so e altera uma instrução em liboplusbindermonitor. A alteração do monitor troca tamanho de alocação 0x40 para 0x38 em OplusBinderMonitor::isMonitorEnabled; o próprio código da Mystic diz que a finalidade não é mais conhecida. Padrão alterado está presente na base usada. Não revertido sem evidência de incompatibilidade, porque monitor não é caminho de animação demonstrado. O dump tmp/coloros/images disponível tem biblioteca diferente em tamanho/hash da base FW atual; não transplantar essa biblioteca por aparência.

Offsets Samsung stock no vendor são 0/0, efetivos no aparelho -1/-1 por override Mystic/product. Já debug.sf.disable_backpressure=1 existe na stock e não foi atribuído à Mystic. O fallback OpenGL no rw-system é condicionado a PowerVR/MSM8917/8937/8940 e não corresponde a Exynos990/Mali. SurfaceFlinger utiliza PhaseOffsets neste runtime (propriedade de escolha WorkDuration ausente); no snapshot idle o painel era 120 Hz, renderRate 60 e janelas de trabalho 16,67 ms. Isso sozinho não prova limitação das animações a 60 Hz nem justifica inventar offsets.

Framestats Vulkan de Chamadas (105 registros válidos): medianas aproximadas despacho 3,94 ms, UI 2,12 ms, espera Sync 0,70 ms, emissão draw 6,23 ms, cauda GPU 12,05 ms e quadro completo 54,37 ms. Cauda GPU medida relativamente a SwapBuffersCompleted, não tempo exclusivo de execução da GPU. Percentis GPU 4950 ms do dump não são valores utilizáveis. Launcher tem contador agregado zero, porém 113 registros individuais: mediana total 5,57 ms. Há trabalho/espera variável na fila; causa específica permanece aberta. Não interpretar spans de centenas de segundos da reconstrução ingênua do atrace longo como travamentos reais: faltam limites de seções no buffer circular.

Nova captura circular com renderer original e buffer 16384 KB ativa; sampler somente leitura em /sys/kernel/gpu e locks DVFS, 100 amostras com 0,5 s, limitado a cerca de 50 s. Usuário solicitado a reproduzir e responder pronto. Encerrar trace imediatamente na retomada; instruções e sessão em out/logs/x1s/android17-ui-2026-10-31/mystic-review-test-state.json. Sem mudança de clock, kernel, HAL ou política térmica. Não há evidência suficiente para afirmar que Mystic é culpada.


### Reprodução com OpenGL: shader e amostragem fora da janela

Trace encerrado ao pronto em /tmp/coloros17-ui/parallel-original-final.atrace (264 MB). Quadros capturados de Chamadas situam-se em uptime 3588,44–3594,10 s; o sampler limitado havia terminado em 3529,01 s, antes da reprodução. Seus valores GPU zero NÃO comprovam falha do driver, clock baixo ou GPU inativa durante animações. Nova rodada deve iniciar sampler só ao final do turno e mantê-lo até o pronto (com limite máximo).

A janela 3586–3596 s mostra Chamadas compilando shader por cerca de 414 ms, incluindo driver_link_program 271 ms; draw total de um frame cerca de 762 ms, com UI em postAndWait por 518 ms. Há também compressão de snapshot do OplusQuickStartCaptureController por 652 ms em thread de system_server; não inferir bloqueio da thread principal a partir desse slice de worker. Ajustes tem cold start e layout pesado. Aguardas runnable de UI chegam a 20–31 ms, porém máscara de CPUs lida depois em background não comprova afinidade errada durante a animação.

Os caches estão presentes: /data/user_de/0/com.android.contacts/cache/com.android.opengl.shaders_cache e com.android.skia.shaders_cache; equivalentes de Ajustes também presentes. O framework usa cache DE nesta base, não code_cache. Arquivos 0400 são substituídos pelo mecanismo existente; não aplicar chmod por aparência. Processos de Chamadas/Ajustes/Launcher ainda vivos, sem always_finish_activities configurado. Não foi identificado patch da Mystic desativando esse cache.

Amostra acumulada OpenGL: Chamadas 28 quadros/22 janky; Ajustes 5/4. Testes de backend haviam reiniciado esses apps, portanto esses dados incluem cold start. Próxima rodada reutiliza os mesmos processos e limpa só contadores gfxinfo. Nenhum novo patch permanente de desempenho aplicado a partir dessa hipótese.


## 31/10/2026 — teste reversível sem overrides Mystic de VSync/Binder

Usuário relatou “quase lá” com cache aquecido, mas ainda lagado, e pediu desativar patches Mystic ou agir sobre eles. Trace e sampler encerrados imediatamente ao responder; originais em /tmp/coloros17-ui/warm-final.atrace e warm-gpu-samples.txt. Mesmos PIDs antes/depois (Launcher 23584, Chamadas 25624, Ajustes 25881): não houve novo cold start nessa rodada. Chamadas teve 247 quadros acumulados desde reset, 135 janky (54,66%); mediana 44 ms. Não converter essa amostra em FPS garantido.

Agora o sampler pegou a interação: 114 amostras, 68 com clock GPU não zero, clocks lidos 156/260/377/455/702 MHz e várias amostras de utilização 96–99% em 377 MHz. Max permitido 800 MHz, sem locks DVFS ativos no snapshot, sensor GPU 40 °C. Leitura instantânea de frequência versus utilização acumulada não prova underclock ou falha do governor; clocks não foram alterados.

Teste solicitado feito exclusivamente em RAM: offsets ro.surface_flinger.vsync_event_phase_offset_ns e vsync_sf_event_phase_offset_ns alterados de -1 para 0, correspondendo à configuração Samsung stock. Ferramenta resetprop extraída do APK local /mnt/caddy/coisas_do_miguel/Mods S20/Magisk-v30.7.apk; executada como applet, sem instalar Magisk, iniciar daemon, modificar boot ou persistir propriedades. Binário em /data/local/tmp/coloros17-tools/magisk.

Também revertida exatamente a instrução da Mystic em liboplusbindermonitor arm64, offset 0x567c, mov w0,#0x38 → mov w0,#0x40 (00078052 → 00088052). Validados base SHA 99973332d2ac9bf31fc9bc19c95022559756f68a3ac1deb44fe2183b204e9b0c, saída 7bb922ba6c350f0e57af2e46aaa01382a3fc40e96277b6ec1bb66158a372005e, tamanho e somente um byte diferente. Cópia root/root 0644 system_lib_file em /dev/coloros17-mystic-ab/liboplusbindermonitor.so, bind sobre /system_ext/lib64/liboplusbindermonitor.so. Originais/partições intactos. O monitor não apareceu mapeado no system_server novo no momento da consulta; não afirmar que essa parte do teste atua em todos os processos.

Reiniciado vendor.hwcomposer-2-3 para recarregar gráficos; SurfaceFlinger e framework voltaram, system_server PID 2502, window/overlay presentes. Recriados overlays fabricados 1440×3200 da barra e reposta densidade 420. Compositor pós-reload reportou em modo 120 Hz app phase 2 ms/SF phase 1 ms, app duration 15,67 ms/SF duration 7,33 ms. Antes havia snapshot em renderRate 60 Hz com fases -1 ns e durações 16,67 ms; snapshots em taxas de render diferentes não provam melhora por si só.

Sem trace ativo, sem novos locks de clock, sem remoção de patches essenciais de boot/VNDK/SELinux/rede. Não restaurada libdolphin de outra versão. Nenhuma reversão Mystic permanente no build até comparação visual. Após PIN, usuário deve repetir transições e conferir barra/brilho/biometria. Rollback exato e hashes em mystic-ab-state.json: desmontar somente esse bind, restaurar os dois ro props para -1 com resetprop -n e recarregar gráficos; reboot também desfaz o teste RAM. A recarga perde overlays fabricados; reaplicá-los para preservar a barra.


### 31/10/2026 — teste sem overrides Mystic rejeitado e revertido

Usuário relatou flickering ao abrir apps e ao chegar notificações. Revertido imediatamente o conjunto experimental: desmontado somente o bind de liboplusbindermonitor e confirmado SHA original 99973332d2ac9bf31fc9bc19c95022559756f68a3ac1deb44fe2183b204e9b0c; ambos os offsets de VSync voltaram a -1, lidos de volta. Reiniciado vendor.hwcomposer-2-3 para descarregar a configuração experimental. Não inserir essa reversão da Mystic no build. O teste alterou dois componentes e não isola qual deles explica as piscadas; comprova regressão do conjunto, não que todos os patches Mystic sejam necessários. Preservar configuração anterior e confirmar imagem antes de nova investigação.


### 31/10/2026 — Novo transporte de áudio Bluetooth para a ColorOS17

O fix legado estava presente, mas a stack nova não publica .a2dp_ctrl e não encontrava HAL de áudio compatível. Foi integrado candidato com provedor padrão HIDL2.0, módulo de saída bluetooth, dependências privadas e FMQ do VNDK34, mantendo o HAL físico/áudio principal Samsung e bibliotecas globais. Aplica nos quatro targets; árvore preparada x1s atualizada, reaplicação sem mudanças. 37 testes passaram. Requer novas vendor e product; nenhuma imagem foi gerada. Som no fone ainda pendente.

O teste em RAM confirmou o registro e uma sessão A2DP aceita. Contudo, recarregar hwservicemanager invalidou a conexão HIDL do Gatekeeper e provocou PIN recusado/wallpaper ausente. Todos os binds foram retirados; reboot completo recuperou o aparelho, confirmado pelo usuário. Não houve alteração/remoção de credenciais ou cadastros. Não repetir essa recarga ao vivo. Detalhes: QuantumROM/patches/coloros/diagnostics/android17-bluetooth-2026-10-31.md.


## 31/10/2026 — attach LTE ausente na ColorOS 17

Corrigido no patch comum de telephony-common.jar o retorno prematuro causado por IOplusDataProfileManager.DEFAULT vazio. A seleção AOSP do APN inicial agora roda quando não existe implementação OEM real; SMS e extensões reais preservados. Comum aos quatro targets. Teste RAM no x1s: 4G e IMS registrados, confirmado pelo usuário e SIP 200 OK. Recarga gráfica recuperada pelo composer; credenciais intactas. Chamadas/VoWiFi/dual-SIM ainda pendentes nesta rodada. Relatório: QuantumROM/patches/coloros/diagnostics/android17-radio-attach-2026-10-31.md. Nenhuma imagem gerada por esta alteração.

Validação do attach LTE: 35 testes passaram (31 gerais e 4 IMS). JAR do cache preparado x1s atualizado atomicamente, sem alterar a firmware original. O teste no aparelho permanece em RAM; sem reempacotamento de imagens.

Atualização da validação: usuário confirmou chamadas de saída VoLTE/VoWiFi. Ciclo controlado de modo avião por 15 s recuperou LTE e REGISTER IMS 200 OK automaticamente, sem reiniciar Android. Ainda sem validação de áudio audível, recebimento, dual-SIM ou perda prolongada de cobertura.


## 31/10/2026 — atualização de boot e DTBO

Substituídos boot.img e dtbo.img dos templates de ZIP x1s, y2s e z3s pelos artefatos de ~/android_kernel_samsung_exynos990/build/out. DTBOs de x1slte e y2slte copiados como dtbo_lte.img; seleção LTE já existente no instalador preservada. O r8s permaneceu intacto. Headers e SHA256 conferidos; sem flash ou teste de boot. Backup e hashes: out/backups/kernel-targets-20261031-204450/manifest.json. ZIPs já gerados não são alterados; gerar novamente para incluir os arquivos novos.


## 31/10/2026 — câmera/APS na ColorOS 17

Foto salvou duas imagens em 4032×3024, mas usuário precisou clicar várias vezes: disparo continua intermitente. Nenhum novo fix promovido. APS stock investigado: motor do donor disponível depende de gralloc/mapper e câmera offline Qualcomm ausentes no serviço Samsung. JNI presente não basta; APS não foi ativado nem declarado restaurado. Relatórios: diagnostics/camera-android17-2026-10-31.md e camera-aps-2026-10-31.md na pasta de patches ColorOS.


## 03/11/2026 — carregamento e investigação de vídeos

Usuário confirmou melhora ao reativar AFC Samsung (afc_disable=0). Novo coloros_charging_compat.rc garante essa preferência no boot para todos os targets; limites elétricos/térmicos continuam no driver. Guarda de HAL Oplus ausente integrada ao oplus-services.jar, validada por100 consultas isoladas e3 testes de framework. Vídeo: preservação da geração da Surface no disconnect integrada nas duas arquiteturas; original reproduziu a falha e sondas ARM32/64 passaram com o candidato;1 teste de integridade/idempotência passou. Validação dos apps reais e trigger init após flash ainda pendentes. Wallpaper afeta estáticos e dinâmicos, sem fix até agora. Demais diagnósticos pausados a pedido do usuário. Detalhes: QuantumROM/patches/coloros/diagnostics/three-bugs-2026-11-03.md.


## 03/11/2026 — redução de spam na ColorOS 17

Guarda da extensão de vibrador Oplus, consultas COTA sem bloqueio infinito e remoção
do init do cliente GNSS Qualcomm incompatível, no manifesto comum dos quatro targets.
Diagnóstico e limites em `QuantumROM/patches/coloros/diagnostics/log-spam-2026-11-03.md`.
Os fixes de carregamento, vídeo e wallpaper foram preservados.


## 03/11/2026 — otimizações de RAM aprovadas

Pré-carregamento especulativo Oplus desativado e cache efetivo limitado a 48 processos no framework comum de x1s/y2s/z3s/r8s. O limite respeita opções menores e é recalculado após políticas OEM. Usuário confirmou desempenho melhor e 5,8 GB na interface. Detalhes, hashes e testes em `QuantumROM/patches/coloros/diagnostics/log-spam-2026-11-03.md`.

## Atualização r8s — 10/11/2026 (substitui o estado histórico do template)

A inspeção dos arquivos atuais confirmou GMKernel/r8s, não y2s. Foram corrigidos os seletores DT e, posteriormente, reutilizado o kernel da build Artisan 4.0.2 de 09/11 com V3 ativo, mantendo o ramdisk da COS. Também foram adicionados o recorte calibrado, a correção P010 condicionada ao par Mali/gralloc e a política de multi-janelas r8s no Oplus, além de estender a transição do carregador offline aos quatro targets. O estudo completo desta rodada, com referências, hashes e pendências sem validação física, está em `QuantumROM/patches/coloros/diagnostics/r8s-artisan-transfer-2026-11-10.md`. As confirmações físicas históricas de x1s não certificam o r8s.
