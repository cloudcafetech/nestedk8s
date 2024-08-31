#!/usr/bin/env bash
# Openshift Jumphost (DNS,TFTP,LB,NFS,DHCP,WEB) host setup script
# DO NOT RUN TFTP, DNS & DHCP in same Host, Use either TFTP (dnsmasq+dhcp+tftp+pxe) or DNS & DHCP
# Ref: (https://www.linuxtechi.com/install-openshift-baremetal-upi/)

DOMAIN=cloudcafe.tech
CTX=ocp414
OCPVERM=4.14
OCPVER=4.14.34

PULLSECRET='{"auths":{"fake":{"auth": "bar"}}}'
#PULLSECRET='copy-and-paste-secret-file'

HIP=`ip -o -4 addr list eth0 | grep -v secondary | awk '{print $4}' | cut -d/ -f1`
SUBNET=`echo $HIP | cut -d. -f1-3`
REV=`echo $SUBNET | awk -F . '{print $3"."$2"."$1".in-addr.arpa"}'`

# Change IP, MAC, Hostname & GW

GW=192.168.29.1 # JIO Router Gateway

BASEMAC=BC:24:11

HIPT=`echo $HIP | awk -F . '{print $4}'`
JIP=214
if [[ "$HIPT" != "$JIP" ]]; then JIP=$HIPT; fi
JIP2=215
BIP=216
M1IP=217
M2IP=218
M3IP=219
I1IP=220
I2IP=221
W1IP=222
W2IP=223

BOOT=bootstrap
MAS1=ocpmaster1
MAS2=ocpmaster2
MAS3=ocpmaster3
INF1=ocpinfra1
INF2=ocpinfra2
WOR1=ocpworker1
WOR2=ocpworker2
JUMP=`hostname`

BOOTMAC=$BASEMAC:11:22:88
MAS1MAC=$BASEMAC:11:22:11
MAS2MAC=$BASEMAC:11:22:22
MAS3MAC=$BASEMAC:11:22:33
INF1MAC=$BASEMAC:11:22:44
INF2MAC=$BASEMAC:11:22:55
WOR1MAC=$BASEMAC:11:22:66
WOR2MAC=$BASEMAC:11:22:77

#########################
## DO NOT MODIFY BELOW ##
#########################

JUMPIP=$SUBNET.$JIP
JUMPIP2=$SUBNET.$JIP2
BOOTIP=$SUBNET.$BIP
MAS1IP=$SUBNET.$M1IP
MAS2IP=$SUBNET.$M2IP
MAS3IP=$SUBNET.$M3IP
INF1IP=$SUBNET.$I1IP
INF2IP=$SUBNET.$I2IP
WOR1IP=$SUBNET.$W1IP
WOR2IP=$SUBNET.$W2IP

red=$(tput setaf 1)
grn=$(tput setaf 2)
yel=$(tput setaf 3)
blu=$(tput setaf 4)
bld=$(tput bold)
nor=$(tput sgr0)

# Download Openshift Software from Red Hat portal
toolsetup() {

echo "$bld$grn Downloading & Installing Openshift binary $nor"
curl -s -o openshift-install-linux.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$OCPVER/openshift-install-linux.tar.gz
tar xpvf openshift-install-linux.tar.gz
rm -rf openshift-install-linux.tar.gz
mv openshift-install /usr/local/bin

curl -s -o openshift-client-linux.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$OCPVER/openshift-client-linux.tar.gz
tar xvf openshift-client-linux.tar.gz
rm -rf openshift-client-linux.tar.gz
mv oc kubectl /usr/local/bin

echo "$bld$grn Downloading Openshift ISO ... $nor"
curl -s -o rhcos-live.x86_64.iso https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OCPVERM/$OCPVER/rhcos-live.x86_64.iso

echo "$bld$grn Downloading Openshift Initramfs Images ... $nor"
curl -s -o rhcos-initramfs.img https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OCPVERM/$OCPVER/rhcos-$OCPVER-x86_64-live-initramfs.x86_64.img

echo "$bld$grn Downloading Openshift Kernel ... $nor"
curl -s -o rhcos-kernel https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OCPVERM/$OCPVER/rhcos-$OCPVER-x86_64-live-kernel-x86_64

echo "$bld$grn Downloading Openshift Rootfs Image ... $nor"
curl -s -o rhcos-rootfs.img https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OCPVERM/$OCPVER/rhcos-$OCPVER-x86_64-live-rootfs.x86_64.img

#curl -s -o rhcos-metal.raw.gz https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OCPVERM/$OCPVER/rhcos-$OCPVER-x86_64-metal.x86_64.raw.gz
#curl -s -o rhcos-metal.x86_64.raw.gz https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OCPVERM/$OCPVER/rhcos-metal.x86_64.raw.gz
#curl -s -o rhcos-qemu.x86_64.qcow2.gz https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OCPVERM/$OCPVER/rhcos-qemu.x86_64.qcow2.gz
#sleep 5
#gunzip rhcos-qemu.x86_64.qcow2.gz
#file rhcos-qemu.x86_64.qcow2

#curl -s -o rhcos-live.x86_64.iso https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/latest/rhcos-live.x86_64.iso
#curl -s -o rhcos-metal.x86_64.raw.gz https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/latest/rhcos-metal.x86_64.raw.gz

}

# Configure DNS Server
dnssetup() {

echo "$bld$grn Configuring DNS Server $nor"
if [[ -n $(netstat -tunpl | grep 53) ]]; then echo "$bld$red DNS Port (53) used, DO NOT RUN dnssetup $nor"; exit; fi
yum install bind bind-utils -y

cat <<EOF > /etc/named.conf
//
// named.conf
//
// Provided by Red Hat bind package to configure the ISC BIND named(8) DNS
// server as a caching only nameserver (as a localhost DNS resolver only).
//
// See /usr/share/doc/bind*/sample/ for example named configuration files.
//

options {
        listen-on port 53 { $JUMPIP; };
#       listen-on-v6 port 53 { any; };
        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        recursing-file  "/var/named/data/named.recursing";
        secroots-file  "/var/named/data/named.secroots";
        allow-query     { localhost; $SUBNET.0/24; };

        /*
         - If you are building an AUTHORITATIVE DNS server, do NOT enable recursion.
         - If you are building a RECURSIVE (caching) DNS server, you need to enable
           recursion.
         - If your recursive DNS server has a public IP address, you MUST enable access
           control to limit queries to your legitimate users. Failing to do so will
           cause your server to become part of large scale DNS amplification
           attacks. Implementing BCP38 within your network would greatly
           reduce such attack surface
        */
        recursion yes;

//      dnssec-enable yes;
//      dnssec-validation yes;
//      dnssec-lookaside auto;
        # Using Google DNS
        forwarders {
                $GW;
                8.8.8.8;
                8.8.4.4;
        };

        /* Path to ISC DLV key */
//      bindkeys-file "/etc/named.iscdlv.key";
//
//      managed-keys-directory "/var/named/dynamic";
        pid-file "/run/named/named.pid";
//      session-keyfile "/run/named/session.key";
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "." IN {
   type hint;
   file "named.ca";
};

zone "$DOMAIN" IN {
  type master;
  file "/etc/named/zones/db.$DOMAIN";
};

zone "$REV" {
  type master;
  file "/etc/named/zones/db.reverse";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOF

mkdir /etc/named/zones
cat <<EOF > /etc/named/zones/db.$DOMAIN
\$TTL    604800
@   	IN  	SOA 	$JUMP.$DOMAIN. contact.$DOMAIN (
                  1     ; Serial
             604800     ; Refresh
              86400     ; Retry
            2419200     ; Expire
             604800     ; Minimum
)
	IN  	NS  	$JUMP

; Name server - A records
$JUMP.$DOMAIN.		IN	A	$JUMPIP
$JUMP.$DOMAIN.		IN	A	$JUMPIP2

; Temp Bootstrap Node
$BOOT.$DOMAIN.		IN	A	$BOOTIP

; Controlplane Node
$MAS1.$CTX.$DOMAIN.	IN	A	$MAS1IP
$MAS2.$CTX.$DOMAIN.	IN	A	$MAS2IP
$MAS3.$CTX.$DOMAIN.	IN	A	$MAS3IP

; Worker Node
$WOR1.$CTX.$DOMAIN.	IN	A	$WOR1IP
$WOR2.$CTX.$DOMAIN.	IN	A	$WOR2IP

; Infra Node
$INF1.$CTX.$DOMAIN.	IN	A	$INF1IP
$INF2.$CTX.$DOMAIN.	IN	A	$INF2IP

; Openshift Internal - Load balancer
api.$CTX.$DOMAIN.	IN	A	$JUMPIP
api-int.$CTX.$DOMAIN.	IN	A	$JUMPIP
*.apps.$CTX.$DOMAIN.	IN	A	$JUMPIP2

; ETCD Cluster
etcd-0.$CTX.$DOMAIN.	IN	A	$MAS1IP
etcd-1.$CTX.$DOMAIN.	IN	A	$MAS2IP
etcd-2.$CTX.$DOMAIN.	IN	A	$MAS3IP


; Openshift Internal SRV records (cluster name - $CTX)
_etcd-server-ssl._tcp.$CTX.$DOMAIN.	86400	IN	SRV	0	10	2380	etcd-0.$CTX
_etcd-server-ssl._tcp.$CTX.$DOMAIN.	86400	IN	SRV	0	10	2380	etcd-1.$CTX
_etcd-server-ssl._tcp.$CTX.$DOMAIN.	86400	IN	SRV	0	10	2380	etcd-2.$CTX

;oauth-openshift.apps.$CTX.$DOMAIN.	IN	A	$JUMPIP2
;console-openshift-console.apps.$CTX.$DOMAIN.	IN	A	$JUMPIP2

EOF

cat <<EOF > /etc/named/zones/db.reverse
\$TTL    604800
@   	IN  	SOA 	$JUMP.$DOMAIN. contact.$DOMAIN (
                  1     ; Serial
             604800     ; Refresh
              86400     ; Retry
            2419200     ; Expire
             604800     ; Minimum
)

; Name servers - NS records
	IN  	NS  	$JUMP.$DOMAIN.

; Name servers - PTR records
$JIP	IN	PTR	$JUMP.$DOMAIN.
$JIP2	IN	PTR	$JUMP.$DOMAIN.

; OpenShift Container Platform Cluster - PTR records
$BIP	IN	PTR	$BOOT.$DOMAIN.
;
$M1IP	IN	PTR	$MAS1.$CTX.$DOMAIN.
$M2IP	IN	PTR	$MAS2.$CTX.$DOMAIN.
$M3IP	IN	PTR	$MAS3.$CTX.$DOMAIN.
;
$W1IP	IN	PTR	$WOR1.$CTX.$DOMAIN.
$W2IP	IN	PTR	$WOR2.$CTX.$DOMAIN.
;
$I1IP	IN	PTR	$INF1.$CTX.$DOMAIN.
$I2IP	IN	PTR	$INF2.$CTX.$DOMAIN.
;
$JIP	IN	PTR	api.$CTX.$DOMAIN.
$JIP	IN	PTR	api-int.$CTX.$DOMAIN.
EOF

echo 'OPTIONS="-4"' >>/etc/sysconfig/named
systemctl start named;systemctl enable --now named
echo "PEERDNS=no" >> /etc/sysconfig/network-scripts/ifcfg-eth0
sed -i "1s/^/nameserver $HIP\n/" /etc/resolv.conf
firewall-cmd --add-port=53/udp --permanent
firewall-cmd --reload

}

# Configure DHCP Server 
dhcpsetup() {

echo "$bld$grn Configuring DHCP Server $nor"
yum install dhcp -y 
yum install dhcp-server -y

cat <<EOF > /etc/dhcp/dhcpd.conf
authoritative;
ddns-update-style interim;
allow booting;
allow bootp;
allow unknown-clients;
ignore client-updates;
default-lease-time 14400;
max-lease-time 14400;
subnet $SUBNET.0 netmask 255.255.255.0 {
 option routers                  $JUMPIP; # lan
 option subnet-mask              255.255.255.0;
 option domain-name              "$DOMAIN";
 option domain-name-servers       $JUMPIP;
 range $SUBNET.$BIP $SUBNET.245;
}

group {
 next-server  $JUMP.$DOMAIN;
 option routers                  $JUMPIP; # lan
 option domain-name              "$DOMAIN";
 option domain-name-servers       $JUMPIP;

 host $BOOT {
  hardware ethernet $BOOTMAC;
  fixed-address $BOOTIP;
  filename "pxelinux.0";
  option host-name $BOOT;
  option domain-name "$DOMAIN";
 }

 host $MAS1 {
  hardware ethernet $MAS1MAC;
  fixed-address $MAS1IP;
  filename "pxelinux.0";
  option host-name $MAS1;
  option domain-name "$DOMAIN";
 }

 host $MAS2 {
  hardware ethernet $MAS2MAC;
  fixed-address $MAS2IP;
  filename "pxelinux.0";
  option host-name $MAS2;
  option domain-name "$DOMAIN";
 }

 host $MAS3 {
  hardware ethernet $MAS3MAC;
  fixed-address $MAS3IP;
  filename "pxelinux.0";
  option host-name $MAS3;
  option domain-name "$DOMAIN";
 }

 host $WOR1 {
  hardware ethernet $WOR1MAC;
  fixed-address $WOR1IP;
  filename "pxelinux.0";
  option host-name $WOR1;
  option domain-name "$DOMAIN";
 }

 host $WOR2 {
  hardware ethernet $WOR2MAC;
  fixed-address $WOR2IP;
  filename "pxelinux.0";
  option host-name $WOR2;
  option domain-name "$DOMAIN";
 }

 host $INF1 {
  hardware ethernet $INF1MAC;
  fixed-address $INF1IP;
  filename "pxelinux.0";
  option host-name $INF1;
  option domain-name "$DOMAIN";
 }

 host $INF2 {
  hardware ethernet $INF2MAC;
  fixed-address $INF2IP;
  filename "pxelinux.0";
  option host-name $INF2;
  option domain-name "$DOMAIN";
 }
}

EOF

systemctl start dhcpd;systemctl enable --now dhcpd
firewall-cmd --add-service=dhcp --permanent
firewall-cmd --reload
}


# Configure DNSMASQ, TFTP with PXE Server
tftpsetup() {

HNM=`hostname`
echo "$bld$grn Configuring DNSMASQ, TFTP with PXE Server $nor"
if [[ -n $(netstat -tunpl | grep 53) ]]; then echo "$bld$red DNS Port (53) used, DO NOT RUN tftpsetup $nor"; exit; fi

yum install net-tools nmstate dnsmasq syslinux tftp-server bind-utils -y
ifconfig eth0:0 $SUBNET.$JIP2 netmask 255.255.255.0
echo "PEERDNS=no" >> /etc/sysconfig/network-scripts/ifcfg-eth0

cp -r /usr/share/syslinux/* /var/lib/tftpboot
mkdir /var/lib/tftpboot/rhcos
mkdir /var/lib/tftpboot/pxelinux.cfg
cp rhcos-initramfs.img /var/lib/tftpboot/rhcos/rhcos-initramfs.img
cp rhcos-kernel /var/lib/tftpboot/rhcos/rhcos-kernel

mv /etc/dnsmasq.conf  /etc/dnsmasq.conf.backup

cat <<EOF > /etc/dnsmasq.conf
interface=eth0
bind-interfaces
domain=$DOMAIN

# DHCP range-leases
dhcp-range=eth0,$SUBNET.$BIP,$SUBNET.225,255.255.255.0,1h

# PXE
dhcp-boot=pxelinux.0,$HNM,$HIP

# Gateway
dhcp-option=3,$GW

# DNS
dhcp-option=6,$JUMPIP, $GW, 8.8.8.8
server=8.8.4.4

# Broadcast Address
dhcp-option=28,$SUBNET.255

# NTP Server
dhcp-option=42,0.0.0.0

###### OpenShift #######

# Hosts MAC & Static IP
dhcp-host=$BOOTMAC,$BOOT,$BOOTIP,86400
dhcp-host=$MAS1MAC,$MAS1,$MAS1IP,86400
dhcp-host=$MAS2MAC,$MAS2,$MAS2IP,86400
dhcp-host=$MAS3MAC,$MAS3,$MAS3IP,86400
dhcp-host=$INF1MAC,$INF1,$INF1IP,86400
dhcp-host=$INF2MAC,$INF2,$INF2IP,86400
dhcp-host=$WOR1MAC,$WOR1,$WOR1IP,86400
dhcp-host=$WOR2MAC,$WOR2,$WOR2IP,86400

# DNS Records
address=/api.$CTX.$DOMAIN/$JUMPIP
address=/api-int.$CTX.$DOMAIN/$JUMPIP
address=/apps.$CTX.$DOMAIN/$JUMPIP2

address=/$JUMP,$JUMPIP
address=/$BOOT,$BOOTIP
address=/$MAS1,$MAS1IP
address=/$MAS2,$MAS2IP
address=/$MAS3,$MAS3IP
address=/$INF1,$INF1IP
address=/$INF2,$INF2IP
address=/$WOR1,$WOR1IP
address=/$WOR2,$WOR2IP
address=/etcd-0.$CTX.$DOMAIN/$MAS1IP
address=/etcd-1.$CTX.$DOMAIN/$MAS2IP
address=/etcd-2.$CTX.$DOMAIN/$MAS3IP

# PTR Records
ptr-record=$JIP.$REV.,"$JUMP"
ptr-record=$JIP2.$REV.,"$JUMP"
ptr-record=$BIP.$REV.,"$BOOT"
ptr-record=$M1IP.$REV.,"$MAS1IP"
ptr-record=$M2IP.$REV.,"$MAS2IP"
ptr-record=$M3IP.$REV.,"$MAS3IP"
ptr-record=$I1IP.$REV.,"$INF1IP"
ptr-record=$I2IP.$REV.,"$INF2IP"
ptr-record=$W1IP.$REV.,"$WOR1IP"
ptr-record=$W2IP.$REV.,"$WOR2IP"
ptr-record=$JIP.$REV.,"api-int.$CTX.$DOMAIN"
ptr-record=$JIP.$REV.,"api.$CTX.$DOMAIN"
###### OpenShift #######

# TFTP
pxe-prompt="Press F8 for menu.", 5
pxe-service=x86PC, "Install COREOS from network server", pxelinux
enable-tftp
tftp-root=/var/lib/tftpboot
EOF

cat <<EOF > /var/lib/tftpboot/pxelinux.cfg/no-default
UI vesamenu.c32
MENU BACKGROUND        bg-ocp.png
MENU COLOR sel         4  #ffffff std
MENU COLOR title       1  #ffffff
TIMEOUT 120
PROMPT 0
MENU TITLE OPENSHIFT 4.x INSTALL PXE MENU
LABEL INSTALL BOOTSTRAP
 kernel http://$JUMPIP:8080/ocp4/rhcos-kernel
 append ip=dhcp rd.neednet=1 initrd=http://$JUMPIP:8080/ocp4/rhcos-initramfs.img coreos.inst.install_dev=sda coreos.live.rootfs_url=http://$JUMPIP:8080/ocp4/rhcos-rootfs.img coreos.inst.ignition_url=http://$JUMPIP:8080/ocp4/bootstrap.ign
LABEL INSTALL MASTER
 kernel http://$JUMPIP:8080/ocp4/rhcos-kernel
 append ip=dhcp rd.neednet=1 initrd=http://$JUMPIP:8080/ocp4/rhcos-initramfs.img coreos.inst.install_dev=sda coreos.live.rootfs_url=http://$JUMPIP:8080/ocp4/rhcos-rootfs.img coreos.inst.ignition_url=http://$JUMPIP:8080/ocp4/master.ign
LABEL INSTALL WORKER
 kernel http://$JUMPIP:8080/ocp4/rhcos-kernel
 append ip=dhcp rd.neednet=1 initrd=http://$JUMPIP:8080/ocp4/rhcos-initramfs.img coreos.inst.install_dev=sda coreos.live.rootfs_url=http://$JUMPIP:8080/ocp4/rhcos-rootfs.img coreos.inst.ignition_url=http://$JUMPIP:8080/ocp4/worker.ign
EOF

cat <<EOF > /var/lib/tftpboot/pxelinux.cfg/bootstrap
DEFAULT pxeboot
TIMEOUT 5
PROMPT 0
LABEL pxeboot
 KERNEL http://$HIP:8080/ocp4/rhcos-kernel
 APPEND ip=dhcp rd.neednet=1 initrd=http://$HIP:8080/ocp4/rhcos-initramfs.img coreos.inst.install_dev=sda coreos.live.rootfs_url=http://$HIP:8080/ocp4/rhcos-rootfs.img coreos.inst.ignition_url=http://$HIP:8080/ocp4/bootstrap.ign
EOF

cat <<EOF > /var/lib/tftpboot/pxelinux.cfg/master
DEFAULT pxeboot
TIMEOUT 5
PROMPT 0
LABEL pxeboot
 KERNEL http://$HIP:8080/ocp4/rhcos-kernel
 APPEND ip=dhcp rd.neednet=1 initrd=http://$HIP:8080/ocp4/rhcos-initramfs.img coreos.inst.install_dev=sda coreos.live.rootfs_url=http://$HIP:8080/ocp4/rhcos-rootfs.img coreos.inst.ignition_url=http://$HIP:8080/ocp4/master.ign
EOF

cat <<EOF > /var/lib/tftpboot/pxelinux.cfg/worker
DEFAULT pxeboot
TIMEOUT 5
PROMPT 0
LABEL pxeboot
 KERNEL http://$HIP:8080/ocp4/rhcos-kernel
 APPEND ip=dhcp rd.neednet=1 initrd=http://$HIP:8080/ocp4/rhcos-initramfs.img coreos.inst.install_dev=sda coreos.live.rootfs_url=http://$HIP:8080/ocp4/rhcos-rootfs.img coreos.inst.ignition_url=http://$HIP:8080/ocp4/worker.ign
EOF

# Link the MAC
ln -s /var/lib/tftpboot/pxelinux.cfg/bootstrap /var/lib/tftpboot/pxelinux.cfg/$(echo $BOOTMAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
ln -s /var/lib/tftpboot/pxelinux.cfg/master /var/lib/tftpboot/pxelinux.cfg/$(echo $MAS1MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
ln -s /var/lib/tftpboot/pxelinux.cfg/master /var/lib/tftpboot/pxelinux.cfg/$(echo $MAS2MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
ln -s /var/lib/tftpboot/pxelinux.cfg/master /var/lib/tftpboot/pxelinux.cfg/$(echo $MAS3MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
ln -s /var/lib/tftpboot/pxelinux.cfg/worker /var/lib/tftpboot/pxelinux.cfg/$(echo $INF1MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
ln -s /var/lib/tftpboot/pxelinux.cfg/worker /var/lib/tftpboot/pxelinux.cfg/$(echo $INF2MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
ln -s /var/lib/tftpboot/pxelinux.cfg/worker /var/lib/tftpboot/pxelinux.cfg/$(echo $WOR1MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
ln -s /var/lib/tftpboot/pxelinux.cfg/worker /var/lib/tftpboot/pxelinux.cfg/$(echo $WOR2MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')

# If Menu Driven in Screen Uncomment below two lines
#mv /var/lib/tftpboot/pxelinux.cfg/no-default /var/lib/tftpboot/pxelinux.cfg/default
#rm -rf /var/lib/tftpboot/pxelinux.cfg/01-*

systemctl start dnsmasq;systemctl enable --now dnsmasq
systemctl start tftp;systemctl enable --now tftp
firewall-cmd --add-service=tftp --permanent 
firewall-cmd --reload

}

# Configure Apache Web Server
websetup() {

echo "$bld$grn Configuring Apache Web Server $nor"
yum install -y httpd
sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf
setsebool -P httpd_read_user_content 1
systemctl start httpd;systemctl enable --now httpd
firewall-cmd --add-port=8080/tcp --permanent
firewall-cmd --reload
}

# Configure HAProxy
lbsetup() {

echo "$bld$grn Configuring HAProxy Server $nor"
yum install net-tools nmstate haproxy -y

# As apiVIPs & ingressVIPs need different ip, create secondary IP in same server (Haproxy)
ifconfig eth0:0 $SUBNET.$JIP2 netmask 255.255.255.0
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-eth0:0
DEVICE=eth0:0
BOOTPROTO=static
IPADDR=$SUBNET.$JIP2
NETMASK=255.255.255.0
ONBOOT=yes
PEERDNS=no
EOF

cat <<EOF > /etc/haproxy/haproxy.cfg
# Global settings
#---------------------------------------------------------------------
global
    maxconn     20000
    log         /dev/log local0 info
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    user        haproxy
    group       haproxy
    daemon
    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats
#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    log                     global
    mode                    http
    option                  httplog
    option                  dontlognull
    option http-server-close
    option redispatch
    option forwardfor       except 127.0.0.0/8
    retries                 3
    maxconn                 20000
    timeout http-request    10000ms
    timeout http-keep-alive 10000ms
    timeout check           10000ms
    timeout connect         40000ms
    timeout client          300000ms
    timeout server          300000ms
    timeout queue           50000ms

# Enable HAProxy stats
listen stats
    bind :9000
    stats uri /stats
    stats refresh 10000ms

# Kube API Server
frontend k8s_api_frontend
    bind :6443
    default_backend k8s_api_backend
    mode tcp

backend k8s_api_backend
    mode tcp
    balance source
    server      $BOOT $BOOTIP:6443 check
    server      $MAS1 $MAS1IP:6443 check
    server      $MAS2 $MAS2IP:6443 check
    server      $MAS3 $MAS3IP:6443 check

# OCP Machine Config Server
frontend ocp_machine_config_server_frontend
    mode tcp
    bind :22623
    default_backend ocp_machine_config_server_backend

backend ocp_machine_config_server_backend
    mode tcp
    balance source
    server      $BOOT $BOOTIP:22623 check
    server      $MAS1 $MAS1IP:22623 check
    server      $MAS2 $MAS2IP:22623 check
    server      $MAS3 $MAS3IP:22623 check

# OCP Ingress - layer 4 tcp mode for each. Ingress Controller will handle layer 7.
frontend ocp_http_ingress_frontend
    bind :80
    default_backend ocp_http_ingress_backend
    mode tcp

backend ocp_http_ingress_backend
    balance source
    mode tcp
    server $MAS1 $MAS1IP:80 check
    server $MAS2 $MAS2IP:80 check
    server $MAS3 $MAS3IP:80 check
    server $INF1 $INF1IP:80 check
    server $INF2 $INF2IP:80 check

frontend ocp_https_ingress_frontend
    bind *:443
    default_backend ocp_https_ingress_backend
    mode tcp

backend ocp_https_ingress_backend
    mode tcp
    balance source
    server $MAS1 $MAS1IP:443 check
    server $MAS2 $MAS2IP:443 check
    server $MAS3 $MAS3IP:443 check
    server $INF1 $INF1IP:443 check
    server $INF2 $INF2IP:443 check

EOF

setsebool -P haproxy_connect_any 1
systemctl start haproxy;systemctl enable --now haproxy

firewall-cmd --add-port=6443/tcp --permanent
firewall-cmd --add-port=6443/tcp --permanent
firewall-cmd --add-port=22623/tcp --permanent
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --add-port=9000/tcp --permanent
firewall-cmd --reload
}

# Configure NFS Server
nfssetup() {

echo "$bld$grn Configuring NFS Server $nor"
yum install nfs-utils -y
mkdir -p /shares/registry
chown -R nobody:nobody /shares/registry
chmod -R 777 /shares/registry

cat <<EOF > /etc/exports
/shares/registry  *(rw,sync,no_subtree_check,no_root_squash,no_all_squash,insecure,no_wdelay)
EOF

setsebool -P nfs_export_all_rw 1
systemctl start nfs-server rpcbind nfs-mountd;systemctl enable --now nfs-server rpcbind
exportfs -rav
exportfs -v

firewall-cmd --add-service mountd --permanent
firewall-cmd --add-service rpc-bind --permanent
firewall-cmd --add-service nfs --permanent
firewall-cmd --reload

}

# Generate Manifests and Ignition files
manifes() {

echo "$bld$grn Generating Manifests and Ignition files $nor"
# Generate SSH Key
ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa <<<y >/dev/null 2>&1
PUBKEY=`cat ~/.ssh/id_rsa.pub`
echo $PUBKEY

rm -rf /var/www/html/ocp4
rm -rf ~/ocp-install
mkdir /var/www/html/ocp4
mkdir ~/ocp-install

cat <<EOF > ~/ocp-install/install-config.yaml
apiVersion: v1
baseDomain: $DOMAIN
compute:
  - hyperthreading: Enabled
    name: worker
    replicas: 4
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 3
metadata:
  name: $CTX # Cluster name
networking:
  machineNetwork:
    - cidr: $SUBNET.0/24
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  networkType: OVNKubernetes
  serviceNetwork:
    - 172.30.0.0/16
platform:
  none: {}
#  baremetal:
#    apiVIPs:
#      - "$JUMPIP"
#    ingressVIPs:
#      - "$JUMPIP2"
fips: false
pullSecret: 'PULL_SECRET'  
sshKey: "ssh-rsa PUBLIC_SSH_KEY"  

EOF

sed -i "s%PULL_SECRET%$PULLSECRET%" ~/ocp-install/install-config.yaml
sed -i "s%ssh-rsa PUBLIC_SSH_KEY%$PUBKEY%" ~/ocp-install/install-config.yaml
cp ~/ocp-install/install-config.yaml ~/ocp-install/install-config.yaml-bak
cp ~/ocp-install/install-config.yaml install-config.yaml

cp rhcos-live.x86_64.iso /var/www/html/ocp4/rhcos-live.x86_64.iso
cp rhcos-kernel /var/www/html/ocp4/rhcos-kernel
cp rhcos-initramfs.img /var/www/html/ocp4/rhcos-initramfs.img
cp rhcos-rootfs.img /var/www/html/ocp4/rhcos-rootfs.img

#cp rhcos-qemu.x86_64.qcow2 /var/www/html/ocp4/rhcos-qemu.x86_64.qcow2

openshift-install create manifests --dir ~/ocp-install/
sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' ~/ocp-install/manifests/cluster-scheduler-02-config.yml
openshift-install create ignition-configs --dir ~/ocp-install/
cp -R ~/ocp-install/*.ign /var/www/html/ocp4

chcon -R -t httpd_sys_content_t /var/www/html/ocp4/
chown -R apache: /var/www/html/ocp4/
chmod 755 /var/www/html/ocp4/

curl localhost:8080/ocp4/
}

# Install ALL
setupall () {

toolsetup
#dnssetup
#dhcpsetup
tftpsetup
websetup
lbsetup
nfssetup
manifes
}

case "$1" in
    'toolsetup')
            toolsetup
            ;;
    'dnssetup')
            dnssetup
            ;;
    'dhcpsetup')
            dhcpsetup
            ;;
    'tftpsetup')
            tftpsetup
            ;;
    'websetup')
            websetup
            ;;
    'lbsetup')
            lbsetup
            ;;
    'nfssetup')
            nfssetup
            ;;
    'manifes')
            manifes
            ;;
    'setupall')
            setupall
            ;;
    *)
            clear
            echo
            echo "$bld$blu Openshift Jumphost (DNS,LB,NFS,DHCP,TFTP,WEB) host setup script $nor"
            echo "$bld$red DO NOT RUN TFTP, DNS & DHCP in same Host. $nor"
            echo "$bld$yel Use either tftpsetup (dnsmasq+dhcp+tftp+pxe) or dnssetup & dhcpsetup $nor"
            echo
            echo "$bld$grn Usage: $0 { toolsetup | dnssetup | dhcpsetup | tftpsetup | websetup | lbsetup | nfssetup | manifes | setupall } $nor"
            echo
            exit 1
            ;;
esac

exit 0
