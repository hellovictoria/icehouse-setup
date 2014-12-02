#!/bin/bash

set -e
set -o xtrace 

#--------------------------------------------------
# Set up global ENV
#---------------------------------------------------
TOPDIR=$(cd $(dirname "$0") && pwd)
source $TOPDIR/localrc
source $TOPDIR/function

#---------------------------------------------------
# unset some variables
#---------------------------------------------------
unset http_proxy
unset https_proxy
unset ftp_proxy
export OS_USERNAME=""
export OS_AUTH_KEY=""
export OS_AUTH_TENANT=""
export OS_STRATEGY=""
export OS_AUTH_STRATEGY=""
export OS_AUTH_URL=""
export SERVICE_ENDPOINT=""

#---------------------------------------------------
# set some variables
#---------------------------------------------------
BASE_SQL_CONN=mysql://$MYSQL_KEYSTONE_USER:$MYSQL_KEYSTONE_PASSWORD@$MYSQL_HOST
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
nkill keystone

openstack-config --set /etc/keystone/keystone.conf \
database connection mysql://keystone:KEYSTONE_DBPASS@controller/keystone

#---------------------------------------------------
# Create Data Base for keystone.
#---------------------------------------------------
cnt=`mysql_cmd "select * from mysql.user;" | grep $MYSQL_KEYSTONE_USER |wc -l`
if [[ $cnt -eq 0 ]];then
    mysql_cmd "create user '$MYSQL_KEYSTONE_USER'@'%' identified by '$MYSQL_KEYSTONE_PASS';"
    mysql_cmd "flush privileges;"
fi

cnt=`mysql_cmd "show databases;" | grep keystone | wc -l`

if [[ $cnt -gt 0 ]]; then
    openstack-db --drop --password $MYSQL_KEYSTONE_PASS --rootpw $MYSQL_ROOT_PASSWORD --service keystone --host $MYSQL_HOST
    cnt=0
fi
 
if [[ $cnt -eq 0 ]]; then
    mysql_cmd "create database keystone CHARACTER SET utf8;"
fi

mysql_cmd "GRANT ALL PRIVILEGES ON keystone.* to 'keystone'@'localhost' IDENTIFIED BY 'KEYSTONE_DBPASS';"
mysql_cmd "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'KEYSTONE_DBPASS';"

#---------------------------------------------------
# Sync Data Base
#--------------------------------------------------
su -s /bin/sh -c "keystone-manage db_sync" keystone

#---------------------------------------------------
# Change keystone.conf
#---------------------------------------------------
#ADMIN_TOKEN=$(openssl rand -hex 10)
echo $ADMIN_TOKEN
openstack-config --set /etc/keystone/keystone.conf DEFAULT admin_token $ADMIN_TOKEN

keystone-manage pki_setup --keystone-user keystone --keystone-group keystone
chown -R keystone:keystone /etc/keystone/ssl
chmod -R o-rwx /etc/keystone/ssl

service openstack-keystone start
chkconfig openstack-keystone on

(crontab -l -u keystone 2>&1 | grep -q token_flush) || \
echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/
keystone-tokenflush.log 2>&1' >> /var/spool/cron/keystone

export OS_SERVICE_TOKEN=$ADMIN_TOKEN
export OS_SERVICE_ENDPOINT=http://$KEYSTONE_HOST:35357/v2.0

#---------------------------------------------------
# Init the databases and endpoints
#---------------------------------------------------
cp  -rf $TOPDIR/keystone_data.sh /tmp/
sed -i "s,%KEYSTONE_HOST%,$KEYSTONE_HOST,g" /tmp/keystone_data.sh
sed -i "s,%SERVICE_TOKEN%,$SERVICE_TOKEN,g" /tmp/keystone_data.sh
sed -i "s,%ADMIN_PASSWORD%,$ADMIN_PASSWORD,g" /tmp/keystone_data.sh
sed -i "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" /tmp/keystone_data.sh
sed -i "s,%SERVICE_ENDPOINT%,$SERVICE_ENDPOINT,g" /tmp/keystone_data.sh

chmod +x /tmp/keystone_data.sh
/tmp/keystone_data.sh
rm -rf /tmp/keystone_data.sh


#---------------------------------------------------
# Generate Keystone RC
#---------------------------------------------------
cat <<EOF > ~/keyrc
export OS_TENANT_NAME=$ADMIN_USER
export OS_USERNAME=$ADMIN_USER
export OS_PASSWORD=$ADMIN_PASSWORD
export OS_AUTH_URL=http://$KEYSTONE_HOST:5000/v2.0/
EOF

source ~/keyrc


set +o xtrace
