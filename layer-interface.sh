# This file defines function signatures for functions that will be called by layer-run.sh.
# If you are implementing a layer and need to override functionality, you will need to create
# a bash file inside your layer's folder with function implementations for any of these functions
# that you want to override. See existing layers, i.e. layer0.sh, layer1.sh, etc. for examples.
# To see exactly when the functions below are called, review the logic in layer-run.sh.

# Default behavior; optional to override
function get_terraform_state_folder() {
	echo $(get_terraform_state_folder_for_layer $LAYER_NAME)
}

function get_state_filename() {
	echo $(get_terraform_state_filename_for_layer $LAYER_NAME)
}

# Optional to override
function before_layer_run() { return 0; }
function get_custom_arguments() { return 0; }
function handle_custom_argument() { return 0; }
function before_arguments_parsed() { return 0; }
function after_arguments_parsed() { return 0; }
function after_terraform_created() { return 0; }
function before_create() { return 0; }
function get_create_parameters() { return 0; }
function after_create() { return 0; }
function before_terminate() { return 0; }
function get_terminate_parameters() { return 0; }
function after_terminate() { return 0; }
function after_layer_run() { return 0; }