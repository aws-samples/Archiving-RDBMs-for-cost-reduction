## Name
Archiving  RDBMS to S3 Glacier for cost reduction

## Description
This solution will demonstrate how to build an automated backup and archiving solution on Amazon S3 Glacier storage classes using AWS Batch, AWS Lambda, and Amazon DynamoDB. This solution will leverage tools such as mysqldump and pg_dump to take database backups from Amazon RDS and Amazon Aurora instances on a recurrent schedule using Amazon EventBridge. The backups will be archived to an Amazon S3 bucket with automatic transition to the S3 Glacier Instant Retrieval class, providing a cost-effective long-term storage solution. 




## Installation
Implementation steps - high level

To test this solution in your environment you will be required to follow these steps:

1. Create an Amazon S3 Bucket to store your archives.
2. Set an Amazon S3 Lifecycle policy on your Amazon S3 bucket so that your objects get moved to lower, less expensive tiers automatically.
3. Create an Elastic Container Registry (ECR) repository to save your container image.
4. Create a Docker image with backup tools and push it to Amazon ECR.
5. Deploy the CloudFormation template.
6. Configure an EventBridge schedule to launch the AWS Lambda function.
7. Create secrets in Secrets Manager for database access.
8. Tag your databases with the appropriate value:keys to be picked up by the AWS Lambda function.


In the following sections, we walk you through the steps in details to create your resources and deploy the solution.


Prerequisites

1. Networking and security components

To facilitate the archival process and communication with AWS Services, you will need to establish a destination subnet.
We suggest simply re-using your databases subnet. Make sure communication to AWS services leverages VPC endpoints, which have the advantage of keeping your traffic within the AWS infrastructure. 



2. A development environment

To build a container image, you will need a development environment with appropriate tools and following characteristics:

* Any Environment with the AWS CLI and Docker:  This could be a local machine, a virtual machine, or any other suitable environment that allows you to interact with the AWS CLI and build Docker containers. If not x86 based (in the case of a Mac for example), make sure to follow the cross-platform compilation instructions detailed in the “Build the Docker image” step.




Deployment of the solution, detailed steps

Create an Amazon S3 Bucket

To create an Amazon S3 bucket, complete the following steps:

1. From the AWS Console, choose Create a new Bucket.
2. Record the bucket name for a later step.



Create an Amazon S3 Lifecycle rule for your newly created Amazon S3 bucket

Before you choose an Amazon S3 glacier storage class for your data, please keep these Amazon S3 Glacier characteristics in mind:


Feature	S3 Glacier Instant Retrieval	S3 Glacier Flexible Retrieval	S3 Glacier Deep Archive
Retrieval Time	Milliseconds	Minutes to 12 hours	9 to 48 hours
Best For	Rarely accessed data needing immediate retrieval	Occasionally accessed archives	Data accessed less than once a year
Storage Cost	Moderate	Lower	Lowest
Retrieval Cost	Higher	Moderate	Lowest
Minimum Storage Duration	90 days	90 days	180 days
Data Durability	99.999999999% (11 nines)	99.999999999% (11 nines)	99.999999999% (11 nines)


Please also take into consideration that Amazon S3 objects that are stored in the S3 Glacier Flexible Retrieval or S3 Glacier Deep Archive storage classes are not immediately accessible. To access an object in these storage classes, you must restore a temporary copy of the object to its S3 bucket.  For additional information on restoring objects in S3 Glacier Flexible Retrieval and S3 Glacier Deep Archive classes, see Restoring an archived object.

Once you have decided on the best Amazon S3 Glacier class for your use case, you can automate the migration of files older than a fixed number of days to a deffirent S3 Glacier storage class, you can configure lifecycle rule. 

To create an Amazon S3 Lifecycle rule, complete the following steps:


1. Select your Bucket from the Amazon S3 console.
2. Go to Management, then choose Create Lifecycle rule under the Lifecycle rule section.


1. Enter a name for your rule, then select Apply to all object on bucket.
2. Select Move current versions of object between storage classes, and in Transition current versions of objects between storage classes section Underneath, select the Amazon S3 class where you would like your objects archived and how many days after their creation they should be transferred.



* Choose Create rule.



Amazon ECR:

 To utilize AWS Batch for backing up and archiving your data, you must have an Elastic Container Registry (ECR) configured to store the container image. 

To create an Elastic Container Repository, complete the following steps:


1. Go into your AWS console to the Elastic Container Registry and choose Create a Repository.
2. Select Private from the Visibility setting. 
3. Enter a repository name.
4. Select Create Repository.
5. Record the Elastic Container Registry URI.




Clone the Docker image

To download a copy of this solution that contains the AWS CloudFormation templates, the AWS Lambda function code and the Dockerfile used to build the container complete the following steps:

1. Log in to your development environment 
2. Enter the following command:

git clone git@ssh.gitlab.aws.dev:ljeanseb/cold_archiving.git .



Build the Docker image

To build and push your Docker image to Amazon ECR, complete the following steps:

1. Go to Amazon ECR in AWS Console and choose your repository name.
2. Select View push commands.


1. Select, and copy each command listed in steps from 1 to 4 from the AWS console to your development environment terminal windows to authenticate and push an image to your Amazon ECR repository. For additional registry authentication methods, including the Amazon ECR credential helper, see Registry Authentication. 
    1. N.B. If you are building docker images from macOS please adapt the docker build command (point #2), to produce a x86 based image by adapting by appending --platform linux/amd64 to the "build" command so it can run on ECS (more https://docs.docker.com/build/building/multi-platform/: 



1. Finally, go back on the AWS console within Amazon ECR and record the URI of the image you just built and uploaded.



Preparing the AWS Lambda function for deployment

The Cloudformation template deployed in the next step expect the Lambda function code to be stored in an Amazon S3 bucket. To store the Lambda function, do the following: 

1. On the Amazon S3 console, choose the Amazon S3 bucket you created earlier (step “Create an Amazon S3 Bucket” above). 
2. Upload to the Amazon S3 bucket the zip file named “cold_archiving_lambda_func.zip” located in the root directory of your cloned copy of this solution repository.



Deploy the CloudFormation stack

To deploy the CloudFormation stack, complete the following steps:

1. Go to the CloudFormation section in the AWS and Choose Create stack with new resources.
2. Select Choose an existing template, then Specify a template, Upload a template file and finally select Choose File.
3. Use the location of the CloudFormation template you downloaded locally and and select the “cold_archiving_cfn.yaml“ file




CloudFormation deployment parameters

 To deploy the CloudFormation stack, you will need to provide some deployment parameters.

To enter the required CloudFormation deployment parameters, complete the following steps: 

1. Enter a Stack name.
2. Enter the docker image URI you previously built in the EcrImage field.
3. Enter an email address in the EmailAlerts field. This used as a destination for alerts. 
4. Enter a Subnet for the Fargate instance, this is the network discussed in the Prerequisites section above. 
5. Enter the destination VPC. 
6. Leave everything else at their default value and choose Submit.



Creating a backup user

The backup process outlined in this blog post utilizes native database management tools, such as "mysqldump," which require credentials to access your database instances. By default, an Amazon RDS DB instance has a single administrative account. However, it is recommended to create a dedicated user account that only has the necessary privileges to perform backups. This approach follows the principle of least privilege, which enhances the security of your database environment. For more information on granting least privilege access, you can refer to thislink.  

To create a backup user, complete the following steps: 

1. Connect to your Amazon RDS database endpoint from a location with the mysql client installed using the following command:

mysql -u admin -h <rds_Endpoint> -p


1. Enter the following command substituting your backup username and wanted password to create a user with the minimum set of required privileges to backup your data:



CREATE USER 'backup_user_name'@'%' IDENTIFIED BY 'your_password';

GRANT LOCK TABLES, SELECT ON DATABASE_NAME.* TO 'backup_user_name'@'%' IDENTIFIED BY 'your_password';




Storing a secret in Secrets Manager

Now that you have created a backup user, you need to store it’s credentials in Secrets Manager. 

To store a secret in Secrets Manager, complete the following steps:

1. Open the AWS Console and choose Secrets manager.
2. Choose Store a new Secret.
3. Choose Secret Type, then select Credential for Amazon RDS database.


1. Enter the credentials for the backup user created in the Creating a backup user step then choose Next.
2. Leave encryption selected to use a generated one or select a customer managed one.
3. Go to Database, and select the database to which this secret should be associated.
4. Choose Next then enter a secret name. It is imperative you precede its name with the “cold-archiving/” prefix (eg. cold-archiving/secret_name). This is to ensure the task execution role will be able to access it and create a connection to your database. Take note of the secret name, including its prefix. 


1. Leave everything else at their default value and store your secret by choosing Next



Create a schedule with EventBridge

The archival process (this solution), should be automated and scheduled to run periodically. You will create a schedule that runs once a month at 01:30 AM using EventBridge .

To create an EventBridge schedule, complete the following steps:

1. Open EventBridge, then under Scheduler, choose Schedules.
2. Choose Create Schedule.
3. Give a name to your schedule, then under Occurence, select Recurring Schedule. 
4. Under Schedule type, select Cron-based schedule.
5. Under Cron expression, you will define the schedule. Here is an example showing a Cron based schedule occurring every first day of the month at 1:30 AM. For more information about the Cron scheduling syntax, you can refer to the information here and here.


1. Select if you would like a flexible or fixed time window, then your timezone and choose Next.




Selecting target type and its parameters

You must select how your Lambda function will be triggered by EventBridge.

To select the Lambda function as a target and configure its input parameters, complete the following steps:

1. Continuing from last step, under Target detail, select Templated targets then AWS Lambda Invoke.
2. Scroll down to Invoke, Select the cold-archiving Lambda function from the drop down as your Lambda function
3. Under the Payload section, input how many days this archive Retention field should be in your DynamoDB journal. The valid JSON format is ‘{“RetentionDays”:“number_of_days“}’. Here is an example setting a schedule for a monthly backup with 365 days of retention:


1. Choose Next, then scroll down to the Permissions section. 
2. Select Use an existing role, then use the role the Cloudformation template created for you (named deployment_name_taskexec-role). In doubt, you can go look at the Cloudformation “outputs” section to find the appropriate role.
3. Under the Retry policy and dead-letter queue (DLQ) section, disable retry under Retry policy, then under Dead-letter queue (DLQ) choose Select an Amazon SQS queue in my AWS account as a DLQ. Finally under SQS queue, select the cold-archiving-error-queue.
4. Scroll down, choose Next then Create schedule. 






## Files Description
-- Docker folder: Files neded to build docker image that will be launched on Fargate by AWS Batch to do the actual backup
- Dockerfile: self-descriptive
- entrypoint.sh: script that launch the backup and the container image launched by Fargate  
- cold_archiving_lambda_func.zip: Lambda function
- cold_archiving_cfn.yaml: this is the Cloudformation template
- lambda_function.py: this is the lambda function that will be triggered on schedule by Eventbridge to handle recurring backup / archive


## License
Apache 2.0
