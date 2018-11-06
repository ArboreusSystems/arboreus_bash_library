#!/usr/bin/env bash

# --------------------------------
# Template :
#   Parameterized wrapper for scripts
#
# --------------------------------

while getopts {{Parameters}} OPTION
do
	case $OPTION in
		{{Parameter}}) echo "{{Parameter}} value $OPTION"
	esac
done
exit 0