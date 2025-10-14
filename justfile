set quiet
set ignore-comments
set unstable # required for scripts

[doc("Display this help and exit")]
help:
    echo >&2 "\nJuju's just recipes\n\nUsage:\n just RECIPE [PARAMETERS]\n"
    just --list --unsorted
    echo >&2 ""

#-----------------------------------------------------------------------------------------------------------------------
# Azure
#-----------------------------------------------------------------------------------------------------------------------

# This recipe assumes you have a config.json file in the same directory as the justfile
[doc('Perform az login for a tenant')]
[group('azure')]
[script('/bin/bash')]
az-login client="":
    config_file="$(realpath {{justfile()}} | xargs dirname)/config.json"
    if [[ ! -f "$config_file" ]]; then
        echo "Config file not found: $config_file"
        exit 1
    fi
    client_lower=$(echo "{{client}}" | tr '[:upper:]' '[:lower:]')
    tenant=$(jq -r --arg name "$client_lower" '.azure_tenants[] | select(.name | ascii_downcase == $name) | .id' "$config_file")
    if [[ -z "$tenant" || "$tenant" == "null" ]]; then
        echo "Invalid client: {{client}}"
        echo "Available clients are: $(jq -r '.azure_tenants[].name' "$config_file" | awk 'ORS=", "' | sed 's/, $//')"
        exit 1
    fi
    az login --tenant=$tenant --use-device-code

[doc('Get the AKS credentials for kubectl/k9s')]
[group('azure')]
az-aks-creds cluster resource-group:
    az aks get-credentials --name {{cluster}} --resource-group {{resource-group}}

#-----------------------------------------------------------------------------------------------------------------------
# AWS
#-----------------------------------------------------------------------------------------------------------------------

[doc('Export a Route53 zone to a file')]
[group('aws')]
[script('/bin/bash')]
aws-route53-export zone-name format="txt" outfile="/dev/stdout":
    zoneid=$(aws route53 list-hosted-zones --output json | jq -r ".HostedZones[] | select(.Name == \"{{zone-name}}.\") | .Id" | cut -d'/' -f3)
    if [[ -z "$zoneid" ]]; then
        echo "Zone {{zone-name}} not found."
        exit 1
    fi
    records=$(aws route53 list-resource-record-sets --hosted-zone-id $zoneid --output json)
    case "{{format}}" in
        txt) records="$(echo $records | jq -jr '.ResourceRecordSets[] | "\(.Name) \t\(.TTL) \t\(.Type) \t\(.ResourceRecords[]?.Value)\n"')" ;;
        json) ;;
        *)
            echo "Invalid format: {{format}}"
            echo "Available formats are: txt, json"
            exit 1
        ;;
    esac

    printf "%s" "$records" > {{outfile}}

[doc('Get the Switch Role URL for an account/role')]
[group('aws')]
[script('/bin/bash')]
aws-get-switch-role-url account-id="" role-name="" display-name="":
    account_id="{{account-id}}"
    role_name="{{role-name}}"
    display_name="{{display-name}}"

    while [[ -z "$account_id" ]]; do
        read -p "AWS Account Number: " account_id
    done
    while [[ -z "$role_name" ]]; do
        read -p "Role Name: " role_name
    done
    while [[ -z "$display_name" ]]; do
        read -p "Display Name: " display_name
    done

    echo "https://signin.aws.amazon.com/switchrole?account=${account_id}&roleName=${role_name}&displayName=${display_name}"

#-----------------------------------------------------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------------------------------------------------

[doc('Create an SSH tunnel to a remote server')]
[group('helpers')]
[script('/bin/bash')]
tunnel local-port="" remote-addr="" remote-port="" bastion-user="" bastion-addr="" bastion-port="22" private-key-path="~/.ssh/id_rsa":
    local_port="{{local-port}}"
    remote_addr="{{remote-addr}}"
    remote_port="{{remote-port}}"
    bastion_user="{{bastion-user}}"
    bastion_addr="{{bastion-addr}}"
    bastion_port="{{bastion-port}}"
    private_key_path="{{private-key-path}}"

    while [[ -z "$local_port" ]]; do
        read -p "Please enter the local port: " local_port
    done
    while [[ -z "$remote_addr" ]]; do
        read -p "Please enter the remote address (final target): " remote_addr
    done
    while [[ -z "$remote_port" ]]; do
        read -p "Please enter the remote port (final target): " remote_port
    done
    while [[ -z "$bastion_user" ]]; do
        read -p "Please enter the bastion user: " bastion_user
    done
    while [[ -z "$bastion_addr" ]]; do
        read -p "Please enter the bastion address: " bastion_addr
    done
    while [[ -z "$bastion_port" ]]; do
        read -p "Please enter the bastion port: " bastion_port
    done
    while [[ -z "$private_key_path" || ! -f "$private_key_path" ]]; do
        read -p "Please enter a path to a valid private key: " private_key_path
    done

    ssh -L ${local_port}:${remote_addr}:${remote_port} -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -i ${private_key_path} -p ${bastion_port} ${bastion_user}@${bastion_addr} &

    tunnel_pid=$!

    echo >&2 ""
    echo >&2 "Tunnel started with PID ${tunnel_pid}."
    echo >&2 "To stop it, run: kill ${tunnel_pid}"
    echo >&2 "You should now be able to connect to 127.0.0.1 on port ${local_port}."