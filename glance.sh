# glance.sh

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
BASE_SQL_CONN=mysql://$MYSQL_GLANCE_USER:$MYSQL_GLANCE_PASS@$MYSQL_HOST
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
nkill glance

#------------------------
# deal with config file
#------------------------
openstack-config --set /etc/glance/glance-api.conf database \
connection mysql://$MYSQL_GLANCE_USER:$MYSQL_GLANCE_PASS@$MYSQL_HOST/glance?charset=utf8

openstack-config --set /etc/glance/glance-registry.conf database \
connection mysql://$MYSQL_GLANCE_USER:$MYSQL_GLANCE_PASS@$MYSQL_HOST/glance?charset=utf8

#------------------------
#create database
#------------------------

#service openstack-glance-api stop
#service openstack-glance-registry stop

cnt=`mysql_cmd "select * from mysql.user;" | grep $MYSQL_GLANCE_USER |wc -l`
if [[ $cnt -eq 0 ]];then
    mysql_cmd "create user '$MYSQL_GLANCE_USER'@'%' identified by '$MYSQL_GLANCE_PASS';"
    mysql_cmd "flush privileges;"
fi

openstack-db --drop --password $MYSQL_GLANCE_PASS --rootpw $MYSQL_ROOT_PASSWORD --service glance --host $MYSQL_HOST
openstack-db --init --password $MYSQL_GLANCE_PASS --rootpw $MYSQL_ROOT_PASSWORD --service glance --host $MYSQL_HOST

#------------------------
#create glance user
#------------------------
export SERVICE_TOKEN=$ADMIN_TOKEN
export SERVICE_ENDPOINT=http://$KEYSTONE_HOST:35357/v2.0

get_tenant SERVICE_TENANT service
get_role ADMIN_ROLE admin

if [[ `keystone user-list | grep glance | wc -l` -eq 0 ]]; then
GLANCE_USER=$(get_id keystone user-create \
            --name=glance \
            --pass="$KEYSTONE_GLANCE_SERVICE_PASSWORD" \
            --tenant_id $SERVICE_TENANT \
            --email=glance@example.com)
keystone user-role-add \
            --tenant_id $SERVICE_TENANT \
            --user_id $GLANCE_USER \
            --role_id $ADMIN_ROLE
GLANCE_SERVICE=$(get_id keystone service-create \
            --name=glance \
            --type=image \
            --description="Glance Image Service")
keystone endpoint-create \
            --region RegionOne \
            --service_id $GLANCE_SERVICE \
            --publicurl "http://$GLANCE_HOST:9292" \
            --adminurl "http://$GLANCE_HOST:9292" \
            --internalurl "http://$GLANCE_HOST:9292"
fi

unset SERVICE_TOKEN
unset SERVICE_ENDPOINT

#------------------------
#change the config file
#------------------------
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken \
auth_uri http://$KEYSTONE_AUTH_HOST:5000
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken \
auth_host $KEYSTONE_AUTH_HOST
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken \
auth_port $KEYSTONE_AUTH_PORT
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken \
auth_protocol $KEYSTONE_AUTH_PROTOCOL
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken \
admin_tenant_name $SERVICE_TENANT_NAME
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken \
admin_user glance
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken \
admin_password $KEYSTONE_GLANCE_SERVICE_PASSWORD
openstack-config --set /etc/glance/glance-api.conf paste_deploy \
flavor keystone

openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken \
auth_uri http://$KEYSTONE_AUTH_HOST:5000
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken \
auth_host $KEYSTONE_AUTH_HOST
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken \
auth_port $KEYSTONE_AUTH_PORT
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken \
auth_protocol $KEYSTONE_AUTH_PROTOCOL
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken \
admin_tenant_name $SERVICE_TENANT_NAME
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken \
admin_user glance
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken \
admin_password $KEYSTONE_GLANCE_SERVICE_PASSWORD
openstack-config --set /etc/glance/glance-registry.conf paste_deploy \
flavor keystone

#------------------------
#start the glance-api glance-registry service
#------------------------
service openstack-glance-api start
service openstack-glance-registry start
chkconfig openstack-glance-api on
chkconfig openstack-glance-registry on


#---------------------------
# create glancerc
#----------------------------
cp -rf $TOPDIR/glancerc /root/
sed -i "s,%KEYSTONE_GLANCE_SERVICE_PASSWORD%,$KEYSTONE_GLANCE_SERVICE_PASSWORD,g" /root/glancerc
sed -i "s,%KEYSTONE_HOST%,$KEYSTONE_HOST,g" /root/glancerc

source ~/glancerc


set +o xtrace
