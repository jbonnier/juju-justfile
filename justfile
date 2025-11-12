set quiet
set ignore-comments

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
az-login client="":
    #!/bin/bash
    config_file="$(realpath {{justfile()}} | xargs dirname)/config.json"
    if [[ ! -f "$config_file" ]]; then
        echo >&2 "Config file not found: $config_file"
        exit 1
    fi
    client_lower=$(echo "{{client}}" | tr '[:upper:]' '[:lower:]')
    tenant=$(jq -r --arg name "$client_lower" '.azure_tenants[] | select(.name | ascii_downcase == $name) | .id' "$config_file")
    if [[ -z "$tenant" || "$tenant" == "null" ]]; then
        echo >&2 "Invalid client: {{client}}"
        echo >&2 "Available clients are: $(jq -r '.azure_tenants[].name' "$config_file" | awk 'ORS=", "' | sed 's/, $//')"
        exit 1
    fi
    az login --tenant=$tenant --use-device-code

[doc('Get the AKS credentials for kubectl/k9s')]
[group('azure')]
az-aks-creds resource-group cluster:
    az aks get-credentials --name {{cluster}} --resource-group {{resource-group}}

[doc('Execute a command in an Azure Container Instance')]
[group('azure')]
az-ci-exec resource-group container-instance-name container-name command="bash":
    az container exec --resource-group {{resource-group}} --name {{container-instance-name}} --container {{container-name}} --exec-command "{{command}}"

#-----------------------------------------------------------------------------------------------------------------------
# AWS
#-----------------------------------------------------------------------------------------------------------------------

[doc('Export a Route53 zone to a file')]
[group('aws')]
aws-route53-export zone-name format="txt" outfile="/dev/stdout":
    #!/bin/bash
    zoneid=$(aws route53 list-hosted-zones --output json | jq -r ".HostedZones[] | select(.Name == \"{{zone-name}}.\") | .Id" | cut -d'/' -f3)
    if [[ -z "$zoneid" ]]; then
        echo >&2 "Zone {{zone-name}} not found."
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
aws-get-switch-role-url account-id="" role-name="" display-name="":
    #!/bin/bash
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
tunnel local-port="" remote-addr="" remote-port="" bastion-user="" bastion-addr="" bastion-port="22" private-key-path="~/.ssh/id_rsa":
    #!/bin/bash
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

    # Get the PID of the last background command
    tunnel_pid=$!

    echo >&2 ""
    echo >&2 "Tunnel started with PID ${tunnel_pid}."
    echo >&2 "To stop it, run: kill ${tunnel_pid}"
    echo >&2 "You should now be able to connect to 127.0.0.1 on port ${local_port}."

#-----------------------------------------------------------------------------------------------------------------------
# Docker tools
#-----------------------------------------------------------------------------------------------------------------------

# For now we simply assume that the server is directly accessible from the host machine.
# Tip: You might need to connect through a bastion, if so, use the tunnel recipe first.
[doc('Run pg_dump in a local container')]
[group('tools')]
pg_dump database-name postgres-user postgres-version="latest" pg-dump-extra-args="":
    #!/bin/bash
    set -eu
    temp_path=$(mktemp -d)
    user_id=$(id -u)
    group_id=$(id -g)
    today=$(date +%Y-%m-%d)
    docker run -it --rm -v "$temp_path:/workspace" --workdir /workspace --user "$user_id:$group_id" postgres:{{postgres-version}} \
        pg_dump -h host.docker.internal -p 5433 -U {{postgres-user}} -W -f dump-${today}.sql -d {{database-name}} {{pg-dump-extra-args}}

    echo >&2 ""
    echo >&2 "Dump created at: $temp_path/dump-${today}.sql"