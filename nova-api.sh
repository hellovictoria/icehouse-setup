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
nkill nova-api
nkill nova-cert
nkill nova-conductor
nkill nova-scheduler
nkill nova-consoleauth
nkill nova-novncproxy

#------------------------
# deal with config file
#------------------------
openstack-config --set /etc/nova/nova.conf \
database connection mysql://$MYSQL_NOVA_USER:$MYSQL_NOVA_PASS@$MYSQL_HOST/nova?charset=utf8

openstack-config --set /etc/nova/nova.conf \
DEFAULT rpc_backend qpid
openstack-config --set /etc/nova/nova.conf \
DEFAULT qpid_hostname $NOVA_HOST

openstack-config --set /etc/nova/nova.conf \
DEFAULT my_ip $NOVA_IP
openstack-config --set /etc/nova/nova.conf \
DEFAULT vncserver_listen $NOVA_IP
openstack-config --set /etc/nova/nova.conf \
DEFAULT vncserver_proxyclient_address $NOVA_IP

#------------------------
#create database
#------------------------
cnt=`mysql_cmd "select * from mysql.user;" | grep $MYSQL_NOVA_USER |wc -l`
if [[ $cnt -eq 0 ]];then
    mysql_cmd "create user '$MYSQL_NOVA_USER'@'%' identified by '$MYSQL_NOVA_PASS';"
    mysql_cmd "flush privileges;"
fi

openstack-db --drop --password $MYSQL_NOVA_PASS --rootpw $MYSQL_ROOT_PASSWORD --service nova --host $MYSQL_HOST
openstack-db --init --password $MYSQL_NOVA_PASS --rootpw $MYSQL_ROOT_PASSWORD --service nova --host $MYSQL_HOST

#------------------------
#create glance user
#------------------------
export SERVICE_TOKEN=$ADMIN_TOKEN
export SERVICE_ENDPOINT=http://$KEYSTONE_HOST:35357/v2.0

get_tenant SERVICE_TENANT service
get_role ADMIN_ROLE admin

if [[ `keystone user-list | grep nova | wc -l` -eq 0 ]]; then
NOVA_USER=$(get_id keystone user-create \
            --name=nova \
            --pass="$KEYSTONE_NOVA_SERVICE_PASSWORD" \
            --tenant_id $SERVICE_TENANT \
            --email=nova@example.com)
keystone user-role-add \
            --tenant_id $SERVICE_TENANT \
            --user_id $NOVA_USER \
            --role_id $ADMIN_ROLE
NOVA_SERVICE=$(get_id keystone service-create \
            --name=nova \
            --type=compute \
            --description="Nova Compute Service")
keystone endpoint-create \
            --region RegionOne \
            --service_id $NOVA_SERVICE \
            --publicurl http://controller:8774/v2/$SERVICE_TENANT \
            --adminurl http://controller:8774/v2/$SERVICE_TENANT \
            --internalurl http://controller:8774/v2/$SERVICE_TENANT
#            --publicurl http://$NOVA_HOST:8774/v2/%\(tenant_id\)s \
#            --adminurl http://$NOVA_HOST:8774/v2/%\(tenant_id\)s \
#            --internalurl http://$NOVA_HOST:8774/v2/%\(tenant_id\)s
RESELLER_ROLE=$(get_id keystone role-create --name=ResellerAdmin)
keystone user-role-add \
            --tenant_id $SERVICE_TENANT \
            --user_id $NOVA_USER \
            --role_id $RESELLER_ROLE
EC2_SERVICE=$(get_id keystone service-create \
            --name=ec2 \
            --type=ec2 \
            --description="EC2 Compatibility Layer")
keystone endpoint-create \
            --region RegionOne \
            --service_id $EC2_SERVICE \
            --publicurl "http://$NOVA_HOST:8773/services/Cloud" \
            --adminurl "http://$NOVA_HOST:8773/services/Admin" \
            --internalurl "http://$NOVA_HOST:8773/services/Cloud"
fi
unset SERVICE_TOKEN
unset SERVICE_ENDPOINT

#------------------------
#change the config file
#------------------------
 openstack-config --set /etc/nova/nova.conf DEFAULT auth_strategy  \
keystone
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

#-----------------------------------
#start the compute services
#-----------------------------------
 service openstack-nova-api start
 service openstack-nova-cert start
 service openstack-nova-consoleauth start
 service openstack-nova-scheduler start
 service openstack-nova-conductor start
 service openstack-nova-novncproxy start
 chkconfig openstack-nova-api on
 chkconfig openstack-nova-cert on
 chkconfig openstack-nova-consoleauth on
 chkconfig openstack-nova-scheduler on
 chkconfig openstack-nova-conductor on
 chkconfig openstack-nova-novncproxy on

#---------------------------
# create novarc
#----------------------------
cp -rf $TOPDIR/novarc /root/
sed -i "s,%KEYSTONE_NOVA_SERVICE_PASSWORD%,$KEYSTONE_NOVA_SERVICE_PASSWORD,g" /root/novarc
sed -i "s,%KEYSTONE_HOST%,$KEYSTONE_HOST,g" /root/novarc

source ~/novarc

set +o xtrace
