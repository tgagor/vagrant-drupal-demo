#!/bin/bash

set -x

# disable selinux
setenforce 0

yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum install -y https://centos7.iuscommunity.org/ius-release.rpm
yum install -y http://www.percona.com/downloads/percona-release/redhat/0.1-3/percona-release-0.1-3.noarch.rpm
rpm --import http://nginx.org/keys/nginx_signing.key

cat > /etc/yum.repos.d/nginx.repo <<REPO
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/mainline/centos/7/x86_64/
gpgcheck=0
enabled=1
REPO

yum update -y

# install used packages
yum install -y nginx \
  php70u-fpm php70u-devel php70u-opcache php70u-mbstring php70u-mysqlnd \
  php70u-process php70u-mcrypt php70u-xml php70u-pdo php70u-gd php70u-pecl-imagick \
  php70u-cli php70u-json php70u-pear \
  Percona-Server-server-56 Percona-Server-client-56 percona-toolkit \
  vim wget

# start db - it will take some time
systemctl start  mysqld.service

# install packages used to build memcached extension
yum groupinstall -y 'Development Tools'
yum install -y zlib-devel libmemcached-devel git unzip memcached

# remove repo dir to refresh it every time
if [ -d /tmp/memcached ]; then
  rm -rf /tmp/memcached
fi

# install memcached extension
git clone -b php7 https://github.com/php-memcached-dev/php-memcached.git /tmp/memcached

cd /tmp/memcached
phpize
./configure --with-php-config=/bin/php-config
make
make install

cat > /etc/php.d/20-memcached.ini <<CONFIG
; Enable memcached extension module
extension=memcached.so
CONFIG

# configure php
cat > /etc/nginx/conf.d/upstream-php-fpm.conf <<CONFIG
upstream php-fpm {
  server 127.0.0.1:9000;
}
CONFIG

cp -f /vagrant/php/php.ini /etc/php.ini
cp -f /vagrant/php/wwwpool.conf /etc/php-fpm.d/www.conf

# configure nginx
rm -f /etc/nginx/conf.d/default.conf
cp /vagrant/nginx/drupal.conf /etc/nginx/conf.d/drupal.conf

# configure database
mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS drupal;
GRANT ALL ON drupal.* TO 'drupal'@'localhost' IDENTIFIED BY 'drupal';
GRANT ALL ON drupal.* TO 'drupal'@'%' IDENTIFIED BY 'drupal';
FLUSH PRIVILEGES;
SQL

# re/start services
systemctl restart php-fpm.service
systemctl restart nginx.service
systemctl start memcached.service

# install drupal
mkdir -p /var/www
cp -a /vagrant/drupal /var/www/drupal
chown -R nginx:nginx /var/www/drupal
