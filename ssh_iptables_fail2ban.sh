#!/usr/bin/env bash

#!/usr/bin/env/bash

## INFO ##
## NOME.............: conf_history.sh
## VERSÃO...........: 1.0
## DESCRIÇÃO........: Atualiza instalação debian ,e posteriormente instala o programa fail2ban
## DATA DA CRIAÇÃO..: 08/11/2024
## ESCRITO POR......: Bruno Lima
## E-MAIL...........: bruno@lc.tec.br
## DISTRO...........: Debian GNU/Linux 12
## LICENÇA..........: GPLv3
## Git Hub..........: https://github.com/bflima

# Função
ERRO() { echo "$1" ; exit 1 ; }

# Limpar tela
clear

# Verificando se usuário é root
[ "$EUID" -eq 0 ] || ERRO "Necessario ter direitos administrativos para executar esse script"

# Verificando se script já foi executado
FILE="/srv/conf_ssh.txt"
[[ -e "$FILE" ]] && ERRO "Script já foi executado" 

# Instalando awk
which syslog-ng || { apt-get update ; apt-get install syslog-ng -y ; }
which iptables  || { apt-get update ; apt-get install iptables  -y ; }
which gawk || { apt-get update ; apt-get install gawk -y ; }
which ssh  || { apt-get update ; apt-get install ssh -y  ; }

# Variáveis
USER_SSH="lc"
PORT="10443"
SSHD=$(find /etc/ -iname "sshd_config")
AUTHLOG=$(find /var/ -iname "auth.log")

clear
echo "Listando top usuários que tentaram conectar no servidor"
lastb | awk '{print $1}' | sort | uniq -c | sort -rn | head -5

echo "Listando contas atacadas"
awk 'gsub(".*sshd.*Failed password for (invalid user )?", "") {print $1}' "$AUTHLOG" | sort | uniq -c | sort -rn | head -5 || ERRO "Erro ao abrir o arquivo"

echo "Listando ips que mais atacaram"
awk 'gsub(".*sshd.*Failed password for (invalid user )?", "") {print $3}' "$AUTHLOG" | sort | uniq -c | sort -rn | head -5 || ERRO "Erro ao abrir o arquivo"

# Verificando usuario lc existe, se não existir irá criar
grep "$USER_SSH" /etc/passwd || { clear ; echo 'Cadastrar novo usário para acessar o ssh' ; useradd "$USER_SSH" && passwd "$USER" ; }

# Backup arquivo sshd
cp "$SSHD"{,.bak}

# Alterar a porta padrão do ssh
sed -i "s/^#Port.*/port $PORT/" "$SSHD"

# Conexões simultaneas
sed -i 's/^#MaxStartups.*/MaxStartups 3:50:10/'  "$SSHD"

# Tempo de espera
sed -i 's/^#LoginGraceTime.*/LoginGraceTime 30/' "$SSHD"

# Quantidade de tentativas
sed -i 's/^#MaxAuthTries.*/MaxAuthTries 3/'      "$SSHD"

# Servidor grafico
sed -i 's/^X11Forwarding.*/X11Forwarding no/g'   "$SSHD"

# Encaminhar pacotes
sed -i 's/^#AllowAgentForwarding.*/AllowAgentForwarding no/' "$SSHD"
sed -i 's/^#AllowTcpForwarding.*/AllowTcpForwarding no/'     "$SSHD"

# Usuarios permitidos para logar no ssh
echo "AllowUsers $USER" >> "$SSHD" 

# Reiniciar SSH
systemctl restart ssh

# instalar fail2-ban
echo "Deseja instalar o fail2ban: S/n: "
read -r ESCOLHA
ESCOLHA=${ESCOLHA:=s}

# Se escolha deiferente de 0, sai do programa
[[ ${ESCOLHA,,} != 's' ]] && { echo "Script finalizado" ; exit 0 ; }

# Instalando fail2ban
which fail2ban  || { apt-get update ; apt-get install fail2ban -y ; }

# Backup arquivo de politicas
JAIL=$(find /etc -iname jail.conf)
\cp "$JAIL" /etc/fail2ban/jail.local

cat > "$JAIL" << EOF
[sshd]
enabled = true
port = "$PORT"
filter = sshd
logpath = /var/log/auth.log
bantime = 7d
maxretry = 3
EOF

# Adicionar porta ao ssh
DEF=$(find /etc -iname defaults-debian.conf)
echo "port = 10443" >> "$DEF"

# Salvar arquivo de execução
echo "Configuracao realizada" | tee > $FILE
echo -e "Arquivos alterados:\n$SSHD\n$JAIL\n$DEF" >> "$FILE"

BAK=$(find /etc/ -iname "*.bak")
for item in $BAK ; do mv "$item" /srv/; done

# Reiniciar fail2ban
systemctl restart fail2ban

# https://www.digitalocean.com/community/tutorials/how-to-harden-openssh-on-ubuntu-18-04-pt
# https://www.vivaolinux.com.br/artigo/SSH-Blindado-Protegendo-o-seu-sistema-de-ataques-SSH?pagina=3

