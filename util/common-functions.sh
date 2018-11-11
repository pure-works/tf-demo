function get_terraform_state_profile() { echo "dpp-dev"; }
function get_terraform_state_region() { echo "us-east-1"; }
function get_terraform_state_bucket() { echo "dpp-terraform"; }

# Terraform state folders
function get_network_state_folder() { echo "${ENVIRON}/layer-compute"; }
function get_database_state_folder() { echo "${ENVIRON}/layer-compute"; }
function get_compute_state_folder() { echo "${ENVIRON}/layer-compute"; }

TERRAFORM_CONFIG_FILE="terraform_config.tf"

LAYER_NETWORK_STATE_FILE="terraform-network.tfstate"
LAYER_DATABASE_STATE_FILE="terraform-database.tfstate"
LAYER_COMPUTE_STATE_FILE="terraform-compute.tfstate"

function taint_or_remove() {
	set +e

	# Taint
	if [ "$TAINT" != "" ]; then
		TAINT=$(echo $TAINT | perl -pe "s# ##g" | perl -pe "s#,#\n#g")

		for t in $TAINT
		do
			MODULE=$(echo $t | cut -d ":" -f 1)
			RESOURCE=$(echo $t | cut -d ":" -f 2)

			if [ "$MODULE" == "$RESOURCE" ]; then
				terraform taint $RESOURCE
			else
				terraform taint -module=$MODULE $RESOURCE
			fi
		done
	fi

	# State removal
	if [ "$RM_STATE" != "" ]; then
		RM_STATE=$(echo $RM_STATE | perl -pe "s# ##g" | perl -pe "s#,#\n#g")

		for s in $RM_STATE
		do
			terraform state rm $s
		done
	fi

	set -e
}

function create_terraform_state_file_backup() {
	local LAYER_NAME=$1
	local BACKUP_FOLDER_NAME=$2
	local ECHO_FUNCTION=$3
	
	# We only will do backups in creation mode. Termination mode doesn't make much sense.
	if [[ "$CREATE" == "true" ]]; then
		# This is where the state file lives.
		local STATE_FOLDER=$(get_terraform_state_folder_for_layer $LAYER_NAME)
		local STATE_FILE=$(get_terraform_state_filename_for_layer $LAYER_NAME)

		# Does the state file exist yet?
		set +e
		
		aws s3 --profile $(get_terraform_state_profile) --region $(get_terraform_state_region) ls s3://$(get_terraform_state_bucket)/${STATE_FOLDER}/${STATE_FILE} > /dev/null 2>&1	&& STATE_FILE_EXISTS=1

		set -e
		
		# If there is a state file, then back it up.
		if [[ $STATE_FILE_EXISTS == 1 ]]; then
			$ECHO_FUNCTION "Backing up state file '${STATE_FILE}' to 's3://$(get_terraform_state_bucket)/${STATE_FOLDER}/${BACKUP_FOLDER_NAME}'..."
			
			aws s3 cp --profile $(get_terraform_state_profile) --region $(get_terraform_state_region) "s3://$(get_terraform_state_bucket)/${STATE_FOLDER}/${STATE_FILE}" "s3://$(get_terraform_state_bucket)/${STATE_FOLDER}/${BACKUP_FOLDER_NAME}/${STATE_FILE}" > /dev/null 2>&1
		fi
	fi
}

function execute_terraform_init() {
	local ECHO_FUNCTION=$1
	
	$ECHO_FUNCTION "Initializing Terraform..."
	
	local ATTEMPT=1
	local MAX_ATTEMPTS=5
	local INIT_EXIT_CODE=0
	
	set +e
	
	while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
		$ECHO_FUNCTION "Attempt $ATTEMPT of $MAX_ATTEMPTS."
		
		# Try to initialize Terraform.
		AWS_PROFILE=$(get_terraform_state_profile) terraform init -input=false 2>&1
		
		INIT_EXIT_CODE=$?
		
		# If everything worked, or if we're past our limit, break out.
		if [[ $INIT_EXIT_CODE == 0 ]]; then
			break
		fi		
	
		# If we're not done yet, sleep a little bit before the next try.
		if [[ $ATTEMPT -ne $MAX_ATTEMPTS ]]; then
			layer_echo "Sleeping for $SLEEP_INTERVAL second(s) before the next attempt..."
			
			sleep $SLEEP_INTERVAL
		else
			# We're at our limit, so stop trying.
			break
		fi
		
		# Next attempt.
		((ATTEMPT++))
	done
	
	set -e
	
	# Return the last exit code from trying to initialize Terraform.
	return $INIT_EXIT_CODE
}

# Dynamic Terraform functions
function create_terraform_configuration_file() {
	local ECHO_FUNCTION=$1
	local LAYER=$2

	# Validation
	if [[ "${STATEFOLDER}" == "" || "${STATEFILE}" == "" ]]; then
		$ECHO_FUNCTION "The STATEFOLDER and/or the STATEFILE variable is empty. Both must have valid values."

		return 1
	fi

	cat - > $TERRAFORM_CONFIG_FILE <<EOF
terraform {
	backend "s3" {
		profile = "$(get_terraform_state_profile)"
		region  = "$(get_terraform_state_region)"
		bucket  = "$(get_terraform_state_bucket)"
		key     = "${STATEFOLDER}/${STATEFILE}"
	}
}
EOF

	append_layer_dependencies_remote_state $ECHO_FUNCTION $LAYER
}

function append_generic_terraform_state() {
	cat - >> $TERRAFORM_CONFIG_FILE <<EOF

data "terraform_remote_state" "$1" {
	backend = "s3"
	config {
		profile = "$(get_terraform_state_profile)"
		region = "$(get_terraform_state_region)"
		bucket = "$(get_terraform_state_bucket)"
		key = "$2"
	}
}
EOF
}

function get_terraform_state_folder_for_layer() {
	local LAYER_NAME=$1

	# Depending on the layer's name, use convention to derive its state folder.
	# There are some special exceptions for a couple layer0 instances (for now).
	if [[ "$LAYER_NAME" == "layer_network" ]]; then
		echo $(get_layer0_global_state_folder)
	elif [[ "$LAYER_NAME" == "layer_database" ]]; then
		echo $(get_layer0_region_state_folder)
	elif [[ "$LAYER_NAME" == "layer_compute" ]]; then
		echo $(get_feature_zone_state_folder)
	else
		layer_echo "Could not determine a Terraform state folder for layer '$LAYER_NAME'."
		return 127;
	fi
}

function get_terraform_state_filename_for_layer() {
	local LAYER_NAME=$1
	local STATE_FILE_VAR_NAME="${LAYER_NAME^^}_STATE_FILE"

	# If there is already a convention-based variable for the state file with a non-blank value, use its value.
	# Otherwise, use convention to determine the state file's name.
	local STATE_FILE_VALUE=$(eval "echo \$$STATE_FILE_VAR_NAME")

	if [[ -z "$STATE_FILE_VALUE" ]]; then
		STATE_FILE_VALUE="terraform-${LAYER_NAME}.tfstate"
	fi

	echo $STATE_FILE_VALUE
}

function append_layer_dependencies_remote_state() {
	local ECHO_FUNCTION=$1
    local DEPENDENCY="network"
	local STATE_FOLDER=$(get_terraform_state_folder_for_layer $DEPENDENCY)
	local STATE_FILE=$(get_terraform_state_filename_for_layer $DEPENDENCY)
	append_generic_terraform_state "$DEPENDENCY" "${STATE_FOLDER}/${STATE_FILE}"
}

function run_generic_layer() {
    local LAYER=$1
    
}