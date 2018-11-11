function usage() {
	echo "--max-retries <n>: attempt <n> retries before exiting"
	echo "--parallelism <n>: adjust 'terraform plan' parallelism"
	echo "--taint <resources>: 'terraform taint' the provided resources (comma-separated list)"
	echo "--rm-state <modules>: 'terraform state rm' the provided resources (comma-separated list)"
	echo "--var-override: add override for one or more variables, e.g. '--var-override vpc_id=vpc-xxxxxxx' (comma separated list)"
	echo "--terraform-path <path to terraform>: a local path to the Terraform executable"
	echo "--help: shows this help"

	show-stack-help $STACKS
}

function parse_arguments() {
	
	configure_getopt

	TEMP=$($GETOPT -o v --long help,env:,create,terminate,max-retries:,taint:,rm-state:,var-override:,vars:,DR,dryrun,terraform-path:,skip-state-folder-deletion,back-up-state-file -n rlizone -- $@)

	eval set -- "$TEMP"

	FULL_CLI="$@"
	CREATE=false
	TERMINATE=false
	ENVIRON=""
	TAINT=""
	RM_STATE=""
	VAR_OVERRIDE=""
	DRYRUN=false
	TERRAFORM_PATH=""
	MAXRETRIES=8
	SKIP_STATE_FOLDER_DELETION=true
	BACK_UP_STATE_FILE=false
	TFVARS=""
	ENV_TYPE="Primary"

	while true; do
		case "$1" in
			--taint ) TAINT="$2"; shift 2;;
			--env ) ENVIRON="$2"; shift 2;;
			--create ) CREATE=true; shift ;;
			--terminate ) TERMINATE=true; shift ;;
			--rm-state ) RM_STATE="$2"; shift 2;;
			--var-override ) VAR_OVERRIDE="$2"; shift 2;;
			--terraform-path ) TERRAFORM_PATH=$2; shift 2;;
			--dryrun ) DRYRUN=true; shift ;;
			--DR ) ENV_TYPE="DR"; shift ;;
			--vars ) TFVARS="$2"; shift 2;
			--skip-state-folder-deletion ) SKIP_STATE_FOLDER_DELETION=true; shift ;;
			--back-up-state-file ) BACK_UP_STATE_FILE=true; shift ;;
			--help ) usage; exit; shift ;;
			-- ) shift; break ;;
			* ) STACKARG="$STACKARG $1"; shift; continue; ;;
		esac
	done
	
	# In that specific case, we will overwrite the $SCOPE parameter to just be that layer.

	if [ "$TERRAFORM_PATH" != "" ]; then
		export PATH="${TERRAFORM_PATH}:$PATH"
	fi

	SPLIT_VAR_OVERRIDE=""

	if [ "$VAR_OVERRIDE" != "" ]; then
		SPLIT_VAR_OVERRIDE=$(echo "-var $VAR_OVERRIDE" | sed 's/,/ -var /g')
	fi
}

function clean_up_terraform_state_for_layer() {
	local LAYER_NAME=$1

	# Remove the state file for the layer.
	zone_echo "Removing the state file for layer '${LAYER_NAME}'..."

	local STATE_FOLDER=$(get_terraform_state_folder_for_layer $LAYER_NAME)
	local STATE_FILE=$(get_terraform_state_filename_for_layer $LAYER_NAME)
	
	aws --profile $(get_terraform_state_profile) --region $(get_terraform_state_region) s3 rm "s3://$(get_terraform_state_bucket)/${STATE_FOLDER}/${STATE_FILE}" > /dev/null
	
	# If there are no files left in this folder, then the zone as a whole is terminated and there is some cleanup we can do.
	local FILES_LEFT=$(aws --profile $(get_terraform_state_profile) --region $(get_terraform_state_region) s3 ls s3://$(get_terraform_state_bucket)/${STATE_FOLDER}/ | grep -P "^\d{4}-\d{2}-\d{2}" | wc -l)
	
	if [[ $FILES_LEFT == 0 ]]; then
		# Remove the state file's folder.
		# Normally deleting all files in a folder automatically deletes the folder, but we might have state file backups in other folders, so we explicitly delete if we need to.
		if [[ "$SKIP_STATE_FOLDER_DELETION" == "false" ]]; then
			zone_echo "Removing the S3 folder for environment '${STATE_FOLDER}'..."
		
			aws --profile $(get_terraform_state_profile) --region $(get_terraform_state_region) s3 rm "s3://$(get_terraform_state_bucket)/${STATE_FOLDER}/" --recursive > /dev/null
		fi
		
		# Remove the "images" folder for the zone which has JSON files, certificate files, etc.
		if [[ "$SKIP_IMAGES_FOLDER_DELETION" == "false" ]]; then
			local ZONE_IMAGES_FOLDER="s3://$(get_terraform_images_bucket)/${ZONE}/"
			
			zone_echo "Removing the S3 images folder '${ZONE_IMAGES_FOLDER}'..."
		
			aws --profile $AWS_PROFILE --region $AWS_REGION s3 rm "$ZONE_IMAGES_FOLDER" --recursive > /dev/null
		fi		
	fi
}

function execute_layer() {
	local MODE=$1
	ATTEMPT=1

	layer_debug "Entering main layer logic section."

	layer_echo "Beginning Terraform 'plan'."

	# Keep trying until we succeed or fail too many times.
	while [ $ATTEMPT -le $MAXRETRIES ]; do
		layer_echo "Attempt $ATTEMPT of $MAXRETRIES."

		# Decide which parameters to use.
		RUN_PARAMETERS=""

		if [ $MODE == "create" ]; then
			RUN_PARAMETERS=$(get_create_parameters)
		else
			RUN_PARAMETERS="$(get_terminate_parameters) -destroy"
		fi

		# Run the Terraform "plan".
		layer_echo "Custom parameters: $RUN_PARAMETERS"
		echo ""

		taint_or_remove

		# Determine whether we give Terraform a variables file or not.
		local VAR_FILE=""


		if [[ -f "${TFVARS}.tfvars" ]]; then
			VAR_FILE="-var-file=${TFVARS}.tfvars"
		else
			layer_echo "Variables file '${TFVARS}.tfvars' could not be found for the layer."
			return 1
		fi

		# Do the Terraform plan and see what shakes out.
		set +e
                
		terraform plan -no-color -out=plan.out -input=false \
			-var aws_profile=${AWS_PROFILE} -var aws_region=${AWS_REGION} \
			$VAR_FILE $RUN_PARAMETERS $SPLIT_VAR_OVERRIDE 2>&1 | tee tf.out

		PLAN_EXIT_CODE=$?

		set -e

		layer_debug "Terraform 'plan' exit code: $PLAN_EXIT_CODE"

		echo ""

		# Did we succeed?
		if [[ $PLAN_EXIT_CODE -eq 0 ]]; then
			layer_echo "Terraform 'plan' succeeded."

			# Run the Terraform "apply" if desired.
			if [[ "$DRYRUN" == "true" ]]; then
				layer_echo "Skipping Terraform 'apply' due to 'dry run' mode."

				break
			else
				layer_echo "Beginning Terraform 'apply'."
				echo ""

				set +e

				terraform apply -no-color plan.out 2>&1 | tee tf.out

				APPLY_EXIT_CODE=$?

				set -e

				layer_debug "Terraform 'apply' exit code: $APPLY_EXIT_CODE"
				echo ""

				# Did we succeed?
				if [[ $APPLY_EXIT_CODE -eq 0 ]]; then
					layer_echo "Terraform 'apply' successful."

					return 0
				else
					layer_echo "Terraform 'apply' encountered errors."
				fi
			fi
		fi

		# Next attempt.
		((ATTEMPT++))
	done

	# For termination, remove the remote state now that the layer is gone.
	if [ $MODE == "terminate" ] && [ $DRYRUN == "false" ]; then
		layer_echo "Removing Terraform state file due to termination succeeding."

		aws --profile $(get_terraform_state_profile) --region $(get_terraform_state_region) s3 rm "s3://$(get_terraform_state_bucket)/$(get_terraform_state_folder)/$(get_state_filename)"
	fi

	# Success!
	return 0
}

function layer_echo() {
	echo -e "[$(date '+%Y-%m-%d %H:%2M:%2S')] [$LAYER_NAME]: $1"
}

function layer_debug() {
	if [[ "$DEBUG" == "true" ]]; then
		layer_echo "[DEBUG]: $1"
	fi
}

function clean_workspace() {
	rm -f plan.out
	rm -f tf.out
	rm -f tf.out.1
	rm -rf .terraform
	rm -f state.tf
	rm -f terraform.tfstate
}
