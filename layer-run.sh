#!/bin/bash

# External imports
source ../util/layer-functions.sh
source ../util/common-functions.sh
source ../layer-interface.sh

# Arguments passed to this function.
LAYER_NAME=$1
ARGS=$@

layer_echo "'${LAYER_NAME}' layer started."
layer_debug "Arguments: $ARGS"

# Import the functions overridden for this layer (if any).
if [[ -f "./${LAYER_NAME}.sh" ]]; then
	source "./${LAYER_NAME}.sh"
fi

clean_workspace

before_layer_run

before_arguments_parsed

parse_arguments $ARGS

after_arguments_parsed

configure_terraform_logging

# Put together the Terraform boilerplate.
STATEFOLDER=$(get_terraform_state_folder) && layer_debug "\$STATEFOLDER: $STATEFOLDER"
STATEFILE=$(get_state_filename) && layer_debug "\$STATEFILE: $STATEFILE"

create_terraform_configuration_file layer_echo $LAYER_NAME

after_terraform_created

layer_debug "Terraform configuration file ($TERRAFORM_CONFIG_FILE) contents:"
layer_debug "\n$(cat $TERRAFORM_CONFIG_FILE)"

# Make a backup of the state file for this layer in case we need to revert later.
if [[ "$BACK_UP_STATE_FILE" == "true" ]]; then
	BACKUP_FOLDER_NAME="${ENVIRON}-${ENV_TYPE}-$(date +%Y-%m-%d.%H:%M:%S)"

	create_terraform_state_file_backup $LAYER_NAME $BACKUP_FOLDER_NAME layer_echo
fi

# Initialize Terraform.
execute_terraform_init layer_echo

# If we're creating, create.
if [ "$CREATE" == "true" ]; then
	layer_debug "Creation mode detected."

	before_create

	execute_layer "create"

	after_create
fi

# If we're terminating, terminate.
if [ "$TERMINATE" == "true" ]; then
	layer_debug "Termination mode detected."

	before_terminate

	execute_layer "terminate"

	after_terminate
fi

after_layer_run

# Done!
layer_echo "Layer finished."