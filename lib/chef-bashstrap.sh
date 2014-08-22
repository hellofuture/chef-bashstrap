##################################################################################
# Setup colours
##################################################################################

TERM=xterm
txtbld=$(tput bold)             # Bold
bldred=${txtbld}$(tput setaf 1) #  red
bldgrn=${txtbld}$(tput setaf 2) #  green
bldylw=${txtbld}$(tput setaf 3) #  yellow
bldblu=${txtbld}$(tput setaf 4) #  blue
bldpur=${txtbld}$(tput setaf 5) #  purple
bldcyn=${txtbld}$(tput setaf 5) #  cyan 
bldwht=${txtbld}$(tput setaf 7) #  white
txtrst=$(tput sgr0)             # Reset
info=${bldwht}*${txtrst}        # Feedback
pass=${bldblu}*${txtrst}
warn=${bldred}*${txtrst}
ques=${bldblu}?${txtrst}

##################################################################################
# Other common stuff
##################################################################################

me=`basename $0`

##################################################################################
# Test for AWS creds
##################################################################################

AWS_DETAILS_WARNING="${bldred}This script requires AWS_REGION, AWS_ACCESS_KEY and AWS_SECRET_ACCESS_KEY environment variables defined in a file called .aws-creds${txtrst}"

if [ ! -f '.aws-creds' ]
then
  echo "$AWS_DETAILS_WARNING"
  exit 1
fi

source .aws-creds

if [ -z $AWS_ACCESS_KEY -o -z $AWS_SECRET_ACCESS_KEY -o -z $AWS_REGION ] 
then
  echo $AWS_DETAILS_WARNING
  exit 1
fi

##################################################################################
# Create config for aws cli tool
##################################################################################

echo "[default]
aws_access_key_id = $AWS_ACCESS_KEY
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
region = $AWS_REGION" > aws.profile

export AWS_CONFIG_FILE=aws.profile

##################################################################################
# Create config for Knife
##################################################################################

cat .chef/knife.rb.src > .chef/knife.rb
echo "knife[:aws_access_key_id]  = \"$AWS_ACCESS_KEY\"
knife[:aws_secret_access_key] = \"$AWS_SECRET_ACCESS_KEY\"
knife[:region] = \"$AWS_REGION\"" >> .chef/knife.rb

##################################################################################
# Handle command line arguments
##################################################################################

BERKS="N"
UPDATE="N"
NAME=""
LOCAL=""
ENVIRONMENT=""
ATTRIBUTE=""

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo "${bldblu}$me${txtrst} - $TITLE"
      echo
      echo "Usage: $me [arguments] name for new instance"
      echo " "
      echo "options:"
      echo "-h, --help                  show brief help"
      echo "-b, --berks                 upload cookbooks from berkshelf to chef server"
      echo "-u, --update                don't create, run chef-client on all existing servers"
      echo "--local                     upload local cookbook (for development)"
      echo "--elastic-ip=ELASTIC_IP     assign that elastic ip"
      echo "--subnet=VPC_SUBNET         assign subnet (needed if not az a)"
      echo "-a, --az=AVAILABILITY_ZONE  specify the availability zone for the instance"
      echo "--flavor=FLAVOR             specify flavor (default ${FLAVOR})"
      echo "--environment=ENVIRONMENT   chef environment to use"
      echo "--ami=AMI_ID                specify ami"
      echo "--ssh-key=SSH_KEY           specify SSH KEY to use"
      echo "--attribute=ATTRIBUTE       specify node connect attribute"
      echo
      exit 0
    ;;
    -a)
      shift
      if test $# -gt 0; then
        AVAILABILITY_ZONE=$1
      else
        echo "${bldred}no availability zone specified${txtrst}"
        exit 1
      fi
      shift    
      ;;
    --az*)
      AVAILABILITY_ZONE=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --environment*)
      ENVIRONMENT=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --elastic-ip*)
      ELASTIC_IP=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --subnet*)
      VPC_SUBNET=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --flavor*)
      FLAVOR=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --ami*)
      BASE_AMI_ID=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --ssh-key*)
      SSH_KEY=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --attribute*)
      ATTRIBUTE=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -b|--berks)
      shift
      BERKS="Y"
      ;;
    -u|--update)
      shift
      UPDATE="Y"
      ;;
    --local)
      shift
      LOCAL="Y"
      ;;
    *)
      NAME=$1
      shift
      ;;
  esac
done

if [ "$UPDATE" == "N" ] && [ -z "$NAME" ]
then
  echo "${bldred}You must specify a name for the instance (try --help)${txtrst}"
  exit 1
fi

if [ "$UPDATE" == "N" ] && [ -z "$AVAILABILITY_ZONE" ]
then
  echo "${bldred}You must specify an availability zone for the instance (try --help)${txtrst}"
  exit 1
fi

if [ ! -z "$IAM_PROFILE" ]
then 
  ARG_IAM_PROFILE="--iam-profile $IAM_PROFILE "
else
  ARG_IAM_PROFILE=""
fi

if [ -z "$AWS_REGION" ]
then
  echo "${bldred}You must specify a AWS_REGION${txtrst}"
  exit 1
fi

if [ ! -z "$ELASTIC_IP" ]
then
  ARG_ELASTIC_IP="--associate-eip $ELASTIC_IP"
else 
  ARG_ELASTIC_IP=""
  if [ ! -z "$PUBLIC_IP" ]
  then
    ARG_PUBLIC_IP="--associate-public-ip"
  else
    ARG_PUBLIC_IP=""
  fi
fi

if [ ! -z "$SUDO" ]
then
  ARG_SUDO="--sudo"
else
  ARG_SUDO=""
fi

if [ -z "$BASE_AMI_ID" ]
then
  echo "${bldred}You must specify a BASE_AMI_ID${txtrst}"
  exit 1
fi 

if [ ! -z "$NODE_CONNECT_ATTRIBUTE" ]
then 
  ARG_NODE_CONNECT_ATTRIBUTE-"--server-connect-attribute $NODE_CONNECT_ATTRIBUTE"
elif [ ! -z "$ATTRIBUTE" ]
then
  ARG_NODE_CONNECT_ATTRIBUTE="--server-connect-attribute $ATTRIBUTE"  
else
  ARG_NODE_CONNECT_ATTRIBUTE=""
fi

if [ -z "$SSH_KEY" ] && [ -z "$AWS_SSH_KEY_ID" ]
then
  echo "${bldred}You must specify a SSH_KEY or the argument --ssh-key${txtrst}"
  exit 1
else
  if [ -z "$AWS_SSH_KEY_ID" ]
  then
    AWS_SSH_KEY_ID="$SSH_KEY"
  fi
  if [ -z "$IDENTITY_FILE" ] 
  then
    IDENTITY_FILE=".ssh/$AWS_SSH_KEY_ID.pem"
  fi
fi

##################################################################################
# Functions
##################################################################################

do_welcome() {
  #
  # Big up your bad self
  #
  echo
  echo "${txtbld}${TITLE}${txtrst}"
  echo "- By ${AUTHOR}"
  echo
}

do_environments() {
  if [ -z "$ENVIRONMENT" ]
  then
    ARG_ENVIRONMENT=""
  else
    # Check environment exists
    echo "${bldblu}Using $ENVIRONMENT Chef environment...${txtrst}"
    echo
    knife environment from file environments/$ENVIRONMENT.json
    knife environment show $ENVIRONMENT
    ARG_ENVIRONMENT="--environment $ENVIRONMENT"
  fi
}

do_berks() { 
  if [ "$BERKS" == "Y" ]
  then
    echo "${bldblu}Uploading Berkshelf cookbooks...${txtrst}"
    echo
    berks install
    berks upload
  else
    echo "${bldylw}Specify --berks to upload Berkshelf cookbooks${txtrst}"
  fi
}

do_local_cookbooks() {
  if [ -z "$LOCAL_COOKBOOKS" ]
  then 
    echo
    echo "${bldylw}No LOCAL_COOKBOOKS specified${txtrst}"
  else
    echo
    echo "${bldblu}Uploading local cookbooks..${txtrst}"
    echo
    for cookbook in ${LOCAL_COOKBOOKS}
    do
      knife cookbook upload $cookbook
    done
  fi
}

do_role() {
  if [ -z "$ROLE" ]
  then 
    echo
    echo "${bldylw}No ROLE specified${txtrst}"
  else
    echo
    echo "${bldblu}Uploading $ROLE role...${txtrst}"
    echo
    knife role from file roles/${ROLE}.json
  fi
}

do_create_aws_data_bag() {
  echo
  echo "${bldblu}Uploading data bag for aws...${txtrst}"
  echo

  mkdir -p data_bags/aws

  echo "{
    \"id\": \"main\",
    \"aws_access_key_id\": \"$AWS_ACCESS_KEY\",
    \"aws_secret_access_key\": \"$AWS_SECRET_ACCESS_KEY\"
  }" > data_bags/aws/main.json

  knife data bag create aws
  knife data bag from file aws data_bags/aws/main.json
}

do_update() {
  if [ "$UPDATE" == "Y" ]
  then
    echo
    echo "${bldblu}Updating all servers${txtrst}"
    echo

    if [ ! -z "$ARG_NODE_CONNECT_ATTRIBUTE" ]
    then
      # Different parameter for some reason.
      ARG_NODE_CONNECT_ATTRIBUTE="${ARG_NODE_CONNECT_ATTRIBUTE/server-connect-attribute/attribute}"
    fi

    if [ ! -z "$SUDO" ]
    then
      tCOMMAND="sudo chef-client"
    else 
      tCOMMAND="chef-client"
    fi

    if [ -z "$ENVIRONMENT" ]
    then
      echo knife ssh "role:${ROLE}" "$tCOMMAND" -x $SSH_USER $ARG_NODE_CONNECT_ATTRIBUTE  -i $IDENTITY_FILE $ARG_ENVIRONMENT
    else
      echo knife ssh "chef_environment:${ENVIRONMENT} AND role:${ROLE}" "$tCOMMAND" -x $SSH_USER $ARG_NODE_CONNECT_ATTRIBUTE -i $IDENTITY_FILE $ARG_ENVIRONMENT
    fi
    exit 0
  fi
}

##################################################################################
# Ensure the specified security group exists
##################################################################################

check_security_groups() {
  
  if [ ! -z "$SECURITY_GROUP" ]
  then
    aws ec2 describe-security-groups --group-ids $SECURITY_GROUP > /dev/null
  fi

  if [ ! -z "$MY_SECURITY_GROUP" ]
  then
    aws ec2 describe-security-groups --group-ids $MY_SECURITY_GROUP > /dev/null
  fi
}

##################################################################################
# Ensure security group of name exists in correct vpc and has the rules that 
# can be found in security_groups/$group_name.json
##################################################################################

ensure_vpc_security_group() {
  tSECURITY_GROUP=$1
  tVPC_ID=$2
  SECURITY_GROUP=`aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$tVPC_ID" "Name=group-name,Values=$tSECURITY_GROUP" --output text --query 'SecurityGroups[*].GroupId'`

  if [ -z "$SECURITY_GROUP" ]
  then
    echo "${bldred}Could not find security group $tSECURITY_GROUP in $tVPC_ID${txtrst}"
    exit 1
  fi
}

##################################################################################
# See if an instance with this name already exists and check it's in 
# the specified availability zone
#
# Accepts optional attribute parameter so you can ask for PrivateIpAddress for
# private VPC instances otherwise defaults to PublicDnsName
##################################################################################


check_for_existing_instance() {

  if [ -z "$1" ]
  then
    CONNECT_ATTR="PublicDnsName"
  else
    CONNECT_ATTR="$1"
  fi

  INSTANCE=`aws ec2 describe-instances --filters aws ec2 describe-instances --filters "Name=tag-key,Values=Name,Name=tag-value,Values=$NAME" "Name=instance-state-name,Values=running" --output text --query "Reservations[*].Instances[*].$CONNECT_ATTR"`
  
  if [ ! -z "$INSTANCE" ]
  then
    EXISTING_AZ=`aws ec2 describe-instances --filters aws ec2 describe-instances --filters "Name=tag-key,Values=Name,Name=tag-value,Values=$NAME" "Name=instance-state-name,Values=running" --output text --query 'Reservations[*].Instances[*].Placement.AvailabilityZone' | head -1`

    if [ "$EXISTING_AZ" != "${AWS_REGION}${AVAILABILITY_ZONE}" ]
    then
      echo "${bldred}An instance called $NAME already exists and it is not in the requested availability zone.${txtrst}"
      exit 1
    fi
  fi
}

do_instance() {
  #
  # Create or bootstrap the instance
  #
  if [ -z "$INSTANCE" ]
  then
    echo
    echo "${bldblu}Creating ${NAME} server node...${txtrst}"
    echo
    knife ec2 server create --image $BASE_AMI_ID --node-name $NAME --run-list "$RUN_LIST" --identity-file $IDENTITY_FILE --flavor $FLAVOR --security-group-ids $SECURITY_GROUP,$MY_SECURITY_GROUP --ssh-key $AWS_SSH_KEY_ID -x $SSH_USER --availability-zone ${AWS_REGION}${AVAILABILITY_ZONE} -T Role=$EC2_ROLE --subnet $VPC_SUBNET $ARG_NODE_CONNECT_ATTRIBUTE $ARG_ENVIRONMENT $ARG_IAM_PROFILE $ARG_PUBLIC_IP $ARG_ELASTIC_IP
  else
    echo
    echo "${bldblu}${NAME} exists as node ${INSTANCE}...${txtrst}"
    echo
    knife bootstrap $INSTANCE -x $SSH_USER --node-name $NAME --run-list "$RUN_LIST" --identity-file $IDENTITY_FILE $ARG_ENVIRONMENT $ARG_SUDO
  fi
}