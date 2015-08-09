#/bin/bash
#
# This script runs a Eucalyptus CloudFormation demo which uses the
# WordPress_Single_Instance_Eucalyptus.template to create WordPress-based
# blog. This demo then shows how this application can be migrated between
# AWS and Eucalyptus.
#
# This script was originally designed to run on a combined CLC+UFS+MC host,
# as installed by FastStart or the Cloud Administrator Course. To run this
# on an arbitrary management workstation, you will need to move the appropriate
# credentials to your management host.
#
# Before running this (or any other demo script in the euca-demo project),
# you should run the following scripts to initialize the demo environment
# to a baseline of known resources which are assumed to exist.
# - Run demo-00-initialize.sh on the CLC as the Eucalyptus Administrator.
# - Run demo-01-initialize-account.sh on the CLC as the Eucalyptus Administrator.
# - Run demo-02-initialize-account-administrator.sh on the CLC as the Demo Account Administrator.
# - Run demo-03-initialize-account-dependencies.sh on the CLC as the Demo Account Administrator.
#
# This script assumes many conventions created by the installation DNS and demo initialization
# scripts.
#

#  1. Initalize Environment

bindir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
templatesdir=${bindir%/*}/templates
tmpdir=/var/tmp

federation=aws

image_name=CentOS-6-x86_64-CFN-AWSCLI

mysql_root=root
mysql_user=demo
mysql_password=password
mysql_db=wordpressdb
mysql_bakfile=$mysql_db.bak

step=0
speed_max=400
run_default=10
pause_default=2
next_default=5

euca_stack_created=n
aws_stack_created=n

create_attempts=24
create_default=20
login_attempts=6
login_default=20
delete_attempts=6
delete_default=20

interactive=1
speed=100
verbose=0
mode=e
euca_region=${AWS_DEFAULT_REGION#*@}
euca_account=${AWS_ACCOUNT_NAME:-demo}
euca_user=${AWS_USER_NAME:-admin}
euca_ssh_user=root
euca_ssh_key=demo
aws_region=us-east-1
aws_account=euca
aws_user=demo
aws_ssh_user=ec2-user
aws_ssh_key=demo


#  2. Define functions

usage () {
    echo "Usage: ${BASH_SOURCE##*/} [-I [-s | -f]] [-v] [-m mode]"
    echo "                   [-r euca_region ] [-a euca_account] [-u euca_user]"
    echo "                   [-R aws_region] [-A aws_account] [-U aws_user]"
    echo "  -I               non-interactive"
    echo "  -s               slower: increase pauses by 25%"
    echo "  -f               faster: reduce pauses by 25%"
    echo "  -v               verbose"
    echo "  -m mode          mode: Run a=AWS, e=Eucalyptus, b=Both or m=Migrate (default: $mode)"
    echo "  -r euca_region   Eucalyptus Region (default: $euca_region)"
    echo "  -a euca_account  Eucalyptus Account (default: $euca_account)"
    echo "  -u euca_user     Eucalyptus User (default: $euca_user)"
    echo "  -R aws_region    AWS Region (default: $aws_region)"
    echo "  -A aws_account   AWS Account (default: $aws_account)"
    echo "  -U aws_user      AWS User (default: $aws_user)"
}

run() {
    if [ -z $1 ] || (($1 % 25 != 0)); then
        ((seconds=run_default * speed / 100))
    else
        ((seconds=run_default * $1 * speed / 10000))
    fi
    if [ $interactive = 1 ]; then
        echo
        echo -n "Run? [Y/n/q]"
        read choice
        case "$choice" in
            "" | "y" | "Y" | "yes" | "Yes") choice=y ;;
            "n" | "N" | "no" | "No") choice=n ;;
             *) echo "cancelled"
                exit 2;;
        esac
    else
        echo
        echo -n -e "Waiting $(printf '%2d' $seconds) seconds..."
        while ((seconds > 0)); do
            if ((seconds < 10 || seconds % 10 == 0)); then
                echo -n -e "\rWaiting $(printf '%2d' $seconds) seconds..."
            fi
            sleep 1
            ((seconds--))
        done
        echo " Done"
        choice=y
    fi
}

pause() {
    if [ -z $1 ] || (($1 % 25 != 0)); then
        ((seconds=pause_default * speed / 100))
    else
        ((seconds=pause_default * $1 * speed / 10000))
    fi
    if [ $interactive = 1 ]; then
        echo "#"
        read pause
        echo -en "\033[1A\033[2K"    # undo newline from read
    else
        echo "#"
        sleep $seconds
    fi
}

next() {
    if [ -z $1 ] || (($1 % 25 != 0)); then
        ((seconds=next_default * speed / 100))
    else
        ((seconds=next_default * $1 * speed / 10000))
    fi
    if [ $interactive = 1 ]; then
        echo
        echo -n "Next? [Y/q]"
        read choice
        case "$choice" in
            "" | "y" | "Y" | "yes" | "Yes") choice=y ;;
             *) echo "cancelled"
                exit 2;;
        esac
    else
        echo
        echo -n -e "Waiting $(printf '%2d' $seconds) seconds..."
        while ((seconds > 0)); do
            if ((seconds < 10 || seconds % 10 == 0)); then
                echo -n -e "\rWaiting $(printf '%2d' $seconds) seconds..."
            fi
            sleep 1
            ((seconds--))
        done
        echo " Done"
        choice=y
    fi
}


#  3. Parse command line options

while getopts Isfvm:r:a:u:R:A:U:? arg; do
    case $arg in
    I)  interactive=0;;
    s)  ((speed < speed_max)) && ((speed=speed+25));;
    f)  ((speed > 0)) && ((speed=speed-25));;
    v)  verbose=1;;
    m)  mode="$OPTARG";;
    r)  euca_region="$OPTARG";;
    a)  euca_account="$OPTARG";;
    u)  euca_user="$OPTARG";;
    R)  aws_region="$OPTARG";;
    A)  aws_account="$OPTARG";;
    U)  aws_user="$OPTARG";;
    ?)  usage
        exit 1;;
    esac
done

shift $(($OPTIND - 1))


#  4. Validate environment

if [ -z $mode ]; then
    echo "-m mode missing!"
    echo "Could not automatically determine mode, and it was not specified as a parameter"
    exit 8
else
    case $mode in
      a|e|b|m) ;;
      *)
        echo "-m $mode invalid: Valid modes are a=AWS (only), e=Eucalyptus (only), b=Both, m=Migrate (only)"
        exit 9;;
    esac
fi

if [ -z $euca_region ]; then
    echo "-r euca_region missing!"
    echo "Could not automatically determine Eucalyptus region, and it was not specified as a parameter"
    exit 10
else
    case $euca_region in
      us-east-1|us-west-1|us-west-2) ;&
      sa-east-1) ;&
      eu-west-1|eu-central-1) ;&
      ap-northeast-1|ap-southeast-1|ap-southeast-2)
        echo "-r $euca_region invalid: Please specify a Eucalyptus region"
        exit 11;;
    esac
fi

if [ -z $euca_account ]; then
    echo "-a euca_account missing!"
    echo "Could not automatically determine Eucalyptus account, and it was not specified as a parameter"
    exit 12
fi

if [ -z $euca_user ]; then
    echo "-u euca_user missing!"
    echo "Could not automatically determine Eucalyptus user, and it was not specified as a parameter"
    exit 14
fi

if [ -z $aws_region ]; then
    echo "-R aws_region missing!"
    echo "Could not automatically determine AWS region, and it was not specified as a parameter"
    exit 20
else
    case $aws_region in
      us-east-1)
        aws_s3_domain=s3.amazonaws.com;;
      us-west-1|us-west-2) ;&
      sa-east-1) ;&
      eu-west-1|eu-central-1) ;&
      ap-northeast-1|ap-southeast-1|ap-southeast-2)
        aws_s3_domain=s3-$aws_region.amazonaws.com;;
    *)
        echo "-R $aws_region invalid: Please specify an AWS region"
        exit 21;;
    esac
fi

if [ -z $aws_account ]; then
    echo "-A aws_account missing!"
    echo "Could not automatically determine AWS account, and it was not specified as a parameter"
    exit 22
fi

if [ -z $aws_user ]; then
    echo "-U aws_user missing!"
    echo "Could not automatically determine AWS user, and it was not specified as a parameter"
    exit 24
fi

euca_user_region=$euca_region-$euca_account-$euca_user@$euca_region

if ! grep -s -q "\[user $euca_region-$euca_account-$euca_user]" ~/.euca/$euca_region.ini; then
    echo "Could not find Eucalyptus ($euca_region) Region Demo ($euca_account) Account Demo ($euca_user) User Euca2ools user!"
    echo "Expected to find: [user $euca_region-$euca_account-$euca_user] in ~/.euca/$euca_region.ini"
    exit 50
fi

euca_profile=$euca_region-$euca_account-$euca_user

if ! grep -s -q "\[profile $euca_profile]" ~/.aws/config; then
    echo "Could not find Eucalyptus ($euca_region) Region Demo ($euca_account) Account Demo ($user) User AWSCLI profile!"
    echo "Expected to find: [profile $euca_profile] in ~/.aws/config"
    exit 51
fi

aws_user_region=$federation-$aws_account-$aws_user@$aws_region

if ! grep -s -q "\[user $federation-$aws_account-$aws_user]" ~/.euca/$federation.ini; then
    echo "Could not find AWS ($aws_account) Account Demo ($aws_user) User Euca2ools user!"
    echo "Expected to find: [user $federation-$aws_account-$aws_user] in ~/.euca/$federation.ini"
    exit 52
fi

aws_profile=$aws_account-$aws_user

if ! grep -s -q "\[profile $aws_profile]" ~/.aws/config; then
    echo "Could not find AWS ($aws_account) Account Demo ($aws_user) User AWSCLI profile!"
    echo "Expected to find: [profile $aws_profile] in ~/.aws/config"
    exit 53
fi

euca_cloudformation_url=$(sed -n -e "s/cloudformation-url = \(.*\)\/services\/CloudFormation$/\1/p" /etc/euca2ools/conf.d/$euca_region.ini)
aws_cloudformation_url=https://cloudformation.$aws_region.amazonaws.com

if [ -z $euca_cloudformation_url ]; then
    echo "Could not automatically determine Eucalyptus CloudFormation URL"
    echo "For Eucalyptus Regions, we attempt to lookup the value of "cloudformation-url" in /etc/euca2ools/conf.d/$euca_region.ini"
    echo 60
fi

if ! rpm -q --quiet w3m; then
    echo "w3m missing: This demo uses the w3m text-mode browser to confirm webpage content"
    exit 98
fi


#  5. Run Demo

start=$(date +%s)

((++step))
if [ $mode = a -o $mode = b ]; then
    aws_demo_initialized=y

    if [ $verbose = 1 ]; then
        clear
        echo
        echo "============================================================"
        echo
        echo "$(printf '%2d' $step). Confirm existence of AWS Demo depencencies"
        echo
        echo "============================================================"
        echo
        echo "Commands:"
        echo
        echo "euca-describe-keypairs --filter \"key-name=demo\" \\"
        echo "                       --region=$aws_user_region"

        next

        echo
        echo "# euca-describe-keypairs --filter \"key-name=demo\" \\"
        echo ">                        --region=$aws_user_region"
        euca-describe-keypairs --filter "key-name=demo" \
                               --region=$aws_user_region | grep "demo" || aws_demo_initialized=n

        next

    else
        euca-describe-keypairs --filter "key-name=demo" \
                               --region=$aws_user_region | grep -s -q "demo" || aws_demo_initialized=n
    fi

    if [ $aws_demo_initialized = n ]; then
        echo
        echo "At least one AWS prerequisite for this script was not met."
        echo "Please re-run the AWS demo initialization scripts referencing this AWS account:"
        echo "- demo-01-initialize-aws_account.sh -r $aws_region -a $aws_account"
        echo "- demo-03-initialize-aws_account-dependencies.sh -r $aws_region -a $aws_account"
        exit 99
    fi
fi


((++step))
if [ $mode = e -o $mode = b ]; then
    euca_demo_initialized=y

    if [ $verbose = 1 ]; then
        clear
        echo
        echo "============================================================"
        echo
        echo "$(printf '%2d' $step). Confirm existence of Eucalyptus Demo depencencies"
        echo
        echo "============================================================"
        echo
        echo "Commands:"
        echo
        echo "euca-describe-images --filter \"manifest-location=images/$image_name.raw.manifest.xml\" \\"
        echo "                     --region=$euca_user_region | cut -f1,2,3"
        echo
        echo "euca-describe-keypairs --filter \"key-name=demo\" \\"
        echo "                       --region=$euca_user_region"

        next

        echo
        echo "# euca-describe-images --filter \"manifest-location=images/$image_name.raw.manifest.xml\" \\"
        echo ">                      --region=$euca_user_region | cut -f1,2,3"
        euca-describe-images --filter "manifest-location=images/$image_name.raw.manifest.xml" \
                             --region=$euca_user_region | cut -f1,2,3 | grep "$image_name" || euca_demo_initialized=n
        pause

        echo "# euca-describe-keypairs --filter \"key-name=demo\"\\"
        echo ">                      --region=$euca_user_region"
        euca-describe-keypairs --filter "key-name=demo" \
                               --region=$euca_user_region | grep "demo" || euca_demo_initialized=n

        next

    else
        euca-describe-images --filter "manifest-location=images/$image_name.raw.manifest.xml" \
                             --region=$euca_user_region | cut -f1,2,3 | grep -s -q "$image_name" || euca_demo_initialized=n
        euca-describe-keypairs --filter "key-name=demo" \
                               --region=$euca_user_region | grep -s -q "demo" || euca_demo_initialized=n
    fi

    if [ $euca_demo_initialized = n ]; then
        echo
        echo "At least one Eucalyptus prerequisite for this script was not met."
        echo "Please re-run the Eucalyptus demo initialization scripts referencing this demo account:"
        echo "- demo-00-initialize.sh -r $euca_region"
        echo "- demo-01-initialize-account.sh -r $euca_region -a $euca_account"
        echo "- demo-03-initialize-account-dependencies.sh -r $euca_region -a $euca_account"
        exit 99
    fi
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Download WordPress CloudFormation Template from AWS S3 Bucket"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "aws s3 cp s3://demo-$aws_account/demo-30-cfn-wordpress/WordPress_Single_Instance_Eucalyptus.template \\"
echo "          $tmpdir/WordPress_Single_Instance_Eucalyptus.template \\"
echo "          --profile $aws_profile --region=$aws_region"

run 50

if [ $choice = y ]; then
    echo
    echo "# aws s3 cp s3://demo-$aws_account/demo-30-cfn-wordpress/WordPress_Single_Instance_Eucalyptus.template \\"
    echo ">           $tmpdir/WordPress_Single_Instance_Eucalyptus.template \\"
    echo ">           --profile $aws_profile --region=$aws_region"
    aws s3 cp s3://demo-$aws_account/demo-30-cfn-wordpress/WordPress_Single_Instance_Eucalyptus.template \
              $tmpdir/WordPress_Single_Instance_Eucalyptus.template \
              --profile $aws_profile --region=$aws_region

    next
fi


((++step))
if [ $verbose = 1 ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Display WordPress CloudFormation template"
    echo "    - Like most CloudFormation Templates, the WordPress Template uses the \"AWSRegionArch2AMI\" Map"
    echo "      to lookup the AMI ID of the Image to use when creating new Instances, based on the Region"
    echo "      in which the Template is run. Similar to AWS, each Eucalyptus Region will also have a unqiue"
    echo "      EMI ID for the Image which must be used there."
    echo "    - This Template has been modified to add a row containing the Eucalyptus Region EMI ID to this"
    echo "      Map. It is otherwise identical to what is run in AWS."
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "more $tmpdir/WordPress_Single_Instance_Eucalyptus.template"

    run 50

    if [ $choice = y ]; then
        echo
        echo "# more $tmpdir/WordPress_Single_Instance_Eucalyptus.template"
        if [ $interactive = 1 ]; then
            more $tmpdir/WordPress_Single_Instance_Eucalyptus.template
        else
            # This will iterate over the file in a manner similar to more, but non-interactive
            ((rows=$(tput lines)-2))
            lineno=0
            while IFS= read line; do
                echo "$line"
                if [ $((++lineno % rows)) = 0 ]; then
                    tput rev; echo -n "--More--"; tput sgr0; echo -n " (Waiting 10 seconds...)"
                    sleep 10
                    echo -e -n "\r                                \r"
                fi
            done < $tmpdir/WordPress_Single_Instance_Eucalyptus.template
        fi

        next 200
    fi
fi


((++step))
if [ $mode = a -o $mode = b ]; then
    if [ $verbose = 1 ]; then
        clear
        echo
        echo "============================================================"
        echo
        echo "$(printf '%2d' $step). List existing AWS Resources"
        echo "    - So we can compare with what this demo creates"
        echo
        echo "============================================================"
        echo
        echo "Commands:"
        echo
        echo "euca-describe-groups --region=$aws_user_region"
        echo
        echo "euca-describe-instances --region=$aws_user_region"

        run 50

        if [ $choice = y ]; then
            echo
            echo "# euca-describe-groups --region=$aws_user_region"
            euca-describe-groups --region=$aws_user_region
            pause

            echo "# euca-describe-instances --region=$aws_user_region"
            euca-describe-instances --region=$aws_user_region

            next
        fi
    fi
fi


((++step))
if [ $mode = a -o $mode = b ]; then
    if [ $verbose = 1 ]; then
        clear
        echo
        echo "============================================================"
        echo
        echo "$(printf '%2d' $step). List existing AWS CloudFormation Stacks"
        echo "    - So we can compare with what this demo creates"
        echo
        echo "============================================================"
        echo
        echo "Commands:"
        echo
        echo "euform-describe-stacks --region=$aws_user_region"

        run 50

        if [ $choice = y ]; then
            echo
            echo "# euform-describe-stacks --region=$aws_user_region"
            euform-describe-stacks --region=$aws_user_region

            next
        fi
    fi
fi


((++step))
if [ $mode = a -o $mode = b ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Create the AWS Stack"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "euform-create-stack --template-file $tmpdir/WordPress_Single_Instance_Eucalyptus.template \\"
    echo "                    --parameter \"KeyName=$aws_ssh_key\" \\"
    echo "                    --parameter \"InstanceType=m1.medium\" \\"
    echo "                    --parameter \"DBUser=$mysql_user\" \\"
    echo "                    --parameter \"DBPassword=$mysql_password\" \\"
    echo "                    --parameter \"DBRootPassword=$mysql_password\" \\"
    echo "                    --parameter \"EndPoint=$aws_cloudformation_url\" \\"
    echo "                    --capabilities CAPABILITY_IAM \\"
    echo "                    --region $aws_user_region \\"
    echo "                    WordPressDemoStack"

    if [ "$(euform-describe-stacks --region $aws_user_region WordPressDemoStack 2> /dev/null | grep "^STACK" | cut -f3)" = "CREATE_COMPLETE" ]; then
        echo
        tput rev
        echo "Already Created!"
        tput sgr0

        next 50

    else
        run

        if [ $choice = y ]; then
            echo
            echo "# euform-create-stack --template-file $tmpdir/WordPress_Single_Instance_Eucalyptus.template \\"
            echo ">                     --parameter \"KeyName=$aws_ssh_key\" \\"
            echo ">                     --parameter \"InstanceType=m1.medium\" \\"
            echo ">                     --parameter \"DBUser=$mysql_user\" \\"
            echo ">                     --parameter \"DBPassword=$mysql_password\" \\"
            echo ">                     --parameter \"DBRootPassword=$mysql_password\" \\"
            echo ">                     --parameter \"EndPoint=$aws_cloudformation_url\" \\"
            echo ">                     --capabilities CAPABILITY_IAM \\"
            echo ">                     --region $aws_user_region \\"
            echo ">                     WordPressDemoStack"
            euform-create-stack --template-file $tmpdir/WordPress_Single_Instance_Eucalyptus.template \
                                --parameter "KeyName=$aws_ssh_key" \
                                --parameter "InstanceType=m1.medium" \
                                --parameter "DBUser=$mysql_user" \
                                --parameter "DBPassword=$mysql_password" \
                                --parameter "DBRootPassword=$mysql_password" \
                                --parameter "EndPoint=$aws_cloudformation_url" \
                                --capabilities CAPABILITY_IAM \
                                --region $aws_user_region \
                                WordPressDemoStack

            aws_stack_created=y

            next
        fi
    fi
fi


((++step))
if [ $mode = a -o $mode = b ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Monitor AWS Stack creation"
    echo "    - NOTE: This can take about 400 - 500 seconds"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "euform-describe-stacks --region $aws_user_region"
    echo
    echo "euform-describe-stack-events --region $aws_user_region WordPressDemoStack | head -5"

    if [ "$(euform-describe-stacks --region $aws_user_region WordPressDemoStack 2> /dev/null | grep "^STACK" | cut -f3)" = "CREATE_COMPLETE" ]; then
        echo
        tput rev
        echo "Already Complete!"
        tput sgr0

        next 50

    else
        run 50

        if [ $choice = y ]; then
            echo
            echo "# euform-describe-stacks --region $aws_user_region"
            euform-describe-stacks --region $aws_user_region
            pause

            attempt=0
            ((seconds=$create_default * $speed / 100))
            while ((attempt++ <= create_attempts)); do
                echo
                echo "# euform-describe-stack-events --region $aws_user_region WordPressDemoStack | head -5"
                euform-describe-stack-events --region $aws_user_region WordPressDemoStack 2> /dev/null | head -5

                status=$(euform-describe-stacks --region $aws_user_region WordPressDemoStack 2> /dev/null | grep "^STACK" | cut -f3)
                if [ -z "$status" -o "$status" = "CREATE_COMPLETE" -o "$status" = "CREATE_FAILED" -o "$status" = "ROLLBACK_COMPLETE" ]; then
                    break
                else
                    echo
                    echo -n "Not finished ($RC). Waiting $seconds seconds..."
                    sleep $seconds
                    echo " Done"
                fi
            done

            next
        fi
    fi
fi


((++step))
if [ $mode = a -o $mode = b ]; then
    if [ $verbose = 1 ]; then
        clear
        echo
        echo "============================================================"
        echo
        echo "$(printf '%2d' $step). List updated AWS Resources"
        echo "    - Note addition of new group and instance"
        echo
        echo "============================================================"
        echo
        echo "Commands:"
        echo
        echo "euca-describe-groups --region $aws_user_region"
        echo
        echo "euca-describe-instances --region $aws_user_region"

        run 50

        if [ $choice = y ]; then
            echo
            echo "# euca-describe-groups --region $aws_user_region"
            euca-describe-groups --region $aws_user_region
            pause

            echo "# euca-describe-instances --region $aws_user_region"
            euca-describe-instances --region $aws_user_region

            next
        fi
    fi
fi


((++step))
if [ $verbose = 1 ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Obtain AWS Instance and Blog details"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "aws_instance_id=\$(euform-describe-stack-resources -n WordPressDemoStack -l WebServer --region=$aws_user_region | cut -f3)"
    echo "aws_public_name=\$(euca-describe-instances --region=$aws_user_region \$aws_instance_id | grep \"^INSTANCE\" | cut -f4)"
    echo "aws_public_ip=\$(euca-describe-instances --region=$aws_user_region \$aws_instance_id | grep \"^INSTANCE\" | cut -f17)"
    echo
    echo "aws_wordpress_url=\$(euform-describe-stacks --region=$aws_user_region WordPressDemoStack | grep \"^OUTPUT.WebsiteURL\" | cut -f3)"

    next

    echo
    echo "# aws_instance_id=\$(euform-describe-stack-resources -n WordPressDemoStack -l WebServer --region=$aws_user_region | cut -f3)"
    aws_instance_id=$(euform-describe-stack-resources -n WordPressDemoStack -l WebServer --region=$aws_user_region | cut -f3)
    echo "$aws_instance_id"
    echo "#"
    echo "# aws_public_name=\$(euca-describe-instances --region=$aws_user_region \$aws_instance_id | grep \"^INSTANCE\" | cut -f4)"
    aws_public_name=$(euca-describe-instances --region=$aws_user_region $aws_instance_id | grep "^INSTANCE" | cut -f4)
    echo "$aws_public_name"
    echo "#"
    echo "# aws_public_ip=\$(euca-describe-instances --region=$aws_user_region \$aws_instance_id | grep \"^INSTANCE\" | cut -f17)"
    aws_public_ip=$(euca-describe-instances --region=$aws_user_region $aws_instance_id | grep "^INSTANCE" | cut -f17)
    echo "$aws_public_ip"
    pause

    echo "# aws_wordpress_url=\$(euform-describe-stacks --region=$aws_user_region WordPressDemoStack | grep \"^OUTPUT.WebsiteURL\" | cut -f3)"
    aws_wordpress_url=$(euform-describe-stacks --region=$aws_user_region WordPressDemoStack | grep "^OUTPUT.WebsiteURL" | cut -f3)
    echo "$aws_wordpress_url"

    next
else
    aws_instance_id=$(euform-describe-stack-resources -n WordPressDemoStack -l WebServer --region=$aws_user_region | cut -f3)
    aws_public_name=$(euca-describe-instances --region=$aws_user_region $aws_instance_id | grep "^INSTANCE" | cut -f4)
    ews_public_ip=$(euca-describe-instances --region=$aws_user_region $aws_instance_id | grep "^INSTANCE" | cut -f17)

    aws_wordpress_url=$(euform-describe-stacks --region=$aws_user_region WordPressDemoStack | grep "^OUTPUT.WebsiteURL" | cut -f3)
fi


((++step))
if [ $mode = a -o $mode = b ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Install WordPress Command-Line Tools on AWS Instance"
    echo "    - This is used to automate WordPress initialization and posting"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "ssh -T -i ~/.ssh/${aws_ssh_key}_id_rsa $aws_ssh_user@$aws_public_name << EOF"
    echo "curl https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar | sudo tee /usr/local/bin/wp > /dev/null"
    echo "sudo chmod +x /usr/local/bin/wp"
    echo "EOF"

    if ssh -i ~/.ssh/${aws_ssh_key}_id_rsa $aws_ssh_user@$aws_public_name "wp --info" | grep -s -q "WP-CLI version"; then
        echo
        tput rev
        echo "Already Installed!"
        tput sgr0

        next 50

    else
        run

        if [ $choice = y ]; then
            attempt=0
            ((seconds=$login_default * $speed / 100))
            while ((attempt++ <= login_attempts)); do
                sed -i -e "/$aws_public_name/d" ~/.ssh/known_hosts
                sed -i -e "/$aws_public_ip/d" ~/.ssh/known_hosts
                ssh-keyscan $aws_public_name 2> /dev/null >> ~/.ssh/known_hosts
                ssh-keyscan $aws_public_ip 2> /dev/null >> ~/.ssh/known_hosts

                echo
                echo "# ssh -i ~/.ssh/${aws_ssh_key}_id_rsa $aws_ssh_user@$aws_public_name"
                ssh -T -i ~/.ssh/${aws_ssh_key}_id_rsa $aws_ssh_user@$aws_public_name << EOF
echo "> curl https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar | sudo tee /usr/local/bin/wp > /dev/null"
curl https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar | sudo tee /usr/local/bin/wp > /dev/null
sleep 1
echo
echo "> sudo chmod +x /usr/local/bin/wp"
sudo chmod +x /usr/local/bin/wp
EOF
                RC=$?
                if [ $RC = 0 -o $RC = 1 ]; then
                    break
                else
                    echo
                    echo -n "Not available ($RC). Waiting $seconds seconds..."
                    sleep $seconds
                    echo " Done"
                fi
            done

            next
        fi
    fi
fi


((++step))
if [ $mode = a -o $mode = b ]; then
    if [ $aws_stack_created = y ]; then
        clear
        echo
        echo "============================================================"
        echo
        echo "$(printf '%2d' $step). Configure WordPress on AWS Instance"
        echo "    - Configure WordPress via a browser:"
        echo "      $aws_wordpress_url"
        echo "    - Using these values:"
        echo "      - Site Title: Demo ($aws_account)"
        echo "      - Username: $mysql_user"
        echo "      - Password: <discover_password>"
        echo "      - Your E-mail: <your email address>"
        echo
        echo "============================================================"
        echo

        # Look into creating this automatically via wp-cli or similar
        # See this URL, which has some details on this: https://www.digitalocean.com/community/tutorials/how-to-use-wp-cli-to-manage-your-wordpress-site-from-the-command-line
        # wp core install --url="$aws_public_name"  --title="Demo ($aws_region)" --admin_user="$mysql_user" --admin_password="$mysql_password" --admin_email="$wordpress_email"

        next 200
    fi
fi


((++step))
if [ $mode = a -o $mode = b ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Create WordPress Blog Post on AWS Instance"
    echo "    - Create a Blog Post in WordPress via a browser:"
    echo "      $aws_wordpress_url"
    echo "    - Login using these values:"
    echo "      - Username: $mysql_user"
    echo "      - Password: <discover_password>"
    echo "    - This is to show migration of the current database content"
    echo
    echo "============================================================"
    echo

    # Look into creating this automatically via wp-cli or similar
    # wp post create --post_status=publish --post_title="Post on $(date" --edit

    next 200
fi


((++step))
if [ $mode = e -o $mode = b ]; then
    if [ $verbose = 1 ]; then
        clear
        echo
        echo "============================================================"
        echo
        echo "$(printf '%2d' $step). List existing Eucalyptus Resources"
        echo "    - So we can compare with what this demo creates"
        echo
        echo "============================================================"
        echo
        echo "Commands:"
        echo
        echo "euca-describe-groups --region=$euca_user_region"
        echo
        echo "euca-describe-instances --region=$euca_user_region"

        run 50

        if [ $choice = y ]; then
            echo
            echo "# euca-describe-groups --region=$euca_user_region"
            euca-describe-groups --region=$euca_user_region
            pause

            echo "# euca-describe-instances --region=$euca_user_region"
            euca-describe-instances --region=$euca_user_region

            next
        fi
    fi
fi


((++step))
if [ $mode = e -o $mode = b ]; then
    if [ $verbose = 1 ]; then
        clear
        echo
        echo "============================================================"
        echo
        echo "$(printf '%2d' $step). List existing Eucalyptus CloudFormation Stacks"
        echo "    - So we can compare with what this demo creates"
        echo
        echo "============================================================"
        echo
        echo "Commands:"
        echo
        echo "euform-describe-stacks --region=$euca_user_region"

        run 50

        if [ $choice = y ]; then
            echo
            echo "# euform-describe-stacks --region=$euca_user_region"
            euform-describe-stacks --region=$euca_user_region

            next
        fi
    fi
fi


((++step))
if [ $mode = e -o $mode = b ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Create the Eucalyptus Stack"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "euform-create-stack --template-file $tmpdir/WordPress_Single_Instance_Eucalyptus.template \\"
    echo "                    --parameter \"KeyName=$euca_ssh_key\" \\"
    echo "                    --parameter \"InstanceType=m1.medium\" \\"
    echo "                    --parameter \"DBUser=$mysql_user\" \\"
    echo "                    --parameter \"DBPassword=$mysql_password\" \\"
    echo "                    --parameter \"DBRootPassword=$mysql_password\" \\"
    echo "                    --parameter \"EndPoint=$euca_cloudformation_url\" \\"
    echo "                    --capabilities CAPABILITY_IAM \\"
    echo "                    --region $euca_user_region \\"
    echo "                    WordPressDemoStack"

    if [ "$(euform-describe-stacks --region $euca_user_region WordPressDemoStack 2> /dev/null | grep "^STACK" | cut -f3)" = "CREATE_COMPLETE" ]; then
        echo
        tput rev
        echo "Already Created!"
        tput sgr0

        next 50

    else
        run

        if [ $choice = y ]; then
            echo
            echo "# euform-create-stack --template-file $tmpdir/WordPress_Single_Instance_Eucalyptus.template \\"
            echo ">                     --parameter \"KeyName=$euca_ssh_key\" \\"
            echo ">                     --parameter \"InstanceType=m1.medium\" \\"
            echo ">                     --parameter \"DBUser=$mysql_user\" \\"
            echo ">                     --parameter \"DBPassword=$mysql_password\" \\"
            echo ">                     --parameter \"DBRootPassword=$mysql_password\" \\"
            echo ">                     --parameter \"EndPoint=$euca_cloudformation_url\" \\"
            echo ">                     --capabilities CAPABILITY_IAM \\"
            echo ">                     --region $euca_user_region \\"
            echo ">                     WordPressDemoStack"
            euform-create-stack --template-file $tmpdir/WordPress_Single_Instance_Eucalyptus.template \
                                --parameter "KeyName=$euca_ssh_key" \
                                --parameter "InstanceType=m1.medium" \
                                --parameter "DBUser=$mysql_user" \
                                --parameter "DBPassword=$mysql_password" \
                                --parameter "DBRootPassword=$mysql_password" \
                                --parameter "EndPoint=$euca_cloudformation_url" \
                                --capabilities CAPABILITY_IAM \
                                --region $euca_user_region \
                                WordPressDemoStack

            euca_stack_created=y

            next
        fi
    fi
fi


((++step))
if [ $mode = e -o $mode = b ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Monitor Eucalyptus Stack creation"
    echo "    - NOTE: This can take about 400 - 500 seconds"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "euform-describe-stacks --region $euca_user_region"
    echo
    echo "euform-describe-stack-events --region $euca_user_region WordPressDemoStack | head -5"

    if [ "$(euform-describe-stacks --region $euca_user_region WordPressDemoStack 2> /dev/null | grep "^STACK" | cut -f3)" = "CREATE_COMPLETE" ]; then
        echo
        tput rev
        echo "Already Complete!"
        tput sgr0

        next 50

    else
        run 50

        if [ $choice = y ]; then
            echo
            echo "# euform-describe-stacks --region $euca_user_region"
            euform-describe-stacks --region $euca_user_region
            pause

            attempt=0
            ((seconds=$create_default * $speed / 100))
            while ((attempt++ <= create_attempts)); do
                echo
                echo "# euform-describe-stack-events --region $euca_user_region WordPressDemoStack | head -5"
                euform-describe-stack-events --region $euca_user_region WordPressDemoStack 2> /dev/null | head -5

                status=$(euform-describe-stacks --region $euca_user_region WordPressDemoStack 2> /dev/null | grep "^STACK" | cut -f3)
                if [ -z "$status" -o "$status" = "CREATE_COMPLETE" -o "$status" = "CREATE_FAILED" -o "$status" = "ROLLBACK_COMPLETE" ]; then
                    break
                else
                    echo
                    echo -n "Not finished ($RC). Waiting $seconds seconds..."
                    sleep $seconds
                    echo " Done"
                fi
            done

            next
        fi
    fi
fi


((++step))
if [ $mode = e -o $mode = b ]; then
    if [ $verbose = 1 ]; then
        clear
        echo
        echo "============================================================"
        echo
        echo "$(printf '%2d' $step). List updated Eucalyptus Resources"
        echo "    - Note addition of new group and instance"
        echo
        echo "============================================================"
        echo
        echo "Commands:"
        echo
        echo "euca-describe-groups --region $euca_user_region"
        echo
        echo "euca-describe-instances --region $euca_user_region"

        run 50

        if [ $choice = y ]; then
            echo
            echo "# euca-describe-groups --region $euca_user_region"
            euca-describe-groups --region $euca_user_region
            pause

            echo "# euca-describe-instances --region $euca_user_region"
            euca-describe-instances --region $euca_user_region

            next
        fi
    fi
fi


((++step))
if [ $verbose = 1 ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Obtain Eucalyptus Instance and Blog details"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "euca_instance_id=\$(euform-describe-stack-resources -n WordPressDemoStack -l WebServer --region=$euca_user_region | cut -f3)"
    echo "euca_public_name=\$(euca-describe-instances --region=$euca_user_region \$euca_instance_id | grep \"^INSTANCE\" | cut -f4)"
    echo "euca_public_ip=\$(euca-describe-instances --region=$euca_user_region \$euca_instance_id | grep \"^INSTANCE\" | cut -f17)"
    echo
    echo "euca_wordpress_url=\$(euform-describe-stacks --region=$euca_user_region WordPressDemoStack | grep \"^OUTPUT.WebsiteURL\" | cut -f3)"
    echo

    next

    echo
    echo "# euca_instance_id=\$(euform-describe-stack-resources -n WordPressDemoStack -l WebServer --region=$euca_user_region | cut -f3)"
    euca_instance_id=$(euform-describe-stack-resources -n WordPressDemoStack -l WebServer --region=$euca_user_region | cut -f3)
    echo "$euca_instance_id"
    echo "#"
    echo "# euca_public_name=\$(euca-describe-instances --region=$euca_user_region \$euca_instance_id | grep \"^INSTANCE\" | cut -f4)"
    euca_public_name=$(euca-describe-instances --region=$euca_user_region $euca_instance_id | grep "^INSTANCE" | cut -f4)
    echo "$euca_public_name"
    echo "#"
    echo "# euca_public_ip=\$(euca-describe-instances --region=$euca_user_region \$euca_instance_id | grep \"^INSTANCE\" | cut -f17)"
    euca_public_ip=$(euca-describe-instances --region=$euca_user_region $euca_instance_id | grep "^INSTANCE" | cut -f17)
    echo "$euca_public_ip"
    pause

    echo "# euca_wordpress_url=\$(euform-describe-stacks --region=$euca_user_region WordPressDemoStack | grep \"^OUTPUT.WebsiteURL\" | cut -f3)"
    euca_wordpress_url=$(euform-describe-stacks --region=$euca_user_region WordPressDemoStack | grep "^OUTPUT.WebsiteURL" | cut -f3)
    echo "$euca_wordpress_url"

    next
else
    euca_instance_id=$(euform-describe-stack-resources -n WordPressDemoStack -l WebServer --region=$euca_user_region | cut -f3)
    euca_public_name=$(euca-describe-instances --region=$euca_user_region $euca_instance_id | grep "^INSTANCE" | cut -f4)
    euca_public_ip=$(euca-describe-instances --region=$euca_user_region $euca_instance_id | grep "^INSTANCE" | cut -f17)

    euca_wordpress_url=$(euform-describe-stacks --region=$euca_user_region WordPressDemoStack | grep "^OUTPUT.WebsiteURL" | cut -f3)
fi


((++step))
if [ $mode = e -o $mode = b -o $mode = m ]; then
    if [ $verbose = 1 ]; then
        clear
        echo
        echo "============================================================"
        echo
        echo "$(printf '%2d' $step). View WordPress on AWS Instance"
        echo "    - Display WordPress via text-mode browser"
        echo "    - Observe current content from AWS"
        echo "    - Alternatively, you can view WordPress via a graphical browser:"
        echo "      $aws_wordpress_url"
        echo
        echo "============================================================"
        echo
        echo "Commands:"
        echo
        echo "w3m -dump $aws_wordpress_url"

        run 50

        if [ $choice = y ]; then

            echo "# w3m -dump $aws_wordpress_url"
            w3m -dump $aws_wordpress_url | sed -e '1,/^  . WordPress.org$/d' -e 's/^\(Posted on [A-Za-z]* [0-9]*, 20..\).*$/\1/'

            next 50

        fi
    fi
fi


((++step))
if [ $mode = e -o $mode = b -o $mode = m ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Backup WordPress on AWS Instance"
    echo "    - Backup WordPress database"
    echo "    - Copy database backup from Instance to AWS S3 Bucket (demo-$aws_account)"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "ssh -T -i ~/.ssh/${aws_ssh_key}_id_rsa $aws_ssh_user@$aws_public_name << EOF"
    echo "mysqldump -u$mysql_root -p$mysql_password $mysql_db > $tmpdir/$mysql_bakfile"
    echo "aws s3 cp $tmpdir/$mysql_bakfile s3://demo-$aws_account/demo-30-cfn-wordpress/$mysql_bakfile --acl public-read"
    echo "EOF"

    run 50

    if [ $choice = y ]; then
        attempt=0
        ((seconds=$login_default * $speed / 100))
        while ((attempt++ <= login_attempts)); do
            sed -i -e "/$aws_public_name/d" ~/.ssh/known_hosts
            sed -i -e "/$aws_public_ip/d" ~/.ssh/known_hosts
            ssh-keyscan $aws_public_name 2> /dev/null >> ~/.ssh/known_hosts
            ssh-keyscan $aws_public_ip 2> /dev/null >> ~/.ssh/known_hosts

            echo
            echo "# ssh -i ~/.ssh/${aws_ssh_key}_id_rsa $aws_ssh_user@$aws_public_name"
            ssh -T -i ~/.ssh/${aws_ssh_key}_id_rsa $aws_ssh_user@$aws_public_name << EOF
echo "> mysqldump -u$mysql_root -p$mysql_password $mysql_db > $tmpdir/$mysql_bakfile"
mysqldump --compatible=mysql4 -u$mysql_root -p$mysql_password $mysql_db > $tmpdir/$mysql_bakfile
sleep 1
echo
echo "> aws s3 cp $tmpdir/$mysql_bakfile s3://demo-$aws_account/demo-30-cfn-wordpress/$mysql_bakfile --acl public-read"
aws s3 cp $tmpdir/$mysql_bakfile s3://demo-$aws_account/demo-30-cfn-wordpress/$mysql_bakfile --acl public-read
rm -f $tmpdir/$mysql_bakfile
EOF
            RC=$?
            if [ $RC = 0 -o $RC = 1 ]; then
                break
            else
                echo
                echo -n "Not available ($RC). Waiting $seconds seconds..."
                sleep $seconds
                echo " Done"
            fi
        done

        next
    fi
fi


((++step))
if [ $mode = e -o $mode = b -o $mode = m ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Restore WordPress on Eucalyptus Instance"
    echo "    - Copy database backup from AWS S3 Bucket (demo-$aws_account) to Instance"
    echo "    - Restore WordPress database"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "ssh -T -i ~/.ssh/${euca_ssh_key}_id_rsa $euca_ssh_user@$euca_public_name << EOF"
    echo "wget http://$aws_s3_domain/demo-$aws_account/demo-30-cfn-wordpress/$mysql_bakfile -O $tmpdir/$mysql_bakfile"
    echo "mysql -u$mysql_root -p$mysql_password -D$mysql_db < $tmpdir/$mysql_bakfile"
    echo "EOF"

    run 50

    if [ $choice = y ]; then
        attempt=0
        ((seconds=$login_default * $speed / 100))
        while ((attempt++ <= login_attempts)); do
            sed -i -e "/$euca_public_name/d" ~/.ssh/known_hosts
            sed -i -e "/$euca_public_ip/d" ~/.ssh/known_hosts
            ssh-keyscan $euca_public_name 2> /dev/null >> ~/.ssh/known_hosts
            ssh-keyscan $euca_public_ip 2> /dev/null >> ~/.ssh/known_hosts

            echo
            echo "# ssh -i ~/.ssh/${euca_ssh_key}_id_rsa $euca_ssh_user@$euca_public_name"
            ssh -T -i ~/.ssh/${euca_ssh_key}_id_rsa $euca_ssh_user@$euca_public_name << EOF
echo "# wget http://$aws_s3_domain/demo-$aws_account/demo-30-cfn-wordpress/$mysql_bakfile -O $tmpdir/$mysql_bakfile"
wget http://$aws_s3_domain/demo-$aws_account/demo-30-cfn-wordpress/$mysql_bakfile -O $tmpdir/$mysql_bakfile
sleep 1
echo
echo "# mysql -u$mysql_root -p$mysql_password -D$mysql_db < $tmpdir/$mysql_bakfile"
mysql -u$mysql_root -p$mysql_password -D$mysql_db < $tmpdir/$mysql_bakfile
EOF
            RC=$?
            if [ $RC = 0 -o $RC = 1 ]; then
                break
            else
                echo
                echo -n "Not available ($RC). Waiting $seconds seconds..."
                sleep $seconds
                echo " Done"
            fi
        done

        next
    fi
fi


((++step))
if [ $mode = e -o $mode = b -o $mode = m ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Confirm WordPress Migration on Eucalyptus Instance"
    echo "    - Display WordPress via text-mode browser"
    echo "    - Confirm latest content from AWS is now running in Eucalyptus"
    echo "    - Alternatively, you can view WordPress via a graphical browser:"
    echo "      $euca_wordpress_url"
    echo
    echo "============================================================"
    echo

    echo "Commands:"
    echo
    echo "w3m -dump $euca_wordpress_url"

    run 50

    if [ $choice = y ]; then

        echo "# w3m -dump $euca_wordpress_url"
        w3m -dump $euca_wordpress_url | sed -e '1,/^  . WordPress.org$/d' -e 's/^\(Posted on [A-Za-z]* [0-9]*, 20..\).*$/\1/'

        next 50

    fi
fi


end=$(date +%s)

echo
echo "Eucalyptus CloudFormation WordPress demo execution complete (time: $(date -u -d @$((end-start)) +"%T"))"
