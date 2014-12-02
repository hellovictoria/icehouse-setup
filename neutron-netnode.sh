#!/bin/bash

set -e
set -o xtrace

#--------------------------------------------------
# Set up global ENV
#---------------------------------------------------
TOPDIR=$(cd $(dirname "$0") && pwd)
source $TOPDIR/localrc
source $TOPDIR/function

###########################################################
#
# Your Configurations.
#
###########################################################
BASE_SQL_CONN=mysql://$MYSQL_NEUTRON_USER:$MYSQL_NEUTRON_PASS@$MYSQL_HOST
unset OS_USERNAME
unset OS_AUTH_KEY
unset OS_AUTH_TENANT
unset OS_STRATEGY
unset OS_AUTH_STRATEGY
unset OS_AUTH_URL
unset SERVICE_TOKEN
unset SERVICE_ENDPOINT
unset http_proxy
unset https_proxy
unset ftp_proxy

KEYSTONE_AUTH_HOST=$KEYSTONE_HOST
KEYSTONE_AUTH_PORT=35357
KEYSTONE_AUTH_PROTOCOL=http
KEYSTONE_SERVICE_HOST=$KEYSTONE_HOST
KEYSTONE_SERVICE_PORT=5000
KEYSTONE_SERVICE_PROTOCOL=http
SERVICE_ENDPOINT=http://$KEYSTONE_HOST:35357/v2.0

#------------------------
# Set up global ENV
#------------------------
TOPDIR=$(cd $(dirname "$0") && pwd)
source $TOPDIR/localrc
source $TOPDIR/function

#---------------------------------------------------
# Clear Front installation
#---------------------------------------------------
cp -rf $TOPDIR/nkill /usr/bin/nkill
chmod +x /usr/bin/nkill
nkill neutron-openvswitch-agent
nkill neutron-l3-agent
nkill neutron-metadata-agent
#----------------------------------------------------------------------------
# Configuration file
# /etc/neutron/neutron.conf
# authentication mechanism, message broker, plug-in
#----------------------------------------------------------------------------

#---------------to use the identity service for authentication---------------
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
auth_strategy keystone
 openstack-config --set /etc/neutron/neutron.conf keystone_authtoken \
auth_uri http://$KEYSTONE_AUTH_HOST:5000
 openstack-config --set /etc/neutron/neutron.conf keystone_authtoken \
auth_host $KEYSTONE_AUTH_HOST
 openstack-config --set /etc/neutron/neutron.conf keystone_authtoken \
auth_protocol $KEYSTONE_AUTH_PROTOCOL
 openstack-config --set /etc/neutron/neutron.conf keystone_authtoken \
auth_port $KEYSTONE_AUTH_PORT 
 openstack-config --set /etc/neutron/neutron.conf keystone_authtoken \
admin_tenant_name $SERVICE_TENANT_NAME
 openstack-config --set /etc/neutron/neutron.conf keystone_authtoken \
admin_user neutron
 openstack-config --set /etc/neutron/neutron.conf keystone_authtoken \
admin_password $KEYSTONE_NEUTRON_SERVICE_PASSWORD

#----------------------to use message broker----------------------------
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
rpc_backend neutron.openstack.common.rpc.impl_qpid
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
qpid_hostname $QPID_HOST

#----------------------to use Modular Layer2(ML2) plug-in----------------
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
core_plugin ml2
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
service_plugins router
#-----------------------to assist with troubleshooting-------------------
sed -i "s/# verbose = True/verbose = True/g" /etc/neutron/neutron.conf

#-----------------------to configure the Layer-3(L3) agent---------------
openstack-config --set /etc/neutron/l3_agent.ini DEFAULT \
interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
openstack-config --set /etc/neutron/l3_agent.ini DEFAULT \
use_namespaces True
#-----------------------to assist with troubleshooting-------------------
cnt=`cat /etc/neutron/l3_agent.ini | grep "verbose =" | wc -l`
if [[ $cnt -eq 0 ]];then
sed -i '1a verbose = True' /etc/neutron/l3_agent.ini
fi

#-----------------------to configure the DHCP agent----------------------
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT \
interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT \
dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT \
use_namespaces True
#-----------------------to assist with troubleshooting-------------------
cnt=`cat /etc/neutron/dhcp_agent.ini | grep "verbose =" | wc -l`
if [[ $cnt -eq 0 ]];then 
    sed -i '1a verbose = True' /etc/neutron/dhcp_agent.ini
fi
#-----------------------to adjust DHCP MTU-------------------------------
openstack-config --set /etc/neutron/dhcp_agent.ini DEFAULT \
dnsmasq_config_file /etc/neutron/dnsmasq-neutron.conf
#-----create and edit /etc/neutron/dnsmasq-neutron.conf -----------------
cat << "EOF" >> /etc/neutron/dnsmasq-neutron.conf
dhcp-option-force=26,1454
EOF

nkill dnsmasq

#------------------------to config the metadata agent--------------------
 openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT \
auth_url http://$KEYSTONE_AUTH_HOST:5000/v2.0
 openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT \
auth_region regionOne
 openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT \
admin_tenant_name  $SERVICE_TENANT_NAME
 openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT \
admin_user neutron
 openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT \
admin_password $KEYSTONE_NEUTRON_SERVICE_PASSWORD
 openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT \
nova_metadata_ip $NOVA_HOST
 openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT \
metadata_proxy_shared_secret $NEUTRON_METADATA_PROXY_SECRET

#-----------------------to assist with troubleshooting-------------------
cnt=`cat /etc/neutron/metadata_agent.ini | grep "verbose =" | wc -l`
if [[ $cnt -eq 0 ]];then
sed -i '1a verbose = True' /etc/neutron/metadata_agent.ini
fi

set +o xtrace





