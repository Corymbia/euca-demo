#!/bin/bash
#
# This script configures Eucalyptus DNS after a Faststart installation
#
# This should be run immediately after the Faststart installer completes
#

#  1. Initalize Environment

bindir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
confdir=${bindir%/*}/conf
tmpdir=/var/tmp

step=0
speed_max=400
run_default=10
pause_default=2
next_default=5

interactive=1
speed=100
showdnsconfig=0
extended=0
region=${AWS_DEFAULT_REGION#*@}
domain=${AWS_DEFAULT_DOMAIN:-$(hostname -i).xip.io}
instance_subdomain=${EUCA_INSTANCE_SUBDOMAIN:-.vm}
loadbalancer_subdomain=${EUCA_LOADBALANCER_SUBDOMAIN:-lb}
if [ "$domain" = "$(hostname -i).xip.io" ]; then
    parent_dns_host=google-public-dns-a.google.com
else
    parent_dns_host=ns1.$domain
fi
parent_dns_ip=$(host $parent_dns_host | cut -d " " -f4)
dns_timeout=30
dns_loadbalancer_ttl=15


#  2. Define functions

usage () {
    echo "Usage: ${BASH_SOURCE##*/} [-I [-s | -f]] [-x] [-e]"
    echo "                             [-r region] [-d domain] [-i instance_subdomain]"
    echo "                             [-b loadbalancer_subdomain] [-p parent_dns_server]"
    echo "  -I                         non-interactive"
    echo "  -s                         slower: increase pauses by 25%"
    echo "  -f                         faster: reduce pauses by 25%"
    echo "  -p                         display example parent DNS server configuration"
    echo "  -e                         extended confirmation of API calls"
    echo "  -r region                  Eucalyptus Region (default: $region)"
    echo "  -d domain                  Eucalyptus Domain (default: $domain)"
    echo "  -i instance_subdomain      Eucalyptus Instance Sub-Domain (default: $instance_subdomain)"
    echo "  -b loadbalancer_subdomain  Eucalyptus Load Balancer Sub-Domain (default: $loadbalancer_subdomain)"
    echo "  -p parent_dns_server       Eucalyptus Parent DNS Server (default: $parent_dns_host)"

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

while getopts Isfxer:d:i:b:p: arg; do
    case $arg in
    I)  interactive=0;;
    s)  ((speed < speed_max)) && ((speed=speed+25));;
    f)  ((speed > 0)) && ((speed=speed-25));;
    x)  showdnsconfig=1;;
    e)  extended=1;;
    r)  region="$OPTARG";;
    d)  domain="$OPTARG";;
    i)  instance_subdomain="$OPTARG";;
    b)  loadbalancer_subdomain="$OPTARG";;
    p)  parent_dns_server="$OPTARG";;

    ?)  usage
        exit 1;;
    esac
done

shift $(($OPTIND - 1))


#  4. Validate environment

if [ -z $region ]; then
    echo "-r region missing!"
    echo "Could not automatically determine region, and it was not specified as a parameter"
    exit 10
else
    case $region in
      us-east-1|us-west-1|us-west-2|sa-east-1|eu-west-1|eu-central-1|ap-northeast-1|ap-southeast-1|ap-southeast-2)
        echo "-r $region invalid: This script can not be run against AWS regions"
        exit 11;;
    esac
fi

if [ -z $domain ]; then
    echo "-d domain missing!"
    echo "Could not automatically determine domain, and it was not specified as a parameter"
    exit 12
fi

if [ -z $instance_subdomain ]; then
    echo "-i instance_subdomain missing!"
    echo "Could not automatically determine instance_subdomain, and it was not specified as a parameter"
    exit 13
fi

if [ -z $loadbalancer_subdomain ]; then
    echo "-b loadbalancer_subdomain missing!"
    echo "Could not automatically determine loadbalancer_subdomain, and it was not specified as a parameter"
    exit 14
fi

if [ -z $parent_dns_server ]; then
    echo "-p parent_dns_server missing!"
    echo "Could not automatically determine parent_dns_server, and it was not specified as a parameter"
    exit 14
fi

user_region=$region-admin@$region

convert_faststart=0
if ! grep -s -q "\[region $region]" /etc/euca2ools/conf.d/$region.ini; then
    echo "Could not find Eucalyptus ($region) Region!"
    echo "Expected to find: [region $region] in /etc/euca2ools/conf.d/$region.ini"
    convert_faststart=1
elif ! grep -s -q "\[user $region-admin]" ~/.euca/$region.ini; then
    echo "Could not find Eucalyptus ($region) Region Eucalyptus Administrator (admin) Euca2ools user!"
    echo "Expected to find: [user $region-admin] in ~/.euca/$region.ini"
    convert_faststart=1
elif [ ! -r ~/.creds/$region/eucalyptus/admin/iamrc ]; then
    echo "Could not find Eucalyptus ($region) Region Eucalyptus Administrator credentials!"
    echo "Expected to find: ~/.creds/$region/eucalyptus/admin/iamrc"
    convert_faststart=1
fi
if [ $convert_faststart = 1 ]; then
    if [ -r ~/.euca/faststart.ini ]; then
        # Convert what FastStart creates into the conventions used by the demos
        cp /var/lib/eucalyptus/keys/cloud-cert.pem /usr/share/euca2ools/certs/cert-$region.pem
        chmod 0644 /usr/share/euca2ools/certs/cert-$region.pem

        sed -n -e "1i; Eucalyptus Region $region\n" \
               -e "s/localhost/$region/" \
               -e "s/[0-9]*:admin/$region-admin/" \
               -e "/^\[region/,/^\user =/p" ~/.euca/faststart.ini > /etc/euca2ools/conf.d/$region.ini

        sed -n -e "1i; Eucalyptus Region $region\n" \
               -e "s/[0-9]*:admin/$region-admin/" \
               -e "/^\[user/,/^account-id =/p" \
               -e "\$a\\\\" ~/.euca/faststart.ini > ~/.euca/$region.ini

        echo "; Eucalyptus Global"  > ~/.euca/global.ini
        echo                       >> ~/.euca/global.ini
        echo "[global]"            >> ~/.euca/global.ini
        echo "region = $region"    >> ~/.euca/global.ini
        echo                       >> ~/.euca/global.ini

        mkdir -p ~/.creds/$region/eucalyptus/admin

        echo AWSAccessKeyId=$(sed -n -e 's/key-id = //p' ~/.euca/faststart.ini)    > ~/.creds/$region/eucalyptus/admin/iamrc
        echo AWSSecretKey=$(sed -n -e 's/secret-key = //p' ~/.euca/faststart.ini) >> ~/.creds/$region/eucalyptus/admin/iamrc

        rm -f ~/.euca/faststart.ini
    else
        echo "Could not find FastStart Euca2ools credentials file to attempt conversion!"
        echo "Expected to find: ~/.euca/faststart.ini"
        exit 29
    fi
fi

# Prevent certain environment variables from breaking commands
unset AWS_DEFAULT_PROFILE
unset AWS_CREDENTIAL_FILE
unset EC2_PRIVATE_KEY
unset EC2_CERT


#  5. Execute Procedure

start=$(date +%s)

((++step))
clear
echo
echo "================================================================================"
echo
echo "$(printf '%2d' $step). Configure Eucalyptus DNS Server"
echo "    - Instances will use the Cloud Controller's DNS Server directly"
echo
echo "================================================================================"
echo
echo "Commands:"
echo
echo "euctl system.dns.nameserver=ns1.$region.$domain --region $user_region"
echo
echo "euctl system.dns.nameserveraddress=$(hostname -i) --region $user_region"

run 50

if [ $choice = y ]; then
    echo
    echo "# euctl system.dns.nameserver=ns1.$region.$domain --region $user_region"
    euctl system.dns.nameserver=ns1.$region.$region --region $user_region
    echo "#"
    echo "# euctl system.dns.nameserveraddress=$(hostname -i) --region $user_region"
    euctl system.dns.nameserveraddress=$(hostname -i) --region $user_region

    next 50
fi


((++step))
clear
echo
echo "================================================================================"
echo
echo "$(printf '%2d' $step). Configure DNS Timeout and TTL"
echo
echo "================================================================================"
echo
echo "Commands:"
echo
echo "euctl dns.tcp.timeout_seconds=$dns_timeout --region $user_region"
echo
echo "euctl services.loadbalancing.dns_ttl=$dns_loadbalancer_ttl --region $user_region"

run 50

if [ $choice = y ]; then
    echo
    echo "# euctl dns.tcp.timeout_seconds=$dns_timeout --region $user_region"
    euctl dns.tcp.timeout_seconds=$dns_timeout --region $user_region
    echo "#"
    echo "# euctl services.loadbalancing.dns_ttl=$dns_loadbalancer_ttl --region $user_region"
    euctl services.loadbalancing.dns_ttl=$dns_loadbalancer_ttl --region $user_region

    next 50
fi


((++step))
clear
echo
echo "================================================================================"
echo
echo "$(printf '%2d' $step). Configure DNS Domain"
echo
echo "================================================================================"
echo
echo "Commands:"
echo
echo "euctl system.dns.dnsdomain=$region.$domain --region $user_region"

run 50

if [ $choice = y ]; then
    echo
    echo "# euctl system.dns.dnsdomain=$region.$domain --region $user_region"
    euctl system.dns.dnsdomain=$region.$domain --region $user_region

    next 50
fi


((++step))
clear
echo
echo "================================================================================"
echo
echo "$(printf '%2d' $step). Configure DNS Sub-Domains"
echo
echo "================================================================================"
echo
echo "Commands:"
echo
echo "euctl cloud.vmstate.instance_subdomain=$instance_subdomain --region $user_region"
echo
echo "euctl services.loadbalancing.dns_subdomain=$loadbalancer_subdomain --region $user_region"

run 50

if [ $choice = y ]; then
    echo
    echo "# euctl cloud.vmstate.instance_subdomain=$instance_subdomain --region $user_region"
    euctl cloud.vmstate.instance_subdomain=$instance_subdomain --region $user_region
    echo "#"
    echo "# euctl services.loadbalancing.dns_subdomain=$loadbalancer_subdomain --region $user_region"
    euctl services.loadbalancing.dns_subdomain=$loadbalancer_subdomain --region $user_region

    next 50
fi


((++step))
clear
echo
echo "================================================================================"
echo
echo "$(printf '%2d' $step). Enable DNS"
echo
echo "================================================================================"
echo
echo "Commands:"
echo
echo "euctl bootstrap.webservices.use_instance_dns=true --region $user_region"
echo
echo "euctl bootstrap.webservices.use_dns_delegation=true --region $user_region"

run 50

if [ $choice = y ]; then
    echo
    echo "# euctl bootstrap.webservices.use_instance_dns=true --region $user_region"
    euctl bootstrap.webservices.use_instance_dns=true --region $user_region
    echo "#"
    echo "# euctl bootstrap.webservices.use_dns_delegation=true --region $user_region"
    euctl bootstrap.webservices.use_dns_delegation=true --region $user_region

    next 50
fi


((++step))
# Construct Eucalyptus Endpoints (assumes AWS-style URLs)
autoscaling_url=http://autoscaling.$region.$domain:8773/
bootstrap_url=http://bootstrap.$region.$domain:8773/
cloudformation_url=http://cloudformation.$region.$domain:8773/
ec2_url=http://ec2.$region.$domain:8773/
elasticloadbalancing_url=http://elasticloadbalancing.$region.$domain:8773/
iam_url=http://iam.$region.$domain:8773/
monitoring_url=http://monitoring.$region.$domain:8773/
properties_url=http://properties.$region.$domain:8773/
reporting_url=http://reporting.$region.$domain:8773/
s3_url=http://s3.$region.$domain:8773/
sts_url=http://sts.$region.$domain:8773/

clear
echo
echo "============================================================"
echo
echo "$(printf '%2d' $step). Update Euca2ools with DNS Region Endpoints"
echo
echo "============================================================"
echo
echo "Commands:"
echo
echo "cat << EOF > /etc/euca2ools/conf.d/$region.ini"
echo "; Eucalyptus Region $region"
echo
echo "[region $region]"
echo "autoscaling-url = $autoscaling_url"
echo "bootstrap-url = $bootstrap_url"
echo "cloudformation-url = $cloudformation_url"
echo "ec2-url = $ec2_url"
echo "elasticloadbalancing-url = $elasticloadbalancing_url"
echo "iam-url = $iam_url"
echo "monitoring-url = $monitoring_url"
echo "properties-url = $properties_url"
echo "reporting-url = $reporting_url"
echo "s3-url = $s3_url"
echo "sts-url = $sts_url"
echo "user = $region-admin"
echo
echo "EOF"

run 50

if [ $choice = y ]; then
    echo "# cat << EOF > /etc/euca2ools/conf.d/$region.ini"
    echo "> ; Eucalyptus Region $region"
    echo ">"
    echo "> [region $region]"
    echo "> autoscaling-url = $autoscaling_url"
    echo "> cloudformation-url = $cloudformation_url"
    echo "> bootstrap-url = $bootstrap_url"
    echo "> ec2-url = $ec2_url"
    echo "> elasticloadbalancing-url = $elasticloadbalancing_url"
    echo "> iam-url = $iam_url"
    echo "> monitoring-url $monitoring_url"
    echo "> properties-url $properties_url"
    echo "> reporting-url $reporting_url"
    echo "> s3-url = $s3_url"
    echo "> sts-url = $sts_url"
    echo "> user = $region-admin"
    echo ">"
    echo "> EOF"
    # Use echo instead of cat << EOF to better show indentation
    echo "; Eucalyptus Region $region"                               > /etc/euca2ools/conf.d/$region.ini
    echo                                                            >> /etc/euca2ools/conf.d/$region.ini
    echo "[region $region]"                                         >> /etc/euca2ools/conf.d/$region.ini
    echo "autoscaling-url = $autoscaling_url"                       >> /etc/euca2ools/conf.d/$region.ini
    echo "cloudformation-url = $cloudformation_url"                 >> /etc/euca2ools/conf.d/$region.ini
    echo "bootstrap-url = $bootstrap_url"                           >> /etc/euca2ools/conf.d/$region.ini
    echo "ec2-url = $ec2_url"                                       >> /etc/euca2ools/conf.d/$region.ini
    echo "elasticloadbalancing-url = $elasticloadbalancing_url"     >> /etc/euca2ools/conf.d/$region.ini
    echo "iam-url = $iam_url"                                       >> /etc/euca2ools/conf.d/$region.ini
    echo "monitoring-url $monitoring_url"                           >> /etc/euca2ools/conf.d/$region.ini
    echo "properties-url $properties_url"                           >> /etc/euca2ools/conf.d/$region.ini
    echo "reporting-url $reporting_url"                             >> /etc/euca2ools/conf.d/$region.ini
    echo "s3-url = $s3_url"                                         >> /etc/euca2ools/conf.d/$region.ini
    echo "sts-url = $sts_url"                                       >> /etc/euca2ools/conf.d/$region.ini
    echo "user = $region-admin"                                     >> /etc/euca2ools/conf.d/$region.ini
    echo                                                            >> /etc/euca2ools/conf.d/$region.ini
fi


((++step))
if [ $showdnsconfig = 1 ]; then
    clear
    echo
    echo "================================================================================"
    echo
    echo "$(printf '%2d' $step). Display Parent DNS Server Configuration"
    echo "    - This is an example of what changes need to be made on the"
    echo "      parent DNS server which will delgate DNS to Eucalyptus"
    echo "      for Eucalyptus DNS names used for instances, ELBs and"
    echo "      services"
    echo "    - You should make these changes to the parent DNS server"
    echo "      manually, once, outside of creating and running demos"
    echo "    - Instances will use the Cloud Controller's DNS Server directly"
    echo "    - This configuration is based on the BIND configuration"
    echo "      conventions used on the cs.prc.eucalyptus-systems.com DNS server"
    echo
    echo "================================================================================"
    echo
    echo "Commands:"
    echo
    echo "# Add these lines to /etc/named.conf on the parent DNS server"
    echo "         zone \"$region.$domain\" IN"
    echo "         {"
    echo "                 type master;"
    echo "                 file \"/etc/named/db.$aws_default_region\";"
    echo "         };"
    echo "#"
    echo "# Create the zone file on the parent DNS server"
    echo "> ;"
    echo "> ; DNS zone for $aws_default_region.$aws_default_domain"
    echo "> ; - Eucalyptus configured to use CLC as DNS server"
    echo ">"
    echo "# cat << EOF > /etc/named/db.$aws_default_region"
    echo "> $TTL 1M"
    echo "> $ORIGIN $aws_default_region.$aws_default_domain"
    echo "> @                       SOA     ns1 root ("
    echo ">                                 $(date +%Y%m%d)01      ; Serial"
    echo ">                                 1H              ; Refresh"
    echo ">                                 10M             ; Retry"
    echo ">                                 1D              ; Expire"
    echo ">                                 1H )            ; Negative Cache TTL"
    echo ">"
    echo ">                         NS      ns1"
    echo ">"
    echo "> ns1                     A       $(hostname -i)"
    echo ">"
    echo "> clc                     A       $(hostname -i)"
    echo "> ufs                     A       $(hostname -i)"
    echo "> mc                      A       $(hostname -i)"
    echo "> osp                     A       $(hostname -i)"
    echo "> walrus                  A       $(hostname -i)"
    echo "> cc                      A       $(hostname -i)"
    echo "> sc                      A       $(hostname -i)"
    echo "> ns1                     A       $(hostname -i)"
    echo ">"
    echo "> console                 A       $(hostname -i)"
    echo ">"
    echo "> autoscaling             A       $(hostname -i)"
    echo "> bootstrap               A       $(hostname -i)"
    echo "> cloudformation          A       $(hostname -i)"
    echo "> ec2                     A       $(hostname -i)"
    echo "> elasticloadbalancing    A       $(hostname -i)"
    echo "> iam                     A       $(hostname -i)"
    echo "> monitoring              A       $(hostname -i)"
    echo "> properties              A       $(hostname -i)"
    echo "> reporting               A       $(hostname -i)"
    echo "> s3                      A       $(hostname -i)"
    echo "> sts                     A       $(hostname -i)"
    echo ">"
    echo "> ${instance_subdomain#.}                   NS      ns1"
    echo "> ${loadbalancer_subdomain#.}                      NS      ns1"
    echo "> EOF"

    next 200
fi

    
((++step))
clear
echo
echo "================================================================================"
echo
echo "$(printf '%2d' $step). Confirm DNS resolution for Services"
echo "    - Confirm service URLS in eucarc resolve"
echo
echo "================================================================================"
echo
echo "Commands:"
echo
echo "dig +short autoscaling.$region.$domain"
echo
echo "dig +short bootstrap.$region.$domain"
echo
echo "dig +short cloudformation.$region.$domain"
echo
echo "dig +short ec2.$region.$domain"
echo
echo "dig +short elasticloadbalancing.$region.$domain"
echo
echo "dig +short iam.$region.$domain"
echo
echo "dig +short monitoring.$region.$domain"
echo
echo "dig +short properties.$region.$domain"
echo
echo "dig +short reporting.$region.$domain"
echo
echo "dig +short s3.$region.$domain"
echo
echo "dig +short sts.$region.$domain"

run 50

if [ $choice = y ]; then
    echo
    echo "# dig +short autoscaling.$region.$domain"
    dig +short autoscaling.$region.$domain
    pause

    echo "# dig +short bootstrap.$region.$domain"
    dig +short bootstrap.$region.$domain
    pause

    echo "# dig +short cloudformation.$region.$domain"
    dig +short cloudformation.$region.$domain
    pause

    echo "# dig +short ec2.$region.$domain"
    dig +short ec2.$region.$domain
    pause

    echo "# dig +short elasticloadbalancing.$region.$domain"
    dig +short elasticloadbalancing.$region.$domain
    pause

    echo "# dig +short iam.$region.$domain"
    dig +short iam.$region.$domain
    pause

    echo "# dig +short monitoring.$region.$domain"
    dig +short monitoring.$region.$domain
    pause

    echo "# dig +short properties.$region.$domain"
    dig +short properties.$region.$domain
    pause

    echo "# dig +short reporting.$region.$domain"
    dig +short reporting.$region.$domain
    pause

    echo "# dig +short s3.$region.$domain"
    dig +short s3.$region.$domain
    pause

    echo "# dig +short sts.$region.$domain"
    dig +short sts.$region.$domain

    next
fi


((++step))
clear
echo
echo "================================================================================"
echo
echo "$(printf '%2d' $step). Confirm API commands work with new URLs"
echo "    - Confirm service describe commands still work"
echo
echo "================================================================================"
echo
echo "Commands:"
echo
echo "euca-describe-regions"
if [ $extended = 1 ]; then
    echo
    echo "euca-describe-availability-zones"
    echo
    echo "euca-describe-keypairs"
    echo
    echo "euca-describe-images"
    echo
    echo "euca-describe-instance-types"
    echo
    echo "euca-describe-instances"
    echo
    echo "euca-describe-instance-status"
    echo
    echo "euca-describe-groups"
    echo
    echo "euca-describe-volumes"
    echo
    echo "euca-describe-snapshots"
fi
echo
echo "eulb-describe-lbs"
echo
echo "euform-describe-stacks"
echo
echo "euscale-describe-auto-scaling-groups"
if [ $extended = 1 ]; then
    echo
    echo "euscale-describe-launch-configs"
    echo
    echo "euscale-describe-auto-scaling-instances"
    echo
    echo "euscale-describe-policies"
fi
echo
echo "euwatch-describe-alarms"

run 50

if [ $choice = y ]; then
    echo
    echo "# euca-describe-regions"
    euca-describe-regions
    pause

    if [ $extended = 1 ]; then
        echo "# euca-describe-availability-zones"
        euca-describe-availability-zones
        pause

        echo "# euca-describe-keypairs"
        euca-describe-keypairs
        pause

        echo "# euca-describe-images"
        euca-describe-images
        pause

        echo "# euca-describe-instance-types"
        euca-describe-instance-types
        pause

        echo "# euca-describe-instances"
        euca-describe-instances
        pause

        echo "# euca-describe-instance-status"
        euca-describe-instance-status
        pause

        echo "# euca-describe-groups"
        euca-describe-groups
        pause

        echo "# euca-describe-volumes"
        euca-describe-volumes
        pause

        echo "# euca-describe-snapshots"
        euca-describe-snapshots
        pause
    fi

    echo
    echo "# eulb-describe-lbs"
    eulb-describe-lbs
    pause

    echo
    echo "# euform-describe-stacks"
    euform-describe-stacks
    pause

    echo
    echo "# euscale-describe-auto-scaling-groups"
    euscale-describe-auto-scaling-groups
    pause

    if [ $extended = 1 ]; then
        echo "# euscale-describe-launch-configs"
        euscale-describe-launch-configs
        pause

        echo "# euscale-describe-auto-scaling-instances"
        euscale-describe-auto-scaling-instances
        pause

        echo "# euscale-describe-policies"
        euscale-describe-policies
        pause
    fi

    echo
    echo "# euwatch-describe-alarms"
    euwatch-describe-alarms

    next
fi


end=$(date +%s)

echo
case $(uname) in
  Darwin)
    echo "Eucalyptus DNS configured (time: $(date -u -r $((end-start)) +"%T"))";;
  *)
    echo "Eucalyptus DNS configured (time: $(date -u -d @$((end-start)) +"%T"))";;
esac
