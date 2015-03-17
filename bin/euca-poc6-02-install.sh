#!/bin/bash
#
# This script installs Eucalyptus
#
# This script should be run on all hosts.
#
# This script is eventually designed to support any combination, but was initially
# written to automate the 6-node POC reference architecture.
# It has not been tested to work in other combinations.
#
# Each student MUST run all prior scripts on relevant hosts prior to this script.
#

#  1. Initalize Environment

if [ -z $EUCA_VNET_MODE ]; then
    echo "Please set environment variables first"
    exit 3
fi

[ "$(hostname -s)" = "$EUCA_CLC_HOST_NAME" ] && is_clc=y || is_clc=n
[ "$(hostname -s)" = "$EUCA_UFS_HOST_NAME" ] && is_ufs=y || is_ufs=n
[ "$(hostname -s)" = "$EUCA_MC_HOST_NAME" ]  && is_mc=y  || is_mc=n
[ "$(hostname -s)" = "$EUCA_CC_HOST_NAME" ]  && is_cc=y  || is_cc=n
[ "$(hostname -s)" = "$EUCA_SC_HOST_NAME" ]  && is_sc=y  || is_sc=n
[ "$(hostname -s)" = "$EUCA_OSP_HOST_NAME" ] && is_osp=y || is_osp=n
[ "$(hostname -s)" = "$EUCA_NC1_HOST_NAME" ] && is_nc=y  || is_nc=n
[ "$(hostname -s)" = "$EUCA_NC2_HOST_NAME" ] && is_nc=y
[ "$(hostname -s)" = "$EUCA_NC3_HOST_NAME" ] && is_nc=y
[ "$(hostname -s)" = "$EUCA_NC4_HOST_NAME" ] && is_nc=y

bindir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
confdir=${bindir%/*}/conf
docdir=${bindir%/*}/doc
logdir=${bindir%/*}/log
scriptsdir=${bindir%/*}/scripts
templatesdir=${bindir%/*}/templates
tmpdir=/var/tmp

step=0
speed_max=400
run_default=10
pause_default=2
next_default=5

interactive=1
speed=100


#  2. Define functions

usage () {
    echo "Usage: ${BASH_SOURCE##*/} [-I [-s | -f]]"
    echo "  -I  non-interactive"
    echo "  -s  slower: increase pauses by 25%"
    echo "  -f  faster: reduce pauses by 25%"
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

while getopts Isf? arg; do
    case $arg in
    I)  interactive=0;;
    s)  ((speed < speed_max)) && ((speed=speed+25));;
    f)  ((speed > 0)) && ((speed=speed-25));;
    ?)  usage
        exit 1;;
    esac
done

shift $(($OPTIND - 1))


#  4. Validate environment

# Verify we are not logged on as root
if [ $(id -u) = 0 ]; then
    echo "You must not be root to execute this script. Using sudo for privileged commands"
    exit 9
fi


#  5. Execute Steps

start=$(date +%s)

((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Configure yum repositories"
echo "    - Install the required release RPMs for EPEL,"
echo "      Eucalyptus and Euca2ools"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "sudo yum install -y \\"
echo "         http://downloads.eucalyptus.com/software/eucalyptus/4.1/centos/6Server/x86_64/epel-release-6-8.noarch.rpm \\"
echo "         http://downloads.eucalyptus.com/software/eucalyptus/4.1/centos/6Server/x86_64/eucalyptus-release-4.1-1.el6.noarch.rpm \\"
echo "         http://downloads.eucalyptus.com/software/euca2ools/3.2/centos/6Server/x86_64/euca2ools-release-3.2-1.el6.noarch.rpm"

run

if [ $choice = y ]; then
    echo
    echo "# sudo yum install -y \\"
    echo ">          http://downloads.eucalyptus.com/software/eucalyptus/4.1/centos/6Server/x86_64/epel-release-6-8.noarch.rpm \\"
    echo ">          http://downloads.eucalyptus.com/software/eucalyptus/4.1/centos/6Server/x86_64/eucalyptus-release-4.1-1.el6.noarch.rpm \\"
    echo ">          http://downloads.eucalyptus.com/software/euca2ools/3.2/centos/6Server/x86_64/euca2ools-release-3.2-1.el6.noarch.rpm"
    sudo yum install -y \
             http://downloads.eucalyptus.com/software/eucalyptus/4.1/centos/6Server/x86_64/epel-release-6-8.noarch.rpm \
             http://downloads.eucalyptus.com/software/eucalyptus/4.1/centos/6Server/x86_64/eucalyptus-release-4.1-1.el6.noarch.rpm \
             http://downloads.eucalyptus.com/software/euca2ools/3.2/centos/6Server/x86_64/euca2ools-release-3.2-1.el6.noarch.rpm

    next 50
fi


packages=""
[ $is_clc = y -o $is_ufs = y ] && packages="$packages eucalyptus-cloud"
[ $is_mc = y ] && packages="$packages eucaconsole"
[ $is_cc = y ] && packages="$packages eucalyptus-cc"
[ $is_sc = y ] && packages="$packages eucalyptus-sc"
[ $is_osp = y ] && packages="$packages eucalyptus-walrus"
[ $is_nc = y ] && packages="$packages eucalyptus-nc eucanetd"


((++step))
clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Install packages"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "sudo yum install -y ${packages# }"

run

if [ $choice = y ]; then
    echo
    echo "# sudo yum install -y ${packages# }"
    sudo yum install -y $packages

    next 50
fi


((++step))
if [ $is_clc = y ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Initialize the database"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "sudo euca_conf --initialize"

    run

    if [ $choice = y ]; then
        echo
        echo "# sudo euca_conf --initialize"
        sudo euca_conf --initialize

        next
    fi
fi


((++step))
if [ $is_clc = y ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Start the Cloud Controller service"
    echo "    - After starting services, wait until they  come up"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "sudo chkconfig eucalyptus-cloud on"
    echo
    echo "sudo service eucalyptus-cloud start"

    run

    if [ $choice = y ]; then
        echo
        echo "# sudo chkconfig eucalyptus-cloud on"
        sudo chkconfig eucalyptus-cloud on
        echo "#"
        echo "# sudo service eucalyptus-cloud start"
        sudo service eucalyptus-cloud start

        echo
        echo  -n "Waiting 60 seconds for user-facing services to come up..."
        sleep 60
        echo " Done"

        echo
        while true; do
            echo -n "Testing services... "
            if curl -s http://$EUCA_UFS_PUBLIC_IP:8773/services/User-API | grep -s -q 404; then
                echo " Started"
                break
            else
                echo " Not yet running"
                echo -n "Waiting another 15 seconds..."
                sleep 15
                echo " Done"
            fi
        done

        next
    fi
fi


((++step))
if [ $is_cc = y ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Start the Cluster Controller service"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "sudo chkconfig eucalyptus-cc on"
    echo
    echo "sudo service eucalyptus-cc start"

    run 50

    if [ $choice = y ]; then
        echo
        echo "# sudo chkconfig eucalyptus-cc on"
        sudo chkconfig eucalyptus-cc on
        echo "#"
        echo "# sudo service eucalyptus-cc start"
        sudo service eucalyptus-cc start

        next 50
    fi
fi


((++step))
if [ $is_clc = y ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Register Walrus as the Object Storage Provider"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "sudo euca_conf --register-walrusbackend --partition walrus --host $EUCA_OSP_PUBLIC_IP --component walrus"

    run 50

    if [ $choice = y ]; then
        echo
        echo "# sudo euca_conf --register-walrusbackend --partition walrus --host $EUCA_OSP_PUBLIC_IP --component walrus"
        sudo euca_conf --register-walrusbackend --partition walrus --host $EUCA_OSP_PUBLIC_IP --component walrus

        next 50
    fi
fi


((++step))
if [ $is_clc = y ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Register User-Facing services"
    echo "    - It is normal to see ERRORs for objectstorage, imagingbackend"
    echo "      and loadbalancingbackend at this point, as they require"
    echo "      further configuration"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "sudo euca_conf --register-service -T user-api -H $EUCA_UFS_PUBLIC_IP -N PODAPI"

    run 50

    if [ $choice = y ]; then
        echo
        echo "# sudo euca_conf --register-service -T user-api -H $EUCA_UFS_PUBLIC_IP -N PODAPI"
        sudo euca_conf --register-service -T user-api -H $EUCA_UFS_PUBLIC_IP -N PODAPI

        next 50
    fi
fi


((++step))
if [ $is_clc = y ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Register Cluster Controller service"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "sudo euca_conf --register-cluster --partition AZ1 --host $EUCA_CC_HOST_PUBLIC_IP --component PODCC"

    run 50

    if [ $choice = y ]; then
        echo
        echo "# sudo euca_conf --register-cluster --partition AZ1 --host $EUCA_CC_PUBLIC_IP --component PODCC"
        sudo euca_conf --register-cluster --partition AZ1 --host $EUCA_CC_PUBLIC_IP --component PODCC

        next 50
    fi
fi


((++step))
if [ $is_clc = y ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Register Storage Controller service"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "sudo euca_conf --register-sc --partition AZ1 --host $EUCA_SC_PUBLIC_IP --component PODSC"

    run 50

    if [ $choice = y ]; then
        echo
        echo "# sudo euca_conf --register-sc --partition AZ1 --host $EUCA_SC_PUBLIC_IP --component PODSC"
        sudo euca_conf --register-sc --partition AZ1 --host $EUCA_SC_PUBLIC_IP --component PODSC

        next 50
    fi
fi


((++step))
if [ $is_clc = y ]; then
    nodes="$EUCA_NC1_PRIVATE_IP"
    [ -z $EUCA_NC2_PRIVATE_IP ] || nodes="$nodes $EUCA_NC2_PRIVATE_IP"
    [ -z $EUCA_NC3_PRIVATE_IP ] || nodes="$nodes $EUCA_NC3_PRIVATE_IP"
    [ -z $EUCA_NC4_PRIVATE_IP ] || nodes="$nodes $EUCA_NC4_PRIVATE_IP"

    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Register Node Controller host(s)"
    echo "    - NOTE: After completing this step, you will need to run"
    echo "      the next step on all Node Controller hosts before you"
    echo "      continue here"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "sudo euca_conf --register-nodes=\"$nodes\""

    run 50

    if [ $choice = y ]; then
        echo
        echo "# sudo euca_conf --register-nodes=\"$nodes\""
        sudo euca_conf --register-nodes="$nodes"

        echo
        echo "Please re-start all Node Controller services at this time"

        next 400
    fi
fi


((++step))
if [ $is_nc = y ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Start Node Controller service"
    echo "    - STOP! This step should only be run after the step"
    echo "      which registers all Node Controller hosts on the"
    echo "      Cloud Controller host"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "sudo chkconfig eucalyptus-nc on"
    echo
    echo "sudo service eucalyptus-nc start"

    run 50

    if [ $choice = y ]; then
        echo
        echo "# sudo chkconfig eucalyptus-nc on"
        sudo chkconfig eucalyptus-nc on
        echo "#"
        echo "# sudo service eucalyptus-nc start"
        sudo service eucalyptus-nc start

        next 50
    fi
fi


((++step))
if [ $is_clc = y ]; then
    clear
    echo
    echo "============================================================"
    echo
    echo "$(printf '%2d' $step). Confirm service status"
    echo "    - NOTE: This step should only be run after the step"
    echo "      which starts the Node Controller service on all Node"
    echo "      Controller hosts"
    echo "    - The following services should be in a NOTREADY state:"
    echo "      - cluster, loadbalancingbackend, imaging"
    echo "    - The following services should be in a BROKEN state:"
    echo "      - storage, objectstorage"
    echo "    - This is normal at this point in time, with partial configuration"
    echo "    - Some output truncated for clarity"
    echo
    echo "============================================================"
    echo
    echo "Commands:"
    echo
    echo "sudo euca-describe-services | cut -f 1-5"

    run 50

    if [ $choice = y ]; then
        echo
        echo "# sudo euca-describe-services | cut -f 1-5"
        sudo euca-describe-services | cut -f 1-5

        next 200
    fi
fi


end=$(date +%s)

echo
echo "Installation and initial configuration complete (time: $(date -u -d @$((end-start)) +"%T"))"