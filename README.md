# gentoo-install — Sovereign Edition

> **Fork de [oddlama/gentoo-install](https://github.com/oddlama/gentoo-install)**  
> Refatorado e blindado por [ViniciusPHDU20](https://github.com/ViniciusPHDU20)

A **Sovereign Edition** transforma a experiência bruta de instalação do Gentoo Linux. Ao invés de lutar contra o `make.conf` e horas de configurações manuais, este instalador analisa seu hardware, define as otimizações perfeitas e oferece uma interface gráfica (TUI) 100% traduzida para o Português para você "forjar o seu próprio sistema limpo".

Além da base sólida, ele inclui um script de pós-instalação cirúrgico para implantar o **Hyprland** usando os *dotfiles* premium do **JaKooLit**.

---

## ✨ Features Exclusivas da Sovereign Edition

| Recurso | Descrição Técnica |
|---------|-------------------|
| **Auto-Detecção de Hardware** | O motor `hardware_detect.sh` lê seu processador, memória e GPU para definir automaticamente `CFLAGS` (`-march=native`), `MAKEOPTS` e `VIDEO_CARDS`. Tudo é injetado no `make.conf` antes do primeiro pacote ser compilado. |
| **Interface 100% Traduzida** | Todos os 30 menus da TUI de configuração possuem descrições detalhadas em **Português**, explicando de forma didática o que é F2FS, LUKS, ZFS, UEFI, e Swap. |
| **zRAM Nativo (Swap em RAM)** | Integração transparente com `zram-generator`. Protege contra travamentos (OOM) em compilações pesadas criando um swap ultrarrápido comprimido via `zstd`, com *tuning* de kernel agressivo via `sysctl`. |
| **Sovereign Profiles** | Escolha entre o perfil **Minimal** (apenas a base do sistema) ou **JaKooLit** (força o Systemd e prepara as dependências Wayland/Core). |
| **F2FS para NVMe** | Suporte nativo ao F2FS. Se detectado um SSD NVMe, o instalador sugere este sistema de arquivos projetado especificamente para memória flash. |
| **Pós-Instalação Automática** | Script `Sovereign_JaKooLit_Gentoo.sh` pronto para uso que converte a base instalada em um ambiente Hyprland deslumbrante e otimizado. |

---

## 🏗️ Arquitetura do Projeto

```text
gentoo-install/                 ← Este repositório
├─ configure                    ← Motor TUI principal (gera o gentoo.conf)
├─ install                      ← Instalador base do Gentoo (lê o gentoo.conf)
├─ hardware_detect.sh           ← Módulo de injeção de flags e scan de hardware
├─ gentoo.conf.example          ← Template referencial de configuração
├─ scripts/                     ← Utilitários internos de chroot e compilação
└─ Sovereign_JaKooLit_Gentoo.sh ← Pós-instalação (Hyprland + Dotfiles)
```

---

## 🚀 Como Usar

### 1. Boot em um Live Environment

Recomenda-se o **Arch Linux ISO** por já conter ferramentas modernas e conexão fácil via `iwctl`.

```bash
pacman -Sy git
git clone https://github.com/ViniciusPHDU20/gentoo-install
cd gentoo-install
```

### 2. Configuração (Sovereign TUI)

```bash
./configure
```
- Escolha **Português**.
- Veja o **Resumo do Hardware** (o sistema detectará sua GPU e CPU).
- No menu de perfis, escolha **JaKooLit** (ou Minimal).
- Configure seu ZRAM (Recomendado 50%).
- Passe pelos menus (partição, locale, rede) e salve ao final. O arquivo gerado será o `gentoo.conf`.

### 3. Instalação da Base

```bash
./install
```
O script fará o particionamento, download do `stage3`, aplicará as flags no `make.conf` e compilará o núcleo do Gentoo (incluindo o Kernel). Não requer supervisão.

Ao finalizar, você verá a mensagem de sucesso. **Dê reboot e logue como root no seu novo Gentoo.**

### 4. Pós-Instalação: O Ambiente Hyprland

Com o sistema base bootado, garantido e conectado à internet, entre na pasta do repositório novamente (agora dentro do seu Gentoo instalado) e execute:

```bash
cd gentoo-install
bash Sovereign_JaKooLit_Gentoo.sh
```

**O que o script faz:**
1. Ativa os repositórios `guru` e `wayland-desktop`.
2. Habilita pacotes de testes (`~amd64`) cirurgicamente apenas para os componentes visuais.
3. Compila o Waybar, Hyprland, Rofi, SWWW, Kitty, entre outros.
4. Habilita o Flatpak e baixa os softwares fechados (Steam, Discord, Wine).
5. Clona o repositório oficial do JaKooLit, injeta patchs de correção e aplica na sua `~/.config`.

---

## 🧠 Detalhes Técnicos Adicionais

### F2FS em NVMe
Seu SSD NVMe sofre menos desgaste (*write amplification*) e entrega maior *throughput* com F2FS do que com ext4/btrfs.
*Nota:* Garanta que o pacote `f2fs-tools` esteja instalado no Live USB antes de iniciar (`pacman -S f2fs-tools`).

### ZRAM vs Swap em Disco
A Sovereign Edition não substitui o swap em disco, ela o **complementa**.
O `swappiness` é configurado para `180`, o que significa que o kernel tentará ao máximo manter os arquivos inativos compactados na RAM via ZRAM (velocidades de ~10GB/s). Só quando a RAM física acabar é que ele paginará para o SSD/HD.

---

## 🆘 Troubleshooting

### `cc1plus: out of memory` (Compilação Morta)
Se a compilação do Firefox ou do Node.js parar abruptamente com este erro, sua máquina ficou sem memória (inclusive o ZRAM esgotou).
**Solução:** Crie um swapfile de disco gigantesco temporariamente:
```bash
fallocate -l 16G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
emerge --resume
```

---

## 📚 Referências

- [Gentoo AMD64 Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64)
- [JaKooLit Hyprland Dotfiles](https://github.com/JaKooLit/Arch-Hyprland)
- [Projeto upstream (Base) — oddlama/gentoo-install](https://github.com/oddlama/gentoo-install)

---

## Licença

Este fork mantém a licença original do projeto upstream. Veja [LICENSE](LICENSE).
