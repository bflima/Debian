#!/usr/bin/env bash

# Modo estrito: sai em erro, variável não definida, erro em pipe.
# 'x' é para debug, remover para produção.
# set -xeuo pipefail
set -eo pipefail # 'u' pode ser muito estrito sem tratamento cuidadoso de variáveis opcionais

## INFO ##
## NOME.............: inotify_monitor.sh
## VERSÃO...........: 2.0
## DESCRIÇÃO........: Monitora eventos do sistema de arquivos e pode instalar um serviço systemd.
## DATA DA CRIAÇÃO..: 27/07/2024
## DATA DA REVISÃO..: 25/05/2025
## ESCRITO POR......: Bruno Lima (Original), Revisado por IA
## E-MAIL...........: bruno@lc.tec.br
## DISTRO...........: Linux (Debian/Ubuntu, Rocky/RHEL)
## VERSÃO HOMOLOGADA: Debian 11/12, Rocky 8/9
## LICENÇA..........: GPLv3
## Git Hub..........: https://github.com/bflima

# --- Globais e Defaults ---
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(readlink -f "$0")
LOG_TAG="inotify_monitor" # Tag para o logger

# Parâmetros configuráveis com seus defaults
DEFAULT_FILEPATH="$PWD"
DEFAULT_EVENTS='create,delete,modify,move,attrib' # Eventos mais comuns
DEFAULT_TS_FORMAT='%d-%m-%Y_%H:%M:%S'
DEFAULT_INOTIFY_EXTRA_PARAMS="-m -r" # Monitorar recursivamente e continuamente por padrão

# Variáveis que serão preenchidas pelos argumentos
opt_filepath="$DEFAULT_FILEPATH"
opt_events="$DEFAULT_EVENTS"
opt_ts_format="$DEFAULT_TS_FORMAT"
opt_inotify_extra_params="$DEFAULT_INOTIFY_EXTRA_PARAMS"
opt_install_service=false
opt_service_name="inotify_monitor.service" # Nome do serviço pode ser customizado

# --- Funções ---

usage() {
  cat << EOF
Uso: $SCRIPT_NAME [OPÇÕES]

Descrição:
  Monitora eventos do sistema de arquivos usando inotifywait e os envia para o syslog.
  Pode também instalar um serviço systemd para execução persistente.

Opções:
  -p, --path <caminho>      Caminho do arquivo ou diretório a ser monitorado.
                            Default: "$DEFAULT_FILEPATH" (diretório atual)
  -e, --events <eventos>    Eventos a serem monitorados, separados por vírgula.
                            Default: "$DEFAULT_EVENTS"
                            Ex: create,delete,modify,move,attrib,open,close
  -t, --ts <formato_ts>     Formato do timestamp para o log (man strftime).
                            Default: "$DEFAULT_TS_FORMAT"
  -x, --extra-params <params> Parâmetros extras a serem passados para o inotifywait.
                            Coloque entre aspas, ex: "-m -r --exclude '.swp'"
                            Default: "$DEFAULT_INOTIFY_EXTRA_PARAMS"
  --install-service         Cria e habilita um serviço systemd para este monitor.
                            Os parâmetros atuais (-p, -e, -t, -x) serão usados no serviço.
  --service-name <nome>     Nome para o serviço systemd (usado com --install-service).
                            Default: "$opt_service_name"
  --uninstall-service       Desabilita e remove o serviço systemd.
  -h, --help                Mostra esta mensagem de ajuda e sai.
EOF
  exit 0
}

log_message() {
    local level="$1" # ex: INFO, ERROR
    local message="$2"
    printf "%s [%s]: %s\n" "$(date +"%d-%m-%Y %H:%M:%S")" "$level" "$message"
    if [[ "$level" == "ERROR" || "$level" == "WARNING" ]]; then
        logger -t "$LOG_TAG" -p user.err "$level: $message"
    else
        logger -t "$LOG_TAG" -p user.info "$message"
    fi
}

check_dependencies() {
    if ! command -v inotifywait &>/dev/null; then
        log_message "ERROR" "inotifywait não encontrado. Tentando instalar 'inotify-tools'."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y inotify-tools
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y inotify-tools
        elif command -v yum &>/dev/null; then
            sudo yum install -y inotify-tools
        else
            log_message "ERROR" "Gerenciador de pacotes não suportado. Instale 'inotify-tools' manualmente."
            exit 1
        fi
        if ! command -v inotifywait &>/dev/null; then
             log_message "ERROR" "Falha ao instalar 'inotify-tools'."
             exit 1
        fi
        log_message "INFO" "'inotify-tools' instalado com sucesso."
    fi
}

create_systemd_unit() {
    if [[ "$EUID" -ne 0 ]]; then
        log_message "ERROR" "Permissão de root é necessária para instalar o serviço systemd."
        exit 1
    fi

    local service_file_path="/etc/systemd/system/$opt_service_name"
    log_message "INFO" "Criando unidade systemd em $service_file_path..."

    # Escapa aspas simples para os parâmetros dentro do ExecStart
    local escaped_filepath="${opt_filepath//\'/\'\\\'\'}"
    local escaped_events="${opt_events//\'/\'\\\'\'}"
    local escaped_ts_format="${opt_ts_format//\'/\'\\\'\'}"
    local escaped_inotify_extra_params="${opt_inotify_extra_params//\'/\'\\\'\'}"

    # Constrói a linha de comando com os parâmetros atuais
    # Nota: Os parâmetros são passados para o script, que os re-parseará quando o serviço iniciar.
    local exec_start_cmd="/bin/bash '$SCRIPT_PATH' --path '$escaped_filepath' --events '$escaped_events' --ts '$escaped_ts_format' --extra-params '$escaped_inotify_extra_params'"

    cat > "$service_file_path" << EOF
[Unit]
Description=Inotify Monitor Service ($opt_service_name) for path '$escaped_filepath'
Documentation=https://github.com/bflima (ou documentação do script)
After=network.target

[Service]
Type=simple
ExecStart=$exec_start_cmd
Restart=always
RestartSec=5
User=root # Ou um usuário menos privilegiado se o caminho permitir
StandardOutput=null # Redireciona stdout para null, pois já usamos logger
StandardError=journal # Redireciona stderr para o journal

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$service_file_path"
    log_message "INFO" "Unidade systemd criada: $service_file_path"
    log_message "INFO" "Executando systemctl daemon-reload..."
    if sudo systemctl daemon-reload; then
        log_message "INFO" "daemon-reload executado com sucesso."
        log_message "INFO" "Para habilitar e iniciar o serviço, execute:"
        log_message "INFO" "  sudo systemctl enable --now $opt_service_name"
        log_message "INFO" "Para verificar o status:"
        log_message "INFO" "  sudo systemctl status $opt_service_name"
        log_message "INFO" "Para ver os logs:"
        log_message "INFO" "  journalctl -u $opt_service_name -f"
    else
        log_message "ERROR" "Falha ao executar systemctl daemon-reload."
    fi
}

uninstall_systemd_unit() {
    if [[ "$EUID" -ne 0 ]]; then
        log_message "ERROR" "Permissão de root é necessária para desinstalar o serviço systemd."
        exit 1
    fi
    local service_file_path="/etc/systemd/system/$opt_service_name"

    if [[ ! -f "$service_file_path" ]]; then
        log_message "INFO" "Serviço '$opt_service_name' não encontrado em $service_file_path."
        exit 0
    fi

    log_message "INFO" "Parando e desabilitando o serviço '$opt_service_name'..."
    sudo systemctl stop "$opt_service_name" &>/dev/null || true # Ignora erro se não estiver rodando
    sudo systemctl disable "$opt_service_name" &>/dev/null || true # Ignora erro se não estiver habilitado

    log_message "INFO" "Removendo o arquivo da unidade: $service_file_path"
    sudo rm -f "$service_file_path"

    log_message "INFO" "Executando systemctl daemon-reload..."
    if sudo systemctl daemon-reload; then
        log_message "INFO" "Serviço '$opt_service_name' desinstalado com sucesso."
    else
        log_message "ERROR" "Falha ao executar systemctl daemon-reload após remover o serviço."
    fi
}

# --- Parseamento de Argumentos (usando getopt para long options) ---
# Nota: getopt (GNU) não é builtin como getopts.
# Se for preciso portabilidade estrita sem getopt, usar getopts e apenas opções curtas,
# ou um loop manual mais complexo.

# Tenta usar getopt. Se não disponível, cai para um parseamento mais simples ou erro.
if ! OPTS=$(getopt -o p:e:t:x:h --long path:,events:,ts:,extra-params:,install-service,service-name:,uninstall-service,help -n "$SCRIPT_NAME" -- "$@"); then
    log_message "ERROR" "Falha ao parsear opções. Use -h ou --help para uso."
    exit 1
fi
eval set -- "$OPTS"

while true; do
  case "$1" in
    -p | --path) opt_filepath="$2"; shift 2 ;;
    -e | --events) opt_events="$2"; shift 2 ;;
    -t | --ts) opt_ts_format="$2"; shift 2 ;;
    -x | --extra-params) opt_inotify_extra_params="$2"; shift 2 ;;
    --install-service) opt_install_service=true; shift ;;
    --service-name) opt_service_name="$2"; shift 2 ;;
    --uninstall-service) uninstall_systemd_unit; exit 0 ;; # Ação imediata
    -h | --help) usage ;;
    --) shift; break ;; # Fim das opções
    *) log_message "ERROR" "Opção interna desconhecida: $1"; usage ;;
  esac
done

# --- Lógica Principal ---

if "$opt_install_service"; then
    check_dependencies # Necessário para inotifywait, mesmo que o serviço o chame depois
    create_systemd_unit
    exit 0
fi

# Se não for instalar serviço, executa o monitoramento
check_dependencies

# Verifica se o caminho é válido (diretório ou arquivo existente)
if [[ ! -e "$opt_filepath" ]]; then
    log_message "ERROR" "Caminho especificado '$opt_filepath' não existe."
    exit 1
fi

# Constrói os parâmetros do inotifywait cuidadosamente
# Removendo -m e -r de opt_inotify_extra_params se já estiverem lá para evitar duplicação,
# já que eles são controlados ou adicionados explicitamente.
# Esta é uma sanitização simples; uma mais robusta seria complexa.
clean_extra_params=$(echo "$opt_inotify_extra_params" | sed 's/-m//g; s/-r//g; s/--monitor//g; s/--recursive//g' | awk '{$1=$1};1') # Remove espaços extras

log_message "INFO" "Iniciando monitoramento em '$opt_filepath'..."
log_message "INFO" "Eventos: '$opt_events'"
log_message "INFO" "Formato TS: '$opt_ts_format'"
log_message "INFO" "Parâmetros extras para inotifywait: '$clean_extra_params'"
log_message "INFO" "Pressione Ctrl+C para parar."

# O formato JSON aqui é uma string, não JSON válido por si só, mas bom para logs.
# Aspas simples dentro do format string para logger não causarem problemas.
# O próprio inotifywait lida com a expansão de %T, %w etc.
# A flag -m (monitor) e -r (recursive) são adicionadas explicitamente ao final
# se não estiverem nos extras, ou se os extras não as desabilitarem de alguma forma.
# A forma como $clean_extra_params é injetado assume que são opções válidas.
# É crucial que $clean_extra_params não contenha nada que quebre a sintaxe.
# Usar `eval` aqui seria perigoso. Passar como argumentos separados seria mais seguro se possível.

# shellcheck disable=SC2086 # Permitir expansão de $clean_extra_params
inotifywait \
    --timefmt "$opt_ts_format" \
    --format "{'timestamp':'%T','watch_path':'%w','filename':'%f','events':'%e'}" \
    -e "$opt_events" \
    $clean_extra_params \
    -m -r \
    "$opt_filepath" | while IFS= read -r line; do
        # Envia cada linha de evento para o logger
        logger -t "$LOG_TAG" -p user.notice "$line"
    done

log_message "INFO" "Monitoramento interrompido."
