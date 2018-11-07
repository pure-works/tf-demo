#!/bin/bash

IFS=','
read -a options <<< "${option}"

echo $options