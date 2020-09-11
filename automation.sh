#!/bin/bash

# Script for automating a few steps in Nutanix
# 1. Create a storage container
# 2. Create a network
# 3. Upload images using an URL
# 4. Create a VM using the earlier created/uploaded items

# Variables
nutanix_ip="192.168.1.42"
username="admin"
password="Nutanix/12"

curl_params="--insecure --silent"
curl_header='Content-Type: application/json'

# Get the storage containers on the system and store them in an array
st_cntrs=($(curl $curl_params -H $curl_header -u $username:$password https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/storage_containers/ | jq '.entities[].name' | tr -d \"))

# Get the networks in the environment
networks=($(curl $curl_params -H $curl_header -u $username:$password https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/networks/ | jq '.entities[].name' | tr -d \"))

# Get the vms in the environment
vms=($(curl $curl_params -H $curl_header -u $username:$password https://${nutanix_ip}:9440/api/nutanix/v2.0/vms/ | jq '.entities[].name' | tr -d \"))

echo "The storage containers in the environment are: ${st_cntrs[@]}"
echo "The networks in the environment are: ${networks[@]}"
echo "The vms in the environment are:${vms[@]}"