#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# NOME:               harden_ssh_fail2ban.sh
# VERSÃO:             2.0
# DESCRIÇÃO:          Realiza hardening do SSH e configura o Fail2ban para
#                     proteger contra ataques de força bruta no Debian.
# AUTOR:              Bruno Lima
# GITHUB:             https://github.com/bflima
# -----------------------------------------------------------------------------

# Modo estrito para um script mais seguro e robusto
set -euo pipefail

# --- Variáveis Globais e Constantes ---
readonly USER_SSH="suporte"
readonly SSH_PORT="22"
readonly SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
readonly SSHD_CUSTOM_CONF="${SSHD_CONFIG_DIR}/99-hardening.conf"
readonly FAIL2BAN_JAIL_DIR="/etc/fail2ban/jail.d"
readonly FAIL2BAN_CUSTOM_CONF="${FAIL2BAN_JAIL_DIR}/sshd-custom.local"

# --- Funções ---
log_msg() {
    echo "INFO: $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERRO: Este script precisa ser executado com privilégios de root (sudo)." >&2
        exit 1
    fi
}

install_dependencies() {
    log_msg "Atualizando lista de pacotes e instalando dependências..."
    apt-get update -qq
    # gawk provê o awk, openssh-server é o servidor ssh, fail2ban é o protetor
    apt-get install -y gawk openssh-server fail2ban
    log_msg "Dependências verificadas/instaladas."
}

configure_ssh() {
    log_msg "Aplicando hardening no SSH..."
    SSH_USER_PASSWD=$(grep '1000' /etc/passwd | cut -d ':' -f 1)
    [[ -d "$SSHD_CONFIG_DIR" ]] || mkdir -p "$SSHD_CONFIG_DIR"
    
    # Fazer backup do arquivo principal apenas uma vez
    if [ ! -f /etc/ssh/sshd_config.bak ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
        log_msg "Backup de /etc/ssh/sshd_config criado em /etc/ssh/sshd_config.bak"
    fi

    # Usar um arquivo de configuração separado em sshd_config.d é a melhor prática
    # Isso evita modificar o arquivo principal e é mais fácil de gerenciar.
    cat > "$SSHD_CUSTOM_CONF" << EOF
# Configurações de Hardening - Gerenciado por script
Port $SSH_PORT
LoginGraceTime 30
MaxAuthTries 3
MaxStartups 3:50:10
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
DebianBanner no
VersionAddendum Windows 2022

# Adicionar o usuário 'suporte' à lista de permissões caso o usuário inicial com id 1000 não exista
# ATENÇÃO: Apenas este usuário poderá logar via SSH!
AllowUsers ${SSH_USER_PASSWD:=$USER_SSH}

# Desabilitar o banner do Debian (opcional)
DebianBanner no
EOF
    
    # Validar a configuração antes de reiniciar
    log_msg "Validando nova configuração do SSH..."
    if sshd -t; then
        log_msg "Configuração do SSH válida. Reiniciando o serviço..."
        systemctl restart sshd
        log_msg "Serviço SSH reiniciado na porta $SSH_PORT."
    else
        log_msg "ERRO: A nova configuração do SSH é inválida!"
    fi
}

configure_fail2ban() {
    log_msg "Configurando Fail2ban para o SSH..."
    
    # Verificar se diretórios foram criados
    [[ -d "$FAIL2BAN_JAIL_DIR" ]] || mkdir -p /etc/fail2ban/jail.d
    
    # Criar um arquivo de configuração local para o SSH em jail.d/
    # Esta é a forma correta de sobrescrever as configurações do jail.conf
    cat > "$FAIL2BAN_CUSTOM_CONF" << EOF
[sshd]
enabled = true
# Aponta para a nova porta do SSH
port = $SSH_PORT
# Aumenta o tempo de ban para 1 semana
bantime = 7d
# Bane após 3 tentativas falhas
maxretry = 3
EOF

    log_msg "Validando configuração do Fail2ban..."
    if fail2ban-client -d; then # -d faz um dump da config, bom para validar
        log_msg "Reiniciando configuração do Fail2ban..."
        systemctl restart fail2ban
        systemctl enable fail2ban
        log_msg "Fail2ban reiniciado e habilitado."
    else
        log_msg "ERRO: A nova configuração do Fail2ban é inválida!"
        exit 1
    fi
}

create_ssh_user() {
    log_msg "Verificando usuário dedicado para SSH..."
    if ! id "${SSH_USER_PASSWD:=$USER_SSH}" &>/dev/null; then
        log_msg "Usuário ${SSH_USER_PASSWD:=$USER_SSH} não encontrado. Criando agora..."
        useradd -m -s /bin/bash "${SSH_USER_PASSWD:=$USER_SSH}"
        log_msg "Por favor, defina uma senha para o novo usuário ${SSH_USER_PASSWD:=$USER_SSH}: "
        passwd "${SSH_USER_PASSWD:=$USER_SSH}" 
    else
        log_msg "Usuário ${SSH_USER_PASSWD:=$USER_SSH} já existe."
    fi
}

# --- Função Principal ---
main() {
    check_root
    
    if [ -f "/srv/conf_ssh_completed.flag" ]; then
        log_msg "Script de hardening já foi executado. Se desejar rodar novamente, remova o arquivo /srv/conf_ssh_completed.flag"
        exit 0
    fi
    
    local ESCOLHA
    read -r -p "Deseja continuar com a aplicação do hardening no SSH e Fail2ban? (S/n): " ESCOLHA
    # Converte a escolha para minúsculas e define 's' como padrão se Enter for pressionado
    ESCOLHA_LOWER=$(echo "${ESCOLHA:-s}" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$ESCOLHA_LOWER" != "s" ]]; then
        log_msg "Operação cancelada pelo usuário. Script finalizado."
        exit 0
    fi

    install_dependencies
    create_ssh_user
    configure_ssh
    configure_fail2ban

    # Criar arquivo de "flag" para indicar que a configuração foi concluída
    mkdir -p /srv/
    echo "Configuração realizada em $(date)" > /srv/conf_ssh_completed.flag
    
    log_msg "--- HARDENING CONCLUÍDO COM SUCESSO ---"
    log_msg "O acesso SSH agora está restrito ao usuário '$USER_SSH' na porta '$SSH_PORT'."
    log_msg "Fail2ban está monitorando a nova porta."
}

# --- Ponto de Entrada do Script ---
main
