# /etc/firejail/vitos-msfconsole.profile
include /etc/firejail/vitos-default.profile
ignore net none
net eth0
private-bin msfconsole,ruby,bundle
