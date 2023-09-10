#!/bin/bash

# --------------------------------
# Define global variables

LIST_PERMISSION_700=();
LIST_PERMISSION_600=();
LIST_PERMISSION_644=();

# --------------------------------
# Add files of ~/.ssh folder in this arrays

# LIST_PERMISSION_700=('Add''Folder''or''files');
# LIST_PERMISSION_600=('Add''Folder''or''files');
# LIST_PERMISSION_644=('Add''Folder''or''files');

# Or use configuration file instead of variables
CONF_FILE="SetSSHFolderPermission.conf.sh";
if [ -f ${CONF_FILE} ]; then
	source ${CONF_FILE};
	echo "Included configuration file: ${CONF_FILE}";
else
    echo "No configuration file proceeding with variables";
fi


# --------------------------------
# Set the 700 permissions

if (( ${#LIST_PERMISSION_700[@]} )); then
	for I_ELEMENT in "${LIST_PERMISSION_700[@]}"
	do
		chmod 700 "${I_ELEMENT}";
		echo "chmod 700 ${I_ELEMENT}";
	done
else
	echo LIST_PERMISSION_700 array is empty;
fi


# --------------------------------
# Set the 600 permissions

if (( ${#LIST_PERMISSION_600[@]} )); then
	for I_ELEMENT in "${LIST_PERMISSION_600[@]}"
	do
		chmod 600 "${I_ELEMENT}";
		echo "chmod 600 ${I_ELEMENT}";
	done
else
	echo LIST_PERMISSION_600 array is empty;
fi


# --------------------------------
# Set the 600 permissions

if (( ${#LIST_PERMISSION_644[@]} )); then
	for I_ELEMENT in "${LIST_PERMISSION_644[@]}"
	do
		chmod 644 "${I_ELEMENT}";
		echo "chmod 644 ${I_ELEMENT}";
	done
else
	echo LIST_PERMISSION_644 array is empty;
fi

