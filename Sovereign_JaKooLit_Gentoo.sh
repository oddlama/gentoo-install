#!/bin/bash
# ==============================================================================
# SOVEREIGN GENTOO HYPRLAND PORT (Baseado no JaKooLit)
# ==============================================================================
# Este script e o pós-install oficial da Sovereign Edition.
# Ele prepara o ambiente Wayland/Hyprland, gerencia os repositorios GURU
# e instala os dotfiles do JaKooLit adaptados pro Gentoo.
# ==============================================================================

set -e # Para se houver erro critico

export CONFIG_PROTECT_MASK="/etc/portage"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

function print_step() {
    echo -e "\n${BLUE}[*] $1${NC}"
}

print_step "Iniciando a Portabilidade do JaKooLit para o Gentoo..."

# Garante que as pastas do Portage existam
mkdir -p /etc/portage/package.use
mkdir -p /etc/portage/package.accept_keywords

mkdir -p /etc/portage/package.mask

# 1. ATIVAR OS REPOSITORIOS E LAYMAN/ESELECT-REPO
print_step "Instalando gerenciador de repositorios (eselect-repository)..."
emerge --autounmask-continue --autounmask-write app-eselect/eselect-repository dev-vcs/git

print_step "Sincronizando arvore principal e adicionando Overlays..."
emaint sync -a || true
eselect repository enable guru || true
eselect repository enable hyproverlay || true
# Sincroniza os novos overlays
emaint sync -r guru || true
emaint sync -r hyproverlay || true

# 2. DEFINIR AS USE FLAGS OBRIGATÓRIAS E KEYWORDS
print_step "Injetando permissoes (USE Flags e ~amd64) pro ecossistema Hyprland..."

cat << 'EOF_USE' > /etc/portage/package.accept_keywords/jakoolit-hyprland
# Liberar pacotes de teste necessarios pro Hyprland
*/*::guru ~amd64
*/*::wayland-desktop ~amd64
gui-wm/hyprland ~amd64
gui-apps/waybar ~amd64
gui-apps/awww ~amd64
gui-apps/swaync ~amd64
EOF_USE

cat << 'EOF_USE2' > /etc/portage/package.use/jakoolit-hyprland
# Flags do ecossistema Wayland
gui-wm/hyprland wayland legacy-renderer
gui-apps/waybar tray network pulseaudio mpd
media-video/pipewire sound-server bluetooth dbus
x11-terms/kitty wayland
media-libs/libvpx postproc
sys-libs/zlib minizip
app-emulation/wine-staging vulkan dxvk
media-libs/libcanberra alsa
dev-qt/qtbase opengl wayland eglfs icu libproxy
dev-qt/qttools opengl
dev-qt/qtdeclarative opengl
kde-frameworks/kwindowsystem X
dev-qt/qt5compat qml icu
kde-frameworks/kconfig qml dbus
app-text/xmlto text
media-libs/libglvnd X
x11-libs/cairo X
dev-cpp/cairomm X
x11-libs/libxkbcommon X wayland
media-libs/freetype harfbuzz
net-wireless/wpa_supplicant dbus
sys-apps/systemd policykit
gui-libs/gtk4-layer-shell vala introspection
gui-libs/gtk wayland
media-libs/libshumate vala
x11-libs/pango X
x11-libs/gtk+ wayland
dev-cpp/gtkmm wayland X
EOF_USE2

# Licencas necessarias (ex: Steam, MS Fonts)
echo "games-util/steam-launcher Valve0x" >> /etc/portage/package.license
echo "media-fonts/corefonts MSttfEULA" >> /etc/portage/package.license

# 3. ATUALIZACAO DE SEGURANCA E RESOLUCAO DE BLOQUEIOS
print_step "Resolvendo dependencias e Dispatch-conf..."
# Aplica automaticamente mudancas nos arquivos de configuracao gerados pelo autounmask
echo "-5" | dispatch-conf || true

# 4. INSTALACAO DO CORE (Hyprland, Waybar, Rofi, Kitty, Network, Audio)
print_step "Compilando o Nucleo do Hyprland e Ferramentas Visuais..."
rm -f /etc/portage/package.use/zz-autounmask* || true

# Patch: Atualiza assinatura do awww que esta quebrado no repositorio GURU
rm -f /var/db/repos/guru/gui-apps/awww/Manifest || true
for ebuild_file in /var/db/repos/guru/gui-apps/awww/*.ebuild; do
    ebuild "$ebuild_file" manifest || true
done
emerge --autounmask-continue --autounmask-write --update --newuse \
    gui-wm/hyprland \
    gui-apps/waybar \
    gui-apps/rofi-wayland \
    x11-terms/kitty \
    gui-apps/awww \
    gui-apps/swaync \
    media-sound/pamixer \
    gui-apps/wl-clipboard \
    gui-apps/grim \
    gui-apps/slurp \
    media-sound/pavucontrol \
    app-misc/jq \
    kde-plasma/polkit-kde-agent \
    sys-process/btop \
    net-misc/networkmanager \
    gnome-extra/nm-applet \
    media-video/pipewire \
    media-video/wireplumber

# Habilitando servicos do Sistema e do Usuario (Network e Audio)
systemctl enable NetworkManager || true
# Habilita PipeWire globalmente para todos os usuarios (resolve o PC mudo)
systemctl --global enable pipewire pipewire-pulse wireplumber || true

# Aplica eventuais autounmask que rolaram acima
echo "-5" | dispatch-conf || true

# 5. ARSENAL DO USUARIO E FLATPAK
print_step "Instalando arsenal nativo (Firefox, Pip, Curl)..."
emerge --autounmask-continue --autounmask-write net-misc/curl dev-python/pip www-client/firefox

print_step "Habilitando Flatpak e instalando apps fechados/games..."
emerge --autounmask-continue --autounmask-write sys-apps/flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Executa em background/nao para o script se der erro no flatpak
flatpak install -y flathub com.discordapp.Discord || true
flatpak install -y flathub com.valvesoftware.Steam || true
flatpak install -y flathub org.winehq.Wine || true

# 6. DOWNLOAD E APLICACAO DOS DOTFILES
print_step "Baixando e instalando os Dotfiles do JaKooLit..."
TARGET_USER=$(grep -E ":1000:" /etc/passwd | cut -d: -f1 || true)
if [ -z "$TARGET_USER" ]; then
    TARGET_USER="root"
    USER_HOME="/root"
else
    USER_HOME=$(eval echo ~$TARGET_USER)
fi

mkdir -p /tmp/jakoolit-dots
cd /tmp/jakoolit-dots
git clone https://github.com/JaKooLit/Hyprland-Dots.git .

# Move configs
mkdir -p "$USER_HOME/.config"
cp -r config/hypr "$USER_HOME/.config/"
cp -r config/waybar "$USER_HOME/.config/"
cp -r config/rofi "$USER_HOME/.config/"
cp -r config/swaync "$USER_HOME/.config/"
cp -r config/kitty "$USER_HOME/.config/"

# Ajusta permissoes
chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config"

# --- Patch Sovereign ---
# Corrige o Rofi quebrando com wallpaper com espaco
sed -i 's/pkill rofi/pkill rofi; sleep 0.2/g' "$USER_HOME/.config/hypr/UserScripts/WallpaperSelect.sh" 2>/dev/null || true

# Cria symlink do awww para swww para manter compatibilidade com os scripts do JaKooLit
ln -sf /usr/bin/awww /usr/bin/swww || true
ln -sf /usr/bin/awww-daemon /usr/bin/swww-daemon || true

print_step "Instalacao Concluida com Sucesso!"
echo -e "${GREEN}O ecossistema JaKooLit Gentoo esta pronto.${NC}"
echo "Se voce esta num chroot, digite 'exit', de reboot, e logue no sistema."
echo "No terminal, digite 'Hyprland' para iniciar a interface!"
