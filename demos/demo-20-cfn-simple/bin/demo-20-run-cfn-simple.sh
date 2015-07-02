#/bin/bash
#
# This script tests Eucalyptus CloudFormation,
# using a simple template which creates a security group and an instance.
#
# This script was originally designed to run on a combined CLC+UFS+MC host,
# as installed by FastStart or the Cloud Administrator Course. To run this
# on an arbitrary management workstation, you will need to move the demo
# account admin user's credentials zip file to
#   ~/.creds/<region>/<demo_account_name>/admin.zip
# then expand it's contents into the
#   ~/.creds/<region>/<demo_account_name>/admin/ directory
# Additionally, if you want to use the -g flag to pause while showing GUI 
# aspects, you will need to set the EUCA_CONSOLE_URL environment variable
# or specify the -c url parameter to the appropriate value.
#
# Before running this (or any other demo script in the euca-demo project),
# you should run the euca-demo-01-initialize-account.sh as the eucalyptus
# administrator, and the euca-demo-02-initialize-dependencies.sh as the demo
# account administrator, to setup common dependencies required by all demos.
#

#  1. Initalize Environment

bindir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
confdir=${bindir%/*}/conf
docdir=${bindir%/*}/doc
logdir=${bindir%/*}/log
scriptsdir=${bindir%/*}/scripts
templatesdir=${bindir%/*}/templates
tmpdir=/var/tmp
prefix=demo-11

image_file=CentOS-6-x86_64-GenericCloud.qcow2.xz

step=0
speed_max=400
run_default=10
pause_default=2
next_default=5

create_attempts=6
create_default=20
login_attempts=6
login_default=20
delete_attempts=6
delete_default=20

interactive=1
speed=100
account=demo
gui=0
consoleurl=${EUCA_CONSOLE_URL:-https://$(hostname)}


#  2. Define functions

usage () {
    echo "Usage: ${BASH_SOURCE##*/} [-I [-s | -f]] [-a account] [-g] [-c url]"
    echo "  -I          non-interactive"
    echo "  -s          slower: increase pauses by 25%"
    echo "  -f          faster: reduce pauses by 25%"
    echo "  -a account  account to use in demo (default: $account)"
    echo "  -g          add steps and time to demo GUI in another window"
    echo "  -c url      console url (default: $consoleurl)"
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

while getopts Isfa:gc:? arg; do
    case $arg in
    I)  interactive=0;;
    s)  ((speed < speed_max)) && ((speed=speed+25));;
    f)  ((speed > 0)) && ((speed=speed-25));;
    a)  account="$OPTARG";;
    g)  gui=1;;
    c)  consoleurl="$OPTARG";;
    ?)  usage
        exit 1;;
    esac
done

shift $(($OPTIND - 1))


#  4. Validate environment

if [ $is_clc = n ]; then
    echo "This script should only be run on the Cloud Controller host"
    exit 10
fi

if [ ! -r ~/.creds/$AWS_DEFAULT_REGION/$account/admin/eucarc ]; then
    echo "-a $account invalid: Could not find $AWS_DEFAULT_REGION Demo Account Administrator credentials!"
    echo "   Expected to find: ~/.creds/$AWS_DEFAULT_REGION/$account/admin/eucarc"
    exit 21
fi

if ! rpm -q --quiet w3m; then
    echo "w3m missing: This demo uses the w3m text-mode browser to confirm webpage content"
    exit 98
fi


#  5. Execute Demo

start=$(date +%s)

((++step))
clear
echo
echo "============================================================"
echo
if [ $account = eucalyptus ]; then
    echo "$(printf '%2d' $step). Use Eucalyptus Administrator credentials"
else
    echo "$(printf '%2d' $step). Use Demo ($account) Account Administrator credentials"
fi
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "cat ~/.creds/$AWS_DEFAULT_REGION/$account/admin/eucarc"
echo
echo "source ~/.creds/$AWS_DEFAULT_REGION/$account/admin/eucarc"

next

echo
echo "# cat ~/.creds/$AWS_DEFAULT_REGION/$account/admin/eucarc"
cat ~/.creds/$AWS_DEFAULT_REGION/$account/admin/eucarc
pause

echo "# source ~/.creds/$AWS_DEFAULT_REGION/$account/admin/eucarc"
source ~/.creds/$AWS_DEFAULT_REGION/$account/admin/eucarc

next


((++step))
demo_initialized=y
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Confirm existence of Demo depencencies"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euca-describe-images | grep \"${image_file%%.*}.raw.manifest.xml\""
echo
echo "euca-describe-keypairs | grep \"admin-demo\""

next

echo
echo "# euca-describe-images | grep \"${image_file%%.*}.raw.manifest.xml\""
euca-describe-images | grep "${image_file%%.*}.raw.manifest.xml" || demo_initialized=n
pause

echo "# euca-describe-keypairs | grep \"admin-demo\""
euca-describe-keypairs | grep "admin-demo" || demo_initialized=n

if [ $demo_initialized = n ]; then
    echo
    echo "At least one prerequisite for this script was not met."
    echo "Please re-run euca-demo-02-initialize-dependencies.sh script."
    exit 99
fi

next


((++step))
# Attempt to clean up any terminated instances which are still showing up in listings
terminated_instance_ids=$(euca-describe-instances --filter "instance-state-name=terminated" | grep "^INSTANCE" | cut -f2)
for instance_id in $terminated_instance_ids; do
    euca-terminate-instances $instance_id &> /dev/null
done

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). List initial resources"
echo "    - So we can compare with what CloudFormation creates"
if [ $gui = 1 ];  then
    echo "    - After listing resources here, confirm via GUI"
fi
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euca-describe-images"
echo
echo "euca-describe-keypairs"
echo 
echo "euca-describe-groups"
echo
echo "euca-describe-instances"

run 50

if [ $choice = y ]; then
    echo
    echo "# euca-describe-images"
    euca-describe-images
    pause

    echo "# euca-describe-keypairs"
    euca-describe-keypairs
    pause 

    echo "# euca-describe-groups"
    euca-describe-groups
    pause

    echo "# euca-describe-instances"
    euca-describe-instances
    
    next

    if [ $gui = 1 ]; then
        echo
        echo "Browse: ${consoleurl}/?account=$account&username=admin"
        echo "        to confirm resources via management console"

        next 400
    fi
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). List CloudFormation Stacks"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euform-describe-stacks"

run 50

if [ $choice = y ]; then
    echo
    echo "# euform-describe-stacks"
    euform-describe-stacks

    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Display Simple Example CloudFormation template"
echo "    - This simple template creates a simple security group"
echo "      and an instance which references a keypair and an image"
echo "      created externally and passed in as parameters"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "more $templatesdir/simple.template.json"

run 50

if [ $choice = y ]; then
    echo
    echo "# more $templatesdir/simple.template.json"
    if [ $interactive = 1 ]; then
        more $templatesdir/simple.template.json
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
        done < $templatesdir/simple.template.json
    fi

    next 200
fi


((++step))
image_id=$(euca-describe-images | grep ${image_file%%.*}.raw.manifest.xml | cut -f2)

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Create the Stack"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euform-create-stack --template-file $templatesdir/simple.template.json -p DemoImageId=$image_id SimpleDemoStack"

run 50

if [ $choice = y ]; then
    echo
    echo "# euform-create-stack --template-file $templatesdir/simple.template.json -p DemoImageId=$image_id SimpleDemoStack"
    euform-create-stack --template-file $templatesdir/simple.template.json -p DemoImageId=$image_id SimpleDemoStack
    
    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Monitor Stack creation"
if [ $gui = 1 ];  then
    echo "    - Alternate betwen here and the GUI to monitor progress"
fi
echo "    - NOTE: This can take about 60 - 80 seconds"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euform-describe-stacks"
echo
echo "euform-describe-stack-events SimpleDemoStack | head -10"

run 50

if [ $choice = y ]; then
    echo
    echo "# euform-describe-stacks"
    euform-describe-stacks
    pause

    attempt=0
    ((seconds=$create_default * $speed / 100))
    while ((attempt++ <= create_attempts)); do
        echo
        echo "# euform-describe-stack-events SimpleDemoStack | head -10"
        euform-describe-stack-events SimpleDemoStack | head -10

        status=$(euform-describe-stacks SimpleDemoStack | grep "^STACK" | cut -f3)
        if [ "$status" = "CREATE_COMPLETE" ]; then
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


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). List updated resources"
echo "    - Note addition of new group and instance"
if [ $gui = 1 ];  then
    echo "    - After listing resources here, confirm via GUI"
fi
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euca-describe-groups"
echo
echo "euca-describe-instances"

run 50

if [ $choice = y ]; then
    echo
    echo "# euca-describe-groups"
    euca-describe-groups
    pause

    echo "# euca-describe-instances"
    euca-describe-instances

    next

    if [ $gui = 1 ]; then
        echo
        echo "Browse: ${consoleurl}/?account=$account&username=admin"
        echo "        to confirm resources via management console"

        next 400
    fi
fi


((++step))
# This is a shortcut assuming no other activity on the system - find the most recently launched instance
result=$(euca-describe-instances | grep "^INSTANCE" | cut -f2,4,11,17 | sort -k3 | tail -1 | cut -f1,2,4 | tr -s '[:blank:]' ':')
instance_id=${result%%:*}
temp=${result%:*} && public_name=${temp#*:}
public_ip=${result##*:}
user=centos

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Confirm ability to login to Instance"
echo "    - If unable to login, view instance console output with:"
echo "      # euca-get-console-output $instance_id"
echo "    - If able to login, first show the private IP with:"
echo "      # ifconfig"
echo "    - Then view meta-data about the public IP with:"
echo "      # curl http://169.254.169.254/latest/meta-data/public-ipv4"
echo "    - Logout of instance once login ability confirmed"
echo "    - NOTE: This can take about 00 - 40 seconds"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "ssh -i ~/.creds/$AWS_DEFAULT_REGION/$account/admin/admin-demo.pem $user@$public_name"

run 50

if [ $choice = y ]; then
    attempt=0
    ((seconds=$login_default * $speed / 100))
    while ((attempt++ <= login_attempts)); do
        sed -i -e "/$public_name/d" ~/.ssh/known_hosts
        sed -i -e "/$public_ip/d" ~/.ssh/known_hosts
        ssh-keyscan $public_name 2> /dev/null >> ~/.ssh/known_hosts
        ssh-keyscan $public_ip 2> /dev/null >> ~/.ssh/known_hosts

        echo
        echo "# ssh -i ~/.creds/$AWS_DEFAULT_REGION/$account/admin/admin-demo.pem $user@$public_name"
        if [ $interactive = 1 ]; then
            ssh -i ~/.creds/$AWS_DEFAULT_REGION/$account/admin/admin-demo.pem $user@$public_name
            RC=$?
        else
            ssh -T -i ~/.creds/$AWS_DEFAULT_REGION/$account/admin/admin-demo.pem $user@$public_name << EOF
echo "# ifconfig"
ifconfig
sleep 5
echo
echo "# curl http://169.254.169.254/latest/meta-data/public-ipv4"
curl -sS http://169.254.169.254/latest/meta-data/public-ipv4 -o /tmp/public-ip4
cat /tmp/public-ip4
sleep 5
EOF
            RC=$?
        fi
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


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Delete the Stack"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euform-delete-stack SimpleDemoStack"

run 50

if [ $choice = y ]; then
    echo
    echo "# euform-delete-stack SimpleDemoStack"
    euform-delete-stack SimpleDemoStack
   
    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Monitor Stack deletion"
if [ $gui = 1 ];  then
    echo "    - Alternate betwen here and the GUI to monitor progress"
fi
echo "    - NOTE: This can take about 60 - 80 seconds"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euform-describe-stacks"
echo
echo "euform-describe-stack-events SimpleDemoStack | head -10"

run 50

if [ $choice = y ]; then
    echo
    echo "# euform-describe-stacks"
    euform-describe-stacks
    pause

    attempt=0
    ((seconds=$delete_default * $speed / 100))
    while ((attempt++ <= delete_attempts)); do
        echo
        echo "# euform-describe-stack-events SimpleDemoStack | head -10"
        euform-describe-stack-events SimpleDemoStack | head -10

        status=$(euform-describe-stacks SimpleDemoStack | grep "^STACK" | cut -f3)
        if [ -z "$status" ]; then
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


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). List remaining resources"
echo "    - Confirm we are back to our initial set"
if [ $gui = 1 ];  then
    echo "    - After listing resources here, confirm via GUI"
fi
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euca-describe-images"
echo
echo "euca-describe-keypairs"
echo
echo "euca-describe-groups"
echo
echo "euca-describe-instances"

run 50

if [ $choice = y ]; then
    echo
    echo "# euca-describe-images"
    euca-describe-images
    pause

    echo "# euca-describe-keypairs"
    euca-describe-keypairs
    pause

    echo "# euca-describe-groups"
    euca-describe-groups
    pause

    echo "# euca-describe-instances"
    euca-describe-instances

    next 200

    if [ $gui = 1 ]; then
        echo
        echo "Browse: ${consoleurl}/?account=$account&username=admin"
        echo "        to confirm resources via management console"

        next 400
    fi
fi


end=$(date +%s)

echo
echo "Eucalyptus CloudFormation simple template testing complete (time: $(date -u -d @$((end-start)) +"%T"))"