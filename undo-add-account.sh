#!/bin/bash
# Run this script as given in delete-account page e.g. following
# bash undo-add-account.sh
# If the default AWS region not passed to the script, we go ahead with Avid Secure default

exportRegion() {
  export AWS_DEFAULT_REGION=$1
  export AWS_REGION=$1
}


if [ -z $AWS_DEFAULT_REGION ]; then
	AWS_DEFAULT_REGION="us-west-1"
fi

exportRegion $AWS_DEFAULT_REGION

USERACCOUNT=`aws sts get-caller-identity --output text --query 'Account'`
echo "User Account Number: " $USERACCOUNT

read -p "Please check account number above and press enter to continue"


DATE=`date +%Y%m%d%H%M%S%Z`
LOG_FILE=Sophos-Optix-undo-script-output-$DATE-$USERACCOUNT.log
exec > >(tee -a ${LOG_FILE} )
exec 2> >(tee -a ${LOG_FILE} >&2)
echo "----------------------------------------"
date
sleep 1

echo "Compiling resources to be removed ..."


#Cloudtrail bucket
if [ -z $CLOUDTRAIL_BUCKET_NAME ]; then
	CLOUDTRAIL_BUCKET_NAME="sophos-optix-cloudtrail-$USERACCOUNT"
fi


FLOW_LOGS_BUCKET_NAME_BASE="sophos-optix-flowlogs-$USERACCOUNT"
LAMBDA_ROLE_V2="Sophos-Optix-lambda-logging-role"

#Check version 
CHECK_ROLE=`aws iam get-role --role-name Avid-role --output text --query 'Role.Arn' 2>/dev/null`

CHECK_ROLE_V2=`aws iam get-role --role-name Sophos-Optix-role --query 'Role.Arn' 2>/dev/null`

script_version1_present="0"
script_version2_present="0"



if [ -n "$CHECK_ROLE" ]; then
	script_version1_present="1"
else
	REGIONS=( $(aws ec2 describe-regions --query "Regions[].{Name:RegionName}" \--output text) )
	for region in ${REGIONS[@]}; do
		VPCLOGGROUP=`aws logs describe-log-groups --log-group-name-prefix Flowlogs-Avid-LogGroup --query 'logGroups[*].logGroupName' --output text`
		if [ -n "$VPCLOGGROUP" ]; then
			script_version1_present="1"
		fi
	done
fi

if [[ -n "$CHECK_ROLE_V2" ]] || [[ "$FORCEUNDO" == "true" ]] ; then
	script_version2_present="1"
fi


if [ $script_version1_present -eq "1" ]; then
	echo "Found v1 resources"
		
	# If the default AWS region not passed to the script, we go ahead with Avid Secure default
	if [ -z $AWS_DEFAULT_REGION ]; then
		exportRegion "us-west-1"
	fi

	REGIONS=( $(aws ec2 describe-regions --query "Regions[].{Name:RegionName}" \--output text) )
	if [ ! -z "$FLOW_LOGS" ]; then
	  echo "Skipping flow-logs configuration"
	  REGIONS=()
	fi

	for region in ${REGIONS[@]}; do

		exportRegion $region
		echo "Doing region specific operations for region: " $AWS_DEFAULT_REGION

		LAMBDA_EXISTS=`aws lambda get-function --function-name Avid-VPC-LOGS-function 2>/dev/null`
		if [ $? == 0 ]; then
		  echo "Deleting Flow-logs Lambda"
		  aws lambda delete-function --function-name Avid-VPC-LOGS-function
		else
		  echo "Flow-logs Lambda doesnt exists"
		fi

		LOG_GROUP_EXISTS=`aws logs describe-log-streams --log-group-name "/aws/lambda/Avid-VPC-LOGS-function" 2>/dev/null`
		if [ $? == 0 ]; then
			echo "Deleting Log group"
		  	aws logs delete-log-group --log-group-name "/aws/lambda/Avid-VPC-LOGS-function"
		fi

		FLOWLOGS=`aws ec2 describe-flow-logs --filter Name=log-group-name,Values=Flowlogs-Avid-LogGroup --query 'FlowLogs[*].FlowLogId' --output text`
		if [ -n "$FLOWLOGS" ]; then
		echo "Deleting Flow-logs"
		aws ec2 delete-flow-logs --flow-log-ids $FLOWLOGS
		fi

		VPCLOGGROUP=`aws logs describe-log-groups --log-group-name-prefix Flowlogs-Avid-LogGroup --query 'logGroups[*].logGroupName' --output text`
		if [ -n "$VPCLOGGROUP" ]; then
		echo "Deleting Log Group"
		aws logs delete-log-group --log-group-name Flowlogs-Avid-LogGroup
		fi

		if [[ -z $AWS_DEFAULT_REGION_FOR_RESOURCES ]]; then
			CLOUDTRAIL_LAMBDA_EXISTS=`aws lambda get-function --function-name Avid-CloudTrail-function 2>/dev/null`
			if [ $? == 0 ]; then
		   	  AWS_DEFAULT_REGION_FOR_RESOURCES=$region
			fi
		fi

	done

	exportRegion $AWS_DEFAULT_REGION_FOR_RESOURCES
	echo "Default Region for CloudTrail: $AWS_DEFAULT_REGION_FOR_RESOURCES"

	if [[ ! -z $AWS_DEFAULT_REGION_FOR_RESOURCES ]]; then
		echo "Deleting Lambda $AWS_DEFAULT_REGION $AWS_REGION"
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

	#echo "Deleting S3 bucket"
	#aws s3 rb s3://avid-cloudtrail-$USERACCOUNT --force

	echo "Deleting Avid-Role"
	DefaultIFS=$IFS

	AvidRoleAttach=`aws iam list-attached-role-policies --role-name Avid-Role --query 'AttachedPolicies[*].PolicyArn' --output text`
	echo "Detaching Attached Policy to Avid-Role-"$AvidRoleAttach
	IFS=$' \t\n' read -r -a attachArray <<< $AvidRoleAttach
	if [ -n "$attachArray" ]; then
		for value in "${attachArray[@]}" 
			do
	      aws iam detach-role-policy --role-name Avid-Role --policy-arn $value
	      if [ "$value" != "arn:aws:iam::aws:policy/SecurityAudit" ] && [ "$value" != "arn:aws:iam::aws:policy/ReadOnlyAccess" ]; then
	        aws iam delete-policy --policy-arn "$value"
	      fi
	    done
	fi

	#re-assigning IFS to previous state
	IFS=$DefaultIFS

	AvidRoleInline=`aws iam list-role-policies --role-name Avid-Role --query 'PolicyNames[*]' --output text`
	echo "Removing Inline Policy from Avid-Role-"$AvidRoleInline
	IFS=$' \t\n' read -r -a arrayInline <<< $AvidRoleInline
	if [ -n "$arrayInline" ]; then
		for value in "${arrayInline[@]}" 
			do
				aws iam delete-role-policy --role-name Avid-Role --policy-name $value
	    done
	fi

	#re-assigning IFS to previous state
	IFS=$DefaultIFS

	aws iam delete-role --role-name Avid-Role

	echo "Deleting other Roles"

	aws iam detach-role-policy --role-name Avid-Lambda-to-CloudWatch --policy-arn arn:aws:iam::aws:policy/CloudWatchEventsReadOnlyAccess
	aws iam delete-role-policy --role-name  Avid-Lambda-to-CloudWatch --policy-name Avid-CT-policy
	aws iam delete-role --role-name Avid-Lambda-to-CloudWatch

	aws iam delete-role-policy --role-name Avid-CT-to-CW --policy-name cloud-traildata-policy
	aws iam delete-role --role-name Avid-CT-to-CW

	aws iam delete-role-policy --role-name Avid-VPCFlow-Role --policy-name Avid-VPCFlow-policy
	aws iam delete-role --role-name Avid-VPCFlow-Role

	echo "Please delete Cloudtrail S3Bucket (s3://avid-cloudtrail-$USERACCOUNT) manually."
fi


if [ $script_version2_present -eq "1" ]; then
	echo "Found v2 resources"

	# If the default AWS region not passed to the script, we go ahead with Avid Secure default
	if [ -z $AWS_DEFAULT_REGION ]; then
		exportRegion "us-west-1"
	fi
	
	# read -p "Please check account number above and press enter to continue "
	REGIONS=( $(aws ec2 describe-regions --query "Regions[].{Name:RegionName}" \--output text) )
	#REGIONS=(us-west-1 us-west-2 us-east-1 us-east-2 eu-west-1 eu-west-2 eu-central-1 ap-south-1 ap-southeast-1 ap-southeast-2 ap-northeast-1 ap-northeast-2 ap-northeast-3 sa-east-1 ca-central-1 eu-west-3 eu-north-1)
	if [ ! -z "$FLOW_LOGS" ]; then
	  echo "Skipping flow-logs configuration"
	  REGIONS=()
	fi

	for region in ${REGIONS[@]}; do
		exportRegion $region
		echo "Doing region specific operations for region: " $AWS_DEFAULT_REGION

		LAMBDA_EXISTS=`aws lambda get-function --function-name Sophos-Optix-flowlogs-fn 2>/dev/null`
		if [ $? == 0 ]; then
		  echo "Deleting Flow-logs Lambda"
		  aws lambda delete-function --function-name Sophos-Optix-flowlogs-fn
		else
		  echo "Flow-logs Lambda doesnt exists"
		fi

		LOG_GROUP_EXISTS=`aws logs describe-log-streams --log-group-name "/aws/lambda/Sophos-Optix-flowlogs-fn" 2>/dev/null`
		if [ $? == 0 ]; then
			echo "Deleting Log group"
		  	aws logs delete-log-group --log-group-name "/aws/lambda/Sophos-Optix-flowlogs-fn"
		fi

		FLOWLOGS=`aws ec2 describe-flow-logs --filter "Name=tag:created_by,Values=optix" --query 'FlowLogs[*].FlowLogId' --output text`
		if [ -n "$FLOWLOGS" ]; then
			echo "Deleting Flow-logs"
			aws ec2 delete-flow-logs --flow-log-ids $FLOWLOGS
		fi

		### Delete SNS topic
		CHECK_SNS=`aws sns get-topic-attributes --topic-arn "arn:aws:sns:$AWS_DEFAULT_REGION:$USERACCOUNT:Sophos-Optix-flowlogs-s3-sns-topic" --output text 2>/dev/null`
		if [ $? == 0 ]; then
			echo "Deleting sns topic Sophos-Optix-flowlogs-s3-sns-topic"
			snsArn="arn:aws:sns:$AWS_DEFAULT_REGION:$USERACCOUNT:Sophos-Optix-flowlogs-s3-sns-topic"
			aws sns delete-topic --topic-arn $snsArn
		fi

		CHECK_POLICY=`aws iam get-role-policy --role-name Sophos-Optix-role --policy-name Sophos-Optix-flowlogs-read-policy-${AWS_DEFAULT_REGION} --output text --query 'PolicyName' 2>/dev/null`
		if [ -n "$CHECK_POLICY" ]; then
			aws iam delete-role-policy --role-name Sophos-Optix-role --policy-name Sophos-Optix-flowlogs-read-policy-${AWS_DEFAULT_REGION}
		fi

		if [[ -z $AWS_DEFAULT_REGION_FOR_RESOURCES ]]; then
			CLOUDTRAIL_LAMBDA_EXISTS=`aws lambda get-function --function-name Sophos-Optix-cloudtrail-fn 2>/dev/null`
			if [ $? == 0 ]; then
		   	  AWS_DEFAULT_REGION_FOR_RESOURCES=$region
			fi
		fi
	done

	exportRegion $AWS_DEFAULT_REGION_FOR_RESOURCES
	echo "Default Region for CloudTrail: $AWS_DEFAULT_REGION_FOR_RESOURCES"

	if [ -z $AWS_DEFAULT_REGION_FOR_RESOURCES ];  then
		exportRegion "us-west-1"
	fi

	if [ ! -z "$CLOUDTRAIL_LAMBDA_EXISTS" ]; then
		echo "Deleting Lambda $AWS_DEFAULT_REGION $AWS_REGION"
		aws lambda delete-function --function-name Sophos-Optix-cloudtrail-fn
		
		echo "Deleting Trail"
		aws cloudtrail delete-trail --name Sophos-Optix-cloudtrail
	fi

	LOG_GROUP_EXISTS=`aws logs describe-log-streams --log-group-name "/aws/lambda/Sophos-Optix-cloudtrail-fn" 2>/dev/null`
	if [ $? == 0 ]; then
		echo "Deleting Log group"
	  	aws logs delete-log-group --log-group-name "/aws/lambda/Sophos-Optix-cloudtrail-fn"
	fi

	### Delete SNS topic
	CHECK=`aws sns get-topic-attributes --topic-arn "arn:aws:sns:$AWS_DEFAULT_REGION:$USERACCOUNT:Sophos-Optix-cloudtrail-s3-sns-topic" --output text 2>/dev/null`
	if [ $? == 0 ] && [ -z "$DONT_DELETE_CLOUDTRAIL_SNS" ]; then
		echo "Deleting sns topic Sophos-Optix-cloudtrail-s3-sns-topic"
		snsArn="arn:aws:sns:$AWS_DEFAULT_REGION:$USERACCOUNT:Sophos-Optix-cloudtrail-s3-sns-topic"
		aws sns delete-topic --topic-arn $snsArn
	fi


	echo "Deleting Sophos-Optix-role"
	DefaultIFS=$IFS

	AvidRoleAttach=`aws iam list-attached-role-policies --role-name Sophos-Optix-role --query 'AttachedPolicies[*].PolicyArn' --output text`
	echo "Detaching Attached Policy to Sophos-Optix-role-"$AvidRoleAttach
	IFS=$' \t\n' read -r -a attachArray <<< $AvidRoleAttach
	if [ -n "$attachArray" ]; then
		for value in "${attachArray[@]}" 
			do
	      aws iam detach-role-policy --role-name Sophos-Optix-role --policy-arn $value
	      if [ "$value" != "arn:aws:iam::aws:policy/SecurityAudit" ] && [ "$value" != "arn:aws:iam::aws:policy/ReadOnlyAccess" ]; then
	        aws iam delete-policy --policy-arn "$value"
	      fi
	    done
	fi

	#re-assigning IFS to previous state
	IFS=$DefaultIFS

	AvidRoleInline=`aws iam list-role-policies --role-name Sophos-Optix-role --query 'PolicyNames[*]' --output text`
	echo "Removing Inline Policy from Sophos-Optix-role-"$AvidRoleInline
	IFS=$' \t\n' read -r -a arrayInline <<< $AvidRoleInline
	if [ -n "$arrayInline" ]; then
		for value in "${arrayInline[@]}" 
		do
				aws iam delete-role-policy --role-name Sophos-Optix-role --policy-name $value
	    done
	fi


	#Remove gaurdduty role
	CHECH_GAURD_DUTY_ROLE=`aws iam get-role --role-name Sophos-Optix-lambda-to-cloudWatch --output text --query 'Role.Arn' 2>/dev/null`
	if [ ! -z "$CHECH_GAURD_DUTY_ROLE" ]; then
		echo "found gaurd duty role, removing"
		aws iam detach-role-policy --role-name Sophos-Optix-lambda-to-cloudWatch --policy-arn arn:aws:iam::aws:policy/CloudWatchEventsReadOnlyAccess
		aws iam delete-role-policy --role-name  Sophos-Optix-lambda-to-cloudWatch --policy-name Sophos-Optix-CT-policy
		aws iam delete-role --role-name Sophos-Optix-lambda-to-cloudWatch
	fi
	#re-assigning IFS to previous state
	IFS=$DefaultIFS

	CHECK_CLOUDTRAIL_POLICY=`aws iam get-role-policy --role-name Sophos-Optix-role --policy-name Sophos-Optix-cloudtrail-read-policy  --output text --query 'PolicyName' 2>/dev/null`
	if [ -n "$CHECK_CLOUDTRAIL_POLICY" ]; then
		aws iam delete-role-policy --role-name Sophos-Optix-role --policy-name Sophos-Optix-cloudtrail-read-policy 
	fi

	aws iam delete-role --role-name Sophos-Optix-role

	echo "Deleting other Roles"

	CHECK_LAMBDA_LOGGING_POLICY=`aws iam get-role-policy --role-name $LAMBDA_ROLE_V2 --policy-name Sophos-Optix-lambda-logging-policy  --output text --query 'PolicyName' 2>/dev/null`	
	if [ -n "$CHECK_LAMBDA_LOGGING_POLICY" ]; then
		aws iam delete-role-policy --role-name $LAMBDA_ROLE_V2 --policy-name Sophos-Optix-lambda-logging-policy
	fi

	CHECK_LAMBDA_ROLE=`aws iam get-role --role-name $LAMBDA_ROLE_V2 --output text --query "Role.RoleName" 2>/dev/null`	
	if [ -n "$CHECK_LAMBDA_ROLE" ]; then
		aws iam delete-role --role-name $LAMBDA_ROLE_V2
	fi

	echo "Please delete Cloudtrail S3Bucket (s3://sophos-optix-cloudtrail-$USERACCOUNT) and all flow log buckets (s3://sophos-optix-flowlogs-$USERACCOUNT-*) manually."
fi

echo "Scripted UNDO completed"


echo "-------------------------------------------"
echo ""
echo "Execution logs are stored in file ./Sophos-Optix-undo-script-output-<time>-<account-id>.log"

