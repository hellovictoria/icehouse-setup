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
BASE_SQL_CONN=mysql://$MYSQL_NOVA_USER:$MYSQL_NOVA_PASSWORD@$MYSQL_HOST
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

#---------------------------------------------------
# Clear Front installation
#---------------------------------------------------
cp -rf $TOPDIR/nkill /usr/bin/nkill
chmod +x /usr/bin/nkill
nkill nova-compute
nkill nova-xvpvncproxy
nkill nova-novncproxy

#---------------------------------------------------
# Configuration file
# /etc/nova/nova.conf
# qpid
#---------------------------------------------------
 openstack-config --set /etc/nova/nova.conf \
database connection mysql://$MYSQL_NOVA_USER:$MYSQL_NOVA_PASS@$NOVA_HOST/nova?charset=utf8
 openstack-config --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
 openstack-config --set /etc/nova/nova.conf keystone_authtoken \
auth_uri http://$KEYSTONE_AUTH_HOST:5000
 openstack-config --set /etc/nova/nova.conf keystone_authtoken \
auth_host $KEYSTONE_AUTH_HOST
 openstack-config --set /etc/nova/nova.conf keystone_authtoken \
auth_protocol $KEYSTONE_AUTH_PROTOCOL
 openstack-config --set /etc/nova/nova.conf keystone_authtoken \
auth_port $KEYSTONE_AUTH_PORT
 openstack-config --set /etc/nova/nova.conf keystone_authtoken \
admin_user nova
 openstack-config --set /etc/nova/nova.conf keystone_authtoken \
admin_tenant_name $SERVICE_TENANT_NAME
 openstack-config --set /etc/nova/nova.conf keystone_authtoken \
admin_password $KEYSTONE_NOVA_SERVICE_PASSWORD

openstack-config --set /etc/nova/nova.conf \
DEFAULT rpc_backend qpid
openstack-config --set /etc/nova/nova.conf \
DEFAULT qpid_hostname $NOVA_HOST

 openstack-config --set /etc/nova/nova.conf \
DEFAULT my_ip $NOVA_COMPUTE_IP
 openstack-config --set /etc/nova/nova.conf \
DEFAULT vnc_enabled True
 openstack-config --set /etc/nova/nova.conf \
DEFAULT vncserver_listen 0.0.0.0
 openstack-config --set /etc/nova/nova.conf \
DEFAULT vncserver_proxyclient_address $NOVA_COMPUTE_IP
 openstack-config --set /etc/nova/nova.conf \
DEFAULT novncproxy_base_url http://$NOVA_HOST:6080/vnc_auto.html

openstack-config --set /etc/nova/nova.conf \
DEFAULT glance_host $GLANCE_HOST

#-----------------------------------
#start the compute services
#-----------------------------------
service libvirtd start
service messagebus start
service openstack-nova-compute start
chkconfig libvirtd on
chkconfig messagebus on
chkconfig openstack-nova-compute on

#---------------------------
# create novarc
#----------------------------
cp -rf $TOPDIR/novarc /root/
sed -i "s,%KEYSTONE_NOVA_SERVICE_PASSWORD%,$KEYSTONE_NOVA_SERVICE_PASSWORD,g" /root/novarc
sed -i "s,%KEYSTONE_HOST%,$KEYSTONE_HOST,g" /root/novarc

source ~/novarc

set +o xtrace
