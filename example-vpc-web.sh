#!/bin/bash

set -e

##################################################################################
# Configuration section
##################################################################################

source .common-config.sh

TITLE="VPC web server"
AUTHOR="Andy Gale <andy@hellofutu.re>"
LOCAL_COOKBOOKS="example-web"
ROLE="web"
RUN_LIST="role[${ROLE}]"
SECURITY_GROUP="sg-xxxxxxxx"
BASE_AMI_ID="ami-8e987ef9"
FLAVOR="c3.large"
VPC_SUBNET="subnet-xxxxxxxx"
VPC_ID="vpc-xxxxxxxx"

##################################################################################
# Get common functions
##################################################################################

source ./chef-bashstrap/strap.sh

##################################################################################
# Run common functions
##################################################################################

do_welcome
do_environments
do_berks
do_local_cookbooks

##################################################################################
# Upload sites data bag
##################################################################################

echo
echo "${bldblu}Uploading data bag for sites...${txtrst}"
echo

knife data bag create sites $ARG_ENVIRONMENT
knife data bag from file sites data_bags/sites/* $ARG_ENVIRONMENT

do_update

ensure_vpc_security_group "example-web" $VPC_ID
check_for_existing_instance "PrivateIpAddress"

do_instance
