# /etc/firejail/vitos-wireshark.profile
include /etc/firejail/vitos-default.profile
ignore net none
net eth0
caps.keep cap_net_raw,cap_net_admin
