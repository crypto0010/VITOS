# /etc/firejail/vitos-nmap.profile
include /etc/firejail/vitos-default.profile
ignore net none
net eth0
netfilter /etc/firejail/vitos-lab-vlan.nft
