#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# NOME...............: bash_extra.sh
# VERSÃO.............: 1.0.5
# DESCRIÇÃO..........: Instala pacotes extras (contrib e non-free)
# AUTOR..............: Bruno Lima
# GITHUB.............: https://github.com/bflima
# DATA DE CRIAÇÃO....: 28/06/2025
# ÚLTIMA ATUALIZAÇÃO.: 28/06/2025
#
# -----------------------------------------------------------------------------
# USO:
#  ./bash_custom.sh

set -euo pipefail

clear

[[ -f /etc/os-release ]] || { echo "ERRO: Não foi possível determinar a distribuição. Abortando."; exit 1 ;}

# Script homologado para distribuição debian
OS_VERSION=$(grep -i "^id" /etc/os-release)
OS_CODENANE=$(grep -i code /etc/os-release)

[[ ${OS_VERSION##*=} == 'debian' ]] || { echo "Script configurado para a distribuição Debian" ; exit 1 ; }

[[ ${OS_CODENANE##*=} == 'bookworm' ]] || { echo "Script configurado para a distribuição Debian" ; exit 1 ; }

# Verificar permissão de root
[[ "$(id -u)" -eq 0 ]] || { echo "ERRO: Este script precisa ser executado com privilégios de root (sudo)." ; exit 1 ; }

SOURCE_CUSTOM="/etc/apt/sources.list"

cat > "$SOURCE_CUSTOM" << EOF
#deb cdrom:[Debian GNU/Linux 12.8.0 _Bookworm_ - Official amd64 NETINST with firmware 20241109-11:04]/ bookworm contrib main non-free-firmware

deb http://deb.debian.org/debian/ ${OS_CODENANE##*=} main non-free-firmware contrib non-free
deb-src http://deb.debian.org/debian/ ${OS_CODENANE##*=} main non-free-firmware contrib non-free

deb http://security.debian.org/debian-security ${OS_CODENANE##*=}-security main non-free-firmware contrib non-free
deb-src http://security.debian.org/debian-security ${OS_CODENANE##*=}-security main non-free-firmware contrib non-free

# bookworm-updates, to get updates before a point release is made;
# see https://www.debian.org/doc/manuals/debian-reference/ch02.en.html#_updates_and_backports
deb http://deb.debian.org/debian/ ${OS_CODENANE##*=}-updates main non-free-firmware contrib non-free
deb-src http://deb.debian.org/debian/ ${OS_CODENANE##*=}-updates main non-free-firmware contrib non-free

# Backports allow you to install newer versions of software made available for this release
deb http://deb.debian.org/debian ${OS_CODENANE##*=}-backports main non-free-firmware contrib non-free
deb-src http://deb.debian.org/debian ${OS_CODENANE##*=}-backports main non-free-firmware contrib non-free

# This system was installed using small removable media
# (e.g. netinst, live or single CD). The matching "deb cdrom"
# entries were disabled at the end of the installation process.
# For information about how to configure apt package sources,
# see the sources.list(5) manual
EOF

# apt paralelo
echo 'Acquire::Queue-Mode "access"; Acquire::Retries "3";' | tee /etc/apt/apt.conf.d/99parallel

apt update 
apt upgrade -y
apt install -y firmware-linux firmware-linux-free firmware-linux-nonfree
