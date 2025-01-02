#!/usr/bin/env python
import boto3, sys, time, re

def lambda_handler(event, context):
    retention = event['RetentionDays']
    rds_client = boto3.client('rds')
    rds_response = rds_client.describe_db_instances()

    boto_client = boto3.client('ssm')
 
    ssmdynamodb = boto_client.get_parameter(Name='ColdArchivingInventoryTable')
    ssmbatchjobqname = boto_client.get_parameter(Name='BatchJobQueueName')
    ssmbatchjobdefname = boto_client.get_parameter(Name='BatchJobDefinitionName')

    inventory_table = ssmdynamodb['Parameter']['Value']

    batch_job_queue_raw = ssmbatchjobqname['Parameter']['Value']
    batch_job_definition_raw = ssmbatchjobdefname['Parameter']['Value']
    batch_job_queue = re.search('(?<=/)(.*)', batch_job_queue_raw)
    batch_job_definition = re.search(r'(?<=/)(.*)(:[0-9])', batch_job_definition_raw)
    batch_job_definition_name = str(batch_job_definition[1])
    batch_job_queue_name = str(batch_job_queue[1])

    for db_instance in rds_response['DBInstances']:
        db_instance_name = db_instance['DBInstanceIdentifier']
        db_arn =  db_instance['DBInstanceArn']
        db_type = db_instance['DBInstanceClass']
        db_storage = db_instance['AllocatedStorage']
        db_engine =  db_instance['Engine']
        rds_host = db_instance.get('Endpoint').get('Address')
        rds_tags = rds_client.list_tags_for_resource(ResourceName=db_arn)
        
        for tag in rds_tags['TagList']:            
            if 'arch:AutomatedBackupSecret' in tag['Key']:                    
                secret = tag['Value']                           
                print("found entity secret\n")
            
            if 'arch:AutomatedDBDumpS3Bucket' in tag['Key']:
                bucket = tag['Value'] 
                print("found s3 bucket: ", bucket, "\n")
            
            if 'arch:DB_name' in  tag['Key']:
                db_names = tag['Value'] 
                print("found DB_name:", db_names, "\n")
            
            if 'arch:DynamoDBtable' in tag['Key']:
                dynamotable = tag['Value'] 
                print("found dynamotable :", dynamotable)   

            if 'arch:DbEngine' in tag['Key']:
                db_engine = tag['Value'] 
                print("found db_engine :", db_engine)

            if 'arch:AutomatedArchiving' in tag['Key'] and 'Active' in tag['Value']:
                print("Found arch_AutomatedArchiving tag")
         
        for tag in rds_tags['TagList']:
            if tag['Key'] == 'arch:AutomatedArchiving' and tag['Value'] == "Active":                                    
                print("##### Starting archival process for tagged db: " , db_instance_name)
                clientbatch = boto3.client('batch') 
                submitjob = clientbatch.submit_job(          
                    jobDefinition=batch_job_definition_name,
                    jobName="cold_archiving_job",
                    jobQueue=batch_job_queue_name,
                    containerOverrides={
                        'environment': [
                            {
                                'name': 'DB_NAME',
                                'value': db_instance_name
                            },
                            {
                                'name': 'SECRETID',
                                'value': secret
                            },
                            {
                                'name': 'BUCKET',
                                'value': bucket,
                            },
                            {
                                'name': 'PGSQL_HOST',
                                'value': db_arn
                            },
                            {
                                'name': 'BACKUP_TARGET',
                                'value': rds_host
                            },
                            {
                                'name': 'DB_ENGINE',
                                'value': db_engine
                            },
                            {
                                'name': 'DB_NAMES',
                                'value': db_names   
                            },
                            {
                                'name': 'INVENTORY_TABLE',
                                'value': inventory_table
                            },                            
                            {
                                'name': 'ARCHIVE_RETENTION_DAYS',
                                'value': retention                                    
                            },                            
                        ]                        
                    },                        
            )