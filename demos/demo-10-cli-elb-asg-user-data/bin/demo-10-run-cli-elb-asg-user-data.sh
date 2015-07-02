#/bin/bash
#
# This script tests API creation of SecurityGroup, ElasticLoadBalancer, 
# LaunchConfiguration, AutoScalingGroup, ScalingPolicy, Alarms, 
# Instances and User-Data Scripts.
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
prefix=demo-05

image_file=CentOS-6-x86_64-GenericCloud.qcow2.xz

step=0
speed_max=400
run_default=10
pause_default=2
next_default=5

create_attempts=12
create_default=20
login_attempts=12
login_default=20
replace_attempts=12
replace_default=20
delete_attempts=12
delete_default=20

interactive=1
speed=100
account=demo
gui=0
consoleurl=${EUCA_CONSOLE_URL:-https://$(hostname)}
instances=2


#  2. Define functions

usage () {
    echo "Usage: ${BASH_SOURCE##*/} [-I [-s | -f]] [-a account] [-g] [-c url] [-n instances]"
    echo "  -I            non-interactive"
    echo "  -s            slower: increase pauses by 25%"
    echo "  -f            faster: reduce pauses by 25%"
    echo "  -a account    account to use in demos (default: $account)"
    echo "  -g            add steps and time to demo GUI in another window"
    echo "  -c url        console url (default: $consoleurl)"
    echo "  -n instances  number of instances to create in autoscale group (default: $instances)"
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

while getopts Isfa:gc:n:? arg; do
    case $arg in
    I)  interactive=0;;
    s)  ((speed < speed_max)) && ((speed=speed+25));;
    f)  ((speed > 0)) && ((speed=speed-25));;
    a)  account="$OPTARG";;
    g)  gui=1;;
    c)  consoleurl="$OPTARG";;
    n)  instances="$OPTARG";;
    ?)  usage
        exit 1;;
    esac
done

shift $(($OPTIND - 1))


#  4. Validate environment

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
echo "$(printf '%2d' $step). Use Demo ($account) Account Administrator credentials"
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
echo "    - So we can compare with what this demo creates"
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
echo "eulb-describe-lbs"
echo
echo "euca-describe-instances"
echo
echo "euscale-describe-launch-configs"
echo
echo "euscale-describe-auto-scaling-groups"
echo
echo "euscale-describe-policies"
echo
echo "euwatch-describe-alarms"

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
    euca-describe-groups | tee $tmpdir/$prefix-$(printf '%02d' $step)-euca-describe-groups.out
    pause

    echo "# eulb-describe-lbs"
    eulb-describe-lbs | tee $tmpdir/$prefix-$(printf '%02d' $step)-eulb-describe-lbs.out
    pause

    echo "# euca-describe-instances"
    euca-describe-instances | tee $tmpdir/$prefix-$(printf '%02d' $step)-euca-describe-instances.out
    pause

    echo "# euscale-describe-launch-configs"
    euscale-describe-launch-configs | tee $tmpdir/$prefix-$(printf '%02d' $step)-euscale-describe-launch-configs.out
    pause

    echo "# euscale-describe-auto-scaling-groups"
    euscale-describe-auto-scaling-groups | tee $tmpdir/$prefix-$(printf '%02d' $step)-euscale-describe-auto-scaling-groups.out
    pause

    echo "# euscale-describe-policies"
    euscale-describe-policies | tee $tmpdir/$prefix-$(printf '%02d' $step)-euscale-describe-policies.out
    pause

    echo "# euwatch-describe-alarms"
    euwatch-describe-alarms | tee $tmpdir/$prefix-$(printf '%02d' $step)-euwatch-describe-alarms.out

    next 200

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
echo "$(printf '%2d' $step). Create a Security Group"
echo "    - We will allow SSH and HTTP"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euca-create-group -d \"Demo Security Group\" DemoSG"
echo
echo "euca-authorize -P icmp -t -1:-1 -s 0.0.0.0/0 DemoSG"
echo
echo "euca-authorize -P tcp -p 22 -s 0.0.0.0/0 DemoSG"
echo
echo "euca-authorize -P tcp -p 80 -s 0.0.0.0/0 DemoSG"
echo
echo "euca-describe-groups DemoSG"

run 50

if [ $choice = y ]; then
    echo
    echo "# euca-create-group -d \"Demo Security Group\" DemoSG"
    euca-create-group -d "Demo Security Group" DemoSG
    pause

    echo "# euca-authorize -P icmp -t -1:-1 -s 0.0.0.0/0 DemoSG"
    euca-authorize -P icmp -t -1:-1 -s 0.0.0.0/0 DemoSG
    pause

    echo "# euca-authorize -P tcp -p 22 -s 0.0.0.0/0 DemoSG"
    euca-authorize -P tcp -p 22 -s 0.0.0.0/0 DemoSG
    pause
 
    echo "# euca-authorize -P tcp -p 80 -s 0.0.0.0/0 DemoSG"
    euca-authorize -P tcp -p 80 -s 0.0.0.0/0 DemoSG
    pause

    echo "# euca-describe-groups DemoSG"
    euca-describe-groups DemoSG

    next
fi


((++step))
zone=$(euca-describe-availability-zones | head -1 | cut -f2)

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Create an ElasticLoadBalancer"
echo "    - Wait for ELB to become available"
echo "    - NOTE: This can take about 100 - 140 seconds"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "eulb-create-lb -z $zone -l \"lb-port=80, protocol=HTTP, instance-port=80, instance-protocol=HTTP\" DemoELB"
echo
echo "eulb-describe-lbs DemoELB"

run

if [ $choice = y ]; then
    echo
    echo "# eulb-create-lb -z $zone -l \"lb-port=80, protocol=HTTP, instance-port=80, instance-protocol=HTTP\" DemoELB"
    eulb-create-lb -z $zone -l "lb-port=80, protocol=HTTP, instance-port=80, instance-protocol=HTTP" DemoELB | tee $tmpdir/$prefix-$(printf '%02d' $step)-eulb-create-lb.out
    pause

    echo "# eulb-describe-lbs DemoELB"
    eulb-describe-lbs DemoELB

    lb_name=$(cut -f2 $tmpdir/$prefix-$(printf '%02d' $step)-eulb-create-lb.out)
    ((seconds=$create_default * $speed / 100))
    while ((attempt++ <= $create_attempts)); do
        echo
        echo "# dig +short $lb_name"
        lb_public_ip=$(dig +short $lb_name)
        if [ -n "$lb_public_ip" ]; then
            echo $lb_public_ip
            break
        else
            echo
            echo -n "Not available. Waiting $seconds seconds..."
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
echo "$(printf '%2d' $step). Configure an ElasticLoadBalancer HealthCheck"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "eulb-configure-healthcheck --healthy-threshold 2 --unhealthy-threshold 2 --interval 15 --timeout 30 \\"
echo "                           --target http:80/index.html DemoELB"

run

if [ $choice = y ]; then
    echo
    echo "# eulb-configure-healthcheck --healthy-threshold 2 --unhealthy-threshold 2 --interval 15 --timeout 30 \\"
    echo "                             --target http:80/index.html DemoELB"
    eulb-configure-healthcheck --healthy-threshold 2 --unhealthy-threshold 2 --interval 15 --timeout 30 \
                               --target http:80/index.html DemoELB | tee $tmpdir/$prefix-$(printf '%02d' $step)-eulb-configure-healthcheck.out

    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Display Demo User-Data script"
echo "    - This simple user-data script will install Apache and configure"
echo "      a simple home page"
echo "    - We will use this in our LaunchConfiguration to automatically"
echo "      configure new instances created by our AutoScalingGroup"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "cat $scriptsdir/$prefix-user-data.sh"

run 50

if [ $choice = y ]; then
    echo
    echo "# cat $scriptsdir/$prefix-user-data.sh"
    cat $scriptsdir/$prefix-user-data.sh

    next 150
fi


((++step))
image_id=$(euca-describe-images | grep "${image_file%%.*}.raw.manifest.xml" | cut -f2)

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Create a LaunchConfiguration"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euscale-create-launch-config DemoLC --image-id $image_id --instance-type m1.small --monitoring-enabled \\"
echo "                                    --key=admin-demo --group=DemoSG \\"
echo "                                    --user-data-file=$scriptsdir/$prefix-user-data.sh"
echo
echo "euscale-describe-launch-configs DemoLC"

run 150

if [ $choice = y ]; then
    echo
    echo "# euscale-create-launch-config DemoLC --image-id $image_id --instance-type m1.small --monitoring-enabled \\"
    echo ">                                     --key=admin-demo --group=DemoSG \\"
    echo ">                                     --user-data-file=$scriptsdir/$prefix-user-data.sh"
    euscale-create-launch-config DemoLC --image-id $image_id --instance-type m1.small --monitoring-enabled \
                                        --key=admin-demo --group=DemoSG \
                                        --user-data-file=$scriptsdir/$prefix-user-data.sh
    pause

    echo "# euscale-describe-launch-configs DemoLC"
    euscale-describe-launch-configs DemoLC

    next
fi


((++step))
zone=$(euca-describe-availability-zones | head -1 | cut -f2)

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Create an AutoScalingGroup"
echo "    - Note we associate the AutoScalingGroup with the"
echo "      ElasticLoadBalancer created earlier"
echo "    - Note there are two methods of checking Instance"
echo "      status"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euscale-create-auto-scaling-group DemoASG --launch-configuration DemoLC \\"
echo "                                          --availability-zones $zone \\"
echo "                                          --load-balancers DemoELB \\"
echo "                                          --min-size $instances --max-size $((instances*2)) --desired-capacity $instances"
echo
echo "euscale-describe-auto-scaling-groups DemoASG"
echo
echo "eulb-describe-instance-health DemoELB"

run 150

if [ $choice = y ]; then
    echo
    echo "# euscale-create-auto-scaling-group DemoASG --launch-configuration DemoLC \\"
    echo ">                                           --availability-zones $zone \\"
    echo ">                                           --load-balancers DemoELB \\"
    echo ">                                           --min-size $instances --max-size $((instances*2)) --desired-capacity $instances"
    euscale-create-auto-scaling-group DemoASG --launch-configuration DemoLC \
                                              --availability-zones $zone \
                                              --load-balancers DemoELB \
                                              --min-size $instances --max-size $((instances*2)) --desired-capacity $instances
    pause

    echo "# euscale-describe-auto-scaling-groups DemoASG"
    euscale-describe-auto-scaling-groups DemoASG
    pause

    echo "# eulb-describe-instance-health DemoELB"
    eulb-describe-instance-health DemoELB

    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Create Policies and Associated Alarms"
echo "    - Create a scale out policy"
echo "    - Create a scale in policy"
echo "    - Update AutoScalingGroup with a termination policy"
echo "    - Create a high-cpu alarm using the scale out policy"
echo "    - Create a low-cpu alarm using the scale in policy"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euscale-put-scaling-policy DemoHighCPUPolicy --auto-scaling-group DemoASG \\"
echo "                                             --adjustment=1 --type ChangeInCapacity"
echo
echo "euscale-put-scaling-policy DemoLowCPUPolicy --auto-scaling-group DemoASG \\"
echo "                                            --adjustment=-1 --type ChangeInCapacity"
echo
echo "euscale-update-auto-scaling-group DemoASG --termination-policies \"OldestLaunchConfiguration\""
echo
echo "euscale-describe-policies"
echo
echo "euwatch-put-metric-alarm DemoAddNodesAlarm --metric-name CPUUtilization --unit Percent \\"
echo "                                           --namespace \"AWS/EC2\" --statistic Average \\"
echo "                                           --period 60 --threshold 50 \\"
echo "                                           --comparison-operator GreaterThanOrEqualToThreshold \\"
echo "                                           --dimensions \"AutoScalingGroupName=DemoASG\" \\"
echo "                                           --evaluation-periods 2 --alarm-actions <DemoHighCPUPolicy arn>"
echo
echo "euwatch-put-metric-alarm DemoDelNodesAlarm --metric-name CPUUtilization --unit Percent \\"
echo "                                           --namespace \"AWS/EC2\" --statistic Average \\"
echo "                                           --period 60 --threshold 10 \\"
echo "                                           --comparison-operator LessThanOrEqualToThreshold \\"
echo "                                           --dimensions \"AutoScalingGroupName=DemoASG\" \\"
echo "                                           --evaluation-periods 2 --alarm-actions <DemoLowCPUPolicy arn>"
echo
echo "euwatch-describe-alarms"

run 150

if [ $choice = y ]; then
    echo
    echo "# euscale-put-scaling-policy DemoHighCPUPolicy --auto-scaling-group DemoASG \\" 
    echo ">                                              --adjustment=1 --type ChangeInCapacity"
    euscale-put-scaling-policy DemoHighCPUPolicy --auto-scaling-group DemoASG \
                                                 --adjustment=1 --type ChangeInCapacity | tee $tmpdir/$prefix-$(printf '%02d' $step)-euscale-put-scaling-policy-high.out
    pause
 
    echo "# euscale-put-scaling-policy DemoLowCPUPolicy --auto-scaling-group DemoASG \\"
    echo ">                                             --adjustment=-1 --type ChangeInCapacity"
    euscale-put-scaling-policy DemoLowCPUPolicy --auto-scaling-group DemoASG \
                                                --adjustment=-1 --type ChangeInCapacity | tee $tmpdir/$prefix-$(printf '%02d' $step)-euscale-put-scaling-policy-low.out
    pause

    echo "# euscale-update-auto-scaling-group DemoASG --termination-policies \"OldestLaunchConfiguration\""
    euscale-update-auto-scaling-group DemoASG --termination-policies "OldestLaunchConfiguration"
    pause

    echo "# euscale-describe-policies"
    euscale-describe-policies
    pause 250

    high_policy=$(cat $tmpdir/$prefix-$(printf '%02d' $step)-euscale-put-scaling-policy-high.out)
    echo "# euwatch-put-metric-alarm DemoAddNodesAlarm --metric-name CPUUtilization --unit Percent \\"
    echo ">                                            --namespace \"AWS/EC2\" --statistic Average \\" 
    echo ">                                            --period 60 --threshold 50 \\"
    echo ">                                            --comparison-operator GreaterThanOrEqualToThreshold \\"
    echo ">                                            --dimensions \"AutoScalingGroupName=DemoASG\" \\"
    echo ">                                            --evaluation-periods 2 --alarm-actions $high_policy"
    euwatch-put-metric-alarm DemoAddNodesAlarm --metric-name CPUUtilization --unit Percent \
                                               --namespace "AWS/EC2" --statistic Average \
                                               --period 60 --threshold 50 \
                                               --comparison-operator GreaterThanOrEqualToThreshold \
                                               --dimensions "AutoScalingGroupName=DemoASG" \
                                               --evaluation-periods 2 --alarm-actions $high_policy
    pause

    low_policy=$(cat $tmpdir/$prefix-$(printf '%02d' $step)-euscale-put-scaling-policy-low.out)
    echo "# euwatch-put-metric-alarm DemoDelNodesAlarm --metric-name CPUUtilization --unit Percent \\"
    echo ">                                            --namespace \"AWS/EC2\" --statistic Average \\"
    echo ">                                            --period 60 --threshold 10 \\"
    echo ">                                            --comparison-operator LessThanOrEqualToThreshold \\"
    echo ">                                            --dimensions \"AutoScalingGroupName=DemoASG\" \\"
    echo ">                                            --evaluation-periods 2 --alarm-actions $low_policy"
    euwatch-put-metric-alarm DemoDelNodesAlarm --metric-name CPUUtilization --unit Percent \
                                               --namespace "AWS/EC2" --statistic Average \
                                               --period 60 --threshold 10 \
                                               --comparison-operator LessThanOrEqualToThreshold \
                                               --dimensions "AutoScalingGroupName=DemoASG" \
                                               --evaluation-periods 2 --alarm-actions $low_policy
    pause

    echo "# euwatch-describe-alarms"
    euwatch-describe-alarms

    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). List updated resources"
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
echo "eulb-describe-lbs"
echo
echo "euca-describe-instances"
echo
echo "euscale-describe-launch-configs"
echo
echo "euscale-describe-auto-scaling-groups"
echo
echo "euscale-describe-policies"
echo
echo "euwatch-describe-alarms"

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
    euca-describe-groups | tee $tmpdir/$prefix-$(printf '%02d' $step)-euca-describe-groups.out
    pause

    echo "# eulb-describe-lbs"
    eulb-describe-lbs | tee $tmpdir/$prefix-$(printf '%02d' $step)-eulb-describe-lbs.out
    pause

    echo "# euca-describe-instances"
    euca-describe-instances | tee $tmpdir/$prefix-$(printf '%02d' $step)-euca-describe-instances.out
    pause

    echo "# euscale-describe-launch-configs"
    euscale-describe-launch-configs | tee $tmpdir/$prefix-$(printf '%02d' $step)-euscale-describe-launch-configs.out
    pause

    echo "# euscale-describe-auto-scaling-groups"
    euscale-describe-auto-scaling-groups | tee $tmpdir/$prefix-$(printf '%02d' $step)-euscale-describe-auto-scaling-groups.out
    pause

    echo "# euscale-describe-policies"
    euscale-describe-policies | tee $tmpdir/$prefix-$(printf '%02d' $step)-euscale-describe-policies.out
    pause

    echo "# euwatch-describe-alarms"
    euwatch-describe-alarms | tee $tmpdir/$prefix-$(printf '%02d' $step)-euwatch-describe-alarms.out

    next 200

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
echo "    - Then view user-data with:"
echo "      # curl http://169.254.169.254/latest/user-data"
echo "    - Logout of instance once login ability confirmed"
echo "    - NOTE: This can take about 20 - 80 seconds"
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
    while ((attempt++ <= $login_attempts)); do
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
curl -sS http://169.254.169.254/latest/meta-data/public-ipv4; echo
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
instance_ids="$(euscale-describe-auto-scaling-groups DemoASG | grep "^INSTANCE" | cut -f2)"
unset instance_names
for instance_id in $instance_ids; do
    instance_names="$instance_names $(euca-describe-instances $instance_id | grep "^INSTANCE" | cut -f4)"
done
instance_names=${instance_names# *}

lb_name=$(eulb-describe-lbs | cut -f3)
lb_public_ip=$(dig +short $lb_name)

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Confirm webpage is visible"
echo "    - Wait for both instances to be \"InService\""
echo "    - Attempt to display webpage first directly via instances,"
echo "      then through the ELB"
echo
echo "============================================================"
echo
echo "Commands:"
for instance_name in $instance_names; do
    echo
    echo "w3m -dump $instance_name"
done
if [ -n "$lb_public_ip" ]; then
    echo
    echo "w3m -dump $lb_name"
    echo "w3m -dump $lb_name"
fi

run 50

if [ $choice = y ]; then
    attempt=0
    ((seconds=$create_default * $speed / 100))
    while ((attempt++ <= create_attempts)); do
        echo
        echo "# eulb-describe-instance-health DemoELB"
        eulb-describe-instance-health DemoELB | tee $tmpdir/$prefix-$(printf '%02d' $step)-eulb-describe-instance-health.out

        if [ $(grep -c "InService" $tmpdir/$prefix-$(printf '%02d' $step)-eulb-describe-instance-health.out) -ge 2 ]; then
            break
        else
            echo
            echo -n "At least 2 instances are not yet \"InService\". Waiting $seconds seconds..."
            sleep $seconds
            echo " Done"
        fi
    done

    echo
    for instance_name in $instance_names; do
        echo "# w3m -dump $instance_name"
        w3m -dump $instance_name
        pause
    done
    if [ -n "$lb_public_ip" ]; then
        echo "# w3m -dump $lb_name"
        w3m -dump $lb_name
        echo "# w3m -dump $lb_name"
        w3m -dump $lb_name
    fi

    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Display Demo Alternate User-Data script"
echo "    - This simple user-data script will install Apache and configure"
echo "      a simple home page"
echo "    - This alternate makes minor changes to the simple home page"
echo "      to demonstrate how updates to a Launch Configuration can handle"
echo "      rolling updates"
echo "    - We will modify our existing LaunchConfiguration to automatically"
echo "      configure new instances created by our AutoScalingGroup"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "cat $scriptsdir/$prefix-user-data-2.sh"

run 50

if [ $choice = y ]; then
    echo
    echo "# cat $scriptsdir/$prefix-user-data-2.sh"
    cat $scriptsdir/$prefix-user-data-2.sh

    next 150
fi


((++step))
image_id=$(euca-describe-images | grep "${image_file%%.*}.raw.manifest.xml" | cut -f2)
user=centos

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Create a Replacement LaunchConfiguration"
echo "    - This will replace the original User-Data Script with a"
echo "      modified version which will alter the home page"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euscale-create-launch-config DemoLC-2 --image-id $image_id --instance-type m1.small --monitoring-enabled \\"
echo "                                      --key=admin-demo --group=DemoSG \\"
echo "                                      --user-data-file=$scriptsdir/$prefix-user-data-2.sh"
echo
echo "euscale-describe-launch-configs DemoLC"
echo "euscale-describe-launch-configs DemoLC-2"

run

if [ $choice = y ]; then
    echo
    echo "# euscale-create-launch-config DemoLC-2 --image-id $image_id --instance-type m1.small --monitoring-enabled \\"
    echo ">                                       --key=admin-demo --group=DemoSG \\"
    echo ">                                       --user-data-file=$scriptsdir/$prefix-user-data-2.sh"
    euscale-create-launch-config DemoLC-2 --image-id $image_id --instance-type m1.small --monitoring-enabled \
                                          --key=admin-demo --group=DemoSG \
                                          --user-data-file=$scriptsdir/$prefix-user-data-2.sh
    pause

    echo "# euscale-describe-launch-configs DemoLC"
    euscale-describe-launch-configs DemoLC
    echo "# euscale-describe-launch-configs DemoLC-2"
    euscale-describe-launch-configs DemoLC-2

    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Update an AutoScalingGroup"
echo "    - This replaces the original LaunchConfiguration with"
echo "      it's replacement created above"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euscale-update-auto-scaling-group DemoASG --launch-configuration DemoLC-2"
echo
echo "euscale-describe-auto-scaling-groups DemoASG"

run

if [ $choice = y ]; then
    echo
    echo "# euscale-update-auto-scaling-group DemoASG --launch-configuration DemoLC-2"
    euscale-update-auto-scaling-group DemoASG --launch-configuration DemoLC-2
    pause

    echo "# euscale-describe-auto-scaling-groups DemoASG"
    euscale-describe-auto-scaling-groups DemoASG

    next
fi


((++step))
instance_ids="$(euscale-describe-auto-scaling-groups DemoASG | grep "^INSTANCE" | cut -f2)"

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Trigger AutoScalingGroup Instance Replacement"
echo "    - We will terminate an existing Instance of the AutoScalingGroup,"
echo "      and confirm a replacement Instance is created with the new"
echo "      LaunchConfiguration and User-Data Script"
echo "    - Wait for a replacement instance to be \"InService\""
echo "    - When done, one instance will use the new LaunchConfiguration,"
echo "      while the other(s) will still use the old LaunchConfiguration"
echo "      (normally we'd iterate through all instances when updating the application)"
echo "    - NOTE: This can take about 140 - 200 seconds (per instance)"
if [ $gui = 1 ];  then
    echo "    - After confirming replacement here, confirm via GUI"
fi
echo
echo "============================================================"
echo
echo "Commands:"
for instance_id in $instance_ids; do
    echo
    echo "euscale-terminate-instance-in-auto-scaling-group $instance_id -D --show-long"
    echo
    echo "euscale-describe-auto-scaling-groups DemoASG"
    echo
    echo "eulb-describe-instance-health DemoELB (repeat until both instances are back is \"InService\")"
    break    # delete only one at this time
done

run 150

if [ $choice = y ]; then
    for instance_id in $instance_ids; do
        echo
        echo "# euscale-terminate-instance-in-auto-scaling-group $instance_id -D --show-long"
        euscale-terminate-instance-in-auto-scaling-group $instance_id -D --show-long
        pause

        attempt=0
        ((seconds=$replace_default * $speed / 100))
        while ((attempt++ <= replace_attempts)); do
            echo
            echo "# euscale-describe-auto-scaling-groups DemoASG"
            euscale-describe-auto-scaling-groups DemoASG
            echo
            echo "# eulb-describe-instance-health DemoELB"
            eulb-describe-instance-health DemoELB | tee $tmpdir/$prefix-$(printf '%02d' $step)-eulb-describe-instance-health.out
            
            if [ $(grep -c "InService" $tmpdir/$prefix-$(printf '%02d' $step)-eulb-describe-instance-health.out) -ge $instances ]; then
                break
            else
                echo
                echo -n "At least $instances instances are not \"InService\". Waiting $seconds seconds..."
                sleep $seconds
                echo " Done"
            fi
        done
        break    # delete only one at this time
    done

    if [ $gui = 1 ]; then
        echo
        echo "Browse: ${consoleurl}/?account=$account&username=admin"
        echo "        to confirm resources via management console"

        next 400
    fi
fi


((++step))
instance_ids="$(euscale-describe-auto-scaling-groups DemoASG | grep "^INSTANCE" | cut -f2)"
unset instance_names
for instance_id in $instance_ids; do
    instance_names="$instance_names $(euca-describe-instances $instance_id | grep "^INSTANCE" | cut -f4)"
done
instance_names=${instance_names# *}

lb_name=$(eulb-describe-lbs | cut -f3)
lb_public_ip=$(dig +short $lb_name)

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Confirm updated webpage is visible"
echo "    - Attempt to display webpage first directly via instances,"
echo "      then through the ELB"
echo
echo "============================================================"
echo
echo "Commands:"
for instance_name in $instance_names; do
    echo
    echo "w3m -dump $instance_name"
done
if [ -n "$lb_public_ip" ]; then
    echo
    echo "w3m -dump $lb_name"
    echo "w3m -dump $lb_name"
fi

run 50

if [ $choice = y ]; then
    echo
    for instance_name in $instance_names; do
        echo "# w3m -dump $instance_name"
        w3m -dump $instance_name
        pause
    done
    if [ -n "$lb_public_ip" ]; then
        echo "# w3m -dump $lb_name"
        w3m -dump $lb_name
        echo "# w3m -dump $lb_name"
        w3m -dump $lb_name
    fi

    next
fi


((++step))
instance_ids="$(euscale-describe-auto-scaling-groups DemoASG | grep "^INSTANCE" | cut -f2)"

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Delete the AutoScalingGroup"
echo "    - We must first reduce sizes to zero"
echo "    - Pause a bit longer for changes to be acted upon"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euscale-update-auto-scaling-group DemoASG --min-size 0 --max-size 0 --desired-capacity 0"
echo 
echo "euscale-delete-auto-scaling-group DemoASG"

run 50

if [ $choice = y ]; then
    echo
    echo "# euscale-update-auto-scaling-group DemoASG --min-size 0 --max-size 0 --desired-capacity 0"
    euscale-update-auto-scaling-group DemoASG --min-size 0 --max-size 0 --desired-capacity 0

    attempt=0
    ((seconds=$delete_default * $speed / 100))
    while ((attempt++ <= delete_attempts)); do
        echo
        echo "# euca-describe-instances $instance_ids"
        euca-describe-instances $instance_ids | tee $tmpdir/$prefix-$(printf '%02d' $step)-euca-describe-instances.out

        if [ $(grep -c "terminated" $tmpdir/$prefix-$(printf '%02d' $step)-euca-describe-instances.out) -ge 2 ]; then
            break
        else
            echo
            echo -n "Instances not yet \"terminated\". Waiting $seconds seconds..."
            sleep $seconds
            echo " Done"
        fi
    done

    echo "# euscale-delete-auto-scaling-group DemoASG"
    euscale-delete-auto-scaling-group DemoASG
    pause

    # While the instances are deleted by deletion of the ASG, which removes the terminated results from listings
    for instance_id in $instance_ids; do
        euca-terminate-instances $instance_id &> /dev/null
    done

    # Repeat, as sometimes some terminated instances are still in listings, so we get a clean final listing
    for instance_id in $instance_ids; do
        euca-terminate-instances $instance_id &> /dev/null
    done

    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Delete the Alarms"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euwatch-delete-alarms DemoAddNodesAlarm"
echo "euwatch-delete-alarms DemoDelNodesAlarm"

run 50

if [ $choice = y ]; then
    echo
    echo "# euwatch-delete-alarms DemoAddNodesAlarm"
    euwatch-delete-alarms DemoAddNodesAlarm
    echo "# euwatch-delete-alarms DemoDelNodesAlarm"
    euwatch-delete-alarms DemoDelNodesAlarm

    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Delete the LaunchConfigurations"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euscale-delete-launch-config DemoLC"
echo "euscale-delete-launch-config DemoLC-2"

run 50

if [ $choice = y ]; then
    echo
    echo "# euscale-delete-launch-config DemoLC"
    euscale-delete-launch-config DemoLC
    echo "# euscale-delete-launch-config DemoLC-2"
    euscale-delete-launch-config DemoLC-2

    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Delete the ElasticLoadBalancer"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "eulb-delete-lb DemoELB"

run 50

if [ $choice = y ]; then
    echo
    echo "# eulb-delete-lb DemoELB"
    eulb-delete-lb DemoELB

    next
fi


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Delete the Security Group"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "euca-delete-group DemoSG"

run 50

if [ $choice = y ]; then
    echo
    echo "# euca-delete-group DemoSG"
    euca-delete-group DemoSG

    next
fi


((++step))
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
echo "eulb-describe-lbs"
echo
echo "euca-describe-instances"
echo
echo "euscale-describe-launch-configs"
echo
echo "euscale-describe-auto-scaling-groups"
echo
echo "euscale-describe-policies"
echo
echo "euwatch-describe-alarms"

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

    echo "# eulb-describe-lbs"
    eulb-describe-lbs
    pause

    echo "# euca-describe-instances"
    euca-describe-instances
    pause

    echo "# euscale-describe-launch-configs"
    euscale-describe-launch-configs
    pause

    echo "# euscale-describe-auto-scaling-groups"
    euscale-describe-auto-scaling-groups
    pause

    echo "# euscale-describe-policies"
    euscale-describe-policies
    pause

    echo "# euwatch-describe-alarms"
    euwatch-describe-alarms

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
echo "Eucalyptus SecurityGroup, ElasticLoadBalancer, LaunchConfiguration,"
echo "           AutoScalingGroup and User-Data Script testing complete (time: $(date -u -d @$((end-start)) +"%T"))"