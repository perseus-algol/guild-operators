#!/usr/bin/env bash
# shellcheck disable=SC2086
#shellcheck source=/dev/null

. "$(dirname $0)"/mithril.library

######################################
# User Variables - Change as desired #
# Common variables set in env file   #
######################################

#MITHRILBIN="${HOME}"/.local/bin/mithril-client # Path for mithril-client binary, if not in $PATH

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
        
		Usage: $(basename "$0") <command> <subcommand>
		Script to run Cardano Mithril Client
		
		-u          Skip script update check overriding UPDATE_CHECK value in env (must be first argument to script)
		    
			Commands:
			environment           Manage mithril environment file
			  setup               Setup mithril environment file
			  override            Override default variable in the mithril environment file
			  update              Update mithril environment file
			snapshot              Interact with Mithril snapshots
			  download            Download latest Mithril snapshot
			  list                List available Mithril snapshots
			    json              List availble Mithril snapshots in JSON format
			  show                Show details of a Mithril snapshot
			    json              Show details of a Mithril snapshot in JSON format
			stake-distribution    Interact with Mithril stake distributions
			  download            Download latest stake distribution
			  list                List available stake distributions
			    json              Output latest Mithril snapshot in JSON format
        
EOF
}

SKIP_UPDATE=N
[[ $1 = "-u" ]] && export SKIP_UPDATE=Y && shift

## mithril environment subcommands

environment_override() {
  local var_to_override="$1"
  local new_value="$2"
  local env_file="${CNODE_HOME}/mithril/mithril.env"

  # Check if the variable exists in the environment file
  if ! grep -q "^${var_to_override}=" "$env_file"; then
    echo "Error: Variable $var_to_override does not exist in $env_file" >&2
    return 1
  fi

  # Use sed to replace the variable's value in the environment file
  sed -i "s|^${var_to_override}=.*|${var_to_override}=${new_value}|" "$env_file"
}

mithril_init() {
  REQUIRED_PARAMETERS="Y"
  . "${CNODE_HOME}"/mithril/mithril.env
  [[ -z "${NETWORK}" ]] && echo "ERROR: The NETWORK must be set before calling $(basename "${0::-3}")!!" && REQUIRED_PARAMETERS="N"
  [[ -z "${RELEASE}" ]] && echo "ERROR: Failed to set RELEASE variable, please check NETWORK variable in env file!!" && REQUIRED_PARAMETERS="N"
  [[ -z "${CNODE_HOME}" ]] && echo "ERROR: The CNODE_HOME must be set before calling $(basename "${0::-3}")!!" && REQUIRED_PARAMETERS="N"
  [[ ! -d "${CNODE_HOME}" ]] && echo "ERROR: The CNODE_HOME directory does not exist, please check CNODE_HOME variable in env file!!" && REQUIRED_PARAMETERS="N"
  [[ -z "${AGGREGATOR_ENDPOINT}" ]] && echo "ERROR: The AGGREGATOR_ENDPOINT must be set before calling $(basename "${0::-3}")!!" && REQUIRED_PARAMETERS="N"
  [[ -z "${GENESIS_VERIFICATION_KEY}" ]] && echo "ERROR: The GENESIS_VERIFICATION_KEY must be set before calling $(basename "${0::-3}")!!" && REQUIRED_PARAMETERS="N"
  [[ ! -x "${MITHRILBIN}" ]] && echo "ERROR: The MITHRILBIN variable does not contain an executable file, please check MITHRILBIN variable in env file!!" && REQUIRED_PARAMETERS="N"
  [[ "${REQUIRED_PARAMETERS}" != "Y" ]] && exit 1
  export GENESIS_VERIFICATION_KEY
  DOWNLOAD_SNAPSHOT="N"
  REMOVE_DB_DIR="N"
}


check_db_dir() {
  # If the DB directory does not exist then set DOWNLOAD_SNAPSHOT to Y
  if [[ ! -d "${DB_DIRECTORY}" ]]; then
    echo "INFO: The db directory does not exist.."
    DOWNLOAD_SNAPSHOT="Y"
  # If the DB directory is empty then set DOWNLOAD_SNAPSHOT to Y and REMOVE_DB_DIR to Y
  elif [[ -d "${DB_DIRECTORY}" ]] && [[ -z "$(ls -A "${DB_DIRECTORY}")" ]] && [[ $(du -cs "${DB_DIRECTORY}"/* 2>/dev/null | awk '/total$/ {print $1}') -eq 0 ]]; then
    echo "INFO: The db directory is empty.."
    REMOVE_DB_DIR="Y"
    DOWNLOAD_SNAPSHOT="Y"
  else
    echo "INFO: The db directory is not empty.."
  fi
}

remove_db_dir() {
  # Mithril client errors if the db folder already exists, so remove it if it is empty
  if [[ "${REMOVE_DB_DIR}" == "Y" ]]; then
    echo "INFO: Removing empty db directory to prepare for snapshot download.."
    rmdir "${DB_DIRECTORY}"
  fi
}

## mithril snapshot subcommands

download_snapshot() {
  if [[ "${DOWNLOAD_SNAPSHOT}" == "Y" ]]; then
    echo "INFO: Downloading latest mithril snapshot.."
    "${MITHRILBIN}" -v --aggregator-endpoint ${AGGREGATOR_ENDPOINT} snapshot download --download-dir ${CNODE_HOME} ${SNAPSHOT_DIGEST}
  else
    echo "INFO: Skipping snapshot download.."
  fi
}

list_snapshots() {
  if [[ $1 == "json" ]]; then
    "${MITHRILBIN}" -v --aggregator-endpoint ${AGGREGATOR_ENDPOINT} snapshot list --json
  else
    "${MITHRILBIN}" -v --aggregator-endpoint ${AGGREGATOR_ENDPOINT} snapshot list
  fi
}

show_snapshot() {
  local digest=""
  local json_flag=""

  for arg in "$@"; do
    if [[ $arg == "json" ]]; then
      json_flag="--json"
    else
      digest="$arg"
    fi
  done

  if [[ -z $digest ]]; then
    echo "ERROR: Snapshot digest is required for the 'show' subcommand" >&2
    exit 1
  fi

  "${MITHRILBIN}" -v --aggregator-endpoint ${AGGREGATOR_ENDPOINT} snapshot show $digest $json_flag
}

## mithril-stake-distribution subcommands

download_stake_distribution() {
  if [[ "${DOWNLOAD_STAKE_DISTRIBUTION}" == "Y" ]]; then
    echo "INFO: Downloading latest mithril stake distribution.."
    "${MITHRILBIN}" -v --aggregator-endpoint ${AGGREGATOR_ENDPOINT} mithril-stake-distribution download --download-dir "${CNODE_HOME}/mithril/" ${STAKE_DISTRIBUTION_DIGEST}
  else
    echo "INFO: Skipping stake distribution download.."
  fi
}

list_stake_distributions() {
  if [[ $1 == "json" ]]; then
    "${MITHRILBIN}" -v --aggregator-endpoint ${AGGREGATOR_ENDPOINT} mithril-stake-distribution list --json
  else
    "${MITHRILBIN}" -v --aggregator-endpoint ${AGGREGATOR_ENDPOINT} mithril-stake-distribution list
  fi
}

#####################
# Execution/Main    #
#####################

update_check "$@"

set_defaults

# Parse command line options
case $1 in
  environment)
    case $2 in
      setup)    
        generate_environment_file
        ;;
      override)
        environment_override $3 $4
        ;;
      update)
        export UPDATE_ENVIRONMENT="Y"
        generate_environment_file
        ;;
      *)
        echo "Invalid environment subcommand: $2" >&2
        usage
        exit 1
        ;;
    esac
    ;;
  snapshot)
    case $2 in
      download)
        check_db_dir
        remove_db_dir
        download_snapshot
        ;;
      list)
        case $3 in
          json)
            list_snapshots json
            ;;
          *)
            list_snapshots
            ;;
        esac
        ;;
      show)
        show_snapshot $3 $4
        ;;
      *)
        echo "Invalid snapshot subcommand: $2" >&2
        usage
        exit 1
        ;;
    esac
    ;;
  stake-distribution)
    case $2 in
      download)
        download_stake_distribution
        ;;
      list)
        case $3 in
          json)
            list_stake_distributions json
            ;;
          *)
            list_stake_distributions
            ;;
        esac
        ;;
      *)
        echo "Invalid mithril-stake-distribution subcommand: $2" >&2
        usage
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Invalid command: $1" >&2
    usage
    exit 1
    ;;
esac

exit 0
