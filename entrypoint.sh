#!/bin/bash

# Exit the script if any command returns a non-zero value
set -e
date_time=$(date +"%Y-%m-%d_%H_%M")
target_account_id="$(aws sts get-caller-identity| jq --raw-output | jq -r '.Account')" 
#target_account_role_name="$(curl -s http://169.254.169.254/latest/meta-data/iam/info | jq --raw-output | jq -r '.InstanceProfileArn')"
efs_mount_point=/mnt/efs

# Write archival logs to a DynamoDB table
write_log () {
    expiry_date=$(date -d +"+${ARCHIVE_RETENTION_DAYS} days")
    echo "Writing journal entry to DynamoDB $INVENTORY_TABLE."
    aws dynamodb put-item --table-name "${INVENTORY_TABLE}" --region="$AWS_REGION" --item '{ "accountId": { "S": "'"${target_account_id}"'" }, "DatabaseName": { "S": "'"${db_name}"'" }, "FILE": { "S": "'"${2}"'" }, "Expiration": {"S": "'"${expiry_date}"'"}, "dumpFileUrl": {"S": "'"s3://${BUCKET}/${2}"'" }}'
}
trap write_log EXIT

# Copy archive to S3
copy_to_bucket () {        
    aws s3 cp "$1" --region="$AWS_REGION" --profile new-profile s3://"${BUCKET}"/"$2"
}
trap copy_to_bucket EXIT

delete_file () {    
    rm -f $1  
}
trap delete_file EXIT

# Create aws cli config sts token
aws configure --profile new-profile set credential_source EcsContainer

# Attempt to access SSM Parameter Store
secure_string="$(aws secretsmanager get-secret-value --secret-id "${SECRETID}" --output json --query 'SecretString' --region="$AWS_REGION" --profile new-profile)"
if [[ ${secure_string} ]]; then
    echo "Successfully accessed secrets manager and got the credentials '${SECRETID}'."        
    export PGPASSWORD="$(aws secretsmanager get-secret-value --secret-id "${SECRETID}" --query SecretString --output text | jq --raw-output | jq -r '.password')"
    export MYSQL_PWD="$(aws secretsmanager get-secret-value --secret-id "${SECRETID}" --query SecretString --output text | jq --raw-output | jq -r '.password')"
    DB_USER="$(aws secretsmanager get-secret-value --secret-id "${SECRETID}" --query SecretString --output text | jq --raw-output | jq -r '.username')"
    echo "Executing archiving for the endpoint ${PGSQL_HOST}."      
    
    IFS=':' list=($DB_NAMES);
    for db_name in "${list[@]}";
        do
        if [[ -z "$db_name" ]]; then
            echo "No DB name specified."
        fi
        echo "Found db_name: ${db_name}"        
        FILENAMETS=RDS_db_dump_${db_name}_${date_time}.sql.gz        
        FULLFILEPATH="${efs_mount_point}/${FILENAMETS}"

        case $DB_ENGINE in
          postgres)            
            echo "Postgres backup in progress"
            time pg_dump -h "$BACKUP_TARGET" -U "$DB_USER" | gzip -9 -c > "$FULLFILEPATH"
            copy_to_bucket "$FULLFILEPATH" "${FILENAMETS}"
            echo "The Database dump was successfully taken and archived to S3."
            delete_file "$FULLFILEPATH"
            echo "Deleted '$FULLFILEPATH'"
            write_log "$db_name" "$FILENAMETS"
            echo "Successfully written to the DynamoDB Inventory Table '${INVENTORY_TABLE}'."
            ;;
        
          mysql | mariadb )            
            echo "Mysql/MariaDB backup in progress"
            time mysqldump -u "$DB_USER" -h "$BACKUP_TARGET" --databases "${db_name}"  >  "${FULLFILEPATH}"
            copy_to_bucket "$FULLFILEPATH" "${FILENAMETS}"
            echo "The Database dump was successfully taken and archived to S3."
            delete_file "$FULLFILEPATH"
            echo "Deleted $FULLFILEPATH'"
            write_log "$db_name" "$FILENAMETS"
            echo "Successfully written to the DynamoDB Inventory Table '${INVENTORY_TABLE}'."
            ;;        
        
          *)
            echo "Unknown DB_ENGINE specified '${DB_ENGINE}."
            exit 1
            ;;
        esac
        done;  
else
    echo "Something went wrong {$?}"
    exit 1
fi
exec "$@"