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
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan \
#tunnel_id_ranges 1:1000
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan \
network_vlan_ranges physnet1:1000:2999

openstack-config --del /etc/neutron/plugins/ml2/ml2_conf.ini ovs enable_tunneling
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs tenant_network_type vlan
openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs bridge_mappings  physnet1:br-eth1

# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs \
#local_ip $INSTANCE_TUNNELS_INTERFACE_IP_ADDRESS
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs \
#tunnel_type gre
# openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini ovs \
#enable_tunneling True


 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup \
firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
 openstack-config --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup \
enable_security_group True

#----------------------------------------------------------------------------
# Configuration file
# /etc/neutron/l3_agent.ini
#----------------------------------------------------------------------------
openstack-config --set /etc/neutron/l3_agent.ini DEFAULT external_network_bridge br-ex

#sed -i "s,# external_network_bridge =,external_network_bridge =,g" /etc/neutron/l3_agent.ini 

#--------------------------------------------------------------------------
# start openvswitch
#--------------------------------------------------------------------------
service openvswitch start
chkconfig openvswitch on

[[ `ovs-vsctl show | grep br-int | wc -l` -gt 0 ]] && ovs-vsctl del-br br-int
sleep 3

[[ `ovs-vsctl show | grep br-ex | wc -l` -gt 0 ]] && ovs-vsctl del-br br-ex
sleep 3

[[ `ovs-vsctl show | grep br-eth1 | wc -l` -gt 0 ]] && ovs-vsctl del-br br-eth1
sleep 3


ovs-vsctl add-br br-eth1
ovs-vsctl add-port br-eth1 eth1
ovs-vsctl add-br br-int
ovs-vsctl add-br br-ex
ovs-vsctl add-port br-ex eth2

rm -rf /etc/neutron/plugin.ini
ln -s plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

cp /etc/init.d/neutron-openvswitch-agent /etc/init.d/neutronopenvswitch-agent.orig
sed -i 's,plugins/openvswitch/ovs_neutron_plugin.ini,plugin.ini,g' /etc/init.d/neutron-openvswitch-agent

#-----------------start the Networking services-----------------------
service neutron-openvswitch-agent start
sleep 10

service neutron-dhcp-agent start
sleep 10
service neutron-l3-agent start
sleep 10
service neutron-metadata-agent start
chkconfig neutron-openvswitch-agent on
chkconfig neutron-l3-agent on
chkconfig neutron-dhcp-agent on
chkconfig neutron-metadata-agent on



set +o xtrace
