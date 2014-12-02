#!/bin/bash

set -e
set -o xtrace

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
nkill neutron
nkill neutron-server

#------------------------
#create database
#------------------------
cnt=`mysql_cmd "select * from mysql.user;" | grep $MYSQL_NEUTRON_USER |wc -l`
if [[ $cnt -eq 0 ]];then
    mysql_cmd "create user '$MYSQL_NEUTRON_USER'@'%' identified by '$MYSQL_NEUTRON_PASS';"
    mysql_cmd "flush privileges;"
fi

openstack-db --drop --password $MYSQL_NEUTRON_PASS --rootpw $MYSQL_ROOT_PASSWORD --service neutron --host $MYSQL_HOST

mysql_cmd "create database neutron CHARACTER SET latin1;"
mysql_cmd "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$MYSQL_NEUTRON_PASS';"
mysql_cmd "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$MYSQL_NEUTRON_PASS';"

#------------------------
#create neutron user
#------------------------
export SERVICE_TOKEN=$ADMIN_TOKEN
export SERVICE_ENDPOINT=http://$KEYSTONE_HOST:35357/v2.0

get_tenant SERVICE_TENANT service
get_role ADMIN_ROLE admin

if [[ `keystone user-list | grep neutron | wc -l` -eq 0 ]]; then
NEUTRON_USER=$(get_id keystone user-create \
            --name=neutron \
            --pass="$KEYSTONE_NEUTRON_SERVICE_PASSWORD" \
            --tenant_id $SERVICE_TENANT \
            --email=neutron@example.com)
keystone user-role-add \
            --tenant_id $SERVICE_TENANT \
            --user_id $NEUTRON_USER \
            --role_id $ADMIN_ROLE
NEUTRON_SERVICE=$(get_id keystone service-create \
            --name=neutron \
            --type=network \
            --description="OpenStack Networking")
keystone endpoint-create \
            --region RegionOne \
            --service_id $NEUTRON_SERVICE \
            --publicurl "http://$NEUTRON_HOST:9696" \
            --adminurl "http://$NEUTRON_HOST:9696" \
            --internalurl "http://$NEUTRON_HOST:9696"
fi

unset SERVICE_TOKEN
unset SERVICE_ENDPOINT

#------------------------ 
#change the config file
#------------------------

#----------------------to use the database-------------------
openstack-config --set /etc/neutron/neutron.conf database connection \
mysql://$MYSQL_NEUTRON_USER:$MYSQL_NEUTRON_PASS@$MYSQL_HOST/neutron

#---------------to use identity service for authentication-----------------
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

#------------------------to use the message broker-------------------------
openstack-config --set /etc/neutron/neutron.conf DEFAULT \
rpc_backend neutron.openstack.common.rpc.impl_qpid
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
qpid_hostname $QPID_HOST

#------------------------to notify compute about network topology changes--------------------------
source /root/keyrc

 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
notify_nova_on_port_status_changes True
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
notify_nova_on_port_data_changes True
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
nova_url http://$NEUTRON_HOST:8774/v2
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
nova_admin_username nova
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
nova_admin_tenant_id $(keystone tenant-list | awk '/ service / { print $2 }')
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
nova_admin_password $KEYSTONE_NEUTRON_SERVICE_PASSWORD
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
nova_admin_auth_url http://$KEYSTONE_AUTH_HOST:$KEYSTONE_AUTH_PORT/v2.0

#------------------to use Modular Layer2(ML2)------------------
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
core_plugin ml2
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
service_plugins router

#-------------------to conf ML2 plug-in--------------------
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
type_drivers vlan
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
tenant_network_types vlan
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
mechanism_drivers openvswitch
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan \
#tunnel_id_ranges 1:1000
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan \
network_vlan_ranges physnet1:1000:2999 

openstack-config --del /etc/neutron/plugins/ml2/ml2_conf.ini ovs enable_tunneling
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs tenant_network_type vlan
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs bridge_mappings  physnet1:br-eth1

 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup \
firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup \
enable_security_group True
#-------------------to conf compute to use networking-----------------------
openstack-config --set /etc/nova/nova.conf DEFAULT \
network_api_class nova.network.neutronv2.api.API
 openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_url http://controller:9696
 openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_auth_strategy keystone
 openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_admin_tenant_name service
 openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_admin_username neutron
 openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_admin_password $KEYSTONE_NEUTRON_SERVICE_PASSWORD
 openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_admin_auth_url http://controller:35357/v2.0
 openstack-config --set /etc/nova/nova.conf DEFAULT \
linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver
 openstack-config --set /etc/nova/nova.conf DEFAULT \
firewall_driver nova.virt.firewall.NoopFirewallDriver
 openstack-config --set /etc/nova/nova.conf DEFAULT \
security_group_api neutron

#--------------create a symbolic link------------------
rm -rf /etc/neutron/plugin.ini
ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

#--------------restart the compute services------------
service openstack-nova-api restart
service openstack-nova-scheduler restart
service openstack-nova-conductor restart
service neutron-server stop

#--------------to use long plug-in names---------------
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
core_plugin neutron.plugins.ml2.plugin.Ml2Plugin
 openstack-config --set /etc/neutron/neutron.conf DEFAULT \
service_plugins neutron.services.l3_router.l3_router_plugin.L3RouterPlugin

#--------------populate the database-------------------
 su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
--config-file /etc/neutron/plugin.ini upgrade head"  neutron

rm -rf /var/log/neutron/server.log
service neutron-server restart
chkconfig neutron-server on


#------------------------------------------------------
# generate neutronrc
#------------------------------------------------------
cp -rf $TOPDIR/neutronrc /root/
sed -i "s,%KEYSTONE_NEUTRON_SERVICE_PASSWORD%,$KEYSTONE_NEUTRON_SERVICE_PASSWORD,g" /root/neutronrc
sed -i "s,%KEYSTONE_HOST%,$KEYSTONE_HOST,g" /root/neutronrc

source /root/neutronrc

set +o xtrace
