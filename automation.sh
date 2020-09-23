#!/bin/bash
########################################################
# Script for automating a few steps in Nutanix
# 1. Create a storage container
# 2. Create a network
# 3. Upload images using an URL
# 4. Create a VM using the earlier created/uploaded items
# 5. Power on the VMs
# 6. Show the console of the created VMs in Chrome (new Window)
########################################################

########################################################
# Variables
########################################################
nutanix_ip="192.168.1.42"
username="admin"
password="Nutanix/12"
curl_params="--insecure --silent"
curl_header='Content-Type: application/json'

########################################################
# Functions
########################################################
# Wait loop till a task is done. Only used for the tasks that take longer than 30 seconds, or have a task id
function task_progress (){
    tsk_uuid=$1
    wait_time=$2

    # Check the task progress
    progress=$(curl "https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/tasks/$tsk_uuid" $curl_params -H "$curl_header" -u $username:$password | jq '. | (.percentage_complete|tostring)+":"+.progress_status' | tr -d \")


    # Run a loop till the Progress is 100%, then check the status
    while [ ${progress%:*} -lt 100 ]
    do
        echo "Task still running. Process is at ${progress%:*}%.. Sleeping $wait_time seconds before retrying"
        sleep $wait_time
        progress=$(curl "https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/tasks/$tsk_uuid" $curl_params -H "$curl_header" -u $username:$password | jq '. | (.percentage_complete|tostring)+":"+.progress_status' | tr -d \")        
    done

}

function payload(){
    # Create the payload needed for the VM
    vm_name_fnct=$1
    network=$2
    str_container=$3
    disk_vm_id=$4
    cdrom_id=$5

    if [ $network = "Yes" ]
    then
        nic_connect=true
    else
        nic_connect=false
    fi

    # Start the Payload creation
    payload_vm='{
        "name":"'$vm_name_fnct'",
        "memory_mb":1024,
        "num_vcpus":1,
        "description":"'$vm_name_fnct'",
        "num_cores_per_vcpu":1,
        "timezone":"UTC",
        "boot":{
            "uefi_boot":false,
            "boot_device_order":[
                "CDROM","DISK","NIC"
                ]
            },
        "vm_disks":[
            {
                "is_cdrom":true,'
    
    # Check if we have asked for a CDROM
    if [[ "$cdrom_id" != "NULL" ]]
    then
        payload_vm=$payload_vm'            
                "is_empty":false,
                "disk_address":{
                    "device_bus":"ide",
                    "device_index":0
                },
                "vm_disk_clone":{
                    "disk_address":{
                        "vmdisk_uuid":"'$cdrom_id'"
                    }
                }
            },'
        
    else
        payload_vm=$payload_vm'            
                "is_empty":true,
                "disk_address":{
                    "device_bus":"ide",
                    "device_index":0
                }
            },'
    fi

    payload_vm=$payload_vm'
            {
                "is_cdrom":false,
                "disk_address":{
                    "device_bus":"scsi",
                    "device_index":0
                },'
    
    # See if we asked to add a cloned disk
    if [[ "$disk_vm_id" != "NULL" ]]
    then            
        payload_vm=$payload_vm'
                "vm_disk_clone":{
                    "disk_address":{
                        "vmdisk_uuid":"'$disk_vm_id'"
                    }
                }'
    else
        payload_vm=$payload_vm'
                "vm_disk_create":{
                    "storage_container_uuid":"'$str_container'",
                    "size":21474836480
                }'
    fi

    # Create the last part of the Paylaod for the VM
    payload_vm=$payload_vm'        }
        ],
        "vm_nics":[
            {
                "network_uuid":"'$network_uuid'",
                "is_connected":'$nic_connect'
            }
        ],
        "hypervisor_type":"ACROPOLIS",
        "vm_features":{
            "AGENT_VM":false
        }
    }'
}

########################################################
# Get the storage containers on the system and store them in an array
st_cntrs=($(curl $curl_params -H "$curl_header" -u $username:$password https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/storage_containers/ | jq '.entities[].name' | tr -d \"))

# Get the networks in the environment
networks=($(curl $curl_params -H "$curl_header" -u $username:$password https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/networks/ | jq '.entities[].name' | tr -d \"))

# Get the images from the environment
images=($(curl $curl_params -H "$curl_header" -u $username:$password https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/images/ | jq '.entities[].name' | tr -d \"))

# Get the vms in the environment
vms=($(curl $curl_params -H "$curl_header" -u $username:$password https://${nutanix_ip}:9440/api/nutanix/v2.0/vms/ | jq '.entities[].name' | tr -d \"))
########################################################


########################################################
# Network there or not to be created
########################################################
if [[ " ${networks[@]} " =~ " api-call-proj " ]]; then # If the network doesn't exist yet, create it
    echo "Network Already exists"
else
    # Create network
    payload='{
    "annotation": "API Calls Project",
    "ip_config": {
        "default_gateway": "10.10.200.254",
        "dhcp_options": {
        "domain_name": "api-call-proj.local",
        "domain_name_servers": "8.8.8.8",
        "domain_search": "api-call-proj.local"
        },
        "dhcp_server_address": "10.10.200.253",
        "network_address": "10.10.200.0",
        "pool": [
        {
            "range": "10.10.200.100 10.10.200.200"
        }
        ],
        "prefix_length": 24
    },
    "logical_timestamp": 0,
    "name": "api-call-proj",
    "vlan_id": 0
    }'

    net_uuid=$(curl --request POST "https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/networks/" -d "$payload" $curl_params -H "$curl_header" -u $username:$password | jq '.network_uuid' | tr -d \")
    if [ -z $net_uuid ]; then
        echo "Network has not been created."
    else
        echo "Network has been created."
    fi
fi

########################################################
# If the storage container not there, create it
########################################################
if [[ " ${st_cntrs[@]} " =~ " Images " ]]; then # If the Images container isn't there, create it
    echo "Storage Container Already exists"
else
    # Create storage containers
    payload_strcntr='{
    "advertised_capacity": 0,
    "compression_delay_in_secs": 0,
    "compression_enabled": true,
    "finger_print_on_write": "NONE",
    "name": "Images",
    "nfs_whitelist_inherited": true,
    "on_disk_dedup": "OFF",
    "vstore_name_list": [
        "Images"
    ]
    }'

    str_uuid=$(curl --request POST "https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/storage_containers/" -d "$payload_strcntr" $curl_params -H "$curl_header" -u $username:$password | jq '.value')
    if [ $str_uuid = "true" ]; then
        echo "Storage Container has been created."
    else
        echo "Storage Container has not been created."
    fi
fi

########################################################
# Create image if not there
########################################################

images_upload_anno=("Ubuntu 18.04 LTS" \
                    "Ubuntu 18.04 LTS MINI" \
                    "Ubuntu 18.04 LTS Server")
images_urls=("https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img" \
             "http://archive.ubuntu.com/ubuntu/dists/bionic/main/installer-amd64/current/images/netboot/mini.iso" \
             "https://releases.ubuntu.com/18.04.5/ubuntu-18.04.5-live-server-amd64.iso")
images_type=("DISK" \
             "ISO" \
             "ISO")

array_count=0

for image in "${images_upload_anno[@]}"
do 

    if [[ " ${images[@]} " =~ " $image " ]]; then # if the image isn't there, create it
        echo "Image Already exists"
    else
        # Upload an image
        payload_image='{
        "name":"'$image'",
        "annotation":"'$image'",
        "image_type":"'${images_type[$array_count]}'_IMAGE",
        "image_import_spec":{
            "storage_container_name":"Images",
            "url":"'${images_urls[$array_count]}'"
        }
        }'
               
        task_uuid=$(curl --request POST "https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/images" -d "$payload_image" $curl_params -H "$curl_header" -u $username:$password | jq '.task_uuid' | tr -d \")

        task_progress $task_uuid 30

        # Check the status of the image upload
        status=${progress#*:}
        if [ $status = "Succeeded" ]; then
            echo "Image uploaded successfully"
        else
            echo "Image uploaded not correct. Please manualy upload the image"
        fi
    fi
    array_count=$((array_count+1))
done

########################################################
# Create VMs
########################################################
if [[ " ${vms[@]} " =~ " Server " ]]; then # if the image isn't there, create it
    echo "VM Already exists"
else
    # Create empty uuid array
    image_uuid=()

    for image in "${images_upload_anno[@]}"
    do
        # Get the disk IDs of the images uploaded earlier and put them in an array
        image_uuid+=($(curl "https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/images" $curl_params -H "$curl_header" -u $username:$password | \
                      jq --arg name "$image" '.entities[] | select (.name==$name) | .vm_disk_id' | tr -d \"))
    done

    # Get the network uuid
    network_uuid=$(curl "https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/networks" $curl_params -H "$curl_header" -u $username:$password | jq '.entities[] | select (.name=="api-call-proj") | .uuid' | tr -d \")

    # Get the storage container uuid
    str_cntr=$(curl "https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/storage_containers/" $curl_params -H "$curl_header" -u $username:$password | jq '.entities[] | select (.name=="Images") | .storage_container_uuid' | tr -d \")

    # Now run through the loop and create VMs based on arrays for network, UUIDs and Names
    #-----------------------------------------------------------
    # image_uuid for the disk images (Server(0), MINI(1), Disk(2))
    # network (yes,yes,no)
    # CDROM (Empty, assigned, assigned)
    #-----------------------------------------------------------
    # Name will be (Server-LTS-Disk-1 till 3) Disk UUID and no CDROM
    # Name will be (Server-mini-1 till 3) mini UUID (ISO)
    # Name will be (Server-LTS-1 till 3) server image UUID (DISK)
    
    array_names=("Server-LTS-Disk-" "Server-mini-" "Server-LTS-")

    for vm_name in "${array_names[@]}"
    do

        # Set the needed parameters based on the VM name
        case "$vm_name" in
            Server-LTS-Disk-)
                vm_disk_id=${image_uuid[0]}
                cd_disk_id="NULL"
                NETWORK="Yes"
                ;;

            Server-mini-)
                vm_disk_id="NULL"
                cd_disk_id=${image_uuid[1]}
                NETWORK="Yes"
                ;;
            
            Server-LTS-)
                vm_disk_id="NULL"
                cd_disk_id=${image_uuid[2]}
                NETWORK="No"
                ;;

            *)
                ;;
        esac


        for nr in 1 2 3
        do

            payload $vm_name$nr $NETWORK $str_cntr $vm_disk_id $cd_disk_id
            #echo $payload_vm | jq '.'
 
            task_uuid=$(curl --request POST "https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/vms?include_vm_disk_config=true&include_vm_nic_config=true" -d "$payload_vm" $curl_params -H "$curl_header" -u $username:$password | jq '.task_uuid' | tr -d \")
    
            task_progress $task_uuid 1

            # Check the status of the VM Creation
            if [[ ${progress#*:} = "Succeeded" ]]
            then
                echo "VM $vm_name$nr has been created"
            else
                echo "VM $vm_name$nr has not been created"
            fi
        done
    done  
fi

########################################################
# Poweron VMs
########################################################
# Get the UUIDs from the VMs we just created
vm_uuid=()
array_names=("Server-LTS-Disk-" "Server-mini-" "Server-LTS-")
for vm_name in "${array_names[@]}"
do
    for nr in 1 2 3
    do  
        vm_name_jq=$vm_name$nr
        vm_uuid+=($(curl $curl_params -H "$curl_header" -u $username:$password https://${nutanix_ip}:9440/api/nutanix/v2.0/vms/ | jq --arg vmname "$vm_name_jq" '.entities[] | select (.name==$vmname) | .uuid' | tr -d \"))
    done
done

# Send the VM the Power-on command
for vm_name_arry in "${vm_uuid[@]}"
do
    task_uuid=$(curl --request POST $curl_params -H "$curl_header" -u $username:$password https://${nutanix_ip}:9440/PrismGateway/services/rest/v2.0/vms/$vm_name_arry/set_power_state -d '{"transition":"on"}' | jq '.task_uuid' | tr -d \")
    task_progress $task_uuid 1
 
    # Check the status of the VM Creation
    if [[ ${progress#*:} = "Succeeded" ]]
    then
        echo "VM has been started"
    else
        echo "VM has not been started"
    fi
done

########################################################
# Open the Console of the created machines
########################################################
array_names=("Server-LTS-Disk-" "Server-mini-" "Server-LTS-")
vm_name_array=()
for vm_name in "${array_names[@]}"
do
    for nr in 1 2 3
    do  
        vm_name_array+=$vm_name$nr
    done
done

count=0
for uuid in "${vm_uuid[@]}"
do
    open --new -a "Google Chrome" --args --new-window  "https://${nutanix_ip}:9440/console/lib/noVNC/vnc_auto.html?path=vnc/vm/$uuid/proxy&title=${vm_name_array[$count]}&uuid=$uuid&uhura=true&attached=false&noV1Access=false&useV3=true"
    count=$((count+1))
done