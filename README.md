chef-bashstrap
==============

The purpose of this repo is to help you easily create bash scripts that allow the creation, management and continuing maintenance of servers and cloud instances with Chef. An easy addition to your Chef repository that makes managing nodes with AWS and Knife much easier.

There a better methods for achieving this at scale but when managing a single server for a personal project or a couple of servers for client we've found this pattern really helpful. These scripts act as a simple wrapper around knife and relevant aws cli commands and allows you to distribute a straightforward script that updates cookbook, roles and other chef configuration and then bootstraps or updates your node.

If you've found yourself writing an update or create node script that runs knife with the various command line arguments you need then this might come in handy. The scripts also helps keep various secrets out of your scripting and therefore out of your repositories.

###Requirements

* [AWS CLI](http://docs.aws.amazon.com/cli/latest/index.html)
* [Chef](http://www.getchef.com/)

###Example usage

Here's how we use it. Add the following files to .gitignore.

	.chef/knife.rb  
	environments/  
	.aws-creds  
	aws.profile
	
Move `knife.rb` (without `knife[:aws_access_key_id]` etc) to `knife.rb.src`.

Create a file called `.aws-creds` with your AWS access key, secret key and region in it.

	AWS_ACCESS_KEY=XXXXXXXXXXXXXXXXXXXX
	AWS_SECRET_ACCESS_KEY=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	AWS_REGION=eu-west-1
	
Create a copy of the most relevant example script and set the variables you need.

####.config-common.sh

This is where you'd put configuration that's common to all the scripts. e.g. in the example we have in the repository we tell our scripts to connect as the *ubnutu* user and that it needs to *sudo* to run it's commands.

	SSH_USER="ubuntu"
	SUDO="Y" 

###Command line options and related variables 

The idea behind these attributes is that you define them in your script, a common script or the .aws-creds file so you don't have to remember them every time you create an instance but they are still available to override if required.


| Variable                         | cli option             | Usage                                               |   
|-----------------------------------------------------------|-----------------------------------------------------|
| `ATTRIBUTE`                      | `--attribute`          | The node connect attribute                          |
| `AVAILABILITY_ZONE`              | `-a`, `--az`           | The availability zone to create the instance in     |
| `AWS_ACCESS_KEY`                 | *none*                 | Used in knife.rb, aws.profile                       |
| `AWS_REGION`                     | *none*                 | Used in knife.rb, aws.profile                       |
| `AWS_SECRET_ACCESS_KEY`          | *none*                 | Used in knife.rb, aws.profile                       |
| `BASE_AMI_ID`                    | `--ami`                | The AMI to base the instance on                     |
| `BERKS`                          | `-b`, `--berks`        | Update and upload Berkshelf cookbooks               |
| `EC2_ROLE`                       | `--ec2-role`           | Creates a tag "Role" with the contents              |
| `ELASTIC_IP`                     | `--elastic-ip`         | Use this elastic IP                                 |
| `ENVIRONMENT`                    | `--environment`        | Use this as Chef environment                        |
| `IAM_PROFILE`                    | `--iam-profile`        | Use this IAM profile for the instance               |
| `FLAVOR`                         | `--flavor`             | Which size instance to use                          |
| `LOCAL`                          | `--local`              | Upload LOCAL_COOKBOOKS from cookbooks               |
| `LOCAL_COOKBOOKS`                | *none*                 | The cookbooks to upload when `--local` is specified |
| `NAME`                           | (anything)             | The name of the instance we're creating             |
| `PUBLIC_IP`                      | `--public-ip`          | Request a public ip                                 |
| `SECURITY_GROUP`                 | `--security-group`     | The security group to assign to the instance        |
| `SSH_KEY`                        | `--ssh-key`            | The SSH key to use                                  |
| `SSH_PATH`                       | `--ssh-path`           | The path to your ssh keys (defaults to ./.ssh)      |
| `SSH_USER`                       | `--ssh-user`           | The use to connect to the instance as               |
| `SUDO`							| `--sudo`               | sudo before running chef-client                     |
| `UPDATE`                         | `--update`             | Update an existing instances                        |
| `VPC_SUBNET`                     | `--subnet`             | Create instance in this VPC subnet                  |


###Functions

####do_welcome

Updates the environment `ENVIRONMENT` from `environments/$ENVIRONMENT.json` and sets up the `ARG_ENVIRONMENT` variable which should be passed to your knife commands.

####do_berks

Installs and uploads Berkshef cookbooks if the `BERKS` variable or the command line option is set.

####do_local_cookbooks

Uploads local cookbooks from `LOCAL_COOKBOOKS` if `LOCAL` or `--local` is set.

####do_role

Uploads `roles/$ROLE.json` if `ROLE` is set.

####do_create_aws_data_bag

Creates a data bag called `aws` and a data bag item called `main` with the following in it: 

	{
		"id": "main",
		"aws_access_key_id": "$AWS_ACCESS_KEY",
    	"aws_secret_access_key": "$AWS_SECRET_ACCESS_KEY"
  	}

Not a pattern we'd recommend but some cookbooks require this. If you use it, but `data_bags/aws/main.json` in `.gitignore`.

####do_update




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
      echo knife ssh "roles:${ROLE}" "$tCOMMAND" -x $SSH_USER $ARG_NODE_CONNECT_ATTRIBUTE  -i $IDENTITY_FILE $ARG_ENVIRONMENT
    else
      echo knife ssh "chef_environment:${ENVIRONMENT} AND roles:${ROLE}" "$tCOMMAND" -x $SSH_USER $ARG_NODE_CONNECT_ATTRIBUTE -i $IDENTITY_FILE $ARG_ENVIRONMENT
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
    knife ec2 server create --image $BASE_AMI_ID --node-name $NAME --run-list "$RUN_LIST" --identity-file $IDENTITY_FILE --flavor $FLAVOR --security-group-ids $SECURITY_GROUP --ssh-key $AWS_SSH_KEY_ID -x $SSH_USER --availability-zone ${AWS_REGION}${AVAILABILITY_ZONE} $ARG_VPC_SUBNET $ARG_EC2_ROLE $ARG_NODE_CONNECT_ATTRIBUTE $ARG_ENVIRONMENT $ARG_IAM_PROFILE $ARG_PUBLIC_IP $ARG_ELASTIC_IP
  else
    echo
    echo "${bldblu}${NAME} exists as node ${INSTANCE}...${txtrst}"
    echo
    knife bootstrap $INSTANCE -x $SSH_USER --node-name $NAME --run-list "$RUN_LIST" --identity-file $IDENTITY_FILE $ARG_ENVIRONMENT $ARG_SUDO
  fi
}
