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
nkill neutron

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

#----------------------------------------------------------------------------
# Configuration file
# /etc/neutron/plugins/ml2/ml2_conf.ini
#----------------------------------------------------------------------------
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
type_drivers vlan
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
tenant_network_types vlan
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 \
mechanism_drivers openvswitch
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan \
tunnel_id_ranges 1:1000


openstack-config --del /etc/neutron/plugins/ml2/ml2_conf.ini ovs enable_tunneling
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs tenant_network_type vlan
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs bridge_mappings  physnet1:br-eth1


# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs \
#local_ip $INSTANCE_TUNNELS_INTERFACE_IP_ADDRESS_COM
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs \
#tunnel_type gre
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs \
#enable_tunneling True


 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup \
firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup \
enable_security_group True

#-----------------------to configure th OVS service----------------------
service openvswitch start
chkconfig openvswitch on
[[ `ovs-vsctl show | grep br-int | wc -l` -gt 0 ]] && ovs-vsctl del-br br-int
sleep 3

[[ `ovs-vsctl show | grep br-eth1 | wc -l` -gt 0 ]] && ovs-vsctl del-br br-eth1
sleep 3

ovs-vsctl add-br br-int
ovs-vsctl add-br br-eth1
ovs-vsctl add-port br-eth1 eth1


#-----------------------to config Compute to use Networking--------------
openstack-config --set /etc/nova/nova.conf DEFAULT \
network_api_class nova.network.neutronv2.api.API
openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_url http://$NOVA_HOST:9696
openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_auth_strategy keystone
openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_admin_tenant_name $SERVICE_TENANT_NAME
openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_admin_username neutron
openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_admin_password $KEYSTONE_NEUTRON_SERVICE_PASSWORD
openstack-config --set /etc/nova/nova.conf DEFAULT \
neutron_admin_auth_url http://$KEYSTONE_HOST:$KEYSTONE_AUTH_PORT/v2.0
openstack-config --set /etc/nova/nova.conf DEFAULT \
linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver
openstack-config --set /etc/nova/nova.conf DEFAULT \
firewall_driver nova.virt.firewall.NoopFirewallDriver
openstack-config --set /etc/nova/nova.conf DEFAULT \
security_group_api neutron

#--------------create a symbolic link------------------
rm -rf /etc/neutron/plugin.ini
ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

cp /etc/init.d/neutron-openvswitch-agent /etc/init.d/neutronopenvswitch-agent.orig
sed -i 's,plugins/openvswitch/ovs_neutron_plugin.ini,plugin.ini,g' /etc/init.d/neutron-openvswitch-agent

#--------------restart the compute service---------------
service openstack-nova-compute restart
sleep 5

#--------------start the OVS agent-----------------------
service neutron-openvswitch-agent start
sleep 5
chkconfig neutron-openvswitch-agent on


set +o xtrace





