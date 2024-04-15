#!/usr/bin/env bash
# shellcheck disable=SC2086
#shellcheck source=/dev/null

. "$(dirname $0)"/mithril.library

######################################
# User Variables - Change as desired #
# Common variables set in env file   #
######################################

#MITHRILBIN="${HOME}"/.local/bin/mithril-signer # Path for mithril-signer binary, if not in $PATH
#HOSTADDR=127.0.0.1                             # Default Listen IP/Hostname for Mithril Signer Server

######################################
# Do NOT modify code below           #
######################################

U_ID=$(id -u)
G_ID=$(id -g)

#####################
# Functions         #
#####################

usage() {
  cat <<-EOF
		
		Usage: $(basename "$0") [-d] [-u]
		
		Cardano Mithril signer wrapper script !!
		-d    Deploy mithril-signer as a systemd service
		-e    Update mithril environment file
		-s    Stop cnode using SIGINT
    -u    Skip update check
		-h    Show this help text
		
		EOF
}

mithril_init() {
  if [[ ! -S "${CARDANO_NODE_SOCKET_PATH}" ]]; then
    echo "ERROR: Could not locate socket file at ${CARDANO_NODE_SOCKET_PATH}, the node may not have completed startup !!"
    exit 1
  fi
  # Move logs to archive
  [[ -f "${LOG_DIR}"/$(basename "${0::-3}").log ]] && mv "${LOG_DIR}/$(basename "${0::-3}")".log "${LOG_DIR}"/archive/
}

get_relay_endpoint() {
  read -r -p "Enter the IP address of the relay endpoint: " RELAY_ENDPOINT_IP
  read -r -p "Enter the port of the relay endpoint (press Enter to use default 3132): " RELAY_PORT
  RELAY_PORT=${RELAY_PORT:-3132}
  echo "Using RELAY_ENDPOINT=${RELAY_ENDPOINT_IP}:${RELAY_PORT} for the Mithril signer relay endpoint."
}


deploy_systemd() {
  echo "Creating ${CNODE_VNAME}-$(basename "${0::-3}") systemd service environment file.."
  if [[ ! -f "${CNODE_HOME}"/mithril/mithril.env ]]; then
    generate_environment_file && echo "Mithril environment file created successfully!!"
  fi

  echo "Deploying ${CNODE_VNAME}-$(basename "${0::-3}") as systemd service.."
  sudo bash -c "cat <<-'EOF' > /etc/systemd/system/${CNODE_VNAME}-$(basename "${0::-3}").service
	[Unit]
	Description=Cardano Mithril signer service
	StartLimitIntervalSec=0
	Wants=network-online.target
	After=network-online.target
	BindsTo=${CNODE_VNAME}.service
	After=${CNODE_VNAME}.service
	
	[Service]
	Type=simple
	Restart=always
	RestartSec=60
	User=${USER}
	EnvironmentFile=${CNODE_HOME}/mithril/mithril.env
	ExecStart=/bin/bash -l -c \"exec ${HOME}/.local/bin/$(basename "${0::-3}") -vv\"
	KillSignal=SIGINT
	SuccessExitStatus=143
	StandardOutput=syslog
	StandardError=syslog
	SyslogIdentifier=${CNODE_VNAME}-$(basename "${0::-3}")
	TimeoutStopSec=5
	KillMode=mixed
	
	[Install]
	WantedBy=multi-user.target
	EOF" && echo "${CNODE_VNAME}-$(basename "${0::-3}").service deployed successfully!!" && sudo systemctl daemon-reload && sudo systemctl enable ${CNODE_VNAME}-"$(basename "${0::-3}")".service
}

stop_signer() {
  CNODE_PID=$(pgrep -fn "$(basename ${CNODEBIN}).*.--port ${CNODE_PORT}" 2>/dev/null) # env was only called in offline mode
  kill -2 ${CNODE_PID} 2>/dev/null
  # touch clean "${CNODE_HOME}"/db/clean # Disabled as it's a bit hacky, but only runs when SIGINT is passed to node process. Should not be needed if node does it's job
  printf "  Sending SIGINT to %s process.." "$(basename "${0::-3}")"
  sleep 5
  exit 0
}

#####################
# Execution / Main  #
#####################

# Parse command line options
while getopts :desuh opt; do
  case ${opt} in
    d ) 
      DEPLOY_SYSTEMD="Y" ;;
    e ) 
      export UPDATE_ENVIRONMENT="Y"
      ;;
    s )
      STOP_SIGNER="Y"
      ;;
    u )
      export SKIP_UPDATE="Y"
      ;;
    h)
      usage
      exit 0
      ;;
    \?)
      echo "Invalid option: -${OPTARG}" >&2
      usage
      exit 1
      ;;
    :)
      echo "Option -${OPTARG} requires an argument." >&2
      usage
      exit 1
      ;;
  esac
done

[[ "${STOP_SIGNER}" == "Y" ]] && stop_signer

# Check for updates
update_check "$@"

# Set defaults and do basic sanity checks
set_defaults

#Deploy systemd if -d argument was specified
if [[ "${DEPLOY_SYSTEMD}" == "Y" ]]; then
  if deploy_systemd ; then
    echo "Mithril signer service successfully deployed" \
    exit 0
  else
    exit 2
  fi
else
  # Run Mithril Signer Server
  echo "Sourcing the Mithril Signer environment file.."
  . "${CNODE_HOME}"/mithril/mithril.env
  echo "Starting Mithril Signer Server.."
  "${MITHRILBIN}" -vvv >> "${LOG_DIR}"/$(basename "${0::-3}").log 2>&1
fi

