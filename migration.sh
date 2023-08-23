
sendLogFile()
{
	echo "Sending log file to Optix"
	exec 2>&-
	RESPONSE=`curl -X POST -F file=@"$1" https://optix.sophos.com/public/uploadlog/$2`
	echo $RESPONSE
	sleep 1
}

setUpDefaultParams()
{
  #Find the account we are trying to add and display to user for confirmation
  USERACCOUNT=`aws sts get-caller-identity --output text --query 'Account'`
  if [ $? != 0 ]; then
    echo -e "\nPlease configure AWS profile e.g. if there exists a profile called dev-profile, then run export AWS_PROFILE=dev-profile. Otherwise run aws configure and add your access credentials."
    sendLogFile $LOG_FILE $REQUEST_ID
    exit 60
  fi

  if [ -z $OPTIX_RESOURCE_KEY ]; then
    OPTIX_RESOURCE_KEY="created_by"
  fi

  if [ -z $OPTIX_RESOURCE_VALUE ]; then
    OPTIX_RESOURCE_VALUE="optix"
  fi

  #Cloudtrail bucket
  if [ -z $CLOUDTRAIL_BUCKET_NAME ]; then
    CLOUDTRAIL_BUCKET_NAME="sophos-optix-cloudtrail-$USERACCOUNT"
  fi

  if [ -z $CLOUDTRAIL_BUCKET_FOLDER ]; then
    if [ "$CLOUDTRAIL_BUCKET_NAME" = "sophos-optix-cloudtrail-$USERACCOUNT" ]; then
      CLOUDTRAIL_BUCKET_FOLDER="sophos-optix-cloudtrail"
    fi
  fi

  #SNS Topic
  if [ -z $CLOUDTRAIL_SNS_TOPIC ]; then
    CLOUDTRAIL_SNS_TOPIC="Sophos-Optix-cloudtrail-s3-sns-topic"
  fi

  if [ -z $CLOUDTRAIL_S3_RETENTION ]; then
    CLOUDTRAIL_S3_RETENTION="365"
  fi

  if [ -z $SET_RETENTION_ON_S3_CLOUDTRAIL ]; then
    SET_RETENTION_ON_S3_CLOUDTRAIL="1"
  fi

  
  CLOUDTRAIL_LAMBDA_NAME="Sophos-Optix-cloudtrail-fn"

  CLOUDTRAIL_TRAIL_NAME="Sophos-Optix-cloudtrail"

  LAMBDA_ROLE="Sophos-Optix-lambda-logging-role"

  SET_DEFAULT_REGION=false
  # IF default AWS region not passed to script, go ahead with optix default
  if [ -z $AWS_DEFAULT_REGION ]; then
    AWS_DEFAULT_REGION=`aws configure get region --output text`
    if [ -z $AWS_DEFAULT_REGION ]; then
      AWS_DEFAULT_REGION="us-west-1"
    fi
    export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
  else
    SET_DEFAULT_REGION=true
  fi

  ## should default TRAIL_REGION kept as is ?
  export TRAIL_REGION=$AWS_DEFAULT_REGION
  echo "Default region to be set as : $AWS_DEFAULT_REGION"

  ISPRODUCTION=FALSE
  collectorDNS="${DNS_PREFIX_FLOW},${DNS_PREFIX_CLOUDTRAIL}"

  if [ -z "$CLOUDTRAIL_LOGS" ]; then
    CLOUDTRAIL_LOGS=1
  fi

  #renaming the log file name to include AccountName
  LOG_FILE_NEW=`echo $LOG_FILE|sed -e "s/.log/-$USERACCOUNT-migrate-cloudtrail.log/g"`
  mv $LOG_FILE "$LOG_FILE_NEW"
  echo ""
}

verifyInputParams()
{
  if [ -z $CUSTOMER_ID ]; then
    echo "CUSTOMER_ID not present. Please use exact command in Step 2B from 'Add account page'. Exiting..."
    sendLogFile $LOG_FILE $REQUEST_ID
    exit 20
  else
    echo "CUSTOMER_ID: $CUSTOMER_ID"
  fi

  if [ -n "$USE_EXISTING_TRAIL_SETUP" ]; then
    export AWS_DEFAULT_REGION=$TRAIL_REGION
    snsARN_FLOW=`aws sns get-topic-attributes --topic-arn "arn:aws:sns:$AWS_DEFAULT_REGION:$USERACCOUNT:$CLOUDTRAIL_SNS_TOPIC" --output text 2>/dev/null`

    if [ $? == 0 ]; then
      echo "Found the SNS mentioned in input params"
    else
      echo "Could not find the SNS mentioned $CLOUDTRAIL_SNS_TOPIC in input params, exiting..."
      exit 30
    fi

    check_objects=`aws s3api get-bucket-acl --bucket $CLOUDTRAIL_BUCKET_NAME 2>/dev/null`
    if [ $? == 0 ]; then
      echo "Found the S3 bucket mentioned in input params"
    else
      echo "Could not find the SNS mentioned $CLOUDTRAIL_BUCKET_NAME in input params, exiting..."
      exit 30
    fi
  fi


  echo ""
  sleep 1
}

setupLogFile()
{
  DATE=`date +%Y%m%d%H%M%S%Z`
  LOG_FILE=Sophos-Optix-script-output-migrate-cloudtrail-$DATE.log
  exec > >(tee -a ${LOG_FILE} )
  exec 2> >(tee -a ${LOG_FILE} >&2)
  echo "----------------------------------------"
  date
  sleep 1
}


checkAWSCliVersion()
{
  AWS_CLI_REQ_VER=2.0.33
  AWS_VER_STR=`aws --version 2>&1`
  if [ $? == 0 ]; then
    AWS_VER=`echo $AWS_VER_STR | cut -c 9- | cut -d' ' -f1`
    if [ "$(printf "$AWS_CLI_REQ_VER\n$AWS_VER" | sort -V | head -n1)" == "$AWS_VER" ] && [[ "$AWS_VER" != "$AWS_CLI_REQ_VER" ]]; then
      echo "Installed aws cli version is $AWS_VER. Please upgrade to $AWS_CLI_REQ_VER or above."
      sendLogFile $LOG_FILE $REQUEST_ID
      exit 40
    else
      echo "AWS CLI version installed: $AWS_VER"
    fi
  else
    echo "aws cli is not installed or the PATH is not set. Please install aws cli version $AWS_CLI_REQ_VER or later (https://docs.aws.amazon.com/cli/latest/userguide/installing.html) and Please make sure PATH is set correctly"
    sendLogFile $LOG_FILE $REQUEST_ID
    exit 50
  fi
}


checkAndCreateBucketActivity(){
  cloudtrailS3BucketArn="arn:aws:s3:::$1"
  check_objects=`aws s3api get-bucket-acl --bucket $1 2>/dev/null`
  if [ $? == 0 ]; then
    echo "S3Bucket ($1) for $2 is already present"
  else
    echo "Creating S3bucket for $2"
    if [ $AWS_DEFAULT_REGION = 'us-east-1' ]; then
      echo "aws s3api create-bucket --bucket $1 --region $AWS_DEFAULT_REGION"
      aws s3api create-bucket --bucket $1 --region $AWS_DEFAULT_REGION
    else
      echo "aws s3api create-bucket --bucket $1 --region $AWS_DEFAULT_REGION --create-bucket-configuration LocationConstraint=$AWS_DEFAULT_REGION"
      aws s3api create-bucket --bucket $1 --region $AWS_DEFAULT_REGION --create-bucket-configuration LocationConstraint=$AWS_DEFAULT_REGION
    fi
    echo "Updating Cloudtrail bucket encryption policy in 5 seconds..."
    sleep 5
    aws s3api put-bucket-tagging --bucket $1 --tagging "TagSet=[{Key=$OPTIX_RESOURCE_KEY,Value=$OPTIX_RESOURCE_VALUE}]"
  fi
  
  echo ""
}

putBucketConfigs() {

  aws s3api put-public-access-block --bucket $1 --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  aws s3api put-bucket-encryption --bucket $1 --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms","KMSMasterKeyID":"aws/s3"}}]}'

  echo "Configured bucket $1 public access config and encryption"
}


configureSNSForBucket()
{
  # Common function to setup SNS and s3 trigger over it
  # $1 -> SNS topic Name
  # $2 -> Bucket Name
  # $3 -> Bucket Folder
  # $4 -> Suffix
  SNS_POLICY_STRING='{"Policy" : "{\"Version\": \"2012-10-17\", \"Statement\": [{\"Sid\": \"OptixSNSpermission20150201\", \"Action\": [\"SNS:Publish\"], \"Effect\": \"Allow\", \"Resource\": \"arn:aws:sns:%%REGION%%:%%USERACCOUNT%%:%%SNS_NAME%%\", \"Principal\": {\"Service\": \"s3.amazonaws.com\"}, \"Condition\": {\"StringEquals\": {\"AWS:SourceArn\": \"arn:aws:s3:::%%S3_NAME%%\"} } } ] }" }'
  SNS_POLICY_STRING=`echo "$SNS_POLICY_STRING" | sed -e "s/%%S3_NAME%%/$2/g" | sed -e "s/%%SNS_NAME%%/$1/g" | sed -e "s/%%USERACCOUNT%%/$USERACCOUNT/g" | sed -e "s/%%REGION%%/$AWS_DEFAULT_REGION/g"`
  echo "check if SNS exists"

  snsARN=`aws sns get-topic-attributes --topic-arn "arn:aws:sns:$AWS_DEFAULT_REGION:$USERACCOUNT:$1" --output text 2>/dev/null`

  if [ $? == 0 ]; then
    echo "SNS already exists, skipping s3 trigger setup, only adding permissions for lambda to subscribe"
    snsARN="arn:aws:sns:$AWS_DEFAULT_REGION:$USERACCOUNT:$1"
  else
    snsARN=`aws sns create-topic --name "$1" --attributes "$SNS_POLICY_STRING" --output text --query 'TopicArn'`

    sed -i -e "s/%%TOPIC_ARN%%/$snsARN/g" $tmp_dir/s3triggersnsconfig.json
    sed -i -e "s/%%folderPrefix%%/$3/g" $tmp_dir/s3triggersnsconfig.json
    sed -i -e "s/%%fileSuffix%%/$4/g" $tmp_dir/s3triggersnsconfig.json
    aws s3api put-bucket-notification-configuration --bucket $2 --notification-configuration file://$tmp_dir/s3triggersnsconfig.json
  fi
  echo ""
}


configureLambdaForCloudtrail()
{
  #Create lambda fn if log-group was created

  CT_LAMBDA_FN=`aws lambda get-function --function-name $CLOUDTRAIL_LAMBDA_NAME --query Configuration.FunctionArn --output text 2>/dev/null`
  if [ $? == 0 ]; then
    echo "Cloudtrail Lambda fn already exists"
  else
    echo "Creating Cloudtrail Lambda function"
    CT_LAMBDA_FN=`aws lambda create-function --function-name $CLOUDTRAIL_LAMBDA_NAME --role $S3LARN --runtime python3.8 --zip-file fileb://$tmp_dir/collector-v2-sns-lambda.zip --handler collector-v2-sns-lambda.lambda_handler --timeout 120 --memory-size 128 --publish --environment Variables="{CUSTOMER_ID=$CUSTOMER_ID,DNS_PREFIX=$DNS_PREFIX_CLOUDTRAIL,DNS_PATH=s3key/cloudtraillogs}" --output text --query 'FunctionArn'`
    echo "CT_LAMBDA_FN: " $CT_LAMBDA_FN
  fi

  #Giving sns permissions to trigger lambda
  aws lambda add-permission --function-name $CLOUDTRAIL_LAMBDA_NAME --statement-id "Sophos-Optix-cloudtrail-sns-lambda-permission" --action lambda:InvokeFunction --principal sns.amazonaws.com --source-arn "$snsARN"

  #Subscribe lambda to sns topic
  aws sns subscribe --protocol lambda --topic-arn $snsARN --notification-endpoint $CT_LAMBDA_FN
  echo "lambda configuration done"
  echo ""
}

createCloudtrail(){
  CT=`aws cloudtrail describe-trails --trail-name-list $CLOUDTRAIL_TRAIL_NAME --output text`
  if [ -z "$CT" ]; then
    echo "Creating Cloudtrail"
    if [ -n "$CLOUDTRAIL_BUCKET_FOLDER" ]; then
      aws cloudtrail create-trail --name $CLOUDTRAIL_TRAIL_NAME --s3-bucket-name $CLOUDTRAIL_BUCKET_NAME --s3-key-prefix $CLOUDTRAIL_BUCKET_FOLDER --include-global-service-events --is-multi-region-trail --enable-log-file-validation
    else
      aws cloudtrail create-trail --name $CLOUDTRAIL_TRAIL_NAME --s3-bucket-name $CLOUDTRAIL_BUCKET_NAME --include-global-service-events --is-multi-region-trail --enable-log-file-validation
    fi
  else
    echo "Cloudtrail already exists"
  fi

  sleep 5
  aws cloudtrail put-event-selectors --trail-name $CLOUDTRAIL_TRAIL_NAME --event-selectors '[{"ReadWriteType": "All","ExcludeManagementEventSources": ["kms.amazonaws.com"],"IncludeManagementEvents": true}]'
  echo ""
}


downloadSingleFile()
{
  rm $tmp_dir/$1 2>/dev/null
  curl -s -o $tmp_dir/$1 "https://avidcore.s3-us-west-2.amazonaws.com/aws/$2"
  printf "Downloaded $3"
  echo ""
}


downloadFiles()
{
  tmp_dir="${TMPDIR:-/tmp/}"

  echo "Downloading 13 config files to tmp folder"

  downloadSingleFile "cloudTrailRole.json" "cloudTrailRole.json" "1"
  downloadSingleFile "lambdaRole.json" "lambdaRole.json" "2"
  downloadSingleFile "CloudTrailRolePermission.json" "CloudTrailRolePermission.json" "3"
  downloadSingleFile "cloudtrails3policy.json" "collectorv2-config/cloudtrails3policy.json" "4"
  downloadSingleFile "lambdaLoggingRole.json" "collectorv2-config/lambdaLoggingRole.json" "5"
  downloadSingleFile "logsbucketlifecyclepolicy.json" "collectorv2-config/logsbucketlifecyclepolicy.json" "6"
  downloadSingleFile "optix-cloudtrail-read-policy.json" "collectorv2-config/optix-log-read-policy.json" "7"
  downloadSingleFile "collector-v2-sns-lambda.zip" "collectorv2-config/collector-v2-sns-lambda.zip" "8"
  downloadSingleFile "s3triggersnsconfig.json" "collectorv2-config/s3triggersnsconfig.json" "9"

  echo "Download complete"
  echo ""
}

verifyDownloadedFiles(){
  verifyFileCreated "cloudTrailRole.json"
  verifyFileCreated "lambdaRole.json"
  verifyFileCreated "CloudTrailRolePermission.json"
  verifyFileCreated "cloudtrails3policy.json"
  verifyFileCreated "lambdaLoggingRole.json"
  verifyFileCreated "logsbucketlifecyclepolicy.json"
  verifyFileCreated "optix-cloudtrail-read-policy.json"
  verifyFileCreated "collector-v2-sns-lambda.zip"
  verifyFileCreated "s3triggersnsconfig.json"
}

verifyFileCreated()
{
  if [ ! -f $tmp_dir/$1 ]; then
      echo "File $tmp_dir/$1 not found after download, please try to run script again after some time!"
      exit 130
  fi
}


configureFiles(){
    sed -i -e "s/%%LOGS_BUCKET%%/$CLOUDTRAIL_BUCKET_NAME/g" $tmp_dir/optix-cloudtrail-read-policy.json

    if [ -n "$CLOUDTRAIL_BUCKET_FOLDER" ]; then
      sed -i -e "s#%%LOGS_FOLDER%%#${CLOUDTRAIL_BUCKET_FOLDER}/#g" $tmp_dir/optix-cloudtrail-read-policy.json
    else
      sed -i -e "s#%%LOGS_FOLDER%%#${CLOUDTRAIL_BUCKET_FOLDER}#g" $tmp_dir/optix-cloudtrail-read-policy.json
    fi

    sed -i -e "s/%%BUCKET_NAME%%/$CLOUDTRAIL_BUCKET_NAME/g" $tmp_dir/cloudtrails3policy.json
    sed -i -e "s#%%BUCKET_FOLDER%%#${CLOUDTRAIL_BUCKET_FOLDER}/#g" $tmp_dir/cloudtrails3policy.json

    sed -i -e "s/%%USER_ACCOUNT%%/$USERACCOUNT/g" $tmp_dir/lambdaLoggingRole.json
    sed -i -e "s/%%RETENTION_PERIOD%%/$CLOUDTRAIL_S3_RETENTION/g" $tmp_dir/logsbucketlifecyclepolicy.json
    echo ""
}


setUpOptixReadRole()
{
  # Replace the AWS external ID placeholder
  sed -i -e "s/EXTERNAL_ID/$EXTERNAL_ID/g" $tmp_dir/role.json

  #Check and create Security-Audit access role
  ACCESSROLEARN=`aws iam get-role --role-name Avid-Role --query Role.Arn --output text 2>/dev/null`
  if [ $? == 0 ]
  then
    echo "Role already exists with ARN: $ACCESSROLEARN"
    EXTERNAL_ID=`aws iam get-role --role-name Avid-Role --query Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals --output text`
  else
	  echo "Unable to find avid role"
	  sendLogFile $LOG_FILE_NEW $REQUEST_ID
	  exit 80
  fi

  echo "########################################################"
  echo "Cross-Account Role ARN: " $ACCESSROLEARN
  echo "External Id: " $EXTERNAL_ID
  echo "########################################################"
  echo ""
}

removeOldSetup() {

	REGIONS=( $(aws ec2 describe-regions --query "Regions[].{Name:RegionName}" \--output text) )


	for region in ${REGIONS[@]}; do
		export AWS_DEFAULT_REGION=$region
		CLOUDTRAIL_LAMBDA_EXISTS=`aws lambda get-function --function-name Avid-CloudTrail-function 2>/dev/null`
		if [ $? == 0 ]; then
	   	  AWS_DEFAULT_REGION_FOR_RESOURCES=$region
		fi
	done

	export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION_FOR_RESOURCES
	echo "Default Region for CloudTrail: $AWS_DEFAULT_REGION_FOR_RESOURCES"

	if [[ ! -z $AWS_DEFAULT_REGION_FOR_RESOURCES ]]; then
		echo "Deleting Lambda"
		aws lambda delete-function --function-name Avid-CloudTrail-function

		echo "Deleting Trail"
		aws cloudtrail delete-trail --name CT-AvidSecure
		
		echo "Deleting log-group"
		aws logs delete-log-group --log-group-name CT-Avid-LogGroup
	fi

	LOG_GROUP_EXISTS=`aws logs describe-log-streams --log-group-name "/aws/lambda/Avid-CloudTrail-function" 2>/dev/null`
	if [ $? == 0 ]; then
		echo "Deleting Log group"
	  	aws logs delete-log-group --log-group-name "/aws/lambda/Avid-CloudTrail-function"
	fi

	echo "Deleting other Roles"

	aws iam detach-role-policy --role-name Avid-Lambda-to-CloudWatch --policy-arn arn:aws:iam::aws:policy/CloudWatchEventsReadOnlyAccess
	aws iam delete-role-policy --role-name  Avid-Lambda-to-CloudWatch --policy-name Avid-CT-policy
	aws iam delete-role --role-name Avid-Lambda-to-CloudWatch

	aws iam delete-role-policy --role-name Avid-CT-to-CW --policy-name cloud-traildata-policy
	aws iam delete-role --role-name Avid-CT-to-CW

}

verifyAccountId() {
	USERACCOUNT=`aws sts get-caller-identity --output text --query 'Account'`
	echo "User Account Number: " $USERACCOUNT

	read -p "Please check account number above and press enter to continue"
}

############################## Script start ##########################################################################################
# Setup Logging
setupLogFile

#Check AWS version; should be $AWS_CLI_REQ_VER or above
checkAWSCliVersion

# Setup default params
setUpDefaultParams

# Verify customerid, request id, external id
verifyInputParams

# Set Account Name for optix UI
verifyAccountId

#Download all required files
downloadFiles

#Verify downloaded files
verifyDownloadedFiles

# Remove v1 resources
removeOldSetup

#Set param values for files
configureFiles

# Check and create Security-Audit access role
setUpOptixReadRole



#Create role so Lambda FN can create logs, might be removed in future

S3LARN=`aws iam get-role --role-name $LAMBDA_ROLE --query Role.Arn --output text 2>/dev/null`
if [ -z $S3LARN ]; then
	echo "Creating role for Lambda function"
	S3LARN=`aws iam create-role --role-name $LAMBDA_ROLE --assume-role-policy-document file://$tmp_dir/lambdaRole.json --tags Key=$OPTIX_RESOURCE_KEY,Value=$OPTIX_RESOURCE_VALUE --output text --query 'Role.Arn'` 
	sleep 5
else
	echo "Role for Lambda function already exists"
fi


################### configure cloudtrail #############################

# Cloudtrail flow = Trail -> S3 -> SNS (s3 key) -> Lambda (s3 key) -> Optix (s3 key)

if [ $CLOUDTRAIL_LOGS -eq 1 ]; then

  export AWS_DEFAULT_REGION=$TRAIL_REGION
  echo "Region updated for cloudtrail: $AWS_DEFAULT_REGION"

  if [ -z $USE_EXISTING_TRAIL_SETUP ]; then

      #Create bucket for Cloudtrail if not present
      checkAndCreateBucketActivity $CLOUDTRAIL_BUCKET_NAME "Cloudtrail"

      

      aws s3api put-bucket-policy --bucket $CLOUDTRAIL_BUCKET_NAME --policy file://$tmp_dir/cloudtrails3policy.json
      echo "S3 bucket policies updated"

      ### Setup new cloudtrail if not present
      createCloudtrail

      #### Start cloudtrail logging
      aws cloudtrail start-logging --name $CLOUDTRAIL_TRAIL_NAME

      ### Set lifecycle management for s3 objects to 1 day
      if [ $SET_RETENTION_ON_S3_CLOUDTRAIL -eq 1 ]; then
        aws s3api put-bucket-lifecycle-configuration --bucket $CLOUDTRAIL_BUCKET_NAME  --lifecycle-configuration file://$tmp_dir/logsbucketlifecyclepolicy.json
      fi

      if [ "$CLOUDTRAIL_BUCKET_NAME" = "sophos-optix-cloudtrail-$USERACCOUNT" ]; then
        echo "Tagging bucket $cloudtrailS3BucketArn"
        aws resourcegroupstaggingapi tag-resources --resource-arn "$cloudtrailS3BucketArn" --tags $OPTIX_RESOURCE_KEY="$OPTIX_RESOURCE_VALUE"
      fi

      putBucketConfigs $CLOUDTRAIL_BUCKET_NAME
    
  fi
  
  ### Configure SNS for cloudtrail
  if [ -n "$CLOUDTRAIL_BUCKET_FOLDER" ]; then
    configureSNSForBucket $CLOUDTRAIL_SNS_TOPIC $CLOUDTRAIL_BUCKET_NAME "$CLOUDTRAIL_BUCKET_FOLDER\/AWSLogs\/$USERACCOUNT\/CloudTrail\/" ".json.gz"
  else
    configureSNSForBucket $CLOUDTRAIL_SNS_TOPIC $CLOUDTRAIL_BUCKET_NAME "AWSLogs\/$USERACCOUNT\/CloudTrail\/" ".json.gz"
  fi
  

  ### Configure Lambda for Cloudtrail
  configureLambdaForCloudtrail
  
  #### Give Avid-Role permission to read flow logs from s3 ####
  echo "Granting permission to Avid-Role to read s3 bucket"
  aws iam put-role-policy --role-name Avid-Role --policy-name Sophos-Optix-cloudtrail-read-policy --policy-document file://$tmp_dir/optix-cloudtrail-read-policy.json

  #### Tagging all cloudtrail resources
  #### Check if default value
  

  if [ "$CLOUDTRAIL_SNS_TOPIC" = "Sophos-Optix-cloudtrail-s3-sns-topic" ]; then
    echo "Tagging sns $snsARN"
    aws resourcegroupstaggingapi tag-resources --resource-arn "$snsARN" --tags $OPTIX_RESOURCE_KEY="$OPTIX_RESOURCE_VALUE"
  fi

  echo "Tagging lambda $CT_LAMBDA_FN"
  aws resourcegroupstaggingapi tag-resources --resource-arn "$CT_LAMBDA_FN" --tags $OPTIX_RESOURCE_KEY="$OPTIX_RESOURCE_VALUE"

fi


aws iam put-role-policy --role-name $LAMBDA_ROLE --policy-name Sophos-Optix-lambda-logging-policy --policy-document file://$tmp_dir/lambdaLoggingRole.json



######################################################################

echo "-------------------------------------------"
echo "All steps done! If you are running this script for the first time and see any errors, Please contact technical support at sophos.com/support and click 'Open a Support Case'."
echo "-------------------------------------------"
echo "Cross-Account Role ARN: " $ACCESSROLEARN
echo "External Id: " $EXTERNAL_ID

sendLogFile $LOG_FILE_NEW $REQUEST_ID
sleep 1