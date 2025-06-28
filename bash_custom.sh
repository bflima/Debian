#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# NOME...............: bash_custom.sh
# VERSÃO.............: 1.0.0
# DESCRIÇÃO..........: Instala pacotes e define customizações de shell para o usuário root
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

[[ -f /etc/os-release ]] || { echo "ERRO: Não foi possível determinar a distribuição. Abortando."; exit1 ;}

# Script homologado para distribuição debian
OS_VERSION=$(grep -i "^id" /etc/os-release)
[[ ${OS_VERSION##*=} == 'debian' ]] || { echo "Script configurado para a distribuição Debian" ; exit 1 ; }

# Verificar permissão de root
[[ "$(id -u)" -eq 0 ]] || { echo "ERRO: Este script precisa ser executado com privilégios de root (sudo)." ; exit 1 ; }

apt update
apt install vim bash-completion fzf curl grc htop btop -y

BASH_CUSTOM="/etc/profile.d/99-custom-bash.sh"

[[ -f $BASH_CUSTOM ]] && { echo arquivo $BASH_CUSTOM existe, favor remover e executar o script novamente ; exit 1 ; }

cat > "$BASH_CUSTOM" << EOF
## Bash Customizado ##
source /usr/share/doc/fzf/examples/key-bindings.bash

# Aliases úteis com cores e formatação
alias grep='grep --color'
alias egrep='egrep --color'
alias ip='ip -c'
alias diff='diff --color'

# Formatação para o prompt -> root@debian[~]#
PS1='\${debian_chroot:+(\$debian_chroot)}\[\033[01;31m\]\u\[\033[01;34m\]@\[\033[01;33m\]\h\[\033[01;34m\][\[\033[00m\]\[\033[01;37m\]\w\[\033[01;34m\]]\[\033[01;31m\]\\$\[\033[00m\] '

# Aliases com grc para colorir a saída
alias tail='grc tail'
alias journalctl='grc journalctl -f'
alias ping='grc ping'
alias ps='grc ps'

# Configurações do Histórico
export HISTCONTROL=erasedups:ignorespace
export HISTTIMEFORMAT="%d/%m/%Y %T "
export HISTSIZE=10000
export HISTFILESIZE=20000
EOF

cat << EOF
----------------------------------------------------------------
FINALIZADO!
As customizações foram aplicadas e estarão disponíveis em novas sessões de login.
Para aplicá-las na sua sessão ATUAL, execute o comando:
  source $BASH_CUSTOM
----------------------------------------------------------------
EOF
