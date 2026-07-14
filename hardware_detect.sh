#!/usr/bin/env bash
# =============================================================================
# hardware_detect.sh — Sovereign Edition
# =============================================================================
# Detecta automaticamente o hardware do usuário e gera um bloco otimizado
# de make.conf com:
#   - CFLAGS nativos para o CPU (-march=native)
#   - CPU_FLAGS_X86 (AVX2, AES-NI, etc.)
#   - MAKEOPTS baseado nos núcleos + RAM disponível
#   - VIDEO_CARDS para GPU (AMD / NVIDIA / Intel / múltiplas)
#   - USE flags mínimas recomendadas para o hardware detectado
#
# Uso:
#   bash hardware_detect.sh              → imprime na tela
#   bash hardware_detect.sh --apply      → aplica direto no /etc/portage/make.conf
#   bash hardware_detect.sh --chroot /mnt → aplica no make.conf de um chroot
# =============================================================================

set -euo pipefail

# --- Cores para output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

APPLY=false
CHROOT_PATH=""

for arg in "$@"; do
    case "$arg" in
        --apply)   APPLY=true ;;
        --chroot)  shift; CHROOT_PATH="$1" ;;
    esac
done

MAKE_CONF="${CHROOT_PATH}/etc/portage/make.conf"

echo -e "${BOLD}${CYAN}=== Sovereign Hardware Detector ===${NC}"
echo ""

# =============================================================================
# 1. CPU — flags nativas
# =============================================================================
echo -e "${YELLOW}[1/4] Detectando CPU...${NC}"

CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
CPU_CORES=$(nproc --all)
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | cut -d: -f2 | xargs)

echo -e "  CPU: ${GREEN}${CPU_MODEL}${NC}"
echo -e "  Núcleos: ${GREEN}${CPU_CORES}${NC}"
echo -e "  Vendor: ${GREEN}${CPU_VENDOR}${NC}"

# Detecção de -march nativa via GCC
MARCH_NATIVE=$(gcc -Q --help=target -march=native 2>/dev/null \
    | grep -m1 '\-march=' \
    | awk '{print $2}' \
    | tr -d '[:space:]') || MARCH_NATIVE="native"

echo -e "  -march: ${GREEN}${MARCH_NATIVE}${NC}"

# CPU_FLAGS_X86 via cpuid2cpuflags (se disponível) ou via /proc/cpuinfo
if command -v cpuid2cpuflags &>/dev/null; then
    CPU_FLAGS=$(cpuid2cpuflags | cut -d: -f2 | xargs)
else
    # Fallback: tradução manual das flags do /proc/cpuinfo
    PROC_FLAGS=$(grep -m1 'flags' /proc/cpuinfo | cut -d: -f2)
    CPU_FLAGS=""
    declare -A FLAG_MAP=(
        ["aes"]="aes"
        ["avx"]="avx"
        ["avx2"]="avx2"
        ["avx512f"]="avx512f"
        ["avx512dq"]="avx512dq"
        ["avx512bw"]="avx512bw"
        ["avx512vl"]="avx512vl"
        ["f16c"]="f16c"
        ["fma"]="fma3"
        ["mmx"]="mmx"
        ["mmxext"]="mmxext"
        ["pclmulqdq"]="pclmul"
        ["popcnt"]="popcnt"
        ["rdrand"]="rdrand"
        ["sha_ni"]="sha"
        ["sse"]="sse"
        ["sse2"]="sse2"
        ["sse3"]="sse3"
        ["sse4_1"]="sse4_1"
        ["sse4_2"]="sse4_2"
        ["ssse3"]="ssse3"
        ["vpclmulqdq"]="vpclmulqdq"
    )
    for proc_flag in "${!FLAG_MAP[@]}"; do
        if echo "$PROC_FLAGS" | grep -qw "$proc_flag"; then
            CPU_FLAGS+="${FLAG_MAP[$proc_flag]} "
        fi
    done
    CPU_FLAGS=$(echo "$CPU_FLAGS" | xargs | tr ' ' '\n' | sort | tr '\n' ' ' | xargs)
fi

echo -e "  CPU_FLAGS_X86: ${GREEN}${CPU_FLAGS}${NC}"

# =============================================================================
# 2. RAM — calcular MAKEOPTS seguro
# =============================================================================
echo -e "\n${YELLOW}[2/4] Detectando RAM...${NC}"

RAM_MB=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
echo -e "  RAM total: ${GREEN}${RAM_MB} MB${NC}"

# Regra: 1 job por 2GB de RAM (margem segura para Firefox/LLVM/Node.js)
# Pacotes pesados como Firefox, LLVM e Node.js consomem até 2-3GB por thread.
# Usar 2GB como base evita OOM mesmo nos piores casos.
JOBS_BY_RAM=$(( RAM_MB / 2000 ))
[[ $JOBS_BY_RAM -lt 1 ]] && JOBS_BY_RAM=1

# Nunca ultrapassar o número de núcleos físicos
JOBS=$(( CPU_CORES < JOBS_BY_RAM ? CPU_CORES : JOBS_BY_RAM ))

# load-average = 90% dos cores (mantém o sistema responsivo durante compilação)
LOAD_AVG=$(echo "scale=1; $CPU_CORES * 0.9" | bc)

# Aviso se RAM for menor que 8GB (compilação pode ser lenta/instável)
if [[ $RAM_MB -lt 8000 ]]; then
    echo -e "  ${RED}⚠ Menos de 8GB de RAM detectados. Recomendado criar swapfile de pelo menos 8GB antes de compilar pacotes grandes (Firefox, LLVM, Node.js).${NC}"
fi

echo -e "  Jobs calculados: ${GREEN}${JOBS}${NC} (fórmula: ${RAM_MB}MB ÷ 2000 = ${JOBS_BY_RAM}, limitado a ${CPU_CORES} cores)"
echo -e "  load-average: ${GREEN}${LOAD_AVG}${NC}"

# =============================================================================
# 3. GPU — detecção e VIDEO_CARDS
# =============================================================================
echo -e "\n${YELLOW}[3/4] Detectando GPU...${NC}"

GPU_INFO=$(lspci 2>/dev/null | grep -Ei '(VGA|3D|Display)' || echo "")

VIDEO_CARDS=""
GPU_USE_FLAGS=""
GPU_PACKAGES=""

if echo "$GPU_INFO" | grep -qi "nvidia"; then
    GPU_VENDOR="NVIDIA"
    VIDEO_CARDS="nvidia"
    GPU_USE_FLAGS="nvidia"
    GPU_PACKAGES="x11-drivers/nvidia-drivers"
    echo -e "  GPU: ${GREEN}NVIDIA detectada${NC}"
    echo -e "  Driver: ${GREEN}nvidia-drivers (proprietário)${NC}"
fi

if echo "$GPU_INFO" | grep -qi "amd\|radeon\|amdgpu"; then
    GPU_VENDOR="AMD"
    VIDEO_CARDS="${VIDEO_CARDS:+$VIDEO_CARDS }amdgpu radeonsi"
    GPU_USE_FLAGS="${GPU_USE_FLAGS:+$GPU_USE_FLAGS }vulkan"
    GPU_PACKAGES="${GPU_PACKAGES:+$GPU_PACKAGES }media-libs/mesa"
    echo -e "  GPU: ${GREEN}AMD detectada${NC}"
    echo -e "  Driver: ${GREEN}amdgpu + radeonsi (open-source, Vulkan nativo)${NC}"
fi

if echo "$GPU_INFO" | grep -qi "intel"; then
    GPU_VENDOR="Intel"
    VIDEO_CARDS="${VIDEO_CARDS:+$VIDEO_CARDS }intel i965"
    GPU_USE_FLAGS="${GPU_USE_FLAGS:+$GPU_USE_FLAGS }vaapi"
    GPU_PACKAGES="${GPU_PACKAGES:+$GPU_PACKAGES }media-libs/mesa"
    echo -e "  GPU: ${GREEN}Intel detectada${NC}"
    echo -e "  Driver: ${GREEN}i915/i965 (open-source)${NC}"
fi

# Híbrido (ex: Intel iGPU + NVIDIA dedicada)
if echo "$GPU_INFO" | grep -qi "nvidia" && echo "$GPU_INFO" | grep -qi "intel"; then
    echo -e "  ${YELLOW}⚠ Híbrido detectado (Intel iGPU + NVIDIA dGPU)${NC}"
    VIDEO_CARDS="intel i965 nvidia"
    GPU_USE_FLAGS="nvidia vaapi"
fi

if [[ -z "$VIDEO_CARDS" ]]; then
    VIDEO_CARDS="vesa"
    echo -e "  GPU: ${RED}Não detectada — usando vesa (fallback)${NC}"
fi

echo -e "  VIDEO_CARDS final: ${GREEN}\"${VIDEO_CARDS}\"${NC}"

# =============================================================================
# 4. Disco — tipo de storage
# =============================================================================
echo -e "\n${YELLOW}[4/4] Detectando tipo de disco...${NC}"

DISK_TYPE=""
ROOT_DEV=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')

if echo "$ROOT_DEV" | grep -q "nvme"; then
    DISK_TYPE="NVMe SSD"
    FS_RECOMENDADO="f2fs"
    echo -e "  Disco: ${GREEN}NVMe detectado → F2FS recomendado${NC}"
elif cat /sys/block/$(basename "$ROOT_DEV" 2>/dev/null)/queue/rotational 2>/dev/null | grep -q "0"; then
    DISK_TYPE="SSD SATA"
    FS_RECOMENDADO="ext4 ou btrfs"
    echo -e "  Disco: ${GREEN}SSD SATA detectado → ext4 ou btrfs recomendado${NC}"
else
    DISK_TYPE="HDD"
    FS_RECOMENDADO="ext4"
    echo -e "  Disco: ${YELLOW}HDD detectado → ext4 recomendado${NC}"
fi

# =============================================================================
# 5. Gerar bloco make.conf
# =============================================================================
echo -e "\n${BOLD}${CYAN}=== Bloco gerado para /etc/portage/make.conf ===${NC}\n"

MAKECONF_BLOCK="
# =============================================================
# Gerado automaticamente por hardware_detect.sh (Sovereign Edition)
# CPU: ${CPU_MODEL}
# GPU: ${GPU_INFO:-Não detectada}
# RAM: ${RAM_MB}MB | Disco: ${DISK_TYPE}
# =============================================================

# --- Compilação nativa para este CPU ---
CFLAGS=\"-march=${MARCH_NATIVE} -O2 -pipe\"
CXXFLAGS=\"\${CFLAGS}\"
FCFLAGS=\"\${CFLAGS}\"
FFLAGS=\"\${CFLAGS}\"

# --- Extensões específicas do CPU (AVX2, AES, etc.) ---
CPU_FLAGS_X86=\"${CPU_FLAGS}\"

# --- Jobs de compilação (otimizado para ${CPU_CORES} cores / ${RAM_MB}MB RAM) ---
MAKEOPTS=\"-j${JOBS} -l${LOAD_AVG}\"

# --- GPU / Drivers de vídeo ---
VIDEO_CARDS=\"${VIDEO_CARDS}\"

# --- USE flags relacionadas ao hardware ---
USE=\"\${USE} ${GPU_USE_FLAGS}\"

# --- Aceitar apenas pacotes estáveis (exceto onde necessário) ---
ACCEPT_KEYWORDS=\"amd64\"
ACCEPT_LICENSE=\"-* @FREE\"
"

echo "$MAKECONF_BLOCK"

# =============================================================================
# 6. Aplicar (se --apply)
# =============================================================================
if [[ "$APPLY" == true ]]; then
    if [[ ! -f "$MAKE_CONF" ]]; then
        echo -e "${RED}make.conf não encontrado em: ${MAKE_CONF}${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Aplicando em: ${MAKE_CONF}${NC}"

    # Backup
    cp "$MAKE_CONF" "${MAKE_CONF}.bak.$(date +%s)"

    # Remove blocos antigos das variáveis que vamos definir
    for VAR in CFLAGS CXXFLAGS FCFLAGS FFLAGS CPU_FLAGS_X86 MAKEOPTS VIDEO_CARDS; do
        sed -i "/^${VAR}=/d" "$MAKE_CONF"
    done

    # Adiciona o novo bloco
    echo "$MAKECONF_BLOCK" >> "$MAKE_CONF"

    echo -e "${GREEN}✅ make.conf atualizado com sucesso!${NC}"
    echo -e "${CYAN}Backup salvo em: ${MAKE_CONF}.bak.*${NC}"
fi

echo -e "\n${GREEN}✅ Detecção completa!${NC}"
if [[ "$APPLY" == false ]]; then
    echo -e "Para aplicar automaticamente no make.conf:"
    echo -e "  ${CYAN}bash hardware_detect.sh --apply${NC}"
    echo -e "Para aplicar em um chroot (ex: /mnt):"
    echo -e "  ${CYAN}bash hardware_detect.sh --apply --chroot /mnt${NC}"
fi
