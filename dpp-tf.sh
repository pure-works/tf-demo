#!/bin/bash

IFS=':'
read -a layers <<< "${LAYERS}"

for env in "${layers[@]}"
do
    echo "Executing ${env}"
done