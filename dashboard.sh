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

#------------------------
#create database
#------------------------
#cnt=`mysql_cmd "select * from mysql.user;" | grep $MYSQL_DASHBOARD_USER |wc -l`
#if [[ $cnt -eq 0 ]];then
#    mysql_cmd "create user '$MYSQL_DASHBOARD_USER'@'%' identified by '$MYSQL_DASHBOARD_PASS';"
#    mysql_cmd "flush privileges;"
#fi

#openstack-db --drop --password $MYSQL_DASHBOARD_PASS --rootpw $MYSQL_ROOT_PASSWORD --service dashboard --host $MYSQL_HOST

#mysql_cmd "create database dashboard CHARACTER SET latin1;"
#mysql_cmd "GRANT ALL PRIVILEGES ON dashboard.* TO 'dashboard'@'localhost' IDENTIFIED BY '$MYSQL_DASHBOARD_PASS';"
#mysql_cmd "GRANT ALL PRIVILEGES ON neutron.* TO 'dashboard'@'%' IDENTIFIED BY '$MYSQL_DASHBOARD_PASS';"

#---------------------------------------------------
# Change local setting configuration.
#---------------------------------------------------

cp /etc/openstack-dashboard/local_settings /etc/openstack-dashboard/local_settings.bak
local_settings=/etc/openstack-dashboard/local_settings

sed -i "s,127.0.0.1,$OPENSTACK_HOST,g" $local_settings

#----------- SELinux policy ------------------------------
cp /etc/selinux/config /etc/selinux/config.bak
selinux_config=/etc/selinux/config
sed -i "s,SELINUX=disabled,SELINUX=enforcing,g" $selinux_config
setsebool -P httpd_can_network_connect on

#----------- start the Apache web server and mamcached-----
service httpd start
service memcached start
chkconfig httpd on
chkconfig memcached on

set +o xtrace
