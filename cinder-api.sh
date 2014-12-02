#!/bin/bash

set -e
set -o xtrace

###########################################################
#
# Your Configurations.
#
###########################################################
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
nkill cinder-api
nkill cinder-scheduler

#--------------------------
# create database 
#--------------------------
cnt=`mysql_cmd "select * from mysql.user;" | grep $MYSQL_CINDER_USER |wc -l`
if [[ $cnt -eq 0 ]];then
    mysql_cmd "create user '$MYSQL_CINDER_USER'@'%' identified by '$MYSQL_CINDER_PASS';"
    mysql_cmd "flush privileges;"
fi

openstack-db --drop --password $MYSQL_CINDER_PASS --rootpw $MYSQL_ROOT_PASSWORD --service cinder --host $MYSQL_HOST

mysql_cmd "create database cinder CHARACTER SET latin1;"
mysql_cmd "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$MYSQL_CINDER_PASS';"
mysql_cmd "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$MYSQL_CINDER_PASS';"

#--------- create database tables for the Block Storage service -----------
su -s /bin/sh -c "keystone-manage db_sync" keystone

#---------------------------------
# create keystone authenticate 
#---------------------------------

export SERVICE_TOKEN=$ADMIN_TOKEN
export SERVICE_ENDPOINT=http://$KEYSTONE_HOST:35357/v2.0

get_tenant SERVICE_TENANT service
get_role ADMIN_ROLE admin

if [[ `keystone user-list | grep cinder | wc -l` -eq 0 ]]; then

CINDER_USER=$(get_id keystone user-create \
            --name=cinder \
            --pass="$KEYSTONE_CINDER_SERVICE_PASSWORD" \
            --tenant_id $SERVICE_TENANT \
            --email=cinder@example.com)

keystone user-role-add \
            --tenant_id $SERVICE_TENANT \
            --user_id $CINDER_USER \
            --role_id $ADMIN_ROLE
CINDER_SERVICE=$(get_id keystone service-create \
            --name=cinder \
            --type=volume \
            --description="OpenStack Block Storage")
keystone endpoint-create \
            --region RegionOne \
            --service_id $CINDER_SERVICE \
            --publicurl "http://$CINDER_HOST:8776/v1/%\(tenant_id\)s" \
            --adminurl "http://$CINDER_HOST:8776/v1/%\(tenant_id\)s" \
            --internalurl "http://$CINDER_HOST:8776/v1/%\(tenant_id\)s"
CINDERV2_SERVICE=$(get_id keystone service-create \
            --name=cinderv2 \
            --type=volumev2 \
            --description="OpenStack Block Storage v2")
keystone endpoint-create \
            --region RegionOne \
            --service_id $CINDERV2_SERVICE \
            --publicurl "http://$CINDER_HOST:8776/v2/%\(tenant_id\)s" \
            --adminurl "http://$CINDER_HOST:8776/v2/%\(tenant_id\)s" \
            --internalurl "http://$CINDER_HOST:8776/v2/%\(tenant_id\)s"

fi

unset SERVICE_TOKEN
unset SERVICE_ENDPOINT

#----------------------------------------------
# modify /etc/cinder/cinder.conf
#----------------------------------------------
openstack-config --set /etc/cinder/cinder.conf database connection \
mysql://cinder:$MYSQL_CINDER_PASS@$CINDER_HOST/cinder

openstack-config --set /etc/cinder/cinder.conf DEFAULT \
auth_strategy keystone
openstack-config --set /etc/cinder/cinder.conf keystone_authtoken \
auth_uri http://$KEYSTONE_HOST:$KEYSTONE_SERVICE_PORT
openstack-config --set /etc/cinder/cinder.conf keystone_authtoken \
auth_host $KEYSTONE_HOST
openstack-config --set /etc/cinder/cinder.conf keystone_authtoken \
auth_protocol $KEYSTONE_AUTH_PROTOCOL
openstack-config --set /etc/cinder/cinder.conf keystone_authtoken \
auth_port $KEYSTONE_AUTH_PORT
openstack-config --set /etc/cinder/cinder.conf keystone_authtoken \
admin_user cinder
openstack-config --set /etc/cinder/cinder.conf keystone_authtoken \
admin_tenant_name $SERVICE_TENANT_NAME
openstack-config --set /etc/cinder/cinder.conf keystone_authtoken \
admin_password $KEYSTONE_CINDER_SERVICE_PASSWORD

#-------------- conf to use the Qpid message broker -------------------
openstack-config --set /etc/cinder/cinder.conf \
DEFAULT rpc_backend qpid
openstack-config --set /etc/cinder/cinder.conf \
DEFAULT qpid_hostname $QPID_HOST

#-------------- conf the Block Storage services to start-------------
service openstack-cinder-api start
service openstack-cinder-scheduler start
chkconfig openstack-cinder-api on
chkconfig openstack-cinder-scheduler on

#---------------------------------------------------
# Generate Keystone RC
#---------------------------------------------------
cat <<EOF > /root/keyrc
export OS_TENANT_NAME=service
export OS_USERNAME=cinder
export OS_PASSWORD=$KEYSTONE_CINDER_SERVICE_PASSWORD
export OS_AUTH_URL=http://$KEYSTONE_HOST:5000/v2.0/
EOF

source ~/keyrc

set +o xtrace
